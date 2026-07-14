local logger = require("parrot.logger")
local rpc = require("parrot.acp.rpc")

local M = {}

local function env_to_table(env)
  if not env then
    return nil
  end
  local result = {}
  for _, item in ipairs(env) do
    if item.name then
      result[item.name] = item.value or ""
    end
  end
  return result
end

---@param path string
---@return boolean, string?
local function valid_path(path)
  if type(path) ~= "string" or path == "" then
    return false, "Path must be a non-empty string"
  end
  if not vim.startswith(path, "/") then
    return false, "Path must be absolute"
  end
  return true
end

---@param path string
---@param params table|nil
---@return string|nil
local function read_file(path, params)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  if not content then
    return nil
  end

  if params and params.line and params.limit then
    local lines = vim.split(content, "\n", { plain = true })
    local start = params.line
    local finish = math.min(#lines, start + params.limit - 1)
    local slice = {}
    for i = start, finish do
      table.insert(slice, lines[i] or "")
    end
    content = table.concat(slice, "\n")
  end

  return content
end

---Create client-side ACP method handlers.
---@param opts { always_approve?: boolean }
---@return fun(method: string, params: table, respond: fun(result: any?, err: table?))
function M.create(opts)
  opts = opts or {}
  local terminals = {}

  return function(method, params, respond)
    if method == "fs/read_text_file" then
      local ok, err = valid_path(params.path)
      if not ok then
        respond(nil, { code = rpc.code.invalid_params, message = err })
        return
      end

      local content = read_file(params.path, params)
      if content == nil then
        respond(nil, { code = rpc.code.internal_error, message = "Could not read file: " .. params.path })
        return
      end

      respond({ content = content })
      return
    end

    if method == "fs/write_text_file" then
      local ok, err = valid_path(params.path)
      if not ok then
        respond(nil, { code = rpc.code.invalid_params, message = err })
        return
      end

      local bufnr = vim.fn.bufnr(params.path)
      if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        local lines = vim.split(params.content, "\n", { plain = true })
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      else
        local dir = vim.fn.fnamemodify(params.path, ":h")
        vim.fn.mkdir(dir, "p")
        local f = io.open(params.path, "w")
        if not f then
          respond(nil, { code = rpc.code.internal_error, message = "Could not open file for writing: " .. params.path })
          return
        end
        f:write(params.content)
        f:close()
      end

      respond({})
      return
    end

    if method == "session/request_permission" then
      if opts.always_approve and params.options and params.options[1] then
        respond({ outcome = { outcome = "selected", optionId = params.options[1].optionId } })
        return
      end

      local labels = {}
      for i, option in ipairs(params.options or {}) do
        labels[i] = option.name or option.optionId or ("Option " .. i)
      end

      if #labels == 0 then
        respond({ outcome = { outcome = "cancelled" } })
        return
      end

      vim.ui.select(labels, {
        prompt = (params.toolCall and params.toolCall.title or "Permission required") .. " — choose:",
      }, function(choice)
        if not choice then
          respond({ outcome = { outcome = "cancelled" } })
          return
        end
        for i, label in ipairs(labels) do
          if label == choice then
            respond({
              outcome = {
                outcome = "selected",
                optionId = params.options[i].optionId,
              },
            })
            return
          end
        end
        respond({ outcome = { outcome = "cancelled" } })
      end)
      return
    end

    if method == "terminal/create" then
      local args = params.args or {}
      local cmd = vim.list_extend({ params.command }, args)
      local term_id = vim.fn.strftime("%Y%m%d%H%M%S") .. "_" .. tostring(math.random(1000, 9999))
      local terminal = {
        id = term_id,
        output = "",
        truncated = false,
        outputByteLimit = params.outputByteLimit,
      }
      terminals[term_id] = terminal

      terminal.instance = vim.system(cmd, {
        text = true,
        env = env_to_table(params.env),
        stdout = function(_, data)
          if not data then
            return
          end
          terminal.output = terminal.output .. data
          if terminal.outputByteLimit and #terminal.output > terminal.outputByteLimit then
            terminal.output = terminal.output:sub(-terminal.outputByteLimit)
            terminal.truncated = true
          end
        end,
      }, function(exit)
        terminal.exitStatus = {
          exitCode = exit.code,
          signal = exit.signal,
        }
        if terminal.on_exit then
          terminal.on_exit(terminal.exitStatus)
        end
      end)

      respond({ terminalId = term_id })
      return
    end

    if method == "terminal/output" then
      local terminal = terminals[params.terminalId]
      if not terminal then
        respond(nil, { code = rpc.code.method_not_found, message = "Terminal not found" })
        return
      end
      respond({
        output = terminal.output,
        truncated = terminal.truncated,
        exitStatus = terminal.exitStatus,
      })
      return
    end

    if method == "terminal/wait_for_exit" then
      local terminal = terminals[params.terminalId]
      if not terminal then
        respond(nil, { code = rpc.code.method_not_found, message = "Terminal not found" })
        return
      end
      if terminal.exitStatus then
        respond(terminal.exitStatus)
        return
      end
      terminal.on_exit = function(status)
        respond(status)
      end
      return
    end

    if method == "terminal/kill" or method == "terminal/release" then
      local terminal = terminals[params.terminalId]
      if terminal then
        if terminal.instance and not terminal.instance:is_closing() then
          terminal.instance:kill(15)
        end
        terminals[params.terminalId] = nil
        respond({})
        return
      end
      respond(nil, { code = rpc.code.method_not_found, message = "Terminal not found" })
      return
    end

    logger.warning("Unhandled ACP client method: " .. method)
    respond(nil, { code = rpc.code.method_not_found, message = "Method not found: " .. method })
  end
end

return M