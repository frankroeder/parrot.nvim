local M = {
  _plugin_name = "parrot.nvim",
  _logfile = "/tmp/parrot.nvim.log",
}

if pcall(require, "notify") then
  vim.notify = require("notify")
end

local function write_to_logfile(msg, kind)
  local logfile = io.open(M._logfile, "a")
  if logfile then
    logfile:write(string.format("[%s] %s: [%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), M._plugin_name, kind, msg))
    logfile:close()
  end
end

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
  if os.getenv("DEBUG_PARROT") then
    log(msg, "Debug", vim.log.levels.DEBUG)
  end
end

return M
