local async = require("blink.cmp.lib.async")
local logger = require("parrot.logger")
local utils = require("parrot.utils")
local comp_utils = require("parrot.completion.utils")

local source = {}

function source.new(opts)
  local self = setmetatable({}, { __index = source })
  self.opts = vim.tbl_deep_extend("keep", opts or {}, {
    show_hidden_files = false,
    max_items = 50,
  })
  return self
end

function source:get_trigger_characters()
  return { "@" }
end

function source:is_available(context)
  return comp_utils.is_completion_available(context.bufnr)
end

local function extract_cmd(context)
  if not context or not context.line then
    return nil
  end
  local line_before_cursor = context.line:sub(1, context.cursor[2])
  return line_before_cursor:match("^%s*(@%S*)")
end

function source:get_completions(context, callback)
  callback = vim.schedule_wrap(callback)
  local cmd = extract_cmd(context)
  if not cmd then
    callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    return
  end

  if cmd == "@" then
    local CompletionItemKind = require("blink.cmp.types").CompletionItemKind
    local items = {
      {
        label = "file",
        kind = CompletionItemKind.Keyword,
        documentation = {
          kind = "markdown",
          value = comp_utils.get_command_documentation("file"),
        },
      },
      {
        label = "buffer",
        kind = CompletionItemKind.Keyword,
        documentation = {
          kind = "markdown",
          value = comp_utils.get_command_documentation("buffer"),
        },
      },
      {
        label = "directory",
        kind = CompletionItemKind.Keyword,
        documentation = {
          kind = "markdown",
          value = comp_utils.get_command_documentation("directory"),
        },
      },
    }
    callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
  elseif cmd:match("^@file:") then
    local path = cmd:sub(7)
    self
      :get_file_completions(context, path)
      :map(function(completion_response)
        callback(completion_response)
      end)
      :catch(function(err)
        logger.error("File completion error: " .. tostring(err))
        callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
      end)
  elseif cmd:match("^@buffer:") then
    local query = cmd:sub(9):lower()
    self
      :get_buffer_completions(context, query)
      :map(function(completion_response)
        callback(completion_response)
      end)
      :catch(function(err)
        logger.error("Buffer completion error: " .. tostring(err))
        callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
      end)
  elseif cmd:match("^@directory:") then
    local path = cmd:sub(12)
    self
      :get_directory_completions(context, path)
      :map(function(completion_response)
        callback(completion_response)
      end)
      :catch(function(err)
        logger.error("Directory completion error: " .. tostring(err))
        callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
      end)
  else
    callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
  end
end

function source:get_file_completions(context, path)
  local cwd = vim.fn.getcwd()
  local target_dir = comp_utils.resolve_path(path, cwd)
  if not target_dir then
    return async.task.new(function(resolve)
      resolve({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    end)
  end
  return comp_utils
    .scan_dir_async(target_dir, async)
    :map(function(entries)
      return comp_utils.fs_stat_all_async(target_dir, entries, async)
    end)
    :map(function(entries)
      local CompletionItemKind = require("blink.cmp.types").CompletionItemKind
      local items = {}
      for _, entry in ipairs(entries) do
        if #items >= self.opts.max_items then
          break
        end
        if self.opts.show_hidden_files or entry.name:sub(1, 1) ~= "." then
          local full_path = utils.path_join(target_dir, entry.name)
          local is_dir = entry.type == "directory"
          local documentation_value
          if is_dir then
            documentation_value = string.format("**Directory:** %s", full_path)
          else
            local size = entry.stat.size or 0
            local mtime = os.date("%Y-%m-%d %H:%M", (entry.stat.mtime or {}).sec or os.time())
            documentation_value =
              string.format("**File:** %s\n**Size:** %d bytes\n**Modified:** %s", full_path, size, mtime)
          end
          table.insert(items, {
            label = is_dir and entry.name .. "/" or entry.name,
            kind = is_dir and CompletionItemKind.Folder or CompletionItemKind.File,
            filterText = entry.name:lower(),
            documentation = {
              kind = "markdown",
              value = documentation_value,
            },
            data = {
              path = entry.name,
              full_path = full_path,
              type = entry.type,
            },
          })
        end
      end
      table.sort(items, function(a, b)
        local a_is_dir = a.kind == CompletionItemKind.Folder
        local b_is_dir = b.kind == CompletionItemKind.Folder
        if a_is_dir and not b_is_dir then
          return true
        elseif not a_is_dir and b_is_dir then
          return false
        else
          return a.label:lower() < b.label:lower()
        end
      end)
      return {
        is_incomplete_forward = (#items >= self.opts.max_items),
        is_incomplete_backward = false,
        items = items,
      }
    end)
end

function source:get_buffer_completions(context, query)
  return async.task.new(function(resolve)
    local CompletionItemKind = require("blink.cmp.types").CompletionItemKind
    local items = {}
    local buffers = vim.api.nvim_list_bufs()
    local current_buf = vim.api.nvim_get_current_buf()
    for _, buf in ipairs(buffers) do
      if #items >= self.opts.max_items then
        break
      end
      if vim.api.nvim_buf_is_loaded(buf) then
        local bufhidden = vim.api.nvim_buf_get_option(buf, "bufhidden")
        local name = vim.api.nvim_buf_get_name(buf)
        local filetype = vim.api.nvim_buf_get_option(buf, "filetype")
        local modified = vim.api.nvim_buf_get_option(buf, "modified")
        if name and name ~= "" and not (bufhidden and bufhidden:match("^wipe")) then
          local filename = vim.fn.fnamemodify(name, ":t")
          local rel_path = vim.fn.fnamemodify(name, ":~:.")
          if
            not query
            or query == ""
            or filename:lower():find(query, 1, true)
            or rel_path:lower():find(query, 1, true)
          then
            local item = {
              label = filename,
              kind = CompletionItemKind.Buffer,
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
              data = { buffer_id = buf, path = name },
            }
            if buf == current_buf then
              table.insert(items, 1, item)
            else
              table.insert(items, item)
            end
          end
        end
      end
    end
    resolve({
      is_incomplete_forward = false,
      is_incomplete_backward = false,
      items = items,
    })
  end)
end

function source:get_directory_completions(context, path)
  local cwd = vim.fn.getcwd()
  local target_dir = comp_utils.resolve_path(path, cwd)
  if not target_dir then
    return async.task.new(function(resolve)
      resolve({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    end)
  end
  return comp_utils
    .scan_dir_async(target_dir, async)
    :map(function(entries)
      return comp_utils.fs_stat_all_async(target_dir, entries, async)
    end)
    :map(function(entries)
      local CompletionItemKind = require("blink.cmp.types").CompletionItemKind
      local items = {}
      for _, entry in ipairs(entries) do
        if #items >= self.opts.max_items then
          break
        end
        if entry.type == "directory" and (self.opts.show_hidden_files or entry.name:sub(1, 1) ~= ".") then
          local full_path = utils.path_join(target_dir, entry.name)
          table.insert(items, {
            label = entry.name .. "/",
            kind = CompletionItemKind.Folder,
            filterText = entry.name:lower(),
            documentation = {
              kind = "markdown",
              value = string.format("**Directory:** %s", full_path),
            },
            data = {
              path = entry.name,
              full_path = full_path,
              type = entry.type,
            },
          })
        end
      end
      table.sort(items, function(a, b)
        return a.label:lower() < b.label:lower()
      end)
      return {
        is_incomplete_forward = (#items >= self.opts.max_items),
        is_incomplete_backward = false,
        items = items,
      }
    end)
end

function source:resolve(item, callback)
  callback = vim.schedule_wrap(callback)
  if not item or not item.data or item.data.type ~= "file" or not item.data.full_path then
    callback(item)
    return
  end
  comp_utils
    .read_file_async(item.data.full_path, 1024, async)
    :map(function(content)
      local is_binary = content:find("\0")
      if is_binary then
        item.documentation = {
          kind = "plaintext",
          value = "Binary file",
        }
      else
        local ext = vim.fn.fnamemodify(item.data.path, ":e")
        item.documentation = {
          kind = "markdown",
          value = "```" .. ext .. "\n" .. content .. "```",
        }
      end
      return item
    end)
    :map(function(resolved_item)
      callback(resolved_item)
    end)
    :catch(function(err)
      logger.error("Resolve error: " .. tostring(err))
      callback(item)
    end)
end

return source
