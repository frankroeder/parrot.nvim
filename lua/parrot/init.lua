local config = require("parrot.config")
local utils = require("parrot.utils")
local cutils = require("parrot.config_utils")
local futils = require("parrot.file_utils")
local Pool = require("parrot.pool")
local Queries = require("parrot.queries")
local State = require("parrot.state")
local ui = require("parrot.ui")
local pft = require("plenary.filetype")
local scan = require("plenary.scandir")
local init_provider = require("parrot.provider").init_provider
local Job = require("plenary.job")

local M = {
  _plugin_name = "parrot.nvim",
  providers = {},
  agents = { -- table of agents
    chat = {},
    command = {},
  },
  cmd = {}, -- default command functions
  config = {}, -- config variables
  hooks = {}, -- user defined command functions
  logger = require("parrot.logger"),
  ui = ui,
}
local pool = Pool:new()
local queries = Queries:new()

-- stop receiving responses for all processes and create a new pool
---@param signal number | nil # signal to send to the process
M.cmd.Stop = function(signal)
  if pool:is_empty() then
    return
  end

  for _, process_info in pool:ipairs() do
    if process_info.job.handle ~= nil and not process_info.job.handle:is_closing() then
      vim.loop.kill(process_info.job.pid, signal or 15)
    end
  end

  pool = Pool:new()
end

--------------------------------------------------------------------------------
-- Module helper functions and variables
--------------------------------------------------------------------------------
---

-- setup function
M._setup_called = false
---@param user_opts table | nil # table with options
M.setup = function(user_opts)
  M._setup_called = true

  if type(user_opts) ~= "table" then
    M.logger.error(string.format("setup() expects table, but got %s", type(user_opts)))
    return
  end

  math.randomseed(os.time())

  local default_opts = vim.deepcopy(config)
  local valid_provider_names = vim.tbl_keys(default_opts.providers)

  if not utils.has_valid_key(user_opts.providers, valid_provider_names) then
    M.logger.error("Invalid provider configuration")
    return false
  end

  M.config = vim.tbl_deep_extend("force", default_opts, user_opts)
  M.providers = cutils.merge_providers(default_opts.providers, user_opts.providers)
  local agents = cutils.merge_agents(default_opts.agents or {}, user_opts.agents or {}, M.providers)
  M.agents = cutils.index_agents_by_name(agents)
  M.hooks = M.config.hooks

  -- Create directories for all config entries ending with "_dir"
  for k, v in pairs(M.config) do
    if type(v) == "string" and k:match("_dir$") then
      local dir = v:gsub("/$", "")
      M.config[k] = dir
      vim.fn.mkdir(dir, "p")
    end
  end

  M._available_providers = vim.tbl_keys(M.providers)
  M._available_provider_agents = vim.tbl_map(function()
    return { chat = {}, command = {} }
  end, M.providers)

  for type, agts in pairs(M.agents) do
    for agt_name, agt in pairs(agts) do
      table.insert(M._available_provider_agents[agt.provider][type], agt_name)
    end
  end

  table.sort(M._available_providers)
  table.sort(M._available_provider_agents)

  -- global state
  Pstate = State:new(M.config.state_dir)
  Pstate:refresh(M._available_providers, M._available_provider_agents)
  M.prepare_commands()

  -- register user commands
  for hook, _ in pairs(M.hooks) do
    vim.api.nvim_create_user_command(M.config.cmd_prefix .. hook, function(params)
      M.call_hook(hook, params)
    end, { nargs = "?", range = true, desc = "Parrot LLM plugin" })
  end

  local completions = {
    ChatNew = { "popup", "split", "vsplit", "tabnew" },
    ChatPaste = { "popup", "split", "vsplit", "tabnew" },
    ChatToggle = { "popup", "split", "vsplit", "tabnew" },
    Context = { "popup", "split", "vsplit", "tabnew" },
  }

  -- register default commands
  for cmd, _ in pairs(M.cmd) do
    if M.hooks[cmd] == nil then
      vim.api.nvim_create_user_command(M.config.cmd_prefix .. cmd, function(params)
        M.cmd[cmd](params)
      end, {
        nargs = "?",
        range = true,
        desc = "Parrot LLM plugin",
        complete = function()
          if completions[cmd] then
            return completions[cmd]
          end

          if cmd == "Agent" then
            local buf = vim.api.nvim_get_current_buf()
            local file_name = vim.api.nvim_buf_get_name(buf)
            return M.get_provider_agents(utils.is_chat(buf, file_name, M.config.chat_dir))
          elseif cmd == "Provider" then
            return M._available_providers
          end
          return {}
        end,
      })
    end
  end

  M.buf_handler()

  for _, name in ipairs({ "curl", "grep", "rg", "ln" }) do
    if vim.fn.executable(name) == 0 then
      M.logger.error(name .. " is not installed, run :checkhealth parrot")
    end
  end

  for prov_name, val in pairs(M.providers) do
    if type(val.api_key) == "table" then
      local command = table.concat(val.api_key, " ")
      local handle = io.popen(command)
      if handle then
        M.providers[prov_name].api_key = handle:read("*a"):gsub("%s+", "")
      else
        M.providers[prov_name].api_key = nil
      end
      handle:close()
      local prov = init_provider(prov_name, M.providers[prov_name].endpoint, M.providers[prov_name].api_key)
      if not prov:verify() then
        M.logger.error("Error verifying api key of " .. prov_name)
      end
    end
  end
end

-- creates prompt commands for each target
M.prepare_commands = function()
  for name, target in pairs(ui.Target) do
    -- uppercase first letter
    local command = name:gsub("^%l", string.upper)

    local agent = M.get_command_agent()
    -- popup is like ephemeral one off chat
    if target == ui.Target.popup then
      agent = M.get_chat_agent()
    end

    local cmd = function(params)
      -- template is chosen dynamically based on mode in which the command is called
      local template = M.config.template_command
      if params.range == 2 then
        template = M.config.template_selection
        -- rewrite needs custom template
        if target == ui.Target.rewrite then
          template = M.config.template_rewrite
        end
        if target == ui.Target.append then
          template = M.config.template_append
        end
        if target == ui.Target.prepend then
          template = M.config.template_prepend
        end
      end
      M.Prompt(params, target, agent.cmd_prefix, agent.model, utils.trim(template), agent.system_prompt, agent.provider)
    end

    M.cmd[command] = function(params)
      cmd(params)
    end
  end
end

-- hook caller
M.call_hook = function(name, params)
  if M.hooks[name] ~= nil then
    return M.hooks[name](M, params)
  end
  M.logger.error("The hook '" .. name .. "' does not exist.")
end

-- call the API
---@param buf number | nil # buffer number
---@param provider table
---@param payload table # payload for api
---@param handler function # response handler
---@param on_exit function | nil # optional on_exit handler
M.query = function(buf, provider, payload, handler, on_exit)
  -- make sure handler is a function
  if type(handler) ~= "function" then
    M.logger.error(
      string.format("query() expects a handler function, but got %s:\n%s", type(handler), vim.inspect(handler))
    )
    return
  end

  if not provider:verify() then
    return
  end

  local qid = utils.uuid()
  queries:add(qid, {
    timestamp = os.time(),
    buf = buf,
    provider = provider.name,
    payload = payload,
    handler = handler,
    on_exit = on_exit,
    response = "",
    first_line = -1,
    last_line = -1,
    ns_id = nil,
    ex_id = nil,
  })

  queries:cleanup(8, 60)

  local curl_params = vim.deepcopy(M.config.curl_params or {})
  payload = provider:preprocess_payload(payload)
  local args = {
    "--no-buffer",
    "--silent",
    "-H",
    "accept: application/json",
    "-H",
    "content-type: application/json",
    "-d",
    vim.json.encode(payload),
  }

  for _, arg in ipairs(args) do
    table.insert(curl_params, arg)
  end

  for _, parg in ipairs(provider:curl_params()) do
    table.insert(curl_params, parg)
  end

  local buffer = ""
  local job = Job:new({
    command = "curl",
    args = curl_params,
    on_exit = function(response, exit_code)
      -- print("EXIT RESP", vim.inspect(response:result()))
      if exit_code ~= 0 then
        M.logger.error("An error occured calling curl .. " .. table.concat(curl_params, " "))
        on_exit(qid)
      end
      local result = response:result()
      result = utils.parse_raw_response(result)
      provider:process_onexit(result)

      if response.handle and not response.handle:is_closing() then
        response.handle:close()
      end

      on_exit(qid)
      local qt = queries:get(qid)
      if qt.ns_id and qt.buf then
        vim.schedule(function()
          vim.api.nvim_buf_clear_namespace(qt.buf, qt.ns_id, 0, -1)
        end)
      end
      pool:remove(response.pid)
    end,
    on_stdout = function(_, data)
      -- print("STDOUT RESP", vim.inspect(data))
      local qt = queries:get(qid)
      if not qt then
        return
      end

      local lines = vim.split(data, "\n")
      -- for line in result:gmatch("[^\n]+") do
      for _, line in ipairs(lines) do
        local raw_json = string.gsub(line, "^data:", "")
        local content = provider:process_stdout(raw_json)
        if content then
          qt.response = qt.response .. content
          buffer = buffer .. content
          handler(qid, content)
        end
      end
    end,
  })
  job:start()
  pool:add(job, buf)
end

-- response handler
---@param buf number | nil # buffer to insert response into
---@param win number | nil # window to insert response into
---@param line number | nil # line to insert response into
---@param first_undojoin boolean | nil # whether to skip first undojoin
---@param prefix string | nil # prefix to insert before each response line
---@param cursor boolean # whether to move cursor to the end of the response
M.create_handler = function(buf, win, line, first_undojoin, prefix, cursor)
  buf = buf or vim.api.nvim_get_current_buf()
  prefix = prefix or ""
  local first_line = line or vim.api.nvim_win_get_cursor(win)[1] - 1
  local finished_lines = 0
  local skip_first_undojoin = not first_undojoin

  local hl_handler_group = "PrtHandlerStandout"
  vim.cmd("highlight default link " .. hl_handler_group .. " CursorLine")

  local ns_id = vim.api.nvim_create_namespace("PrtHandler_" .. utils.uuid())

  local ex_id = vim.api.nvim_buf_set_extmark(buf, ns_id, first_line, 0, {
    strict = false,
    right_gravity = false,
  })

  local response = ""
  return vim.schedule_wrap(function(qid, chunk)
    local qt = queries:get(qid)
    if not qt then
      return
    end
    -- if buf is not valid, stop
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    -- undojoin takes previous change into account, so skip it for the first chunk
    if skip_first_undojoin then
      skip_first_undojoin = false
    else
      utils.undojoin(buf)
    end

    if not qt.ns_id then
      qt.ns_id = ns_id
    end

    if not qt.ex_id then
      qt.ex_id = ex_id
    end

    first_line = vim.api.nvim_buf_get_extmark_by_id(buf, ns_id, ex_id, {})[1]

    -- clean previous response
    local line_count = #vim.split(response, "\n")
    vim.api.nvim_buf_set_lines(buf, first_line + finished_lines, first_line + line_count, false, {})

    -- append new response
    response = response .. chunk
    utils.undojoin(buf)

    -- prepend prefix to each line
    local lines = vim.split(response, "\n")
    for i, l in ipairs(lines) do
      lines[i] = prefix .. l
    end

    local unfinished_lines = {}
    for i = finished_lines + 1, #lines do
      table.insert(unfinished_lines, lines[i])
    end

    vim.api.nvim_buf_set_lines(buf, first_line + finished_lines, first_line + finished_lines, false, unfinished_lines)

    local new_finished_lines = math.max(0, #lines - 1)
    for i = finished_lines, new_finished_lines do
      vim.api.nvim_buf_add_highlight(buf, qt.ns_id, hl_handler_group, first_line + i, 0, -1)
    end
    finished_lines = new_finished_lines

    local end_line = first_line + #vim.split(response, "\n")
    qt.first_line = first_line
    qt.last_line = end_line - 1

    -- move cursor to the end of the response
    if cursor then
      utils.cursor_to_line(end_line, buf, win)
    end
  end)
end

--------------------
-- Chat logic
--------------------

M._toggle = {}

M._toggle_kind = {
  unknown = 0, -- unknown toggle
  chat = 1, -- chat toggle
  popup = 2, -- popup toggle
  context = 3, -- context toggle
}

---@param kind number # kind of toggle
---@return boolean # true if toggle was closed
M._toggle_close = function(kind)
  if
    M._toggle[kind]
    and M._toggle[kind].win
    and M._toggle[kind].buf
    and M._toggle[kind].close
    and vim.api.nvim_win_is_valid(M._toggle[kind].win)
    and vim.api.nvim_buf_is_valid(M._toggle[kind].buf)
    and vim.api.nvim_win_get_buf(M._toggle[kind].win) == M._toggle[kind].buf
  then
    if #vim.api.nvim_list_wins() == 1 then
      M.logger.warning("Can't close the last window.")
    else
      M._toggle[kind].close()
      M._toggle[kind] = nil
    end
    return true
  end
  M._toggle[kind] = nil
  return false
end

---@param kind number # kind of toggle
---@param toggle table # table containing `win`, `buf`, and `close` information
M._toggle_add = function(kind, toggle)
  M._toggle[kind] = toggle
end

---@param kind string # string representation of the toggle kind
---@return number # numeric kind of the toggle
M._toggle_resolve = function(kind)
  kind = kind:lower()
  if kind == "chat" then
    return M._toggle_kind.chat
  elseif kind == "popup" then
    return M._toggle_kind.popup
  elseif kind == "context" then
    return M._toggle_kind.context
  end
  M.logger.warning("Unknown toggle kind: " .. kind)
  return M._toggle_kind.unknown
end

---@param buf number | nil # buffer number
M.prep_md = function(buf)
  -- disable swapping for this buffer and set filetype to markdown
  vim.api.nvim_command("setlocal noswapfile")
  -- better text wrapping
  vim.api.nvim_command("setlocal wrap linebreak")
  -- auto save on TextChanged, InsertLeave
  vim.api.nvim_command("autocmd TextChanged,InsertLeave <buffer=" .. buf .. "> silent! write")

  -- register shortcuts local to this buffer
  buf = buf or vim.api.nvim_get_current_buf()

  -- ensure normal mode
  vim.api.nvim_command("stopinsert")
  utils.feedkeys("<esc>", "xn")
end

M.prep_chat = function(buf, file_name)
  if not utils.is_chat(buf, file_name, M.config.chat_dir) then
    return
  end

  if buf ~= vim.api.nvim_get_current_buf() then
    return
  end

  M.prep_md(buf)

  if M.config.chat_prompt_buf_type then
    vim.api.nvim_set_option_value("buftype", "prompt", { buf = buf })
    vim.fn.prompt_setprompt(buf, "")
    vim.fn.prompt_setcallback(buf, function()
      M.cmd.ChatRespond({ args = "" })
    end)
  end

  -- setup chat specific commands
  local range_commands = {
    {
      command = "ChatRespond",
      modes = M.config.chat_shortcut_respond.modes,
      shortcut = M.config.chat_shortcut_respond.shortcut,
      comment = "Parrot Chat Respond",
    },
    {
      command = "ChatNew",
      modes = M.config.chat_shortcut_new.modes,
      shortcut = M.config.chat_shortcut_new.shortcut,
      comment = "Parrot Chat New",
    },
  }
  for _, rc in ipairs(range_commands) do
    local cmd = M.config.cmd_prefix .. rc.command .. "<cr>"
    for _, mode in ipairs(rc.modes) do
      if mode == "n" or mode == "i" then
        utils.set_keymap({ buf }, mode, rc.shortcut, function()
          vim.api.nvim_command(M.config.cmd_prefix .. rc.command)
          -- go to normal mode
          vim.api.nvim_command("stopinsert")
          utils.feedkeys("<esc>", "xn")
        end, rc.comment)
      else
        utils.set_keymap({ buf }, mode, rc.shortcut, ":<C-u>'<,'>" .. cmd, rc.comment)
      end
    end
  end

  local ds = M.config.chat_shortcut_delete
  utils.set_keymap({ buf }, ds.modes, ds.shortcut, M.cmd.ChatDelete, "Parrot Chat Delete")

  local ss = M.config.chat_shortcut_stop
  utils.set_keymap({ buf }, ss.modes, ss.shortcut, M.cmd.Stop, "Parrot Chat Stop")

  -- make last.md a symlink to the last opened chat file
  local last = M.config.chat_dir .. "/last.md"
  if file_name ~= last then
    os.execute("ln -sf " .. file_name .. " " .. last)
  end
end

M.prep_context = function(buf, file_name)
  if not utils.ends_with(file_name, ".parrot.md") then
    return
  end

  if buf ~= vim.api.nvim_get_current_buf() then
    return
  end

  M.prep_md(buf)
end

M.buf_handler = function()
  local gid = utils.create_augroup("PrtBufHandler", { clear = true })

  utils.autocmd({ "BufEnter" }, nil, function(event)
    local buf = event.buf

    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    local file_name = vim.api.nvim_buf_get_name(buf)

    M.prep_chat(buf, file_name)
    M.prep_context(buf, file_name)
  end, gid)
end

---@param params table | string # table with args or string args
---@return number # buf target
M.resolve_buf_target = function(params)
  local args = ""
  if type(params) == "table" then
    args = params.args or ""
  else
    args = params
  end

  if args == "popup" then
    return ui.BufTarget.popup
  elseif args == "split" then
    return ui.BufTarget.split
  elseif args == "vsplit" then
    return ui.BufTarget.vsplit
  elseif args == "tabnew" then
    return ui.BufTarget.tabnew
  else
    return ui.BufTarget.current
  end
end

---@param file_name string
---@param target number | nil # buf target
---@param kind number # nil or a toggle kind
---@param toggle boolean # whether to toggle
---@return number # buffer number
M.open_buf = function(file_name, target, kind, toggle)
  target = target or ui.BufTarget.current

  -- close previous popup if it exists
  M._toggle_close(M._toggle_kind.popup)

  if toggle then
    M._toggle_close(kind)
  end

  local close, buf, win

  if target == ui.BufTarget.popup then
    local old_buf = utils.get_buffer(file_name)

    buf, win, close, _ = ui.create_popup(
      old_buf,
      M._plugin_name .. " Popup",
      function(w, h)
        local top = M.config.style_popup_margin_top or 2
        local bottom = M.config.style_popup_margin_bottom or 8
        local left = M.config.style_popup_margin_left or 1
        local right = M.config.style_popup_margin_right or 1
        local max_width = M.config.style_popup_max_width or 160
        local ww = math.min(w - (left + right), max_width)
        local wh = h - (top + bottom)
        return ww, wh, top, (w - ww) / 2
      end,
      { on_leave = false, escape = false, persist = true, keep_buf = true },
      { border = M.config.style_popup_border or "single" }
    )

    if not toggle then
      M._toggle_add(M._toggle_kind.popup, { win = win, buf = buf, close = close })
    end

    if old_buf == nil then
      -- read file into buffer and force write it
      vim.api.nvim_command("silent 0read " .. file_name)
      vim.api.nvim_command("silent file " .. file_name)
      vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
    else
      -- move cursor to the beginning of the file and scroll to the end
      utils.feedkeys("ggG", "xn")
    end

    -- delete whitespace lines at the end of the file
    local last_content_line = utils.last_content_line(buf)
    vim.api.nvim_buf_set_lines(buf, last_content_line, -1, false, {})
    -- insert a new line at the end of the file
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
    vim.api.nvim_command("silent write! " .. file_name)
  elseif target == ui.BufTarget.split then
    vim.api.nvim_command("split " .. file_name)
  elseif target == ui.BufTarget.vsplit then
    vim.api.nvim_command("vsplit " .. file_name)
  elseif target == ui.BufTarget.tabnew then
    vim.api.nvim_command("tabnew " .. file_name)
  else
    -- is it already open in a buffer?
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(b) == file_name then
        for _, w in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(w) == b then
            vim.api.nvim_set_current_win(w)
            return b
          end
        end
      end
    end

    -- open in new buffer
    vim.api.nvim_command("edit " .. file_name)
  end

  buf = vim.api.nvim_get_current_buf()
  win = vim.api.nvim_get_current_win()
  close = close or function() end

  if not toggle then
    return buf
  end

  if target == ui.BufTarget.split or target == ui.BufTarget.vsplit then
    close = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
  end

  if target == ui.BufTarget.tabnew then
    close = function()
      if vim.api.nvim_win_is_valid(win) then
        local tab = vim.api.nvim_win_get_tabpage(win)
        vim.api.nvim_set_current_tabpage(tab)
        vim.api.nvim_command("tabclose")
      end
    end
  end

  M._toggle_add(kind, { win = win, buf = buf, close = close })

  return buf
end

---@param params table # table with args
---@param toggle boolean # whether chat is toggled
---@return number # buffer number
M.new_chat = function(params, toggle)
  M._toggle_close(M._toggle_kind.popup)

  -- prepare filename
  local time = os.date("%Y-%m-%d.%H-%M-%S")
  local stamp = tostring(math.floor(vim.loop.hrtime() / 1000000) % 1000)
  -- make sure stamp is 3 digits
  while #stamp < 3 do
    stamp = "0" .. stamp
  end
  time = time .. "." .. stamp
  local filename = M.config.chat_dir .. "/" .. time .. ".md"
  local template = string.format(utils.trim(M.config.chat_template), M.config.chat_user_prefix)

  -- escape underscores (for markdown)
  template = template:gsub("_", "\\_")

  local cbuf = vim.api.nvim_get_current_buf()

  -- strip leading and trailing newlines
  template = template:gsub("^%s*(.-)%s*$", "%1") .. "\n"

  -- create chat file
  vim.fn.writefile(vim.split(template, "\n"), filename)
  local target = M.resolve_buf_target(params)
  local buf = M.open_buf(filename, target, M._toggle_kind.chat, toggle)

  if params.range == 2 then
    utils.append_selection(params, cbuf, buf, utils.trim(M.config.template_selection))
  end
  utils.feedkeys("G", "xn")
  return buf
end

---@return number # buffer number
M.cmd.ChatNew = function(params)
  -- if chat toggle is open, close it and start a new one
  if M._toggle_close(M._toggle_kind.chat) then
    params.args = params.args or ""
    if params.args == "" then
      params.args = M.config.toggle_target
    end
    return M.new_chat(params, true)
  end

  return M.new_chat(params, false)
end

M.cmd.ChatToggle = function(params)
  M._toggle_close(M._toggle_kind.popup)
  if M._toggle_close(M._toggle_kind.chat) and params.range ~= 2 then
    return
  end

  -- create new chat file otherwise
  params.args = params.args or ""
  if params.args == "" then
    params.args = M.config.toggle_target
  end

  -- if the range is 2, we want to create a new chat file with the selection
  if params.range ~= 2 then
    -- check if last.md chat file exists and open it
    local last = M.config.chat_dir .. "/last.md"
    if vim.fn.filereadable(last) == 1 then
      -- resolve symlink
      last = vim.fn.resolve(last)
      M.open_buf(last, M.resolve_buf_target(params), M._toggle_kind.chat, true)
      return
    end
  end

  M.new_chat(params, true)
end

M.cmd.ChatPaste = function(params)
  -- if there is no selection, do nothing
  if params.range ~= 2 then
    M.logger.warning("Please select some text to paste into the chat.")
    return
  end

  -- get current buffer
  local cbuf = vim.api.nvim_get_current_buf()

  local last = M.config.chat_dir .. "/last.md"

  -- make new chat if last doesn't exist
  if vim.fn.filereadable(last) ~= 1 then
    -- skip rest since new chat will handle snippet on it's own
    M.cmd.ChatNew(params)
    return
  end

  params.args = params.args or ""
  if params.args == "" then
    params.args = M.config.toggle_target
  end
  local target = M.resolve_buf_target(params)

  last = vim.fn.resolve(last)
  local buf = utils.get_buffer(last)
  local win_found = false
  if buf then
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(w) == buf then
        vim.api.nvim_set_current_win(w)
        vim.api.nvim_set_current_buf(buf)
        win_found = true
        break
      end
    end
  end
  buf = win_found and buf or M.open_buf(last, target, M._toggle_kind.chat, true)

  utils.append_selection(params, cbuf, buf, utils.trim(M.config.template_selection))
  utils.feedkeys("G", "xn")
end

M.cmd.ChatDelete = function()
  -- get buffer and file
  local buf = vim.api.nvim_get_current_buf()
  local file_name = vim.api.nvim_buf_get_name(buf)

  -- check if file is in the chat dir
  if not utils.starts_with(file_name, M.config.chat_dir) then
    M.logger.warning("File " .. vim.inspect(file_name) .. " is not in chat dir")
    return
  end

  -- delete without confirmation
  if not M.config.chat_confirm_delete then
    futils.delete_file(file_name, M.config.chat_dir)
    return
  end

  -- ask for confirmation
  vim.ui.input({ prompt = "Delete " .. file_name .. "? [y/N] " }, function(input)
    if input and input:lower() == "y" then
      futils.delete_file(file_name, M.config.chat_dir)
    end
  end)
end

M.chat_respond = function(params)
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  local agent = M.get_chat_agent()
  local agent_name = agent.name
  local agent_provider = agent.provider
  local prov = M.get_provider()

  if not prov:verify() then
    return
  end

  if not pool:unique_for_buffer(buf) then
    M.logger.warning("Another parrot process is already running for this buffer.")
    return
  end

  -- go to normal mode
  vim.cmd("stopinsert")

  -- get all lines
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- check if file looks like a chat file
  local file_name = vim.api.nvim_buf_get_name(buf)
  if not utils.is_chat(buf, file_name, M.config.chat_dir) then
    M.logger.warning("File " .. vim.inspect(file_name) .. " does not look like a chat file")
    return
  end

  -- headers are fields before first ---
  local headers = {}
  local header_end = nil
  local line_idx = 0
  ---parse headers
  for _, line in ipairs(lines) do
    -- first line starts with ---
    if line:sub(1, 3) == "---" then
      header_end = line_idx
      break
    end
    -- parse header fields
    local key, value = line:match("^[-#] (%w+): (.*)")
    if key ~= nil then
      headers[key] = value
    end

    line_idx = line_idx + 1
  end

  if header_end == nil then
    M.logger.error("Error while parsing headers: --- not found. Check your chat template.")
    return
  end

  -- message needs role and content
  local messages = {}
  local role = ""
  local content = ""

  -- iterate over lines
  local start_index = header_end + 1
  local end_index = #lines
  if params.range == 2 then
    start_index = math.max(start_index, params.line1)
    end_index = math.min(end_index, params.line2)
  end

  -- if model contains { } then it is a json string otherwise it is a model name
  if headers.model and headers.model:match("{.*}") then
    -- unescape underscores before decoding json
    headers.model = headers.model:gsub("\\_", "_")
    headers.model = vim.json.decode(headers.model)
  end

  if headers.model and type(headers.model) == "table" then
    agent_name = headers.model.model
  elseif headers.model and headers.model:match("%S") then
    agent_name = headers.model
  end

  if headers.role and headers.role:match("%S") then
    ---@diagnostic disable-next-line: cast-local-type
    agent_name = agent_name .. " & custom role"
  end

  local agent_prefix = "🦜:"
  local agent_suffix = "[{{agent}}]"
  ---@diagnostic disable-next-line: cast-local-type
  agent_suffix =
    utils.template_render_from_list(agent_suffix, { ["{{agent}}"] = agent_name .. " - " .. agent_provider })

  for index = start_index, end_index do
    local line = lines[index]
    if line:sub(1, #M.config.chat_user_prefix) == M.config.chat_user_prefix then
      table.insert(messages, { role = role, content = content })
      role = "user"
      content = line:sub(#M.config.chat_user_prefix + 1)
    elseif line:sub(1, #agent_prefix) == agent_prefix then
      table.insert(messages, { role = role, content = content })
      role = "assistant"
      content = ""
    elseif role ~= "" then
      content = content .. "\n" .. line
    end
  end
  -- insert last message not handled in loop
  table.insert(messages, { role = role, content = content })

  -- replace first empty message with system prompt
  content = ""
  if headers.role and headers.role:match("%S") then
    content = headers.role
  else
    content = agent.system_prompt
  end
  if content:match("%S") then
    -- make it multiline again if it contains escaped newlines
    content = content:gsub("\\n", "\n")
    messages[1] = { role = "system", content = content }
  end

  -- write assistant prompt
  local last_content_line = utils.last_content_line(buf)
  vim.api.nvim_buf_set_lines(buf, last_content_line, last_content_line, false, { "", agent_prefix .. agent_suffix, "" })

  local query_prov =
    init_provider(agent.provider, M.providers[agent.provider].endpoint, M.providers[agent.provider].api_key)
  query_prov:set_model(agent.model)

  -- call the model and write response
  M.query(
    buf,
    query_prov,
    utils.prepare_payload(messages, headers.model, agent.model),
    M.create_handler(buf, win, utils.last_content_line(buf), true, "", not M.config.chat_free_cursor),
    vim.schedule_wrap(function(qid)
      local qt = queries:get(qid)
      if not qt then
        return
      end

      -- write user prompt
      last_content_line = utils.last_content_line(buf)
      utils.undojoin(buf)
      vim.api.nvim_buf_set_lines(
        buf,
        last_content_line,
        last_content_line,
        false,
        { "", "", M.config.chat_user_prefix, "" }
      )

      -- delete whitespace lines at the end of the file
      last_content_line = utils.last_content_line(buf)
      utils.undojoin(buf)
      vim.api.nvim_buf_set_lines(buf, last_content_line, -1, false, {})
      -- insert a new line at the end of the file
      utils.undojoin(buf)
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })

      -- if topic is ?, then generate it
      if headers.topic == "?" then
        -- insert last model response
        table.insert(messages, { role = "assistant", content = qt.response })

        -- ask model to generate topic/title for the chat
        local topic_prompt = M.providers[M.get_provider().name].topic_prompt
        if topic_prompt ~= "" then
          table.insert(messages, { role = "user", content = topic_prompt })
        end

        -- prepare invisible buffer for the model to write to
        local topic_buf = vim.api.nvim_create_buf(false, true)
        local topic_handler = M.create_handler(topic_buf, nil, 0, false, "", false)

        local topic_prov = M.get_provider()
        topic_prov:check({ model = M.providers[topic_prov.name].topic_model })
        topic_prov:set_model(M.providers[topic_prov.name].topic_model)

        -- call the model
        M.query(
          nil,
          topic_prov,
          utils.prepare_payload(messages, M.providers[topic_prov.name].topic_model, nil),
          topic_handler,
          vim.schedule_wrap(function()
            -- get topic from invisible buffer
            local topic = vim.api.nvim_buf_get_lines(topic_buf, 0, -1, false)[1]
            -- close invisible buffer
            vim.api.nvim_buf_delete(topic_buf, { force = true })
            -- strip whitespace from ends of topic
            topic = topic:gsub("^%s*(.-)%s*$", "%1")
            -- strip dot from end of topic
            topic = topic:gsub("%.$", "")

            -- if topic is empty do not replace it
            if topic == "" then
              return
            end

            -- replace topic in current buffer
            utils.undojoin(buf)
            vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "# topic: " .. topic })
          end)
        )
      end

      if not M.config.chat_free_cursor then
        local line = vim.api.nvim_buf_line_count(buf)
        utils.cursor_to_line(line, buf, win)
      end
      vim.cmd("doautocmd User PrtDone")
    end)
  )
end

M.cmd.ChatRespond = function(params)
  if params.args == "" then
    M.chat_respond(params)
    return
  end

  -- ensure args is a single positive number
  local n_requests = tonumber(params.args)
  if n_requests == nil or math.floor(n_requests) ~= n_requests or n_requests <= 0 then
    M.logger.warning("args for ChatRespond should be a single positive number, not: " .. params.args)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cur_index = #lines
  while cur_index > 0 and n_requests > 0 do
    if lines[cur_index]:sub(1, #M.config.chat_user_prefix) == M.config.chat_user_prefix then
      n_requests = n_requests - 1
    end
    cur_index = cur_index - 1
  end

  params.range = 2
  params.line1 = cur_index + 1
  params.line2 = #lines
  M.chat_respond(params)
end

M.cmd.ChatFinder = function()
  local has_fzf, fzf_lua = pcall(require, "fzf-lua")

  local filename_from_selection = function(selected)
    return string.match(selected[1], "(%d%d%d%d%-%d%d%-%d%d%.%d%d%-%d%d%-%d%d%.%d%d%d%.md)")
  end

  if has_fzf then
    local actions = require("fzf-lua").defaults.actions.files
    actions["ctrl-p"] = function(selected)
      local filename = filename_from_selection(selected)
      return M.open_buf(M.config.chat_dir .. "/" .. filename, ui.BufTarget.popup, M._toggle_kind.chat, false)
    end
    -- add custom action to delete chat files
    actions["ctrl-d"] = {
      fn = function(selected)
        local filename = filename_from_selection(selected)
        if vim.fn.confirm("Are you sure you want to delete " .. filename .. "?", "&Yes\n&No", 2) == 1 then
          futils.delete_file(M.config.chat_dir .. "/" .. filename, M.config.chat_dir)
          M.logger.info(filename .. " deleted.state")
        end
      end,
      -- TODO: Fix bug, currently not possible --
      reload = false,
    }

    if M.config.toggle_target == "popup" then
      actions["default"] = actions["ctrl-p"]
    elseif M.config.toggle_target == "split" then
      actions["default"] = actions["ctrl-s"]
    elseif M.config.toggle_target == "vsplit" then
      actions["default"] = actions["ctrl-v"]
    elseif M.config.toggle_target == "tabnew" then
      actions["default"] = actions["ctrl-t"]
    end

    fzf_lua.fzf_exec("rg --no-heading topic --type=md", {
      cwd = M.config.chat_dir,
      prompt = "Chat selection ❯",
      fzf_opts = M.config.fzf_lua_opts,
      previewer = "builtin",
      fn_transform = function(x)
        return require("fzf-lua").make_entry.file(x, { file_icons = true, color_icons = true })
      end,
      actions = actions,
    })
    return
  else
    local chat_files = scan.scan_dir(M.config.chat_dir, { depth = 1, search_pattern = "%d+%.md$" })
    vim.ui.select(chat_files, {
      prompt = "Select your chat file:",
      format_item = function(item)
        local read_first_line = function(it)
          local file = io.open(it, "r")
          if not file then
            M.logger.error("Failed to open file: " .. it)
            return ""
          end
          local first_line = file:read("*l")
          file:close()
          return first_line or ""
        end
        return read_first_line(item)
      end,
    }, function(selected_chat)
      if selected_chat == nil then
        M.logger.warning("Invalid chat file selection.")
        return
      end
      M.open_buf(selected_chat, M.resolve_buf_target(M.config.toggle_target), M._toggle_kind.chat, false)
    end)
  end
end

M.switch_provider = function(selected_prov)
  if selected_prov == nil then
    M.logger.warning("Empty provider selection")
    return
  end

  if M.providers[selected_prov] then
    Pstate:set_provider(selected_prov)
    Pstate:refresh(M._available_providers, M._available_provider_agents)
    M.prepare_commands()
    M.logger.info("Switched to provider: " .. selected_prov)
    return
  else
    M.logger.error("Provider not found: " .. selected_prov)
    return
  end
end

M.cmd.Provider = function(params)
  local prov_arg = string.gsub(params.args, "^%s*(.-)%s*$", "%1")
  local has_fzf, fzf_lua = pcall(require, "fzf-lua")
  if prov_arg ~= "" then
    M.switch_provider(prov_arg)
  elseif has_fzf then
    fzf_lua.fzf_exec(M._available_providers, {
      prompt = "Provider selection ❯",
      fzf_opts = M.config.fzf_lua_opts,
      complete = function(selection)
        M.switch_provider(selection[1])
      end,
    })
  else
    vim.ui.select(M._available_providers, {
      prompt = "Select your provider:",
    }, function(selected_prov)
      M.switch_provider(selected_prov)
    end)
  end
end

M.switch_agent = function(is_chat, selected_agent, prov)
  if selected_agent == nil then
    M.logger.warning("Empty agent selection")
    return
  end

  if is_chat and M.agents.chat[selected_agent] then
    Pstate:set_agent(prov.name, selected_agent, "chat")
    M.logger.info("Chat agent: " .. Pstate:get_agent(prov.name, "chat"))
    prov:check(M.agents.chat[selected_agent])
  elseif is_chat then
    M.logger.warning(selected_agent .. " is not a Chat agent")
  elseif M.agents.command[selected_agent] then
    Pstate:set_agent(prov.name, selected_agent, "command")
    M.logger.info("Command agent: " .. Pstate:get_agent(prov.name, "command"))
    prov:check(M.agents.command[selected_agent])
  else
    M.logger.warning(selected_agent .. " is not a Command agent")
  end
  Pstate:refresh(M._available_providers, M._available_provider_agents)
  M.prepare_commands()
end

M.cmd.Agent = function(params)
  local prov = M.get_provider()
  local buf = vim.api.nvim_get_current_buf()
  local file_name = vim.api.nvim_buf_get_name(buf)
  local is_chat = utils.is_chat(buf, file_name, M.config.chat_dir)
  local agent_name = string.gsub(params.args, "^%s*(.-)%s*$", "%1")
  local has_fzf, fzf_lua = pcall(require, "fzf-lua")

  if agent_name ~= "" then
    if not M.agents.chat[agent_name] and not M.agents.command[agent_name] then
      M.logger.warning("Unknown agent: " .. agent_name)
      return
    end
    M.switch_agent(is_chat, agent_name, prov)
  elseif has_fzf then
    fzf_lua.fzf_exec(M.get_provider_agents(is_chat), {
      prompt = "Agent selection ❯",
      fzf_opts = M.config.fzf_lua_opts,
      preview = require("fzf-lua").shell.raw_preview_action_cmd(function(items)
        if is_chat then
          return string.format("echo %q", vim.fn.shellescape(vim.json.encode(M.agents.chat[items[1]])))
        else
          return string.format("echo %q", vim.fn.shellescape(vim.json.encode(M.agents.command[items[1]])))
        end
      end),
      complete = function(selection)
        if #selection == 0 then
          M.logger.warning("No agent selected")
          return
        end
        local selected_agent = selection[1]
        M.switch_agent(is_chat, selected_agent, prov)
      end,
    })
  else
    vim.ui.select(M.get_provider_agents(is_chat), {
      prompt = "Select your agent:",
    }, function(selected_agent)
      M.switch_agent(is_chat, selected_agent, prov)
    end)
  end
end

---@return table # { cmd_prefix, name, model, system_prompt, provider }
M.get_command_agent = function()
  local template = M.config.command_prompt_prefix_template
  local prov = M.get_provider()
  local cmd_prefix =
    utils.template_render_from_list(template, { ["{{agent}}"] = Pstate:get_agent(prov.name, "command") })
  local name = Pstate:get_agent(prov.name, "command")
  local model = M.agents.command[name].model
  local system_prompt = M.agents.command[name].system_prompt
  return {
    cmd_prefix = cmd_prefix,
    name = name,
    model = model,
    system_prompt = system_prompt,
    provider = M.agents.command[name].provider,
  }
end

---@return table # { cmd_prefix, name, model, system_prompt, provider }
M.get_chat_agent = function()
  local template = M.config.command_prompt_prefix_template
  local prov = M.get_provider()
  local cmd_prefix = utils.template_render_from_list(template, { ["{{agent}}"] = Pstate:get_agent(prov.name, "chat") })
  local name = Pstate:get_agent(prov.name, "chat")
  local model = M.agents.chat[name].model
  local system_prompt = M.agents.chat[name].system_prompt
  return {
    cmd_prefix = cmd_prefix,
    name = name,
    model = model,
    system_prompt = system_prompt,
    provider = M.agents.chat[name].provider,
  }
end

M.get_provider = function()
  local _state_prov = Pstate:get_provider()
  local endpoint = M.providers[_state_prov].endpoint
  local api_key = M.providers[_state_prov].api_key
  return init_provider(_state_prov, endpoint, api_key)
end

M.get_provider_agents = function(is_chat)
  local prov = M.get_provider()
  if is_chat then
    return M._available_provider_agents[prov.name].chat
  else
    return M._available_provider_agents[prov.name].command
  end
end

M.cmd.Context = function(params)
  M._toggle_close(M._toggle_kind.popup)
  -- if there is no selection, try to close context toggle
  if params.range ~= 2 then
    if M._toggle_close(M._toggle_kind.context) then
      return
    end
  end

  local cbuf = vim.api.nvim_get_current_buf()

  local file_name = ""
  local buf = utils.get_buffer(".parrot.md")
  if buf then
    file_name = vim.api.nvim_buf_get_name(buf)
  else
    local git_root = futils.find_git_root()
    if git_root == "" then
      M.logger.warning("Not in a git repository")
      return
    end
    file_name = git_root .. "/.parrot.md"
  end

  if vim.fn.filereadable(file_name) ~= 1 then
    vim.fn.writefile({ "Additional context is provided below.", "" }, file_name)
  end

  params.args = params.args or ""
  if params.args == "" then
    params.args = M.config.toggle_target
  end
  local target = M.resolve_buf_target(params)
  buf = M.open_buf(file_name, target, M._toggle_kind.context, true)

  if params.range == 2 then
    utils.append_selection(params, cbuf, buf, utils.trim(M.config.template_selection))
  end

  utils.feedkeys("G", "xn")
end

M.Prompt = function(params, target, prompt, model, template, system_template, agent_provider)
  -- enew, new, vnew, tabnew should be resolved into table
  if type(target) == "function" then
    target = target()
  end

  target = target or ui.Target.enew()

  -- get current buffer
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  if not pool:unique_for_buffer(buf) then
    M.logger.warning("Another parrot process is already running for this buffer.")
    return
  end

  -- defaults to normal mode
  local selection = nil
  local prefix = ""
  local start_line = vim.api.nvim_win_get_cursor(0)[1]
  local end_line = start_line

  -- handle range
  if params.range == 2 then
    start_line = params.line1
    end_line = params.line2
    local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)

    local min_indent = nil
    local use_tabs = false
    -- measure minimal common indentation for lines with content
    for i, line in ipairs(lines) do
      lines[i] = line
      -- skip whitespace only lines
      if not line:match("^%s*$") then
        local indent = line:match("^%s*")
        -- contains tabs
        if indent:match("\t") then
          use_tabs = true
        end
        if min_indent == nil or #indent < min_indent then
          min_indent = #indent
        end
      end
    end
    if min_indent == nil then
      min_indent = 0
    end
    prefix = string.rep(use_tabs and "\t" or " ", min_indent)

    for i, line in ipairs(lines) do
      lines[i] = line:sub(min_indent + 1)
    end

    selection = table.concat(lines, "\n")

    if selection == "" then
      M.logger.warning("Please select some text to rewrite")
      return
    end
  end

  M._selection_first_line = start_line
  M._selection_last_line = end_line

  local callback = function(command)
    -- dummy handler
    local handler = function() end
    -- default on_exit strips trailing backticks if response was markdown snippet
    local on_exit = function(qid)
      local qt = queries:get(qid)
      if not qt then
        return
      end
      -- if buf is not valid, return
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end

      local flc, llc
      local fl = qt.first_line
      local ll = qt.last_line
      -- remove empty lines from the start and end of the response
      while true do
        -- get content of first_line and last_line
        flc = vim.api.nvim_buf_get_lines(buf, fl, fl + 1, false)[1]
        llc = vim.api.nvim_buf_get_lines(buf, ll, ll + 1, false)[1]

        if not flc or not llc then
          break
        end

        local flm = flc:match("%S")
        local llm = llc:match("%S")

        -- break loop if both lines contain non-whitespace characters
        if flm and llm then
          break
        end

        -- break loop lines are equal
        if fl >= ll then
          break
        end

        if not flm then
          utils.undojoin(buf)
          vim.api.nvim_buf_set_lines(buf, fl, fl + 1, false, {})
        else
          utils.undojoin(buf)
          vim.api.nvim_buf_set_lines(buf, ll, ll + 1, false, {})
        end
        ll = ll - 1
      end

      -- if fl and ll starts with triple backticks, remove these lines
      if flc and llc and flc:match("^%s*```") and llc:match("^%s*```") then
        -- remove first line with undojoin
        utils.undojoin(buf)
        vim.api.nvim_buf_set_lines(buf, fl, fl + 1, false, {})
        -- remove last line
        utils.undojoin(buf)
        vim.api.nvim_buf_set_lines(buf, ll - 1, ll, false, {})
        ll = ll - 2
      end
      qt.first_line = fl
      qt.last_line = ll

      -- option to not select response automatically
      if not M.config.command_auto_select_response then
        return
      end

      -- don't select popup response
      if target == ui.Target.popup then
        return
      end

      -- default works for rewrite and enew
      local start = fl
      local finish = ll

      if target == ui.Target.append then
        start = M._selection_first_line - 1
      end

      if target == ui.Target.prepend then
        finish = M._selection_last_line + ll - fl
      end

      -- select from first_line to last_line
      vim.api.nvim_win_set_cursor(0, { start + 1, 0 })
      vim.api.nvim_command("normal! V")
      vim.api.nvim_win_set_cursor(0, { finish + 1, 0 })
    end

    -- prepare messages
    local messages = {}
    local filetype = pft.detect(vim.api.nvim_buf_get_name(buf))
    local filename = vim.api.nvim_buf_get_name(buf)
    local sys_prompt = utils.template_render(system_template, command, selection, filetype, filename)
    sys_prompt = sys_prompt or ""
    local prov = M.get_provider()
    if prov.name ~= agent_provider then
      M.logger.error("Mismatch of agent and current provider " .. prov.name .. " and " .. agent_provider)
      return
    end
    -- messages = prov:add_system_prompt(messages, sys_prompt)

    if sys_prompt ~= "" then
      table.insert(messages, { role = "system", content = sys_prompt })
    end

    local repo_instructions = futils.find_repo_instructions()
    if repo_instructions ~= "" and sys_prompt ~= "" then
      table.insert(messages, { role = "system", content = repo_instructions })
    end

    local filecontent = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    local user_prompt = utils.template_render(template, command, selection, filetype, filename, filecontent)
    table.insert(messages, { role = "user", content = user_prompt })

    -- cancel possible visual mode before calling the model
    utils.feedkeys("<esc>", "xn")

    local cursor = true
    if not M.config.command_auto_select_response then
      cursor = false
    end

    -- mode specific logic
    if target == ui.Target.rewrite then
      -- delete selection
      vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line - 1, false, {})
      -- prepare handler
      handler = M.create_handler(buf, win, start_line - 1, true, prefix, cursor)
    elseif target == ui.Target.append then
      -- move cursor to the end of the selection
      vim.api.nvim_win_set_cursor(0, { end_line, 0 })
      -- put newline after selection
      vim.api.nvim_put({ "" }, "l", true, true)
      -- prepare handler
      handler = M.create_handler(buf, win, end_line, true, prefix, cursor)
    elseif target == ui.Target.prepend then
      -- move cursor to the start of the selection
      vim.api.nvim_win_set_cursor(0, { start_line, 0 })
      -- put newline before selection
      vim.api.nvim_put({ "" }, "l", false, true)
      -- prepare handler
      handler = M.create_handler(buf, win, start_line - 1, true, prefix, cursor)
    elseif target == ui.Target.popup then
      M._toggle_close(M._toggle_kind.popup)
      -- create a new buffer
      local popup_close = nil
      buf, win, popup_close, _ = ui.create_popup(
        nil,
        M._plugin_name .. " popup (close with <esc>/<C-c>)",
        function(w, h)
          local top = M.config.style_popup_margin_top or 2
          local bottom = M.config.style_popup_margin_bottom or 8
          local left = M.config.style_popup_margin_left or 1
          local right = M.config.style_popup_margin_right or 1
          local max_width = M.config.style_popup_max_width or 160
          local ww = math.min(w - (left + right), max_width)
          local wh = h - (top + bottom)
          return ww, wh, top, (w - ww) / 2
        end,
        { on_leave = true, escape = true },
        { border = M.config.style_popup_border or "single" }
      )
      -- set the created buffer as the current buffer
      vim.api.nvim_set_current_buf(buf)
      -- set the filetype to markdown
      vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
      -- better text wrapping
      vim.api.nvim_command("setlocal wrap linebreak")
      -- prepare handler
      handler = M.create_handler(buf, win, 0, false, "", false)
      M._toggle_add(M._toggle_kind.popup, { win = win, buf = buf, close = popup_close })
    elseif type(target) == "table" then
      if target.type == ui.Target.new().type then
        vim.cmd("split")
        win = vim.api.nvim_get_current_win()
      elseif target.type == ui.Target.vnew().type then
        vim.cmd("vsplit")
        win = vim.api.nvim_get_current_win()
      elseif target.type == ui.Target.tabnew().type then
        vim.cmd("tabnew")
        win = vim.api.nvim_get_current_win()
      end

      buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_set_current_buf(buf)

      local group = utils.create_augroup("PrtScratchSave" .. utils.uuid(), { clear = true })
      vim.api.nvim_create_autocmd({ "BufWritePre" }, {
        buffer = buf,
        group = group,
        callback = function(ctx)
          vim.api.nvim_set_option_value("buftype", "", { buf = ctx.buf })
          vim.api.nvim_buf_set_name(ctx.buf, ctx.file)
          vim.api.nvim_command("w!")
          vim.api.nvim_del_augroup_by_id(ctx.group)
        end,
      })

      local ft = target.filetype or filetype
      vim.api.nvim_set_option_value("filetype", ft, { buf = buf })

      handler = M.create_handler(buf, win, 0, false, "", cursor)
    end

    -- call the model and write the response
    local agent = M.get_command_agent()
    prov:set_model(agent.model)

    M.query(
      buf,
      prov,
      utils.prepare_payload(messages, model, agent.model),
      handler,
      vim.schedule_wrap(function(qid)
        on_exit(qid)
        vim.cmd("doautocmd User PrtDone")
      end)
    )
  end

  vim.schedule(function()
    local args = params.args or ""
    if args:match("%S") then
      callback(args)
      return
    end

    -- if prompt is not provided, run the command directly
    if not prompt or prompt == "" then
      callback(nil)
      return
    end

    local input_function = M.config.user_input_ui == "custom" and ui.input
      or M.config.user_input_ui == "native" and vim.ui.input
    if input_function then
      input_function({ prompt = prompt }, function(input)
        if not input or input == "" or input:match("^%s*$") then
          return
        end
        callback(input)
      end)
    else
      M.logger.error("Invalid user input ui option", M.config.user_input_ui)
    end
  end)
end

return M
