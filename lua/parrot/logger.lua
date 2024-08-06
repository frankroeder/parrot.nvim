local M = {
  _plugin_name = "parrot.nvim",
  _logfile = vim.fn.stdpath("state") .. "/parrot.nvim.log",
  _max_log_lines = 10000,
  _debug_enabled = vim.env.DEBUG_PARROT ~= nil,
}

-- Use pcall to safely require the notify plugin
local notify_ok, notify = pcall(require, "notify")
if notify_ok then
  vim.notify = notify
end

-- Utility function to read file contents
local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return ""
  end
  local content = file:read("*a")
  file:close()
  return content
end

-- Utility function to write file contents
local function write_file(path, content)
  local file = io.open(path, "w")
  if not file then
    return false
  end
  file:write(content)
  file:close()
  return true
end

-- Limit the number of lines in the log file
local function limit_logfile_lines()
  local content = read_file(M._logfile)
  local lines = vim.split(content, "\n")
  if #lines > M._max_log_lines then
    table.remove(lines, 1)
  end
  return table.concat(lines, "\n")
end

-- Write a message to the log file
local function write_to_logfile(msg, kind)
  local limited_log = limit_logfile_lines()
  local new_log_entry = string.format("[%s] %s: [%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), M._plugin_name, kind, msg)
  write_file(M._logfile, limited_log .. new_log_entry)
end

-- Log a message with a specified kind and level
local function log(msg, kind, level)
  if kind == "ErrorMsg" or kind == "Debug" then
    write_to_logfile(msg, kind)
  end
  if kind ~= "Debug" then
    vim.schedule(function()
      vim.notify(msg, level, { title = M._plugin_name .. " " .. kind })
    end)
  end
end

-- Logging functions
function M.error(msg)
  log(msg, "ErrorMsg", vim.log.levels.ERROR)
end

function M.warning(msg)
  log(msg, "WarningMsg", vim.log.levels.WARN)
end

function M.info(msg)
  log(msg, "Normal", vim.log.levels.INFO)
end

function M.debug(msg)
  if M._debug_enabled then
    log(msg, "Debug", vim.log.levels.DEBUG)
  end
end

return M
