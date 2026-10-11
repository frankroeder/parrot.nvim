--- JSON-RPC 2.0 client for newline-delimited stdio transport.
local logger = require("parrot.logger")

local M = {}

M.code = {
  method_not_found = -32601,
  invalid_params = -32602,
  internal_error = -32603,
}

---@class parrot.acp.RpcClient
---@field request fun(method: string, params: table, callback: fun(err: table?, result: any?))
---@field notify fun(method: string, params: table)
---@field terminate fun()

---Start an RPC subprocess.
---@param cmd string[]
---@param dispatchers { notification: fun(method: string, params: table), server_request: fun(method: string, params: table, respond: fun(result: any?, err: table?)), on_exit?: fun(code: integer) }
---@return parrot.acp.RpcClient
function M.start(cmd, dispatchers)
  local state = {
    buffer = "",
    next_id = 1,
    pending = {},
    closing = false,
  }

  local function fail_pending(message)
    local error_obj = { code = M.code.internal_error, message = message }
    -- remove before calling: a callback that terminates again would otherwise recurse forever
    for req_id, cb in pairs(state.pending) do
      state.pending[req_id] = nil
      cb(error_obj, nil)
    end
  end

  ---@type vim.SystemObj
  local system_obj

  local function write(msg)
    if not state.closing then
      msg.jsonrpc = "2.0"
      system_obj:write(vim.json.encode(msg) .. "\n")
    end
  end

  local function send_response(id, result, error)
    if error then
      write({ id = id, error = error })
    else
      write({ id = id, result = result or vim.empty_dict() })
    end
  end

  local function dispatch(msg)
    if msg.method and msg.id then
      dispatchers.server_request(msg.method, msg.params, function(result, err)
        send_response(msg.id, result, err)
      end)
    elseif msg.method then
      dispatchers.notification(msg.method, msg.params)
    elseif msg.id then
      local cb = state.pending[msg.id]
      if cb then
        state.pending[msg.id] = nil
        cb(msg.error, msg.result)
      end
    end
  end

  local function handle_data(data)
    state.buffer = state.buffer .. data

    while true do
      local pos = state.buffer:find("\n", 1, true)
      if not pos then
        break
      end

      local line = state.buffer:sub(1, pos - 1)
      state.buffer = state.buffer:sub(pos + 1)

      if line ~= "" then
        -- JSON null fields decode to nil instead of vim.NIL userdata
        local ok, msg = pcall(vim.json.decode, line, { luanil = { object = true } })
        if not ok then
          logger.error("ACP invalid JSON: " .. line)
        else
          -- a throwing handler must neither leave the agent without a response nor stall later lines
          local ok_dispatch, dispatch_err = pcall(dispatch, msg)
          if not ok_dispatch then
            logger.error("ACP handler error: " .. tostring(dispatch_err))
            if msg.method and msg.id then
              send_response(msg.id, nil, { code = M.code.internal_error, message = tostring(dispatch_err) })
            end
          end
        end
      end
    end
  end

  system_obj = vim.system(cmd, {
    stdin = true,
    detach = true, -- own process group, so terminate also stops children of wrapper scripts
    stdout = function(err, data)
      if err then
        logger.error("ACP connection error: " .. tostring(err))
      elseif data then
        vim.schedule(function()
          handle_data(data)
        end)
      end
    end,
    stderr = function(_, data)
      if data then
        logger.debug("ACP stderr: " .. data)
      end
    end,
  }, function(result)
    vim.schedule(function()
      state.closing = true -- requests to the dead process would stay pending forever
      fail_pending("ACP agent exited")
      if dispatchers.on_exit then
        dispatchers.on_exit(result.code)
      end
    end)
  end)

  return {
    request = function(method, params, callback)
      if state.closing then
        callback({ code = M.code.internal_error, message = "ACP connection closed" }, nil)
        return
      end

      local req_id = state.next_id
      state.next_id = state.next_id + 1
      state.pending[req_id] = callback
      write({ id = req_id, method = method, params = params })
    end,

    notify = function(method, params)
      write({ method = method, params = params })
    end,

    terminate = function()
      state.closing = true
      fail_pending("ACP connection terminated")
      if not system_obj:is_closing() then
        vim.uv.kill(-system_obj.pid, "sigterm")
      end
    end,
  }
end

return M
