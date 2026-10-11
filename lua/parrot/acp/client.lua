local client_handlers = require("parrot.acp.client_handlers")
local logger = require("parrot.logger")
local rpc = require("parrot.acp.rpc")

local M = {}

---@class parrot.acp.Connection
---@field rpc parrot.acp.RpcClient
---@field sessions table<string, boolean> Session ids created or loaded by this agent process
---@field slash_commands table[]|nil Advertised slash commands, nil until the agent sent them
---@field active_prompts table<string, { session_id: string }>
---@field _streams table<string, fun(text: string)> Per-session streaming callbacks
---@field initialized boolean
---@field load_session boolean Agent supports session/load
---@field can_close boolean Agent supports session/close

local connections = {}
-- qids cancelled before their session/prompt was sent
local cancelled_qids = {}

M.INIT_TIMEOUT_MS = 60000

-- Command prompts (inline edits, popups, ...) run in one-shot sessions without any tools: their
-- reply is inserted verbatim into the editor, so tool calls and narration ("I'll check the file
-- first...") must not happen. Each session is deleted right after its prompt. The rules must say
-- that there are no tools, otherwise the agent still announces lookups and ends the turn.
M.COMMAND_RULES = "You are called from a Neovim plugin and your reply is inserted verbatim into the editor. "
  .. "You have no tools in this session: you cannot read files, search, or run commands, and the prompt "
  .. "already contains everything you need. Reply immediately with the final answer only, never with a plan, "
  .. "preamble, or narration."

-- grok agent profile with an empty toolset: the allowlist must be non-empty, so it names one
-- tool and removes it again together with the always-on MCP meta tools.
M.COMMAND_PROFILE = {
  name = "parrot-command",
  description = "One-shot editor command without tools",
  tools = { "todo_write" },
  injectDefaultTools = false,
  disallowedTools = { "todo_write", "search_tool", "use_tool" },
}

---Hash of the first n messages; tells whether a chat buffer still continues its ACP session.
---@param messages table[]
---@param n number
---@return string
function M.history_hash(messages, n)
  local parts = {}
  for i = 1, n do
    parts[i] = messages[i].role .. ":" .. vim.trim(messages[i].content or "")
  end
  return vim.fn.sha256(table.concat(parts, "\n"))
end

---Return the stored chat session entry if `messages` extend the history it has seen.
---@param entry table|nil { id: string, n: number, hash: string }
---@param messages table[]
---@return table|nil
function M.continued_entry(entry, messages)
  if type(entry) ~= "table" or not entry.id or not entry.n or entry.n >= #messages then
    return nil
  end
  if M.history_hash(messages, entry.n) ~= entry.hash then
    return nil
  end
  return entry
end

---Fetch models via `grok models` (or equivalent CLI subcommand): async with callback, otherwise sync.
---@param cli_command string[]
---@param callback? fun(models: string[])
---@return string[]
function M.fetch_models_from_cli(cli_command, callback)
  local cmd = vim.list_extend(vim.deepcopy(cli_command), { "models" })
  local function parse(res)
    local models = {}
    for line in (res.stdout or ""):gmatch("[^\r\n]+") do
      local id = line:match("^%s*[%*%-]%s+([%w%.%-]+)")
      if id then
        table.insert(models, id)
      end
    end
    return models
  end

  if vim.fn.executable(cmd[1]) ~= 1 then
    if callback then
      callback({})
    end
    return {}
  end
  -- same 5s cap as the curl model fetch
  if not callback then
    return parse(vim.system(cmd, { text = true }):wait(5000))
  end
  vim.system(cmd, { text = true, timeout = 5000 }, function(res)
    local models = parse(res)
    vim.schedule(function()
      callback(models)
    end)
  end)
  return {}
end

---Convert OpenAI-style chat messages to ACP prompt blocks.
---System messages are skipped; they become session rules (see create_session).
---@param messages table[]
---@return table[]
function M.messages_to_prompt(messages)
  local turns = vim.tbl_filter(function(m)
    return m.role ~= "system" and (m.content or ""):match("%S") ~= nil
  end, messages)
  local blocks = {}
  for _, m in ipairs(turns) do
    -- label the turns when a whole transcript is replayed into a fresh session
    local text = #turns > 1 and (m.role .. ":\n" .. m.content) or m.content
    table.insert(blocks, { type = "text", text = text })
  end
  return blocks
end

---One agent process per provider, command and model.
---@param config table Provider config
---@param model string
---@return string
local function connection_key(config, model)
  return (config.name or "") .. "|" .. table.concat(config.command, " ") .. "|" .. model
end

---Format a JSON-RPC error for user-facing logs.
---@param err table|string|nil
---@return string
function M.format_rpc_error(err)
  if type(err) ~= "table" then
    return tostring(err or "unknown error")
  end
  local msg = err.message or "ACP error"
  if err.data ~= nil then
    local data = err.data
    if type(data) == "table" then
      data = vim.inspect(data)
    end
    msg = msg .. ": " .. tostring(data)
  end
  return msg
end

---Pick an auth method from the initialize result: the configured one, else the agent's default
---(Grok: cached_token; preferring XAI_API_KEY causes 401s for OIDC-session models), else the API key.
---@param init_result table
---@param config table
---@return string|nil method_id
---@return string|nil error
function M.resolve_auth_method_id(init_result, config)
  local advertised = {}
  for _, method in ipairs(init_result.authMethods or {}) do
    advertised[method.id or ""] = true
  end
  local id = config.auth_method or vim.tbl_get(init_result, "_meta", "defaultAuthMethodId") or "cached_token"
  if advertised[id] then
    return id
  end
  if advertised["xai.api_key"] and (os.getenv("XAI_API_KEY") or "") ~= "" then
    return "xai.api_key"
  end
  return nil, "Run `grok login` first, or set XAI_API_KEY."
end

---The agent command with the model flag before its subcommand (`grok agent -m MODEL stdio`), else at the end.
---(no --always-approve: a flag of the process could not be turned off again by `:PrtAcpMode`)
---@param config table
---@param model string
---@return string[]
local function build_command(config, model)
  local cmd = vim.deepcopy(config.command)
  local at = cmd[#cmd] == "stdio" and #cmd or #cmd + 1
  table.insert(cmd, at, "-m")
  table.insert(cmd, at + 1, model)
  return cmd
end

---Create a session. One-shot command sessions get an empty toolset and lower reasoning effort.
---The system prompt is passed as session rules: as a prompt block, agents treat it as injected text.
---@param config table
---@param connection parrot.acp.Connection
---@param tool_free boolean One-shot command session (inline edits, popups, ...)
---@param cwd string
---@param system string|nil
---@param callback fun(err: string?, session_id: string?)
local function create_session(config, connection, tool_free, cwd, system, callback)
  local rules = {}
  local command_rules = config.command_rules or M.COMMAND_RULES
  if tool_free and command_rules ~= "" then
    table.insert(rules, command_rules)
  end
  if system and system:match("%S") then
    table.insert(rules, system)
  end
  local meta = {}
  if #rules > 0 then
    meta.rules = table.concat(rules, "\n\n")
  end
  if tool_free then
    meta.agentProfile = M.COMMAND_PROFILE
  end
  local params = { cwd = cwd, mcpServers = {} }
  if next(meta) then
    params._meta = meta
  end
  connection.rpc.request("session/new", params, function(err, result)
    if err then
      callback(M.format_rpc_error(err))
      return
    end
    if not result or not result.sessionId then
      callback("session/new returned no sessionId")
      return
    end

    connection.sessions[result.sessionId] = true

    -- inline edits are simple tasks; a lower reasoning effort roughly halves their latency
    local effort = config.command_reasoning_effort
    if not tool_free or not effort or effort == "" then
      callback(nil, result.sessionId)
      return
    end
    connection.rpc.request("session/set_config_option", {
      sessionId = result.sessionId,
      configId = "reasoning_effort",
      value = effort,
    }, function(effort_err)
      if effort_err then
        logger.debug("ACP reasoning_effort not applied: " .. M.format_rpc_error(effort_err))
      end
      callback(nil, result.sessionId)
    end)
  end)
end

---Close a session and delete it from the agent's session store (one-shot and replaced sessions).
---@param connection parrot.acp.Connection
---@param session_id string
local function discard_session(connection, session_id)
  local live = connection.sessions[session_id]
  connection.sessions[session_id] = nil
  local function delete()
    -- grok extension; other agents answer "method not found", which is ignored
    connection.rpc.request("_x.ai/session/delete", { sessionId = session_id }, function() end)
  end
  if live and connection.can_close then
    connection.rpc.request("session/close", { sessionId = session_id }, delete)
  else
    delete()
  end
end

---Reuse (or session/load) the chat session of `entry`, otherwise create a new session.
---@param config table
---@param connection parrot.acp.Connection
---@param tool_free boolean
---@param cwd string
---@param entry table|nil
---@param system string|nil
---@param callback fun(err: string?, session_id: string?)
local function open_session(config, connection, tool_free, cwd, entry, system, callback)
  if not entry then
    create_session(config, connection, tool_free, cwd, system, callback)
    return
  end
  if connection.sessions[entry.id] then
    callback(nil, entry.id)
    return
  end
  if not connection.load_session or config.resume_session == false then
    create_session(config, connection, tool_free, cwd, system, callback)
    return
  end

  local function load()
    connection.rpc.request("session/load", {
      sessionId = entry.id,
      cwd = cwd,
      mcpServers = {},
    }, function(err, result)
      if err or not result then
        logger.info("ACP session/load failed, creating new session: " .. M.format_rpc_error(err))
        create_session(config, connection, tool_free, cwd, system, callback)
        return
      end
      connection.sessions[entry.id] = true
      callback(nil, entry.id)
    end)
  end

  -- The agent process of another model may hold this session; it would keep its turns without
  -- the ones sent here, even on a later session/load (grok does). Close it there first.
  for _, other in pairs(connections) do
    if other ~= connection and other.sessions[entry.id] then
      other.sessions[entry.id] = nil
      if other.can_close then
        other.rpc.request("session/close", { sessionId = entry.id }, load)
        return
      end
    end
  end
  load()
end

---@param connection parrot.acp.Connection
---@param err string|nil
local function finish_connection_callbacks(connection, err)
  local callbacks = connection._pending_callbacks or {}
  connection._pending_callbacks = nil
  for _, cb in ipairs(callbacks) do
    cb(err, err and nil or connection)
  end
end

---Get or create an initialized ACP connection.
---@param config table
---@param model string
---@param callback fun(err: string?, connection: parrot.acp.Connection?)
function M.get_connection(config, model, callback)
  local key = connection_key(config, model)
  local existing = connections[key]
  if existing then
    if existing.initialized then
      callback(nil, existing)
    else
      table.insert(existing._pending_callbacks, callback)
    end
    return
  end

  local handler, kill_terminals, cancel_permission = client_handlers.create(config)

  local connection = {
    sessions = {},
    kill_terminals = kill_terminals,
    cancel_permission = cancel_permission,
    active_prompts = {},
    _streams = {},
    initialized = false,
    _pending_callbacks = { callback },
  }

  connections[key] = connection

  -- callbacks first: terminating fails the pending requests, whose callbacks end up here again
  local function fail(err)
    finish_connection_callbacks(connection, err)
    if connections[key] == connection then
      connections[key] = nil
    end
    if connection.rpc then
      connection.rpc.terminate()
    end
  end

  -- vim.system throws on spawn failure (e.g. missing binary or cwd)
  local ok_start, rpc_client = pcall(rpc.start, build_command(config, model), {
    on_exit = function(code)
      logger.info("ACP agent exited (" .. tostring(code) .. ") for " .. key)
      kill_terminals()
      -- Only clear the registry slot if it still points at this connection;
      -- a replacement may already have been created after terminate().
      if connections[key] == connection then
        connections[key] = nil
      end
    end,
    notification = function(method, params)
      if method ~= "session/update" then
        return
      end

      local update = params.update or {}
      local kind = update.sessionUpdate
      local stream = connection._streams[params.sessionId]

      if stream and (kind == "agent_message_chunk" or (kind == "agent_thought_chunk" and config.show_thoughts)) then
        local text = vim.tbl_get(update, "content", "text")
        if text then
          stream(text)
        end
      elseif kind == "available_commands_update" then
        connection.slash_commands = vim.tbl_map(function(cmd)
          return { name = cmd.name, description = cmd.description, hint = cmd.input and cmd.input.hint }
        end, update.availableCommands or {})
        if connection._slash_commands_ready then
          connection._slash_commands_ready()
        end
      end
    end,
    server_request = handler,
  })
  if not ok_start then
    fail("Could not start ACP agent: " .. tostring(rpc_client))
    return
  end
  connection.rpc = rpc_client

  -- a hung initialize/authenticate (e.g. login prompt) would otherwise queue every prompt forever
  vim.defer_fn(function()
    if not connection.initialized and connection._pending_callbacks then
      fail("ACP agent did not initialize in time (check `grok login`)")
    end
  end, M.INIT_TIMEOUT_MS)

  connection.rpc.request("initialize", {
    protocolVersion = 1,
    clientCapabilities = {
      fs = { readTextFile = true, writeTextFile = true },
      terminal = true,
    },
    clientInfo = {
      name = "parrot.nvim",
      title = "parrot.nvim",
      version = "1.0.0",
    },
  }, function(err, result)
    if err then
      fail(M.format_rpc_error(err))
      return
    end

    local method_id, auth_err = M.resolve_auth_method_id(result, config)
    if not method_id then
      fail(auth_err)
      return
    end

    connection.rpc.request("authenticate", { methodId = method_id }, function(auth_rpc_err)
      if auth_rpc_err then
        fail(M.format_rpc_error(auth_rpc_err))
        return
      end
      connection.initialized = true
      connection.load_session = vim.tbl_get(result, "agentCapabilities", "loadSession") == true
      connection.can_close = vim.tbl_get(result, "agentCapabilities", "sessionCapabilities", "close") ~= nil
      finish_connection_callbacks(connection, nil)
    end)
  end)
end

---Send a prompt and stream agent message chunks.
---Command prompts run in a fresh session. Chat prompts (opts.session_key = chat file) reuse the
---chat's session and only send the messages it has not seen yet; if the buffer history diverged
---(edited, other chat), a new session gets the full transcript. opts.raw sends the messages as-is
---(slash commands) into the chat's session without touching its history.
---@param config table
---@param opts table
function M.prompt(config, opts)
  local model = opts.model or config.model or (config.models and config.models[1])
  local kind = opts.session_kind or "command"
  local cwd = opts.cwd or vim.fn.getcwd()
  local qid = opts.qid
  local state = opts.state
  local chat_key = kind == "chat" and state and opts.session_key

  local function done(err, result)
    if qid then
      cancelled_qids[qid] = nil
    end
    if err and opts.on_error then
      opts.on_error(err)
    end
    if opts.on_done then
      opts.on_done(result)
    end
  end

  M.get_connection(config, model, function(err, connection)
    if err then
      done(err)
      return
    end

    local messages = opts.messages or {}
    local stored = chat_key and state:get_acp_session(config.name, chat_key)
    local entry = stored
    if not opts.raw then
      entry = M.continued_entry(stored, messages)
      -- a stopped turn may still be finishing in that session: continue the chat in a new one
      if entry and connection._streams[entry.id] then
        entry = nil
      end
    end

    local system = messages[1] and messages[1].role == "system" and messages[1].content or nil
    -- slash commands (raw) need the full agent even outside chats
    local tool_free = kind == "command" and not opts.raw
    open_session(config, connection, tool_free, cwd, entry, system, function(session_err, session_id)
      if session_err then
        done(session_err)
        return
      end

      if stored and stored.id ~= session_id then
        discard_session(connection, stored.id) -- replaced by a new session
      end
      local resumed = entry and entry.id == session_id
      -- one-shot sessions are deleted after the prompt: commands, and slash commands without a chat session
      local one_shot = kind == "command" or (opts.raw and not resumed)
      local to_send = messages
      if resumed and not opts.raw then
        to_send = vim.list_slice(messages, entry.n + 1)
      end
      local prompt_blocks = M.messages_to_prompt(to_send)
      local cancelled_early = qid and cancelled_qids[qid]
      if #prompt_blocks == 0 or cancelled_early then
        -- a new session that never got its prompt is useless; the chat's old one was discarded above
        if not resumed then
          discard_session(connection, session_id)
          if chat_key and not opts.raw then
            state:set_acp_session(config.name, chat_key, nil)
          end
        end
        done(nil, cancelled_early and { stopReason = "cancelled" } or nil)
        return
      end

      -- e.g. a slash command while the chat's turn still runs would take over its stream
      if connection._streams[session_id] then
        done("ACP session is busy, wait for the running prompt to finish")
        return
      end

      if qid then
        connection.active_prompts[qid] = { session_id = session_id }
      end

      local response = {}
      local stream = function(text)
        table.insert(response, text)
        if opts.on_chunk then
          opts.on_chunk(text)
        end
      end
      connection._streams[session_id] = stream

      connection.rpc.request("session/prompt", {
        sessionId = session_id,
        prompt = prompt_blocks,
      }, function(prompt_err, result)
        if qid then
          connection.active_prompts[qid] = nil
        end
        if connection._streams[session_id] == stream then
          connection._streams[session_id] = nil
        end

        local cancelled = result and result.stopReason == "cancelled"
        if cancelled then
          logger.info("ACP prompt cancelled")
        end

        -- Remember what the chat session has seen; drop it after errors so the next prompt starts clean.
        if chat_key and not opts.raw then
          local new_entry = nil
          if not prompt_err and not cancelled then
            local seen = vim.list_extend(vim.list_slice(messages), {
              { role = "assistant", content = table.concat(response) },
            })
            new_entry = { id = session_id, n = #seen, hash = M.history_hash(seen, #seen) }
          end
          -- a stopped turn finishing late must not clear the session that replaced it
          local current = state:get_acp_session(config.name, chat_key)
          if new_entry or (current and current.id == session_id) then
            state:set_acp_session(config.name, chat_key, new_entry)
          end
          if not new_entry then
            discard_session(connection, session_id) -- the next prompt starts a new one
          end
        end

        if one_shot then
          discard_session(connection, session_id)
        end
        done(prompt_err and M.format_rpc_error(prompt_err), result)
      end)
    end)
  end)
end

---Delete a stored session of a deleted chat from the agent's history (`grok sessions delete <id>`).
---Runs without an agent connection; other agents have no such CLI command and keep theirs.
---@param config table Provider config
---@param session_id string
function M.delete_stored_session(config, session_id)
  local cli = vim.deepcopy(config.cli_command or { (config.command or { "grok" })[1] })
  if vim.fs.basename(cli[1]) ~= "grok" or vim.fn.executable(cli[1]) ~= 1 then
    return
  end
  vim.list_extend(cli, { "sessions", "delete", session_id })
  vim.system(cli, { text = true })
end

---Cancel a prompt. If it has not been sent yet (still connecting or opening its session),
---it is remembered and M.prompt skips sending it.
---@param qid string
function M.cancel(qid)
  for _, connection in pairs(connections) do
    local active = connection.active_prompts[qid]
    if active then
      connection.rpc.notify("session/cancel", {
        sessionId = active.session_id,
      })
      connection.cancel_permission(active.session_id)
      connection.active_prompts[qid] = nil
      return
    end
  end
  cancelled_qids[qid] = true
end

---Terminate every active ACP connection (e.g. on Neovim exit).
function M.terminate_all()
  for key, connection in pairs(connections) do
    connection.kill_terminals() -- on_exit may not get to run while Neovim exits
    connection.rpc.terminate()
    connections[key] = nil
  end
end

---Slash commands of the agent process of config.model, nil until the agent sent them.
---@param config table
---@return table[]|nil # { name, description, hint }[]
function M.slash_commands(config)
  local connection = connections[connection_key(config, config.model)]
  return connection and connection.slash_commands
end

---Learn the slash commands of the agent process of config.model: the agent advertises them via
---available_commands_update after session/new, so a throwaway session is opened if needed.
---@param config table
---@param callback fun(err: string?, commands: table[]?)
function M.load_slash_commands(config, callback)
  M.get_connection(config, config.model, function(err, connection)
    if err or connection.slash_commands then
      callback(err, connection and connection.slash_commands)
      return
    end
    -- concurrent loads (e.g. repeated <Tab>) share one throwaway session
    if connection._slash_waiters then
      table.insert(connection._slash_waiters, callback)
      return
    end
    connection._slash_waiters = { callback }

    local function finish(session_id, load_err)
      local waiters = connection._slash_waiters
      if not waiters then
        return
      end
      connection._slash_waiters, connection._slash_commands_ready = nil, nil
      if session_id then
        discard_session(connection, session_id)
      end
      for _, cb in ipairs(waiters) do
        cb(load_err, connection.slash_commands)
      end
    end

    create_session(config, connection, false, vim.fn.getcwd(), nil, function(session_err, session_id)
      if session_err or connection.slash_commands then
        finish(session_id, session_err)
        return
      end
      connection._slash_commands_ready = function()
        finish(session_id)
      end
      vim.defer_fn(function()
        finish(session_id, "timed out waiting for the slash commands")
      end, 15000)
    end)
  end)
end

return M
