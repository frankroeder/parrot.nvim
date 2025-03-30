local async = require('blink.cmp.lib.async')
local logger = require("parrot.logger")
local utils = require("parrot.utils")


local function resolve_path(path, cwd)
  if not path then
    path = ""
  end
  local is_absolute = path:match("^[/\\]") or (vim.uv.os_uname().sysname == 'Windows_NT' and path:match("^%a:[/\\]"))
  local target_dir
  if path:match("[/\\]$") then
    target_dir = path
  else
    local dir_part = path:match("(.*)[/\\]") or ""
    if is_absolute then
      target_dir = dir_part
    else
      target_dir = utils.path_join(cwd, dir_part)
    end
  end
  if target_dir == "" then
    target_dir = is_absolute and "/" or cwd
  end
  if target_dir:match("^~") then
    target_dir = vim.fn.expand(target_dir)
  end
  return target_dir
end

-- Filesystem Operations
local function scan_dir_async(path)
  local max_entries = 200
  return async.task.new(function(resolve, reject)
    vim.uv.fs_opendir(path, function(err, handle)
      if err ~= nil or handle == nil then return reject(err) end
      local all_entries = {}
      local function read_dir()
        vim.uv.fs_readdir(handle, function(err, entries)
          if err ~= nil or entries == nil then return reject(err) end
          vim.list_extend(all_entries, entries)
          if #entries == max_entries then
            read_dir()
          else
            resolve(all_entries)
          end
        end)
      end
      read_dir()
    end, max_entries)
  end)
end

local function fs_stat_all(cwd, entries)
  local tasks = {}
  for _, entry in ipairs(entries) do
    table.insert(
      tasks,
      async.task.new(function(resolve)
        vim.uv.fs_stat(utils.path_join(cwd, entry.name), function(err, stat)
          if err then return resolve(nil) end
          resolve({ name = entry.name, type = entry.type, stat = stat })
        end)
      end)
    )
  end
  return async.task.await_all(tasks):map(function(entries)
    return vim.tbl_filter(function(entry) return entry ~= nil end, entries)
  end)
end

local function read_file(path, byte_limit)
  return async.task.new(function(resolve, reject)
    vim.uv.fs_open(path, 'r', 438, function(open_err, fd)
      if open_err or fd == nil then return reject(open_err) end
      vim.uv.fs_read(fd, byte_limit, 0, function(read_err, data)
        vim.uv.fs_close(fd, function() end)
        if read_err or data == nil then return reject(read_err) end
        resolve(data)
      end)
    end)
  end)
end

-- Completion Source
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
  local ok, result = pcall(function()
    local buf = context.bufnr
    local file_name = vim.api.nvim_buf_get_name(buf)
    local loaded_config = require("parrot.config")
    if loaded_config.loaded then
      local chat_dir = loaded_config.options.chat_dir
      if utils.is_chat(buf, file_name, chat_dir) then
        return true
      end
    end
    local buf_type = vim.api.nvim_buf_get_option(buf, "buftype")
    local buf_name = vim.fn.bufname(buf)
    if buf_type == "nofile" and buf_name == "" then
      local namespace_ids = vim.api.nvim_get_namespaces()
      for _, ns_id in pairs(namespace_ids) do
        local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })
        for _, extmark in ipairs(extmarks) do
          if extmark[4] and extmark[4].virt_text then
            for _, virt_text in ipairs(extmark[4].virt_text) do
              if
                virt_text[1]
                and type(virt_text[1]) == "string"
                and (virt_text[1]:match("Enter text here") or virt_text[1]:match("confirm with: CTRL%-W_q or CTRL%-C"))
              then
                return true
              end
            end
          end
        end
      end
    end
    return false
  end)
  if not ok then
    logger.error("Error in blink.cmp is_available: " .. tostring(result))
    return false
  end
  return result
end

local function extract_cmd(context)
  if not context or not context.line then
    return nil
  end
  local line_before_cursor = context.line:sub(1, context.cursor[2])
  local cmd = line_before_cursor:match("^%s*(@%S*)")
  return cmd
end

function source:get_completions(context, callback)
  callback = vim.schedule_wrap(callback)
  local cmd = extract_cmd(context)
  if not cmd then
    callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    return
  end

  if cmd == "@" then
    local CompletionItemKind = require('blink.cmp.types').CompletionItemKind
    local items = {
      {
        label = "file",
        kind = CompletionItemKind.Keyword,
        documentation = {
          kind = "markdown",
          value = "**@file:**\n\nEmbed a file in your chat message.\n\nType `@file:` followed by a relative or absolute path.",
        },
      },
      {
        label = "buffer",
        kind = CompletionItemKind.Keyword,
        documentation = {
          kind = "markdown",
          value = "**@buffer:**\n\nEmbed a buffer in your chat message.\n\nType `@buffer:` followed by a buffer name.",
        },
      },
      {
        label = "directory",
        kind = CompletionItemKind.Keyword,
        documentation = {
          kind = "markdown",
          value = "**@directory:**\n\nEmbed all files in a directory.\n\nType `@directory:` followed by a directory path.",
        },
      },
    }
    callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
  elseif cmd:match("^@file:") then
    local path = cmd:sub(7)
    self:get_file_completions(context, path):map(function(completion_response)
      callback(completion_response)
    end):catch(function(err)
      logger.error("File completion error: " .. tostring(err))
      callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    end)
  elseif cmd:match("^@buffer:") then
    local query = cmd:sub(9):lower()
    self:get_buffer_completions(context, query):map(function(completion_response)
      callback(completion_response)
    end):catch(function(err)
      logger.error("Buffer completion error: " .. tostring(err))
      callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    end)
  elseif cmd:match("^@directory:") then
    local path = cmd:sub(12)
    self:get_directory_completions(context, path):map(function(completion_response)
      callback(completion_response)
    end):catch(function(err)
      logger.error("Directory completion error: " .. tostring(err))
      callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    end)
  else
    callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
  end
end

function source:get_file_completions(context, path)
  local cwd = vim.fn.getcwd()
  local target_dir = resolve_path(path, cwd)
  if not target_dir then
    return async.task.new(function(resolve)
      resolve({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    end)
  end
  return scan_dir_async(target_dir):map(function(entries)
    return fs_stat_all(target_dir, entries)
  end):map(function(entries)
    local CompletionItemKind = require('blink.cmp.types').CompletionItemKind
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
          documentation_value = string.format("**File:** %s\n**Size:** %d bytes\n**Modified:** %s", full_path, size, mtime)
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
    local CompletionItemKind = require('blink.cmp.types').CompletionItemKind
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
          if not query or query == "" or filename:lower():find(query, 1, true) or rel_path:lower():find(query, 1, true) then
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
  local target_dir = resolve_path(path, cwd)
  if not target_dir then
    return async.task.new(function(resolve)
      resolve({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    end)
  end
  return scan_dir_async(target_dir):map(function(entries)
    return fs_stat_all(target_dir, entries)
  end):map(function(entries)
    local CompletionItemKind = require('blink.cmp.types').CompletionItemKind
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
  read_file(item.data.full_path, 1024):map(function(content)
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
  end):map(function(resolved_item)
    callback(resolved_item)
  end):catch(function(err)
    logger.error("Resolve error: " .. tostring(err))
    callback(item)
  end)
end

return source
