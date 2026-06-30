---User-facing ACP helpers: slash commands, session modes, tab completion.
local acp_client = require("parrot.acp.client")
local logger = require("parrot.logger")

local M = {}

---Grok session toggles (Grok does not advertise ACP session modes over stdio).
M.GROK_TOGGLES = {
  {
    id = "always-approve-on",
    name = "Always approve",
    description = "Skip permission prompts",
    slash = "/always-approve on",
  },
  {
    id = "always-approve-off",
    name = "Ask permission",
    description = "Prompt before each tool call",
    slash = "/always-approve off",
  },
}

---@param config table
---@return boolean
local function is_grok_config(config)
  local cmd = config.command or { "grok", "agent", "stdio" }
  return cmd[1] == "grok"
end

---@param parrot table
---@return table|nil ctx
function M.get_context(parrot)
  if not parrot.chat_handler then
    return nil
  end

  local buf = vim.api.nvim_get_current_buf()
  local acp_sessions = require("parrot.acp.sessions")
  local scope = acp_sessions.session_scope(buf, parrot.options.chat_dir, parrot.chat_handler.state)
  local is_chat = scope.is_chat_buf
  local prov = parrot.chat_handler:get_provider(is_chat)

  if not prov or not prov.is_acp or not prov:is_acp() then
    return nil
  end

  local model_obj = parrot.chat_handler:get_model(scope.kind)
  if not model_obj or not model_obj.name then
    return nil
  end

  local config = prov:get_runtime_config()
  config._acp_cwd = scope.cwd
  config._slash_cache_state = parrot.chat_handler.state

  return {
    parrot = parrot,
    prov = prov,
    config = config,
    model_obj = model_obj,
    is_chat = is_chat,
    scope = scope,
    buf = buf,
    win = vim.api.nvim_get_current_win(),
  }
end

---@param config table
---@param callback? fun(version: string)
---@return string|nil
function M.cli_version_hash(config, callback)
  return acp_client.fetch_cli_version(config.cli_command or { (config.command or { "grok" })[1] }, callback)
end

---Resolve CLI version from state cache, fetching only when unknown.
-- Supports callback for non-blocking: if cb provided and cache miss, async fetch then cb+save.
---@param state table
---@param config table
---@param provider_name string
---@param callback? fun(version: string)
---@return string|nil
function M.resolve_cli_version(state, config, provider_name, callback)
  local version = state:get_cli_version_hash(provider_name)
  if version and version ~= "" then
    if callback then callback(version) end
    return version
  end
  if callback then
    local u = require("parrot.utils")
    u.check_internet(function(online)
      if not online then
        callback("")
        return
      end
      M.cli_version_hash(config, function(v)
        if v and v ~= "" then
          state:set_cli_version_hash(provider_name, v)
          state:save()
        end
        callback(v or "")
      end)
    end)
    return nil
  end
  local u = require("parrot.utils")
  if not u.has_internet(1200) then
    return ""
  end
  version = M.cli_version_hash(config)
  if version ~= "" then
    state:set_cli_version_hash(provider_name, version)
    state:save()
  end
  return version
end

---Load persisted slash commands into runtime config (no CLI/version I/O).
---@param state table
---@param config table
---@param provider_name string
---@param cache_expiry_hours number
function M.preload_slash_cache_from_state(state, config, provider_name, cache_expiry_hours)
  local entry = state:get_slash_commands_cache_entry(provider_name, cache_expiry_hours, nil, false)
  if entry and entry.commands then
    config._slash_commands_cache = entry.commands
    config._slash_commands_complete = entry.complete == true
  end
end

---@param parrot table
---@param ctx table
---@return boolean
function M.is_slash_cache_complete(parrot, ctx)
  if ctx.config._slash_commands_complete then
    return true
  end
  if not parrot.chat_handler or not parrot.chat_handler.state then
    return false
  end
  local entry = parrot.chat_handler.state:get_slash_commands_cache_entry(
    ctx.prov.name,
    parrot.options.model_cache_expiry_hours,
    nil,
    true
  )
  return entry ~= nil
end

---Schedule a background refresh when only the partial initialize-time list is cached.
---@param parrot table
---@param ctx table
function M.schedule_slash_cache_refresh(parrot, ctx)
  if ctx.config._slash_refresh_scheduled or M.is_slash_cache_complete(parrot, ctx) then
    return
  end
  if not parrot.chat_handler or not parrot.chat_handler.state then
    return
  end

  ctx.config._slash_refresh_scheduled = true
  vim.schedule(function()
    ctx.config._slash_refresh_scheduled = nil
    M.refresh_slash_commands_cache(
      parrot.chat_handler.state,
      ctx.config,
      ctx.prov.name,
      parrot.options.model_cache_expiry_hours,
      function() end
    )
  end)
end

---@param parrot table
---@param ctx table
---@return table[]
function M.load_runtime_slash_cache(parrot, ctx)
  if ctx.config._slash_commands_cache and #ctx.config._slash_commands_cache > 0 then
    return ctx.config._slash_commands_cache
  end

  if not parrot.chat_handler or not parrot.chat_handler.state then
    return {}
  end

  M.preload_slash_cache_from_state(
    parrot.chat_handler.state,
    ctx.config,
    ctx.prov.name,
    parrot.options.model_cache_expiry_hours
  )

  return ctx.config._slash_commands_cache or {}
end

---Refresh slash commands from the ACP agent when state cache is stale.
-- When callback given, version resolve + warm are non-blocking.
---@param state table
---@param config table
---@param provider_name string
---@param cache_expiry_hours number
---@param callback? fun(err: string?, commands: table[]?)
function M.refresh_slash_commands_cache(state, config, provider_name, cache_expiry_hours, callback)
  local has_cb = type(callback) == "function"
  callback = callback or function() end
  local function proceed(version)
    config._slash_cache_state = state
    config.name = config.name or provider_name
    config._cli_version_hash = version ~= "" and version or nil
    if state:is_slash_commands_cache_valid(provider_name, cache_expiry_hours, version) then
      local entry = state:get_slash_commands_cache_entry(provider_name, cache_expiry_hours, version, true)
      config._slash_commands_cache = entry and entry.commands or {}
      config._slash_commands_complete = true
      callback(nil, config._slash_commands_cache)
      return
    end
    local cli = (config.command or { "grok" })[1]
    if vim.fn.executable(cli) ~= 1 then
      callback("ACP command not executable: " .. cli)
      return
    end
    acp_client.warm_session_cache(config, function(err)
      local commands = config._slash_commands_cache or {}
      if #commands > 0 and version ~= "" and config._slash_commands_complete then
        state:set_cached_slash_commands(provider_name, commands, version, true)
        state:save()
      end
      callback(err, commands)
    end)
  end
  if has_cb then
    M.resolve_cli_version(state, config, provider_name, function(v)
      proceed(v or "")
    end)
    return
  end
  local sync_version = M.resolve_cli_version(state, config, provider_name)
  proceed(sync_version or "")
end

---@param config table
---@return table[]
function M.cached_slash_commands(config)
  return config._slash_commands_cache or {}
end

---@param config table
---@return table[]
function M.cached_modes(config)
  local modes = config._session_modes_cache
  if modes and #modes > 0 then
    return modes
  end
  if is_grok_config(config) then
    return M.GROK_TOGGLES
  end
  return {}
end

---@param config table
---@return string|nil
function M.current_mode_id(config)
  return config._current_mode_id
end

---Numbered fzf entries (same approach as fzf-lua ui_select).
---@param items string[]
---@return string[]
local function numbered_fzf_entries(items)
  local entries = {}
  local num_width = math.max(1, math.ceil(math.log10(#items)))
  local num_format = "%" .. num_width .. "d"

  local magenta = function(text)
    local ok, utils = pcall(require, "fzf-lua.utils")
    if ok and utils.ansi_codes and utils.ansi_codes.magenta then
      return utils.ansi_codes.magenta(text)
    end
    return text
  end

  for i, item in ipairs(items) do
    table.insert(entries, string.format("%s. %s", magenta(string.format(num_format, i)), item))
  end
  return entries
end

---@param selected string[]
---@param opts table
local function fzf_accept_item(selected, opts)
  if not selected or #selected == 0 then
    return
  end
  local idx = tonumber((selected[1] or ""):match("^%s*(%d+)%."))
  local choice = idx and opts._items and opts._items[idx]
  if opts._on_choice then
    opts._on_choice(choice)
  end
end

---@param items string[]
---@param prompt string
---@param on_select fun(choice: string|nil)
local function pick_list_fzf(items, prompt, on_select)
  local fzf_lua = require("fzf-lua")
  local fzf_actions = require("fzf-lua.actions")

  -- Forward-declare: callbacks must not close over `opts` during `{ ... }` construction
  -- (Lua locals are not in scope until the assignment finishes — `opts` would be nil).
  local opts = {}
  opts.prompt = prompt:gsub(":%s?$", "> ")
  opts.previewer = false
  opts.no_hide = true
  opts._items = items
  opts._on_choice = function(choice)
    opts._on_choice_called = true
    vim.schedule(function()
      on_select(choice)
    end)
  end
  opts.fzf_opts = {
    ["--layout"] = "reverse",
    ["--info"] = "inline",
    ["--no-multi"] = true,
    ["--preview-window"] = "hidden:right:0",
  }
  opts.winopts = {
    preview = { hidden = true },
  }
  opts.actions = {
    ["default"] = { fn = fzf_accept_item, desc = "accept-item" },
    ["enter"] = { fn = fzf_accept_item, desc = "accept-item" },
  }
  opts.fn_selected = function(selected, o)
    local function exec_choice()
      if not selected then
        on_select(nil)
        return
      end
      o._on_choice_called = nil
      fzf_actions.act(selected, o)
      if not o._on_choice_called then
        on_select(nil)
      end
    end

    if o.__CTX and o.__CTX.mode == "i" then
      vim.cmd([[noautocmd lua vim.api.nvim_feedkeys('i', 'n', true)]])
      vim.api.nvim_create_autocmd("ModeChanged", {
        pattern = "*:i*",
        once = true,
        callback = exec_choice,
      })
    else
      exec_choice()
    end
  end

  fzf_lua.fzf_exec(numbered_fzf_entries(items), opts)
end

---@param items string[]
---@param prompt string
---@param _options table Reserved for future picker configuration.
---@param on_select fun(choice: string|nil)
local function pick_list(items, prompt, _options, on_select)
  if #items == 0 then
    on_select(nil)
    return
  end

  local has_fzf = pcall(require, "fzf-lua")
  if has_fzf then
    pick_list_fzf(items, prompt, on_select)
    return
  end

  vim.ui.select(items, { prompt = prompt }, function(choice)
    vim.schedule(function()
      on_select(choice)
    end)
  end)
end

---@param parrot table
---@param text string Slash command text (with or without leading /).
function M.run_slash_command(parrot, text)
  local ctx = M.get_context(parrot)
  if not ctx then
    logger.error("Current provider does not support ACP slash commands")
    return
  end

  if not text or text == "" then
    return
  end

  if not text:match("^/") then
    text = "/" .. text
  end

  local utils = require("parrot.utils")
  local ResponseHandler = require("parrot.response_handler")
  local target_buf, target_win = ctx.buf, ctx.win

  if ctx.scope.kind == "command" then
    target_buf, target_win = parrot.ui.create_popup(
      nil,
      "ACP slash command (close with <esc>)",
      function(w, h)
        return math.min(w - 4, 120), math.min(h - 4, 30), 2, 2
      end,
      { on_leave = true, escape = true },
      { border = parrot.options.style_popup_border or "single" }
    )
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = target_buf })
  end

  local spinner = parrot.options.enable_spinner and require("parrot.spinner"):new(parrot.options.spinner_type)
  if spinner then
    spinner:start("ACP command...", false)
  end

  local handler = ResponseHandler:new(
    parrot.chat_handler.queries,
    target_buf,
    target_win,
    ctx.scope.is_chat_buf and utils.last_content_line(target_buf) or 0,
    true,
    "",
    false,
    spinner
  ):create_handler()

  parrot.chat_handler:acp_query(target_buf, ctx.prov, {
    model = ctx.model_obj.name,
    messages = { { role = "user", content = text } },
  }, handler, vim.schedule_wrap(function()
    if spinner then
      spinner:stop()
    end
  end))
end

---Build Neovim cmdline completion items (word + menu) from slash commands.
---@param commands table[]
---@param lead string
---@return table[]
local function command_completion_items(commands, lead)
  local results = {}
  lead = (lead or ""):gsub("^/*", ""):lower()

  for _, cmd in ipairs(commands) do
    local name = cmd.name or ""
    if lead == "" or vim.startswith(name:lower(), lead) then
      local desc = cmd.description or cmd.hint or ""
      table.insert(results, desc ~= "" and { word = name, menu = desc } or { word = name })
    end
  end

  table.sort(results, function(a, b)
    return a.word < b.word
  end)
  return results
end

---@param parrot table
---@param arg_lead string
---@return table[]
function M.slash_complete(parrot, arg_lead)
  local ctx = M.get_context(parrot)
  if not ctx then
    return {}
  end

  M.schedule_slash_cache_refresh(parrot, ctx)
  return command_completion_items(M.load_runtime_slash_cache(parrot, ctx), arg_lead)
end

---@param parrot table
---@param arg_lead string
---@return table[]
function M.mode_complete(parrot, arg_lead)
  local ctx = M.get_context(parrot)
  if not ctx then
    return {}
  end

  local lead = (arg_lead or ""):lower()
  local results = {}

  for _, mode in ipairs(M.cached_modes(ctx.config)) do
    local id = mode.id or ""
    if lead == "" or vim.startswith(id:lower(), lead) or vim.startswith((mode.name or ""):lower(), lead) then
      local desc = mode.description or ""
      table.insert(results, desc ~= "" and { word = id, menu = desc } or { word = id })
    end
  end

  table.sort(results, function(a, b)
    return a.word < b.word
  end)
  return results
end

---@param parrot table
---@param params table
function M.select_slash_command(parrot, params)
  local ctx = M.get_context(parrot)
  if not ctx then
    logger.error("Current provider does not support ACP slash commands")
    return
  end

  local arg = vim.trim(params.args or "")
  if arg ~= "" then
    M.run_slash_command(parrot, arg)
    return
  end

  local function show_picker(commands)
    if #commands == 0 then
      logger.warning("No slash commands advertised by the ACP agent")
      return
    end

    local labels, by_label = {}, {}
    for _, cmd in ipairs(commands) do
      local hint = cmd.hint and (" — " .. cmd.hint) or ""
      local desc = cmd.description and (" — " .. cmd.description) or ""
      local label = cmd.name .. (hint ~= "" and hint or desc)
      by_label[label] = cmd
      table.insert(labels, label)
    end

    pick_list(labels, "ACP slash command ❯", parrot.options, function(choice)
      if not choice then
        return
      end
      local cmd = by_label[choice]
      if not cmd then
        local name = choice:match("^([%w%-]+)")
        if not name then
          return
        end
        for _, item in ipairs(commands) do
          if item.name == name then
            cmd = item
            break
          end
        end
      end
      if not cmd then
        return
      end
      local name = cmd.name
      if cmd.hint then
        vim.ui.input({ prompt = "/" .. name .. " ", default = "" }, function(input)
          local text = "/" .. name
          if input and input:match("%S") then
            text = text .. " " .. input
          end
          M.run_slash_command(parrot, text)
        end)
      else
        M.run_slash_command(parrot, "/" .. name)
      end
    end)
  end

  local spinner = parrot.options.enable_spinner and require("parrot.spinner"):new(parrot.options.spinner_type)

  local function open_picker()
    show_picker(M.load_runtime_slash_cache(parrot, ctx))
  end

  if M.is_slash_cache_complete(parrot, ctx) then
    open_picker()
    return
  end

  if spinner then
    spinner:start("Loading ACP slash commands...", false)
  end

  M.refresh_slash_commands_cache(
    parrot.chat_handler.state,
    ctx.config,
    ctx.prov.name,
    parrot.options.model_cache_expiry_hours,
    function(err, refreshed)
      if spinner then
        spinner:stop()
      end
      if err then
        logger.warning("Failed to load slash commands: " .. tostring(err))
      end
      open_picker()
      if refreshed and #refreshed == 0 then
        logger.warning("No slash commands advertised by the ACP agent")
      end
    end
  )
end

---@param parrot table
---@param mode table
---@param ctx table
---@param callback fun(err: string?)
local function apply_mode(parrot, mode, ctx, callback)
  if mode.slash then
    ctx.config._current_mode_id = mode.id
    M.run_slash_command(parrot, mode.slash)
    callback(nil)
    return
  end

  local kind = ctx.scope.kind
  acp_client.set_mode(ctx.config, ctx.model_obj.name, kind, mode.id, function(err)
    if not err then
      ctx.config._current_mode_id = mode.id
      logger.info("ACP mode set to: " .. mode.name)
    end
    callback(err)
  end)
end

---@param parrot table
---@param params table
function M.select_mode(parrot, params)
  local ctx = M.get_context(parrot)
  if not ctx then
    logger.error("Current provider does not support ACP session modes")
    return
  end

  local arg = vim.trim(params.args or "")
  if arg ~= "" then
    for _, mode in ipairs(M.cached_modes(ctx.config)) do
      if mode.id == arg or mode.name == arg then
        apply_mode(parrot, mode, ctx, function(err)
          if err then
            logger.error("Failed to set ACP mode: " .. tostring(err))
          end
        end)
        return
      end
    end
    logger.error("Unknown mode: " .. arg)
    return
  end

  local modes = M.cached_modes(ctx.config)
  if #modes == 0 then
    logger.warning("No session modes available for this ACP agent")
    return
  end

  local current = M.current_mode_id(ctx.config)
  local labels, by_label = {}, {}
  for _, mode in ipairs(modes) do
    local prefix = mode.id == current and "● " or "○ "
    local desc = mode.description and (" — " .. mode.description) or ""
    local label = prefix .. mode.name .. desc
    by_label[label] = mode
    table.insert(labels, label)
  end

  pick_list(labels, "ACP session mode ❯", parrot.options, function(choice)
    if not choice then
      return
    end
    local mode = by_label[choice]
    if not mode then
      return
    end
    apply_mode(parrot, mode, ctx, function(err)
      if err then
        logger.error("Failed to set ACP mode: " .. tostring(err))
      end
    end)
  end)
end

return M