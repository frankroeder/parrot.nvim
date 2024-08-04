local M = {
  _plugin_name = "parrot.nvim",
  _logfile = vim.fn.stdpath("state") .. "/parrot.nvim.log",
}

if pcall(require, "notify") then
  vim.notify = require("notify")
end

--- Writes a message to the log file.
--- @param msg string # The message to log.
--- @param kind string # The type of log message (e.g., "ErrorMsg", "Debug").
local function write_to_logfile(msg, kind)
  local logfile_path = M._logfile
  local max_lines = 10000

  --- Limits the number of lines in the log file.
  --- @return string # The limited log content.
  local function limit_logfile_lines()
    local lines = {}
    for line in io.lines(logfile_path) do
      table.insert(lines, line)
      if #lines > max_lines then
        table.remove(lines, 1)
      end
    end
    return table.concat(lines, "\n")
  end

  local logfile = io.open(logfile_path, "w+")
  if logfile then
    local limited_log = limit_logfile_lines()
    logfile:write(limited_log)
    logfile:write(string.format("[%s] %s: [%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), M._plugin_name, kind, msg))
    logfile:close()
  end
end

--- Logs a message with a specified kind and level.
--- @param msg string # The message to log.
--- @param kind string # The type of log message (e.g., "ErrorMsg", "Debug").
--- @param level number # The log level (e.g., vim.log.levels.ERROR).
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

--- Logs an error message.
--- @param msg string # The error message.
function M.error(msg)
  log(msg, "ErrorMsg", vim.log.levels.ERROR)
end

--- Logs a warning message.
--- @param msg string # The warning message.
function M.warning(msg)
  log(msg, "WarningMsg", vim.log.levels.WARN)
end

--- Logs an informational message.
--- @param msg string # The informational message.
function M.info(msg)
  log(msg, "Normal", vim.log.levels.INFO)
end

--- Logs a debug message if debugging is enabled.
--- @param msg string # The debug message.
function M.debug(msg)
  if os.getenv("DEBUG_PARROT") then
    log(msg, "Debug", vim.log.levels.DEBUG)
  end
end

return M
