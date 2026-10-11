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

---Loaded buffer of exactly this path, symlinks resolved (vim.fn.bufnr would also match e.g. `a.lua.orig`).
---An unmodified buffer is first reloaded from disk: the agent's shell may have changed the file.
---@param path string
---@return integer|nil
local function loaded_buf(path)
  path = vim.fn.resolve(vim.fs.normalize(path))
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name ~= "" and vim.api.nvim_buf_is_loaded(b) and vim.fn.resolve(vim.fs.normalize(name)) == path then
      if not vim.bo[b].modified then
        local autoread = vim.bo[b].autoread
        vim.bo[b].autoread = true
        vim.cmd.checktime(b)
        vim.bo[b].autoread = autoread
      end
      return b
    end
  end
end

---@param path string
---@param params table { line?: integer (1-based), limit?: integer }
---@return string|nil
local function read_file(path, params)
  local content
  local b = loaded_buf(path)
  if b then
    -- agent writes go into the buffer, so reads must see them too
    content = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n") .. (vim.bo[b].eol and "\n" or "")
  else
    local f = io.open(path, "r")
    if not f then
      return nil
    end
    content = f:read("*a")
    f:close()
  end

  if params.line or params.limit then
    local lines = vim.split(content, "\n", { plain = true })
    local start = params.line or 1
    local finish = params.limit and start + params.limit - 1 or #lines
    content = table.concat(vim.list_slice(lines, start, finish), "\n")
  end

  return content
end

---Create client-side ACP method handlers.
---@param opts { always_approve?: boolean } Provider runtime config (read on each request)
---@return fun(method: string, params: table, respond: fun(result: any?, err: table?)) handler
---@return fun() kill_terminals Kills the agent's running terminals (when its connection goes away)
---@return fun(session_id: string) cancel_permission Answers an open permission prompt with `cancelled`
function M.create(opts)
  opts = opts or {}
  local terminals = {}
  local next_terminal_id = 0
  local pending_permissions = {} -- sessionId -> { [key] = fun() answering an open prompt with `cancelled` }

  -- ACP: after session/cancel the client must answer pending permission requests with `cancelled`
  local function cancel_permission(session_id)
    for _, cancel in pairs(pending_permissions[session_id] or {}) do
      cancel()
    end
  end

  -- terminals run in their own process group (detach): killing only the shell would leave its
  -- children running, and they keep the output pipes (and terminal/wait_for_exit) open
  local function kill(terminal)
    if not terminal.instance:is_closing() then
      vim.uv.kill(-terminal.instance.pid, "sigterm")
    end
  end

  local function kill_terminals()
    for id, terminal in pairs(terminals) do
      kill(terminal)
      terminals[id] = nil
    end
  end

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

      local bufnr = loaded_buf(params.path)
      if bufnr then
        -- the final newline is the buffer's eol, not an extra empty line
        local lines = vim.split(params.content:gsub("\n$", ""), "\n", { plain = true })
        local old_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local was_modified, old_eol, old_fixeol = vim.bo[bufnr].modified, vim.bo[bufnr].eol, vim.bo[bufnr].fixeol
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        -- write the agent's bytes exactly: a final newline only if its content has one
        vim.bo[bufnr].eol = params.content:sub(-1) == "\n"
        vim.bo[bufnr].fixeol = false
        -- save like an unopened file would be written: the agent's shell commands read the disk
        local saved, save_err = pcall(vim.api.nvim_buf_call, bufnr, function()
          vim.cmd("silent noautocmd write")
        end)
        vim.bo[bufnr].fixeol = old_fixeol
        if not saved then
          -- the agent is told the write failed, so the buffer must not keep its text either
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, old_lines)
          vim.bo[bufnr].eol = old_eol
          vim.bo[bufnr].modified = was_modified
          respond(nil, { code = rpc.code.internal_error, message = "Could not save buffer: " .. tostring(save_err) })
          return
        end
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

      respond(vim.empty_dict())
      return
    end

    if method == "session/request_permission" then
      if opts.always_approve then
        for _, option in ipairs(params.options or {}) do
          if vim.startswith(option.kind or "", "allow") then
            respond({ outcome = { outcome = "selected", optionId = option.optionId } })
            return
          end
        end
      end

      local labels = {}
      for i, option in ipairs(params.options or {}) do
        labels[i] = option.name or option.optionId or ("Option " .. i)
      end

      if #labels == 0 then
        respond({ outcome = { outcome = "cancelled" } })
        return
      end

      -- answer once: either the user's choice or `cancelled` when the prompt turn is cancelled first
      local answered = false
      local key = {} -- several prompts of one session may be open at once
      local pending = pending_permissions[params.sessionId] or {}
      pending_permissions[params.sessionId] = pending
      local function answer(outcome)
        if answered then
          return
        end
        answered = true
        pending[key] = nil
        respond({ outcome = outcome })
      end
      pending[key] = function()
        answer({ outcome = "cancelled" })
      end

      vim.ui.select(labels, {
        prompt = (params.toolCall and params.toolCall.title or "Permission required") .. " — choose:",
      }, function(_, idx)
        if idx then
          answer({ outcome = "selected", optionId = params.options[idx].optionId })
        else
          answer({ outcome = "cancelled" })
        end
      end)
      return
    end

    if method == "terminal/create" then
      local args = params.args or {}
      -- grok sends a whole command line (`bash -lc '...'`) without args; run it through a shell
      local cmd = #args == 0 and { "sh", "-c", params.command } or vim.list_extend({ params.command }, args)
      local terminal = {
        output = "",
        truncated = false,
        waiters = {}, -- responders of terminal/wait_for_exit
      }

      local function collect(_, data)
        if not data then
          return
        end
        terminal.output = terminal.output .. data
        local limit = params.outputByteLimit
        if limit and #terminal.output > limit then
          -- cut at a character boundary: drop UTF-8 continuation bytes at the start
          terminal.output = terminal.output:sub(-limit):gsub("^[\128-\191]+", "")
          terminal.truncated = true
        end
      end

      terminal.instance = vim.system(cmd, {
        text = true,
        detach = true,
        cwd = params.cwd,
        env = env_to_table(params.env),
        stdout = collect,
        stderr = collect,
      }, function(exit)
        terminal.exitStatus = {
          exitCode = exit.code,
          signal = exit.signal ~= 0 and tostring(exit.signal) or vim.NIL,
        }
        for _, waiter in ipairs(terminal.waiters) do
          waiter(terminal.exitStatus)
        end
      end)

      next_terminal_id = next_terminal_id + 1
      local term_id = "term-" .. next_terminal_id
      terminals[term_id] = terminal
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
      table.insert(terminal.waiters, respond)
      return
    end

    if method == "terminal/kill" or method == "terminal/release" then
      local terminal = terminals[params.terminalId]
      if terminal then
        kill(terminal)
        -- kill keeps output and exit status readable until release
        if method == "terminal/release" then
          terminals[params.terminalId] = nil
        end
        respond(vim.empty_dict())
        return
      end
      respond(nil, { code = rpc.code.method_not_found, message = "Terminal not found" })
      return
    end

    logger.warning("Unhandled ACP client method: " .. method)
    respond(nil, { code = rpc.code.method_not_found, message = "Method not found: " .. method })
  end,
    kill_terminals,
    cancel_permission
end

return M
