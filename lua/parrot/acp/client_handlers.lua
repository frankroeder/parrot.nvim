local logger = require("parrot.logger")
local rpc = require("parrot.acp.rpc")

local M = {}

---`:PrtAcpMode` overrides of the providers' `always_approve`, by provider name
M.always_approve = {}

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

---Reject empty, relative, and NUL paths before any filesystem access.
---@param path string
---@return string|nil norm
---@return string|nil err
local function absolute_path(path)
  if type(path) ~= "string" or path == "" then
    return nil, "Path must be a non-empty string"
  end
  if path:find("\0", 1, true) then
    return nil, "Path must not contain null bytes"
  end
  if not vim.startswith(path, "/") then
    return nil, "Path must be absolute"
  end
  return vim.fs.normalize(path)
end

---Real path of `path`, walking up to the nearest existing ancestor for files not created yet.
---Symlinks are resolved, so a link inside a root that points outside does not stay inside.
---@param path string
---@return string|nil resolved
---@return string|nil err
local function resolve_real(path)
  local norm, err = absolute_path(path)
  if not norm then
    return nil, err
  end

  local real = vim.uv.fs_realpath(norm)
  if real then
    return vim.fs.normalize(real):gsub("/$", "")
  end

  local suffix = ""
  local current = norm
  while true do
    local parent = vim.fs.dirname(current)
    if not parent or parent == current then
      return nil, "Path is outside the allowed project root"
    end
    local base = vim.fs.basename(current)
    if base == "" or base == "." or base == ".." then
      return nil, "Path must not contain .."
    end
    suffix = "/" .. base .. suffix
    local parent_real = vim.uv.fs_realpath(parent)
    if parent_real then
      return (vim.fs.normalize(parent_real):gsub("/$", "")) .. suffix
    end
    current = parent
  end
end

---True when `resolved` is `root` or a file inside it (`root_old` is not inside `root`).
---@param resolved string
---@param root string
---@return boolean
local function inside_root(resolved, root)
  root = root:gsub("/$", "")
  return resolved == root or vim.startswith(resolved, root .. "/")
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
---@param opts { name?: string, always_approve?: boolean, roots?: string[] } Provider runtime config
---@return fun(method: string, params: table, respond: fun(result: any?, err: table?)) handler
---@return fun() kill_terminals Kills the agent's running terminals (when its connection goes away)
---@return fun(session_id: string) cancel_permission Answers an open permission prompt with `cancelled`
---@return { note_session: fun(session_id: string|nil, cwd: string) } access Register a session cwd as an allowed root
function M.create(opts)
  opts = opts or {}
  local terminals = {}
  local next_terminal_id = 0
  local pending_permissions = {} -- sessionId -> { [key] = fun() answering an open prompt with `cancelled` }
  local roots = {} -- real paths the agent may read, write, and use as a terminal cwd
  local session_root = {} -- sessionId -> one of `roots`
  local grants = {} -- sessionId -> true after the user picks an allow_* permission option

  local function add_root(path)
    if type(path) ~= "string" or path == "" or path:find("\0", 1, true) then
      return nil
    end
    local norm = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
    local real = vim.uv.fs_realpath(norm)
    if not real then
      return nil
    end
    real = vim.fs.normalize(real):gsub("/$", "")
    for _, existing in ipairs(roots) do
      if existing == real then
        return real
      end
    end
    table.insert(roots, real)
    return real
  end

  for _, root in ipairs(opts.roots or {}) do
    add_root(root)
  end

  local access = {}

  ---Remember `cwd` as an allowed root and, when `session_id` is set, bind the session to it.
  ---@param session_id string|nil
  ---@param cwd string
  function access.note_session(session_id, cwd)
    local real = add_root(cwd)
    if real and type(session_id) == "string" and session_id ~= "" then
      session_root[session_id] = real
    end
  end

  local function approved(session_id)
    local approve = M.always_approve[opts.name]
    if approve == nil then
      approve = opts.always_approve
    end
    if approve then
      return true
    end
    return type(session_id) == "string" and grants[session_id] == true
  end

  ---@param session_id string|nil
  ---@param path string
  ---@return string|nil resolved
  ---@return string|nil err
  local function authorize(session_id, path)
    if not approved(session_id) then
      return nil, "Permission denied"
    end
    local resolved, err = resolve_real(path)
    if not resolved then
      return nil, err
    end
    local candidates = (type(session_id) == "string" and session_root[session_id]) and { session_root[session_id] }
      or roots
    for _, root in ipairs(candidates) do
      if inside_root(resolved, root) then
        return resolved
      end
    end
    return nil, "Path is outside the allowed project root"
  end

  local function deny(respond, err)
    respond(nil, { code = rpc.code.invalid_params, message = err or "Permission denied" })
  end

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
      local resolved, err = authorize(params.sessionId, params.path)
      if not resolved then
        deny(respond, err)
        return
      end

      local content = read_file(resolved, params)
      if content == nil then
        respond(nil, { code = rpc.code.internal_error, message = "Could not read file: " .. params.path })
        return
      end

      respond({ content = content })
      return
    end

    if method == "fs/write_text_file" then
      local resolved, err = authorize(params.sessionId, params.path)
      if not resolved then
        deny(respond, err)
        return
      end

      local bufnr = loaded_buf(resolved)
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
        local dir = vim.fn.fnamemodify(resolved, ":h")
        vim.fn.mkdir(dir, "p")
        local f = io.open(resolved, "w")
        if not f then
          respond(nil, { code = rpc.code.internal_error, message = "Could not open file for writing: " .. resolved })
          return
        end
        f:write(params.content)
        f:close()
      end

      respond(vim.empty_dict())
      return
    end

    if method == "session/request_permission" then
      local approve = M.always_approve[opts.name]
      if approve == nil then
        approve = opts.always_approve
      end
      if approve then
        -- prefer allow_once: an allow_always answer would outlive turning always_approve off again
        local allow
        for _, option in ipairs(params.options or {}) do
          if option.kind == "allow_once" or (not allow and vim.startswith(option.kind or "", "allow")) then
            allow = option
          end
        end
        if allow then
          respond({ outcome = { outcome = "selected", optionId = allow.optionId } })
          return
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
          local option = params.options[idx]
          -- only an explicit allow survives with always_approve off; auto-approve does not grant this
          if option and type(option.kind) == "string" and vim.startswith(option.kind, "allow") then
            if type(params.sessionId) == "string" and params.sessionId ~= "" then
              grants[params.sessionId] = true
            end
          end
          answer({ outcome = "selected", optionId = option.optionId })
        else
          answer({ outcome = "cancelled" })
        end
      end)
      return
    end

    if method == "terminal/create" then
      if not approved(params.sessionId) then
        deny(respond, "Permission denied")
        return
      end

      local cwd = params.cwd
      if type(cwd) ~= "string" or cwd == "" then
        cwd = (type(params.sessionId) == "string" and session_root[params.sessionId]) or roots[1]
        if not cwd then
          deny(respond, "Path is outside the allowed project root")
          return
        end
      else
        local resolved_cwd, cwd_err = authorize(params.sessionId, cwd)
        if not resolved_cwd then
          deny(respond, cwd_err)
          return
        end
        cwd = resolved_cwd
      end

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
        cwd = cwd,
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
    cancel_permission,
    access
end

return M
