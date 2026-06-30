--- JSON-RPC 2.0 client for newline-delimited stdio transport.
local logger = require("parrot.logger")

local M = {}

M.code = {
  parse_error = -32700,
  invalid_request = -32600,
  method_not_found = -32601,
  invalid_params = -32602,
  internal_error = -32603,
}

---@class parrot.acp.RpcClient
---@field request fun(method: string, params: table, callback: fun(err: table?, result: any?))
---@field notify fun(method: string, params: table)
---@field response fun(id: number, result: any?, error: table?)
---@field terminate fun()
---@field system_obj vim.SystemObj

---Start an RPC subprocess.
---@param cmd string[]
---@param dispatchers table
---@param opts? { cwd?: string, env?: table<string,string> }
---@return parrot.acp.RpcClient
function M.start(cmd, dispatchers, opts)
  opts = opts or {}
  local state = {
    buffer = "",
    next_id = 1,
    pending = {},
    closing = false,
  }

  local function fail_pending(message)
    local error_obj = { code = M.code.internal_error, message = message or "ACP connection closed" }
    for req_id, cb in pairs(state.pending) do
      cb(error_obj, nil)
      state.pending[req_id] = nil
    end
  end

  ---@type vim.SystemObj
  local system_obj

  local function send_response(id, result, error)
    if state.closing then
      return false
    end

    local response = { jsonrpc = "2.0", id = id }
    if error then
      response.error = error
    else
      response.result = result or {}
    end

    system_obj:write(vim.json.encode(response) .. "\n")
    return true
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
        local ok, msg = pcall(vim.json.decode, line)
        if not ok then
          if dispatchers.on_error then
            dispatchers.on_error(M.code.parse_error, "Invalid JSON: " .. line)
          end
        elseif msg.method and msg.id then
          if dispatchers.server_request then
            dispatchers.server_request(msg.id, msg.method, msg.params, function(result, err)
              send_response(msg.id, result, err)
            end)
          else
            send_response(msg.id, nil, { code = M.code.method_not_found, message = "Method not found" })
          end
        elseif msg.method then
          if dispatchers.notification then
            dispatchers.notification(msg.method, msg.params)
          end
        elseif msg.id then
          local cb = state.pending[msg.id]
          if cb then
            state.pending[msg.id] = nil
            cb(msg.error, msg.result)
          end
        end
      end
    end
  end

  system_obj = vim.system(cmd, {
    cwd = opts.cwd,
    env = opts.env,
    stdin = true,
    stdout = function(err, data)
      if err then
        if dispatchers.on_error then
          vim.schedule(function()
            dispatchers.on_error(2, err)
          end)
        end
        return
      end
      if data then
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
      fail_pending("ACP agent exited")
      if dispatchers.on_exit then
        dispatchers.on_exit(result.code or 0, result.signal or 0)
      end
    end)
  end)

  return {
    system_obj = system_obj,

    request = function(method, params, callback)
      if state.closing then
        return false
      end

      local req_id = state.next_id
      state.next_id = state.next_id + 1
      state.pending[req_id] = callback

      system_obj:write(vim.json.encode({
        jsonrpc = "2.0",
        id = req_id,
        method = method,
        params = params,
      }) .. "\n")

      return true, req_id
    end,

    response = send_response,

    notify = function(method, params)
      if state.closing then
        return false
      end

      system_obj:write(vim.json.encode({
        jsonrpc = "2.0",
        method = method,
        params = params,
      }) .. "\n")

      return true
    end,

    terminate = function()
      state.closing = true
      fail_pending("ACP connection terminated")
      if not system_obj:is_closing() then
        system_obj:kill(15)
      end
    end,
  }
end

return M