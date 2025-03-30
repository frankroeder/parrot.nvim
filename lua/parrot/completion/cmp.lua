local has_cmp, cmp = pcall(require, "cmp")
local comp_utils = require("parrot.completion.utils")
local logger = require("parrot.logger")

local source = {}

source.new = function()
  return setmetatable({}, { __index = source })
end

source.is_available = function()
  return comp_utils.is_completion_available()
end

source.get_trigger_characters = function()
  return { "@" }
end

-- Extract @command from input (CMP-specific)
local function extract_cmd(request)
  if not request or not request.context or not request.context.cursor_before_line or not request.offset then
    return nil
  end
  local text = request.context.cursor_before_line:sub(1, request.offset)
  return text:match("^%s*(@%S*)")
end

-- Get base completion items (@file, @buffer, @directory)
local function get_base_completion_items()
  return {
    {
      label = "file",
      kind = cmp.lsp.CompletionItemKind.Keyword,
      documentation = {
        kind = "markdown",
        value = comp_utils.get_command_documentation("file"),
      },
    },
    {
      label = "buffer",
      kind = cmp.lsp.CompletionItemKind.Keyword,
      documentation = {
        kind = "markdown",
        value = comp_utils.get_command_documentation("buffer"),
      },
    },
    {
      label = "directory",
      kind = cmp.lsp.CompletionItemKind.Keyword,
      documentation = {
        kind = "markdown",
        value = comp_utils.get_command_documentation("directory"),
      },
    },
  }
end

-- Get file completions synchronously
local function get_file_completions(path, only_directories, max_items)
  only_directories = only_directories or false
  max_items = max_items or 50

  -- Use pcall for the entire function to ensure we don't crash
  local ok, result = pcall(function()
    -- Handle possible nil or empty input
    if not path then
      path = ""
    end

    -- Get current working directory
    local cwd = vim.fn.getcwd()
    local target_dir = comp_utils.resolve_path(path, cwd)

    -- Handle potential errors with pcall
    local scan_ok, handle = pcall(vim.loop.fs_scandir, target_dir)
    local files = {}

    if not scan_ok or not handle then
      return files
    end

    -- Collect directory entries
    local count = 0
    while count < max_items do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then
        break
      end

      -- Skip hidden files unless explicitly requested
      if not name:match("^%.") then
        local item_kind
        local is_valid = true

        if type == "directory" then
          item_kind = cmp.lsp.CompletionItemKind.Folder
          name = name .. "/"
        elseif type == "file" then
          if only_directories then
            is_valid = false
          else
            item_kind = cmp.lsp.CompletionItemKind.File
          end
        else
          -- Skip if not a file or directory
          is_valid = false
        end

        if is_valid then
          -- Compute the full path for the item
          local full_path = vim.fn.getcwd() .. "/" .. name
          if path ~= "" then
            if path:match("^/") then
              full_path = path .. name
            else
              full_path = vim.fn.getcwd() .. "/" .. path .. name
            end
          end

          -- Prepare documentation based on item type
          local documentation_value
          if type == "file" then
            local stat = vim.loop.fs_stat(full_path)
            if stat then
              local size = stat.size
              local mtime = os.date("%Y-%m-%d %H:%M", stat.mtime.sec)
              documentation_value =
                string.format("**File:** %s\n**Size:** %d bytes\n**Modified:** %s", full_path, size, mtime)
            else
              -- Fallback if stat fails
              documentation_value = string.format("**File:** %s", full_path)
            end
          else
            documentation_value = string.format("**Directory:** %s", full_path)
          end

          -- Create the completion item with enhanced information
          table.insert(files, {
            label = name,
            kind = item_kind,
            filterText = name:lower(),
            documentation = {
              kind = "markdown",
              value = documentation_value,
            },
          })

          count = count + 1
        end
      end
    end

    -- Sort files and directories (directories first)
    table.sort(files, function(a, b)
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

    return files
  end)

  -- If an error occurred, log it and return empty array
  if not ok then
    logger.error("Error in get_file_completions: " .. tostring(result))
    return {}
  end

  return result
end

-- Get all buffer completion items, optionally filtered by query
local function get_buffer_completions(query, max_items)
  max_items = max_items or 50

  -- Wrap in pcall to ensure we don't crash if any API call fails
  local ok, result = pcall(function()
    local buffers = vim.api.nvim_list_bufs()
    local items = {}
    local current_buf = vim.api.nvim_get_current_buf()

    for _, buf in ipairs(buffers) do
      if #items >= max_items then
        break
      end

      -- Skip unloaded buffers
      if vim.api.nvim_buf_is_loaded(buf) then
        -- Safely check buffer options
        local bufhidden = ""
        local name = ""
        local filetype = ""
        local modified = false

        -- Use pcall for each API call to prevent errors
        pcall(function() bufhidden = vim.api.nvim_buf_get_option(buf, "bufhidden") end)
        pcall(function() name = vim.api.nvim_buf_get_name(buf) end)
        pcall(function() filetype = vim.api.nvim_buf_get_option(buf, "filetype") end)
        pcall(function() modified = vim.api.nvim_buf_get_option(buf, "modified") end)

        -- Skip unnamed buffers and those marked for wiping
        if name and name ~= "" and not (bufhidden and bufhidden:match("^wipe")) then
          -- Get additional metadata for better presentation
          local filename = vim.fn.fnamemodify(name, ":t")
          local rel_path = vim.fn.fnamemodify(name, ":~:.") or filename

          -- Apply query filter if provided
          if not query or query == "" or
             filename:lower():find(query, 1, true) or
             rel_path:lower():find(query, 1, true) then

            -- Create item with enhanced display info
            local item = {
              label = filename,
              kind = cmp.lsp.CompletionItemKind.Buffer,
              detail = string.format("Buffer No.: [%d]\nRelative path: %s\n", buf, rel_path),
              filterText = filename:lower(),
              documentation = {
                kind = "markdown",
                value = string.format(
                  "Absolute path: %s\nType: %s\n%s",
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
    end

    return items
  end)

  -- If there was an error, return empty list but log it
  if not ok then
    logger.error("Error in get_buffer_completions: " .. tostring(result))
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
      return {
        items = get_base_completion_items(),
        isIncomplete = false
      }
    elseif cmd:match("^@file:") then
      local path = cmd:sub(7)
      local items = get_file_completions(path, false, 50)
      return { items = items, isIncomplete = (#items > 0) }
    elseif cmd:match("^@buffer:") then
      local query = cmd:sub(9):lower()
      local items = get_buffer_completions(query, 50)
      return { items = items, isIncomplete = false }
    elseif cmd:match("^@directory:") then
      local path = cmd:sub(12)
      local items = get_file_completions(path, true, 50)
      return { items = items, isIncomplete = (#items > 0) }
    else
      return { items = {}, isIncomplete = false }
    end
  end)

  if not ok then
    logger.error("Completion error: " .. tostring(result))
    callback({
      items = { { label = "Error: " .. tostring(result), kind = cmp.lsp.CompletionItemKind.Text } },
      isIncomplete = false,
    })
    return
  end

  callback(result)
end

cmp.register_source("parrot_completion", source.new())

return source
