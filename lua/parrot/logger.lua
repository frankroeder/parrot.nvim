local M = {
  _plugin_name = "parrot.nvim",
  _logfile = "/tmp/parrot.nvim.log",
}

local function write_to_logfile(msg, kind)
  local logfile = io.open(M._logfile, "a")
  if logfile then
    logfile:write(string.format("[%s] %s: [%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), M._plugin_name, kind, msg))
    logfile:close()
  end
end

local function log(msg, kind)
  if kind == "ErrorMsg" or kind == "Debug" then
    write_to_logfile(msg, kind)
  end
  if kind ~= "Debug" then
    print(string.format("%s: [%s] %s", M._plugin_name, kind, msg))
  end
end

function M.error(msg)
  log(msg, "ErrorMsg")
end

function M.warning(msg)
  log(msg, "WarningMsg")
end

function M.info(msg)
  log(msg, "Normal")
end

function M.debug(msg)
  if os.getenv("DEBUG_PARROT") then
    log(msg, "Debug")
  end
end

return M
