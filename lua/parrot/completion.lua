local utils = require("parrot.utils")
local has_cmp, cmp = pcall(require, "cmp")

if not has_cmp then
  return { context = {
    insert_contexts = function(content)
      return content
    end,
  } }
end

local source = { context = require("parrot.context") }

source.new = function()
  return setmetatable({}, { __index = source })
end

source.is_available = function()
  -- Wrap in pcall to ensure we don't crash if any API call fails
  local ok, result = pcall(function()
    local buf = vim.api.nvim_get_current_buf()
    local file_name = vim.api.nvim_buf_get_name(buf)

    -- Check if in a parrot chat file
    local loaded_config = require("parrot.config")
    if loaded_config.loaded then
      local chat_dir = loaded_config.options.chat_dir
      if utils.is_chat(buf, file_name, chat_dir) then
        return true
      end
    end

    -- Check if in UI input buffer for rewrite operations
    local buf_type = vim.api.nvim_buf_get_option(buf, "buftype")
    local buf_name = vim.fn.bufname(buf)
    if buf_type == "nofile" and buf_name == "" then
      -- This is a potential UI input buffer for rewrite operations
      -- Check for presence of the prompt virtual text with "Enter text here"
      local namespace_ids = vim.api.nvim_get_namespaces()
      for _, ns_id in pairs(namespace_ids) do
        local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })
        for _, extmark in ipairs(extmarks) do
          if extmark[4] and extmark[4].virt_text then
            for _, virt_text in ipairs(extmark[4].virt_text) do
              if virt_text[1] and type(virt_text[1]) == "string" and virt_text[1]:match("Enter text here") then
                return true
              end
            end
          end
        end
      end
    end

    return false
  end)

  -- If there was an error, fallback to false but log it
  if not ok then
    local logger = require("parrot.logger")
    logger.error("Error in completion source is_available: " .. tostring(result))
    return false
  end

  return result
end

source.get_trigger_characters = function()
  return { "@" }
end

local function extract_cmd(request)
  if request == nil then
    return nil
  end
  if not request or not request.context or not request.context.cursor_before_line or not request.offset then
    return nil
  end
  local text = request.context.cursor_before_line:sub(1, request.offset)
  local cmd = text:match("^%s*(@%S*)")
  return cmd
end

local function completion_items_for_path(path)
  -- Use pcall for the entire function to ensure we don't crash
  local ok, result = pcall(function()
    -- Handle possible nil or empty input
    if not path then
      path = ""
    end

    -- Ensure path is a string
    if type(path) ~= "string" then
      path = tostring(path)
    end

    -- Detect absolute path
    local is_absolute = path:match("^[/\\]") or path:match("^%a:[/\\]")
    local target_dir

    -- Safely determine target directory
    if is_absolute then
      -- Handle absolute path
      if #path > 0 and not path:match("[/\\]$") then
        -- Remove the last part as it's the incomplete filename
        local path_without_last = path:match("(.*)[/\\][^/\\]*$") or ""
        target_dir = path_without_last
      else
        target_dir = path
      end
    else
      -- Handle relative path from cwd
      local path_parts = {}
      local ok_split = pcall(function()
        path_parts = utils.path_split(path)
      end)
      if not ok_split then
        path_parts = {}
      end

      if #path > 0 and not path:match("[/\\]$") and #path_parts > 0 then
        table.remove(path_parts)
      end

      -- Get current working directory
      local cwd = ""
      local ok_cwd, cwd_result = pcall(vim.fn.getcwd)
      if ok_cwd and cwd_result then
        cwd = cwd_result
      end

      -- Safely join paths
      local ok_join = pcall(function()
        target_dir = utils.path_join(cwd, unpack(path_parts))
      end)

      if not ok_join or not target_dir then
        target_dir = cwd
      end
    end

    -- Expand any ~ in the path
    if target_dir:match("^~") then
      local ok_expand, expanded = pcall(vim.fn.expand, target_dir)
      if ok_expand and expanded then
        target_dir = expanded
      end
    end

    -- Handle potential errors with pcall
    local scan_ok, handle = pcall(vim.loop.fs_scandir, target_dir)
    local files = {}

    if not scan_ok or not handle then
      return files
    end

    -- Limit the number of results to prevent performance issues
    local max_items = 100
    local count = 0

    while count < max_items do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then
        break
      end

      -- Skip hidden files unless explicitly requested
      if not (name:match("^%.") and not path:match("%.")) then
        local item_kind
        local is_valid = true

        if type == "file" then
          item_kind = cmp.lsp.CompletionItemKind.File
        elseif type == "directory" then
          item_kind = cmp.lsp.CompletionItemKind.Folder
          name = name .. "/"
        else
          -- Skip if not a file or directory
          is_valid = false
        end

        if is_valid then
          table.insert(files, {
            label = name,
            kind = item_kind,
            filterText = name:lower(), -- Better filtering
          })

          count = count + 1
        end
      end
    end

    -- Sort files and directories
    local sort_ok = pcall(function()
      table.sort(files, function(a, b)
        -- Directories first, then files
        local a_is_dir = a.label:sub(-1) == "/"
        local b_is_dir = b.label:sub(-1) == "/"

        if a_is_dir and not b_is_dir then
          return true
        elseif not a_is_dir and b_is_dir then
          return false
        else
          return a.label:lower() < b.label:lower()
        end
      end)
    end)

    -- If sort fails, return unsorted files (better than nothing)
    return files
  end)

  -- If an error occurred, log it and return empty array
  if not ok then
    local logger = require("parrot.logger")
    logger.error("Error in completion_items_for_path: " .. tostring(result))
    return {}
  end

  return result
end

local function completion_items_for_buffers()
  -- Wrap in pcall to ensure we don't crash if any API call fails
  local ok, result = pcall(function()
    local buffers = vim.api.nvim_list_bufs()
    local items = {}
    local current_buf = vim.api.nvim_get_current_buf()

    for _, buf in ipairs(buffers) do
      -- Skip unloaded buffers
      if vim.api.nvim_buf_is_loaded(buf) then
        -- Safely check buffer options
        local bufhidden = ""
        local name = ""
        local filetype = ""
        local modified = false

        -- Use pcall for each API call to prevent errors
        pcall(function()
          bufhidden = vim.api.nvim_buf_get_option(buf, "bufhidden")
        end)

        pcall(function()
          name = vim.api.nvim_buf_get_name(buf)
        end)

        pcall(function()
          filetype = vim.api.nvim_buf_get_option(buf, "filetype")
        end)

        pcall(function()
          modified = vim.api.nvim_buf_get_option(buf, "modified")
        end)

        -- Skip unnamed buffers and those marked for wiping
        if name and name ~= "" and not (bufhidden and bufhidden:match("^wipe")) then
          -- Get additional metadata for better presentation
          local filename = vim.fn.fnamemodify(name, ":t")
          local rel_path

          -- Safely get relative path
          ok, rel_path = pcall(vim.fn.fnamemodify, name, ":~:.")
          if not ok or not rel_path then
            rel_path = filename
          end

          -- Create item with enhanced display info
          local item = {
            label = filename,
            kind = cmp.lsp.CompletionItemKind.Buffer,
            detail = rel_path,
            filterText = filename:lower(), -- Better for filtering
            documentation = {
              kind = "markdown",
              value = string.format(
                "**Buffer %d: %s**\n\n%s\n\nType: %s\n%s",
                buf,
                rel_path,
                name,
                filetype ~= "" and filetype or "unknown",
                modified and "*(modified)*" or ""
              ),
            },
          }

          -- Prioritize current buffer
          if buf == current_buf then
            table.insert(items, 1, item)
          else
            table.insert(items, item)
          end
        end
      end
    end

    -- Only return a reasonable number of items
    if #items > 50 then
      items = { unpack(items, 1, 50) }
    end

    return items
  end)

  -- If there was an error, return empty list but log it
  if not ok then
    local logger = require("parrot.logger")
    logger.error("Error in completion_items_for_buffers: " .. tostring(result))
    return {}
  end

  return result
end

source.complete = function(self, request, callback)
  local ok, result = pcall(function()
    local cmd = extract_cmd(request)
    if not cmd then
      return { items = {}, isIncomplete = false }
    end

    if cmd == "@" then
      -- Enhanced initial suggestions with documentation
      local items = {
        {
          label = "file",
          kind = cmp.lsp.CompletionItemKind.Keyword,
          documentation = {
            kind = "markdown",
            value = "**@file:**\n\nEmbed a file in your chat message.\n\nType `@file:` followed by a relative or absolute path.",
          },
        },
        {
          label = "buffer",
          kind = cmp.lsp.CompletionItemKind.Keyword,
          documentation = {
            kind = "markdown",
            value = "**@buffer:**\n\nEmbed a buffer in your chat message.\n\nType `@buffer:` followed by a buffer name.",
          },
        },
      }
      return { items = items, isIncomplete = false }
    elseif cmd == "@file" then
      local item = {
        label = "@file:",
        kind = cmp.lsp.CompletionItemKind.Keyword,
        documentation = {
          kind = "markdown",
          value = "**Select a file**\n\nEnter a relative path (from current directory) or an absolute path.",
        },
      }
      return { items = { item }, isIncomplete = true }
    elseif cmd == "@buffer" then
      local item = {
        label = "@buffer:",
        kind = cmp.lsp.CompletionItemKind.Keyword,
        documentation = {
          kind = "markdown",
          value = "**Select a buffer**\n\nEnter a buffer name from the list.",
        },
      }
      return { items = { item }, isIncomplete = true }
    elseif cmd:match("^@file:") then
      local path = cmd:sub(7)
      local items = completion_items_for_path(path)
      return { items = items, isIncomplete = (#items > 0) }
    elseif cmd:match("^@buffer:") then
      local query = cmd:sub(9):lower()
      local items = completion_items_for_buffers()

      -- Filter items if there's a query
      if query and query ~= "" then
        local filtered = {}
        for _, item in ipairs(items) do
          if item.label:lower():find(query, 1, true) or (item.detail and item.detail:lower():find(query, 1, true)) then
            table.insert(filtered, item)
          end
        end
        items = filtered
      end

      return { items = items, isIncomplete = false }
    else
      return { items = {}, isIncomplete = false }
    end
  end)

  if not ok then
    -- Log error but don't crash the UI
    local logger = require("parrot.logger")
    logger.error("Completion error: " .. tostring(result))
    callback({ items = {}, isIncomplete = false })
    return
  end

  callback(result)
end

cmp.register_source("parrot_completion", source.new())

return source
