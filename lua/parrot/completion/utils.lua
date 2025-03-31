local logger = require("parrot.logger")
local utils = require("parrot.utils")

local M = {}

-- Check if completion should be available in the current context
---@return boolean Whether completion should be available
function M.is_completion_available(bufnr)
  -- Wrap in pcall to ensure we don't crash if any API call fails
  local ok, result = pcall(function()
    local buf = bufnr or vim.api.nvim_get_current_buf()
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
      -- This is a potential UI input buffer for interactive commands
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

  -- If there was an error, fallback to false but log it
  if not ok then
    logger.error("Error in completion source is_availability: " .. tostring(result))
    return false
  end

  return result
end

-- Get the documentation text for a command
---@param cmd string The command (@file, @buffer, etc.)
---@return string The markdown documentation
function M.get_command_documentation(cmd)
  local docs = {
    file = "**@file:**\n\nEmbed a file in your chat message.\n\nType `@file:` followed by a relative or absolute path.",
    buffer = "**@buffer:**\n\nEmbed a buffer in your chat message.\n\nType `@buffer:` followed by a buffer name.",
    directory = "**@directory:**\n\nEmbed all files in a directory.\n\nType `@directory:` followed by a directory path.",
  }

  return docs[cmd] or ""
end

-- Resolve a path relative to a base directory
---@param path string The path to resolve (may be relative or absolute)
---@param cwd string The base directory for relative paths
---@return string The resolved target directory
function M.resolve_path(path, cwd)
  if not path then
    path = ""
  end

  -- Detect absolute path
  local is_absolute = path:match("^[/\\]") or (vim.uv.os_uname().sysname == "Windows_NT" and path:match("^%a:[/\\]"))
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

function M.scan_dir_async(path, async)
  local max_entries = 200
  return async.task.new(function(resolve, reject)
    vim.uv.fs_opendir(path, function(err, handle)
      if err ~= nil or handle == nil then
        return reject(err)
      end
      local all_entries = {}
      local function read_dir()
        vim.uv.fs_readdir(handle, function(err, entries)
          if err ~= nil or entries == nil then
            return reject(err)
          end
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

function M.fs_stat_all_async(cwd, entries, async)
  local tasks = {}
  for _, entry in ipairs(entries) do
    table.insert(
      tasks,
      async.task.new(function(resolve)
        vim.uv.fs_stat(utils.path_join(cwd, entry.name), function(err, stat)
          if err then
            return resolve(nil)
          end
          resolve({ name = entry.name, type = entry.type, stat = stat })
        end)
      end)
    )
  end
  return async.task.await_all(tasks):map(function(entries)
    return vim.tbl_filter(function(entry)
      return entry ~= nil
    end, entries)
  end)
end

function M.read_file_async(path, byte_limit, async)
  return async.task.new(function(resolve, reject)
    vim.uv.fs_open(path, "r", 438, function(open_err, fd)
      if open_err or fd == nil then
        return reject(open_err)
      end
      vim.uv.fs_read(fd, byte_limit, 0, function(read_err, data)
        vim.uv.fs_close(fd, function() end)
        if read_err or data == nil then
          return reject(read_err)
        end
        resolve(data)
      end)
    end)
  end)
end

return M
