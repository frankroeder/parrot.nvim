local M = {
  _plugin_name = "parrot.nvim",
  _logfile = vim.fn.stdpath("state") .. "/parrot.nvim.log",
  _max_log_lines = 10000,
  _debug_enabled = vim.env.DEBUG_PARROT ~= nil,
  notify = vim.notify
}

-- Use pcall to safely require the notify plugin
local notify_ok, notify = pcall(require, "notify")
if notify_ok then
  M.notify = notify
end

-- Get stack trace information
local function get_stack_trace(level)
  level = level or 3 -- Skip get_stack_trace, log function, and public function
  local info = debug.getinfo(level, "Sl")
  if info then
    return string.format("%s:%d", info.source:match("([^/]+)$") or info.source, info.currentline or 0)
  end
  return "unknown:0"
end

-- Validate and sanitize log message
local function sanitize_message(msg)
  if type(msg) ~= "string" then
    if type(msg) == "table" then
      return vim.inspect(msg)
    else
      return tostring(msg)
    end
  end
  -- Ensure message is not empty
  if msg:match("^%s*$") then
    return "Empty log message"
  end
  return msg
end

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
    -- Remove oldest lines to stay under limit
    while #lines > M._max_log_lines do
      table.remove(lines, 1)
    end
  end
  return table.concat(lines, "\n")
end

-- Write a message to the log file with context
local function write_to_logfile(msg, kind, stack_info)
  local limited_log = limit_logfile_lines()
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local log_entry = string.format("[%s] %s: [%s] %s", timestamp, M._plugin_name, kind, msg)

  -- Add stack trace for errors and warnings
  if kind == "ErrorMsg" or kind == "WarningMsg" then
    log_entry = log_entry .. string.format(" (at %s)", stack_info)
  end

  local success = write_file(M._logfile, limited_log .. log_entry .. "\n")
  if not success and kind ~= "Debug" then
    -- Fallback to M.notify if file write fails
    vim.schedule(function()
      M.notify("Failed to write to log file: " .. M._logfile, vim.log.levels.WARN, { title = M._plugin_name })
    end)
  end
end

-- Log a message with a specified kind and level
local function log(msg, kind, level, include_stack)
  msg = sanitize_message(msg)
  local stack_info = include_stack and get_stack_trace(4) or nil

  if kind == "ErrorMsg" or kind == "Debug" or kind == "WarningMsg" then
    write_to_logfile(msg, kind, stack_info)
  end

  if kind ~= "Debug" then
    vim.schedule(function()
      local notify_opts = { title = M._plugin_name .. " " .. kind }

      -- Add stack trace to error notifications in debug mode
      if M._debug_enabled and stack_info and (kind == "ErrorMsg" or kind == "WarningMsg") then
        msg = msg .. "\nLocation: " .. stack_info
      end

      M.notify(msg, level, notify_opts)
    end)
  end
end

-- Logging functions with better context
function M.error(msg, context)
  if context then
    msg = string.format("%s\nContext: %s", msg, vim.inspect(context))
  end
  log(msg, "ErrorMsg", vim.log.levels.ERROR, true)
end

function M.warning(msg, context)
  if context then
    msg = string.format("%s\nContext: %s", msg, vim.inspect(context))
  end
  log(msg, "WarningMsg", vim.log.levels.WARN, true)
end

function M.info(msg)
  log(msg, "Normal", vim.log.levels.INFO, false)
end

function M.debug(msg, context)
  if M._debug_enabled then
    if context then
      msg = string.format("%s\nContext: %s", msg, vim.inspect(context))
    end
    log(msg, "Debug", vim.log.levels.DEBUG, true)
  end
end

-- Critical errors that should always be logged
function M.critical(msg, context)
  if context then
    msg = string.format("CRITICAL: %s\nContext: %s", msg, vim.inspect(context))
  else
    msg = "CRITICAL: " .. msg
  end
  log(msg, "ErrorMsg", vim.log.levels.ERROR, true)
end

-- Function to enable/disable debug logging at runtime
function M.set_debug(enabled)
  M._debug_enabled = enabled
  M.info("Debug logging " .. (enabled and "enabled" or "disabled"))
end

return M
