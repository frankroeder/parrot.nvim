---User-facing ACP helpers: slash commands, permission modes, tab completion.
local acp_client = require("parrot.acp.client")
local acp_sessions = require("parrot.acp.sessions")
local logger = require("parrot.logger")
local Picker = require("parrot.picker")

local M = {}

---Grok permission modes of `:PrtAcpMode` (Grok advertises no ACP session modes).
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

---ACP context of the current buffer, or nil when its provider is not an ACP agent.
---@param parrot table
---@return table|nil ctx
function M.get_context(parrot)
  local buf = vim.api.nvim_get_current_buf()
  local scope = acp_sessions.session_scope(buf, parrot.options.chat_dir, parrot.chat_handler.state)
  local prov = parrot.chat_handler:get_provider(scope.kind == "chat")

  if prov.type ~= "acp" then
    return nil
  end

  local model_obj = parrot.chat_handler:get_model(scope.kind)
  -- warm-ups talk to the agent process of this buffer's model
  prov:set_model(model_obj.name)
  local config = prov:get_runtime_config()
  config._slash_cache_state = parrot.chat_handler.state

  return {
    prov = prov,
    config = config,
    model_obj = model_obj,
    scope = scope,
    buf = buf,
  }
end

---Slash commands cached in state.json, nil until acp_client.warm_session_cache has learned them.
---@param parrot table
---@param ctx table
---@return table[]|nil
local function slash_commands(parrot, ctx)
  return parrot.chat_handler.state:get_cached_slash_commands(ctx.prov.name, parrot.options.model_cache_expiry_hours)
end

---@param config table
---@return table[]
function M.modes(config)
  return vim.fs.basename((config.command or { "grok" })[1]) == "grok" and M.GROK_TOGGLES or {}
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

  local ResponseHandler = require("parrot.response_handler")

  -- Output goes to a popup; in chat buffers the command still runs in the chat's session
  -- (acp_scope_buf) without altering the markdown transcript.
  local target_buf, target_win = parrot.ui.create_popup(nil, "ACP slash command (close with <esc>)", function(w, h)
    return math.min(w - 4, 120), math.min(h - 4, 30), 2, 2
  end, { on_leave = true, escape = true }, { border = parrot.options.style_popup_border or "single" })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = target_buf })

  local spinner = parrot.options.enable_spinner and require("parrot.spinner"):new(parrot.options.spinner_type)
  if spinner then
    spinner:start("ACP command...", false)
  end

  local handler = ResponseHandler:new(parrot.chat_handler.queries, target_buf, target_win, 0, true, "", false, spinner)
    :create_handler()

  parrot.chat_handler:acp_query(
    target_buf,
    ctx.prov,
    {
      model = ctx.model_obj.name,
      messages = { { role = "user", content = text } },
      acp_raw = true,
      acp_scope_buf = ctx.buf,
    },
    handler,
    vim.schedule_wrap(function(qid)
      if spinner then
        spinner:stop()
      end
      -- several commands (e.g. /compact, /context) only act on the session and print nothing over ACP
      local qt = qid and parrot.chat_handler.queries:get(qid)
      if
        qt
        and qt.response == ""
        and not qt.error_occurred
        and not qt.cancelled
        and vim.api.nvim_buf_is_valid(target_buf)
      then
        vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, { text .. " done (the agent sent no output)" })
      end
    end)
  )
end

---Cmdline completion of slash command names (complete functions must return strings).
---@param parrot table
---@param arg_lead string
---@return string[]
function M.slash_complete(parrot, arg_lead)
  local ctx = M.get_context(parrot)
  if not ctx then
    return {}
  end

  local commands = slash_commands(parrot, ctx)
  -- completion must not block: learn the full list in the background for the next <Tab>
  if not commands then
    vim.schedule(function()
      acp_client.warm_session_cache(ctx.config)
    end)
  end

  local lead = (arg_lead or ""):gsub("^/*", ""):lower()
  local results = {}
  for _, cmd in ipairs(commands or {}) do
    if vim.startswith(cmd.name:lower(), lead) then
      table.insert(results, cmd.name)
    end
  end
  table.sort(results)
  return results
end

---@param parrot table
---@param arg_lead string
---@return string[]
function M.mode_complete(parrot, arg_lead)
  local ctx = M.get_context(parrot)
  if not ctx then
    return {}
  end

  local lead = (arg_lead or ""):lower()
  local results = {}

  for _, mode in ipairs(M.modes(ctx.config)) do
    if vim.startswith(mode.id:lower(), lead) or vim.startswith(mode.name:lower(), lead) then
      table.insert(results, mode.id)
    end
  end

  table.sort(results)
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

  local function show_picker()
    local commands = slash_commands(parrot, ctx) or {}
    if #commands == 0 then
      logger.warning("No slash commands advertised by the ACP agent")
      return
    end

    local labels, by_label = {}, {}
    for _, cmd in ipairs(commands) do
      local detail = cmd.hint or cmd.description
      local label = (cmd.name .. (detail and (" — " .. detail) or "")):gsub("\n", " ")
      by_label[label] = cmd
      table.insert(labels, label)
    end

    Picker.select(labels, { prompt = "ACP slash command", fzf_opts = parrot.options.fzf_lua_opts }, function(choice)
      local cmd = by_label[choice]
      if not cmd then
        return
      end
      if cmd.hint then
        vim.ui.input({ prompt = "/" .. cmd.name .. " ", default = "" }, function(input)
          local text = "/" .. cmd.name
          if input and input:match("%S") then
            text = text .. " " .. input
          end
          M.run_slash_command(parrot, text)
        end)
      else
        M.run_slash_command(parrot, "/" .. cmd.name)
      end
    end)
  end

  -- known commands open the picker without starting an agent
  if slash_commands(parrot, ctx) then
    show_picker()
    return
  end

  local spinner = parrot.options.enable_spinner and require("parrot.spinner"):new(parrot.options.spinner_type)
  if spinner then
    spinner:start("Loading ACP slash commands...", false)
  end

  acp_client.warm_session_cache(ctx.config, function(err)
    if spinner then
      spinner:stop()
    end
    if err then
      logger.warning("Failed to load slash commands: " .. tostring(err))
    end
    show_picker()
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

  local function apply(mode)
    -- permission prompts are answered by the client handlers: toggle the provider of both slots
    local always_approve = mode.id == "always-approve-on"
    for _, is_chat in ipairs({ true, false }) do
      local prov = parrot.chat_handler:get_provider(is_chat)
      if prov.name == ctx.prov.name then
        prov:get_runtime_config().always_approve = always_approve
        prov:get_runtime_config()._current_mode_id = mode.id
      end
    end
    acp_client.set_always_approve(ctx.prov.name, always_approve)
    -- the chat's own session is toggled too
    if ctx.scope.kind == "chat" then
      M.run_slash_command(parrot, mode.slash)
    end
    logger.info("ACP mode set to: " .. mode.name)
  end

  local modes = M.modes(ctx.config)
  local arg = vim.trim(params.args or "")
  if arg ~= "" then
    for _, mode in ipairs(modes) do
      if mode.id == arg or mode.name == arg then
        apply(mode)
        return
      end
    end
    logger.error("Unknown mode: " .. arg)
    return
  end

  if #modes == 0 then
    logger.warning("No session modes available for this ACP agent")
    return
  end

  local labels, by_label = {}, {}
  for _, mode in ipairs(modes) do
    local prefix = mode.id == ctx.config._current_mode_id and "● " or "○ "
    local desc = mode.description and (" — " .. mode.description) or ""
    local label = prefix .. mode.name .. desc
    by_label[label] = mode
    table.insert(labels, label)
  end

  Picker.select(labels, { prompt = "ACP session mode", fzf_opts = parrot.options.fzf_lua_opts }, function(choice)
    if by_label[choice] then
      apply(by_label[choice])
    end
  end)
end

return M
