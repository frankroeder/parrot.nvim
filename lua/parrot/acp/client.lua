local acp_sessions = require("parrot.acp.sessions")
local client_handlers = require("parrot.acp.client_handlers")
local logger = require("parrot.logger")
local protocol = require("parrot.acp.protocol")
local rpc = require("parrot.acp.rpc")

local M = {}

---@class parrot.acp.Connection
---@field rpc parrot.acp.RpcClient
---@field model string
---@field sessions table<string, string>
---@field slash_commands table[]
---@field config_options table[]
---@field modes table|nil
---@field active_prompts table<string, { session_id: string, req_id: number? }>
---@field _streams table<string, fun(text: string)> Per-session streaming callbacks
---@field initialized boolean

local connections = {}
local warm_inflight = {}

---@param kind string
---@param cwd string
---@return string
local function session_cache_key(kind, cwd)
  return kind .. ":" .. acp_sessions.repo_key(cwd)
end

---@param config table
---@return string
local function resolve_session_cwd(config)
  return config._acp_cwd or config.cwd or vim.fn.getcwd()
end

local function parse_models_from_init(result)
  local models = {}
  local available = vim.tbl_get(result, "_meta", "modelState", "availableModels")
      or vim.tbl_get(result, "models", "availableModels")
  if available then
    for _, item in ipairs(available) do
      local id = item.modelId or item.id or item.value
      if id then
        table.insert(models, id)
      end
    end
  end
  return models
end

local function parse_models_from_session(result)
  local models = {}
  local available = vim.tbl_get(result, "models", "availableModels")
  if available then
    for _, item in ipairs(available) do
      local id = item.modelId or item.id
      if id then
        table.insert(models, id)
      end
    end
  end
  return models
end

---Normalize ACP slash commands (vim.json decodes JSON null as vim.NIL userdata).
---@param commands table[]|table|nil
---@return table[]
function M.normalize_slash_commands(commands)
  if not commands then
    return {}
  end

  local normalized = {}
  local seen = {}

  local function add(cmd)
    if type(cmd) ~= "table" or not cmd.name or seen[cmd.name] then
      return
    end
    seen[cmd.name] = true
    local hint = nil
    if type(cmd.input) == "table" and cmd.input.hint and cmd.input.hint ~= vim.NIL then
      hint = tostring(cmd.input.hint)
    end
    table.insert(normalized, {
      name = tostring(cmd.name),
      description = cmd.description and tostring(cmd.description) or nil,
      hint = hint,
    })
  end

  if type(commands) == "table" then
    for _, cmd in ipairs(commands) do
      add(cmd)
    end
    if #normalized == 0 then
      for _, cmd in pairs(commands) do
        add(cmd)
      end
    end
  end

  return normalized
end

local normalize_slash_commands = M.normalize_slash_commands

local function parse_slash_commands(result)
  return normalize_slash_commands(vim.tbl_get(result, "_meta", "availableCommands"))
end

local function parse_config_options(result)
  local options = vim.tbl_get(result, "configOptions")
  if options then
    return options
  end
  local xai = vim.tbl_get(result, "_meta", "x.ai/sessionConfig", "options")
  if xai then
    local mapped = {}
    for _, item in ipairs(xai) do
      table.insert(mapped, {
        id = item.id,
        name = item.label or item.name or item.id,
        category = item.category,
        currentValue = item.selected and item.id or nil,
        type = "select",
        options = { { value = item.id, name = item.label or item.id } },
      })
    end
    return mapped
  end
  return {}
end

---Fetch CLI version string used to invalidate cached slash commands.
-- If callback provided, runs async and invokes callback(result); never waits.
-- Otherwise sync (for on-demand post-startup use).
---@param cli_command string[]
---@param callback? fun(version: string)
---@return string|nil
function M.fetch_cli_version(cli_command, callback)
  local cmd = vim.deepcopy(cli_command or { "grok" })
  table.insert(cmd, "--version")
  if vim.fn.executable(cmd[1]) ~= 1 then
    if callback then callback("") end
    return ""
  end
  if callback then
    vim.system(cmd, { text = true }, function(res)
      local output = (res and res.stdout) or ""
      local line = output:match("[^\r\n]+")
      local version = line and vim.trim(line) or ""
      -- Deliver on the main loop; downstream callers use vim.fn.
      vim.schedule(function()
        callback(version)
      end)
    end)
    return nil
  end
  local proc = vim.system(cmd, { text = true })
  local result = proc:wait()
  local output = (result and result.stdout) or ""
  local line = output:match("[^\r\n]+")
  return line and vim.trim(line) or ""
end

---Fetch models via `grok models` (or equivalent CLI subcommand).
-- If callback provided, async + cb(models); else sync return.
---@param cli_command string[]
---@param callback? fun(models: string[])
---@return string[]
function M.fetch_models_from_cli(cli_command, callback)
  local cmd = vim.deepcopy(cli_command)
  table.insert(cmd, "models")
  if vim.fn.executable(cmd[1]) ~= 1 then
    if callback then callback({}) end
    return {}
  end
  if callback then
    vim.system(cmd, { text = true }, function(res)
      local output = (res and res.stdout) or ""
      local models = {}
      for line in output:gmatch("[^\r\n]+") do
        local id = line:match("^%s*[%*%-]%s+([%w%.%-]+)")
        if id then table.insert(models, id) end
      end
      vim.schedule(function()
        callback(models)
      end)
    end)
    return {}
  end
  local proc = vim.system(cmd, { text = true })
  local result = proc:wait()
  local output = (result and result.stdout) or ""
  local models = {}
  for line in output:gmatch("[^\r\n]+") do
    local id = line:match("^%s*[%*%-]%s+([%w%.%-]+)")
    if id then table.insert(models, id) end
  end
  return models
end

---Convert OpenAI-style chat messages to ACP prompt blocks.
---@param messages table[]
---@return table[]
function M.messages_to_prompt(messages)
  local blocks = {}
  for _, message in ipairs(messages) do
    local role = message.role
    local content = message.content or ""
    if content:match("%S") then
      if role == "system" then
        table.insert(blocks, {
          type = "text",
          text = "System instructions:\n" .. content,
        })
      else
        table.insert(blocks, {
          type = "text",
          text = content,
        })
      end
    end
  end
  return blocks
end

---@param config table Provider config
---@param model string|nil
---@return string
local function connection_key(config, model)
  local cmd = config.command or { "grok", "agent", "stdio" }
  local extras = config.args or {}
  local model_id = model or config.model or (config.models and config.models[1]) or "default"
  return table.concat(cmd, " ") .. "|" .. table.concat(extras, " ") .. "|" .. model_id
end

local SUBCOMMANDS = { stdio = true, headless = true, serve = true, leader = true }

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

---Pick an auth method from initialize authMethods (xAI ACP headless flow).
---Prefer the agent-advertised default (Grok: cached_token). Preferring XAI_API_KEY when both
---exist causes 401s on cli-chat-proxy for OIDC-session models (composer, etc.).
---@param init_result table
---@param config table
---@return string|nil method_id
---@return string|nil error
function M.resolve_auth_method_id(init_result, config)
  local advertised = {}
  for _, method in ipairs(init_result.authMethods or {}) do
    if method.id then
      advertised[method.id] = true
    end
  end

  if config.auth_method then
    if advertised[config.auth_method] then
      return config.auth_method
    end
    return nil, "auth method not advertised: " .. config.auth_method
  end

  -- Agent default (e.g. Grok _meta.defaultAuthMethodId = "cached_token")
  local default_id = vim.tbl_get(init_result, "_meta", "defaultAuthMethodId")
  if default_id and advertised[default_id] then
    return default_id
  end

  if advertised["cached_token"] then
    return "cached_token"
  end

  local api_key = vim.tbl_get(config, "env", "XAI_API_KEY") or os.getenv("XAI_API_KEY")
  if api_key and api_key ~= "" and advertised["xai.api_key"] then
    return "xai.api_key"
  end

  return nil, "Run `grok login` first, or set XAI_API_KEY."
end

---Insert agent flags before the subcommand (e.g. `grok agent -m MODEL stdio`).
---@param cmd string[]
---@param flags string[]
---@return string[]
local function insert_before_subcommand(cmd, flags)
  if #flags == 0 then
    return cmd
  end
  local insert_at = #cmd + 1
  for i = #cmd, 1, -1 do
    if SUBCOMMANDS[cmd[i]] then
      insert_at = i
    end
  end
  for i = #flags, 1, -1 do
    table.insert(cmd, insert_at, flags[i])
  end
  return cmd
end

---@param config table
---@param model string|nil
---@return string[]
local function build_command(config, model)
  local cmd = vim.deepcopy(config.command or { "grok", "agent", "stdio" })
  local flags = {}

  for _, arg in ipairs(config.args or {}) do
    table.insert(flags, arg)
  end

  if model then
    table.insert(flags, config.model_flag or "-m")
    table.insert(flags, model)
  end

  if config.always_approve then
    table.insert(flags, "--always-approve")
  end

  if config.no_auto_update then
    -- Global CLI flag: goes right after the binary (grok --no-auto-update agent stdio).
    table.insert(cmd, 2, "--no-auto-update")
  end

  insert_before_subcommand(cmd, flags)
  return cmd
end

---@param connection parrot.acp.Connection
---@param config table
---@param result table
local function apply_session_result(connection, config, result)
  local session_models = parse_models_from_session(result)
  if #session_models > 0 then
    config._runtime_models = session_models
  end

  local options = parse_config_options(result)
  if #options > 0 then
    connection.config_options = options
  end

  if result.modes then
    connection.modes = result.modes
  end

  local session_commands = result.availableCommands or vim.tbl_get(result, "_meta", "availableCommands")
  if session_commands then
    local commands = normalize_slash_commands(session_commands)
    if #commands > 0 then
      connection.slash_commands = commands
      connection.slash_commands_complete = true
    end
  end
end

---@param config table
---@param connection parrot.acp.Connection
---@param kind string
---@param cwd string
---@param session_opts table|nil
---@param callback fun(err: string?, session_id: string?)
local function create_session(config, connection, kind, cwd, session_opts, callback)
  connection.rpc.request(protocol.agent.session_new, {
    cwd = cwd,
    mcpServers = config.mcp_servers or {},
  }, function(err, result)
    if err then
      callback(M.format_rpc_error(err))
      return
    end
    if not result or not result.sessionId then
      callback("session/new returned no sessionId")
      return
    end

    connection.sessions[session_cache_key(kind, cwd)] = result.sessionId
    apply_session_result(connection, config, result)

    if session_opts and session_opts.state and config.name then
      acp_sessions.save_id(session_opts.state, config.name, kind, cwd, result.sessionId)
    end

    callback(nil, result.sessionId)
  end)
end

---@param config table
---@param connection parrot.acp.Connection
---@param kind string "chat" or "command"
---@param cwd string
---@param session_opts table|nil { state?: table }
---@param callback fun(err: string?, session_id: string?)
local function ensure_session(config, connection, kind, cwd, session_opts, callback)
  local cache_key = session_cache_key(kind, cwd)
  if connection.sessions[cache_key] then
    callback(nil, connection.sessions[cache_key])
    return
  end

  local resume = config.resume_session ~= false
  local persisted = resume and acp_sessions.get_id(session_opts and session_opts.state, config.name, kind, cwd)

  if connection.load_session and persisted then
    connection.rpc.request(protocol.agent.session_load, {
      sessionId = persisted,
      cwd = cwd,
      mcpServers = config.mcp_servers or {},
    }, function(err, result)
      if err or not result then
        logger.info("ACP session/load failed, creating new session: " .. tostring(err and err.message or err))
        create_session(config, connection, kind, cwd, session_opts, callback)
        return
      end

      connection.sessions[cache_key] = persisted
      apply_session_result(connection, config, result)

      if session_opts and session_opts.state and config.name then
        acp_sessions.save_id(session_opts.state, config.name, kind, cwd, persisted)
      end

      logger.debug("ACP resumed session " .. persisted .. " for " .. kind)
      callback(nil, persisted)
    end)
    return
  end

  create_session(config, connection, kind, cwd, session_opts, callback)
end

---Cache slash commands and modes on the provider runtime config.
---@param config table
---@param connection parrot.acp.Connection
local function cache_session_state(config, connection)
  config._slash_commands_cache = connection.slash_commands
  config._slash_commands_complete = connection.slash_commands_complete == true
  if connection.modes and connection.modes.availableModes then
    config._session_modes_cache = connection.modes.availableModes
    config._current_mode_id = connection.modes.currentModeId
  end
end

---@param config table
---@param connection parrot.acp.Connection
local function persist_slash_commands_cache(config, connection)
  if not config._slash_cache_state or not config.name then
    return
  end
  if not connection.slash_commands_complete or #connection.slash_commands == 0 then
    return
  end
  if not config._cli_version_hash or config._cli_version_hash == "" then
    return
  end

  config._slash_cache_state:set_cached_slash_commands(
    config.name,
    connection.slash_commands,
    config._cli_version_hash,
    true
  )
  config._slash_cache_state:save()
end

---Get or create an initialized ACP connection.
---@param config table
---@param model string
---@param callback fun(err: string?, connection: parrot.acp.Connection?)
local function finish_connection_callbacks(connection, err)
  local callbacks = connection._pending_callbacks or {}
  connection._pending_callbacks = nil
  for _, cb in ipairs(callbacks) do
    cb(err, err and nil or connection)
  end
end

function M.get_connection(config, model, callback)
  local key = connection_key(config, model)
  local existing = connections[key]
  if existing then
    if existing.initialized then
      callback(nil, existing)
      return
    end
    existing._pending_callbacks = existing._pending_callbacks or {}
    table.insert(existing._pending_callbacks, callback)
    return
  end

  local cmd = build_command(config, model)
  if vim.fn.executable(cmd[1]) ~= 1 then
    callback("ACP command not executable: " .. cmd[1])
    return
  end

  local handler = client_handlers.create({
    always_approve = config.always_approve,
  })

  local connection = {
    model = model,
    config = config,
    sessions = {},
    slash_commands = {},
    config_options = {},
    modes = nil,
    active_prompts = {},
    _streams = {},
    initialized = false,
    _pending_callbacks = { callback },
  }

  connections[key] = connection

  connection.rpc = rpc.start(cmd, {
    on_error = function(_, err)
      logger.error("ACP connection error: " .. tostring(err))
    end,
    on_exit = function(code)
      logger.info("ACP agent exited (" .. tostring(code) .. ") for " .. key)
      connection._streams = {}
      connection.active_prompts = {}
      -- Only clear the registry slot if it still points at this connection;
      -- a replacement may already have been created after terminate().
      if connections[key] == connection then
        connections[key] = nil
      end
    end,
    notification = function(method, params)
      if method ~= protocol.client.session_update then
        return
      end

      local update = params.update or {}
      local stream = params.sessionId and connection._streams[params.sessionId]

      if update.sessionUpdate == "agent_message_chunk" and stream then
        local text = vim.tbl_get(update, "content", "text")
        if text then
          stream(text)
        end
      elseif update.sessionUpdate == "agent_thought_chunk" and stream then
        if connection.config and connection.config.show_thoughts then
          local text = vim.tbl_get(update, "content", "text")
          if text then
            stream(text)
          end
        end
      elseif update.sessionUpdate == "available_commands_update" then
        connection.slash_commands = normalize_slash_commands(update.availableCommands)
        connection.slash_commands_complete = true
        if connection.config then
          cache_session_state(connection.config, connection)
          persist_slash_commands_cache(connection.config, connection)
        end
        if connection._slash_warm_cb then
          connection._slash_warm_cb()
        end
      elseif update.sessionUpdate == "config_option_update" then
        connection.config_options = update.configOptions or connection.config_options
      elseif update.sessionUpdate == "current_mode_update" and connection.modes then
        connection.modes.currentModeId = update.modeId or update.currentModeId
      end
    end,
    server_request = function(id, method, params, respond)
      handler(method, params, function(result, error)
        connection.rpc.response(id, result, error)
      end)
    end,
  }, {
    cwd = config.cwd,
    env = config.env,
  })

  connection.rpc.request(protocol.agent.initialize, {
    protocolVersion = protocol.PROTOCOL_VERSION,
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
      connection.rpc.terminate()
      connections[key] = nil
      finish_connection_callbacks(connection, M.format_rpc_error(err))
      return
    end

    local method_id, auth_err = M.resolve_auth_method_id(result, config)
    if not method_id then
      connection.rpc.terminate()
      connections[key] = nil
      finish_connection_callbacks(connection, auth_err)
      return
    end

    local auth_params = { methodId = method_id }
    if config.headless then
      auth_params._meta = { headless = true }
    end

    connection.rpc.request(protocol.agent.authenticate, auth_params, function(auth_rpc_err)
      if auth_rpc_err then
        connection.rpc.terminate()
        connections[key] = nil
        finish_connection_callbacks(connection, M.format_rpc_error(auth_rpc_err))
        return
      end

      connection.initialized = true
      connection.load_session = vim.tbl_get(result, "agentCapabilities", "loadSession") == true
      connection.slash_commands = parse_slash_commands(result)
      connection.config_options = parse_config_options(result)

      local init_models = parse_models_from_init(result)
      if #init_models > 0 then
        config._runtime_models = init_models
      end

      finish_connection_callbacks(connection, nil)
    end)
  end)
end

---Send a prompt and stream agent message chunks.
---@param config table
---@param opts table
function M.prompt(config, opts)
  local model = opts.model or config.model or (config.models and config.models[1])
  local kind = opts.session_kind or "command"
  local cwd = opts.cwd or vim.fn.getcwd()
  local qid = opts.qid

  if opts.state then
    config._slash_cache_state = opts.state
    if config.name then
      local cached_version = opts.state:get_cli_version_hash(config.name)
      if cached_version and cached_version ~= "" then
        config._cli_version_hash = cached_version
      end
    end
  end

  M.get_connection(config, model, function(err, connection)
    if err or not connection then
      if opts.on_error then
        opts.on_error(err or "connection failed")
      end
      if opts.on_done then
        opts.on_done()
      end
      return
    end

    local session_opts = { state = opts.state }
    ensure_session(config, connection, kind, cwd, session_opts, function(session_err, session_id)
      if session_err or not session_id then
        if opts.on_error then
          opts.on_error(session_err or "session failed")
        end
        if opts.on_done then
          opts.on_done()
        end
        return
      end

      local prompt_blocks = opts.prompt or M.messages_to_prompt(opts.messages or {})
      if #prompt_blocks == 0 then
        if opts.on_done then
          opts.on_done()
        end
        return
      end

      if qid then
        connection.active_prompts[qid] = { session_id = session_id }
      end

      local stream = function(text)
        if opts.on_chunk then
          opts.on_chunk(text)
        end
      end
      connection._streams[session_id] = stream

      connection.rpc.request(protocol.agent.session_prompt, {
        sessionId = session_id,
        prompt = prompt_blocks,
      }, function(prompt_err, result)
        if qid then
          connection.active_prompts[qid] = nil
        end
        if connection._streams[session_id] == stream then
          connection._streams[session_id] = nil
        end

        if prompt_err then
          if opts.on_error then
            opts.on_error(M.format_rpc_error(prompt_err))
          end
        elseif result and result.stopReason == "cancelled" then
          logger.info("ACP prompt cancelled")
        end

        if opts.on_done then
          opts.on_done(result)
        end
      end)
    end)
  end)
end

---Cancel an active prompt.
---@param config table
---@param model string
---@param qid string
function M.cancel(config, model, qid)
  local key = connection_key(config, model)
  local connection = connections[key]
  if not connection then
    return
  end

  local active = connection.active_prompts[qid]
  if not active then
    return
  end

  connection.rpc.notify(protocol.agent.session_cancel, {
    sessionId = active.session_id,
  })
  connection.active_prompts[qid] = nil
end

---Terminate all connections for a provider.
---@param config table
function M.terminate_provider(config)
  for key, connection in pairs(connections) do
    if vim.startswith(key, table.concat(config.command or { "grok" }, " ")) then
      connection.rpc.terminate()
      connections[key] = nil
    end
  end
end

---Terminate every active ACP connection (e.g. on Neovim exit).
function M.terminate_all()
  for key, connection in pairs(connections) do
    connection.rpc.terminate()
    connections[key] = nil
  end
end

---Terminate a single model-specific connection.
---@param config table
---@param model string|nil
function M.terminate_connection(config, model)
  local key = connection_key(config, model)
  local connection = connections[key]
  if connection then
    connection.rpc.terminate()
    connections[key] = nil
  end
end

---Warm slash-command and mode caches (for tab completion and pickers).
---ACP advertises the full command list after session creation via available_commands_update.
---@param config table
---@param callback? fun(err: string?)
function M.warm_session_cache(config, callback)
  callback = callback or function() end
  local model = config.model or (config.models and config.models[1])
  local key = connection_key(config, model)

  if warm_inflight[key] then
    table.insert(warm_inflight[key], callback)
    return
  end
  warm_inflight[key] = { callback }

  local function complete_all(warm_err)
    local callbacks = warm_inflight[key] or {}
    warm_inflight[key] = nil
    for _, cb in ipairs(callbacks) do
      cb(warm_err)
    end
  end

  M.get_connection(config, model, function(err, connection)
    if err or not connection then
      complete_all(err)
      return
    end

    connection.config = config
    local settled = false
    local cwd = config.cwd or vim.fn.getcwd()
    local session_opts = config._slash_cache_state and { state = config._slash_cache_state } or nil

    local function finish(warm_err)
      if settled then
        return
      end
      settled = true
      connection._slash_warm_cb = nil
      cache_session_state(config, connection)
      persist_slash_commands_cache(config, connection)
      complete_all(warm_err)
    end

    connection._slash_warm_cb = function()
      if connection.slash_commands_complete then
        finish(nil)
      end
    end

    ensure_session(config, connection, "command", cwd, session_opts, function(sess_err)
      if sess_err then
        finish(sess_err)
        return
      end

      cache_session_state(config, connection)
      if connection.slash_commands_complete then
        finish(nil)
        return
      end

      vim.defer_fn(function()
        if not settled then
          finish("slash command warm timed out")
        end
      end, 15000)
    end)
  end)
end

---Return slash commands for the default connection.
---@param config table
---@param callback fun(commands: table[])
function M.get_slash_commands(config, callback)
  local model = config.model or (config.models and config.models[1])
  M.get_connection(config, model, function(_, connection)
    local commands = connection and connection.slash_commands or {}
    if connection then
      cache_session_state(config, connection)
    end
    callback(commands)
  end)
end

---Set session mode when supported.
---@param config table
---@param model string
---@param kind string
---@param mode_id string
---@param callback fun(err: string?)
function M.set_mode(config, model, kind, mode_id, callback)
  M.get_connection(config, model, function(err, connection)
    if err or not connection then
      callback(err)
      return
    end
    local session_opts = config._slash_cache_state and { state = config._slash_cache_state } or nil
    ensure_session(config, connection, kind, resolve_session_cwd(config), session_opts, function(session_err, session_id)
      if session_err then
        callback(session_err)
        return
      end
      connection.rpc.request(protocol.agent.session_set_mode, {
        sessionId = session_id,
        modeId = mode_id,
      }, function(mode_err)
        if mode_err then
          callback(mode_err.message or vim.inspect(mode_err))
          return
        end
        if not connection.modes then
          connection.modes = {}
        end
        connection.modes.currentModeId = mode_id
        config._current_mode_id = mode_id
        callback(nil)
      end)
    end)
  end)
end

---Try to set a config option (model, mode, etc.).
---@param config table
---@param model string
---@param kind string
---@param config_id string
---@param value string
---@param callback fun(err: string?)
function M.set_config_option(config, model, kind, config_id, value, callback)
  M.get_connection(config, model, function(err, connection)
    if err or not connection then
      callback(err)
      return
    end
    local session_opts = config._slash_cache_state and { state = config._slash_cache_state } or nil
    ensure_session(config, connection, kind, resolve_session_cwd(config), session_opts, function(session_err, session_id)
      if session_err then
        callback(session_err)
        return
      end
      connection.rpc.request(protocol.agent.session_set_config_option, {
        sessionId = session_id,
        configId = config_id,
        value = value,
      }, function(cfg_err)
        if cfg_err then
          callback(cfg_err.message or vim.inspect(cfg_err))
          return
        end
        callback(nil)
      end)
    end)
  end)
end

---@param kind string
---@param cwd string
---@return string
function M.session_cache_key(kind, cwd)
  return session_cache_key(kind, cwd)
end

return M