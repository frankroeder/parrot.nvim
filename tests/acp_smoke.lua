-- Fast offline smoke: get_context → run_slash_command → acp_query dispatch (no grok stdio).
local ChatHandler = require("parrot.chat_handler")
local acp_client = require("parrot.acp.client")
local acp_sessions = require("parrot.acp.sessions")
local acp_ui = require("parrot.acp.ui")
local init_provider = require("parrot.provider").init_provider

local chat_dir = vim.fn.tempname() .. "_smoke_chats"
vim.fn.mkdir(chat_dir, "p")

local handler = ChatHandler:new({
  state_dir = vim.fn.tempname() .. "_smoke_state",
  chat_dir = chat_dir,
  cmd_prefix = "Prt",
  enable_spinner = false,
  chat_template = "# {{user}}\n\n",
  chat_user_prefix = "User",
  toggle_target = "popup",
  system_prompt = { chat = "", command = "" },
}, {
  grok = {
    type = "acp",
    name = "grok",
    command = { "grok", "agent", "stdio" },
    models = { "grok-build" },
  },
}, { "grok" }, { grok = { "grok-build" } }, {})

local stub = init_provider({
  type = "acp",
  name = "grok",
  command = { "grok", "agent", "stdio" },
  models = { "grok-build" },
})
function stub:verify()
  return true
end
handler.current_provider.chat = stub
handler.current_provider.command = stub

local parrot = {
  chat_handler = handler,
  options = {
    chat_dir = chat_dir,
    enable_spinner = false,
    model_cache_expiry_hours = 48,
    style_popup_border = "single",
  },
  ui = require("parrot.ui"),
}

local project = vim.fn.tempname() .. "_smoke_proj"
vim.fn.mkdir(project, "p")
local original_cwd = vim.fn.getcwd()
vim.cmd("cd " .. vim.fn.fnameescape(project))

local chat_file = chat_dir .. "/smoke.md"
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buf, chat_file)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "smoke" })
vim.api.nvim_set_current_buf(buf)
acp_sessions.bind_chat_project_cwd(handler.state, chat_file)

local ctx = acp_ui.get_context(parrot)
assert(ctx ~= nil, "get_context")
assert(ctx.is_chat == true, "ctx.is_chat")
assert(ctx.scope.kind == "chat", "ctx.scope.kind")

local other = vim.fn.tempname() .. "_smoke_other"
vim.fn.mkdir(other, "p")
vim.cmd("cd " .. vim.fn.fnameescape(other))

local captured = {}
function handler:acp_query(target_buf, prov, payload, _response_handler, on_exit)
  captured.buf = target_buf
  local scope = acp_sessions.session_scope(target_buf, chat_dir, self.state)
  captured.session_kind = scope.kind
  captured.cwd = scope.cwd
  captured.cache_key = acp_client.session_cache_key(scope.kind, scope.cwd)
  if on_exit then
    on_exit()
  end
end

acp_ui.run_slash_command(parrot, "/compact")

assert(captured.buf == buf, "slash uses chat buf not popup")
assert(captured.session_kind == "chat", "session_kind")
assert(vim.fn.resolve(project) == vim.fn.resolve(captured.cwd), "cwd vs bound project")
assert(captured.cache_key == "chat:" .. vim.fn.resolve(project), "cache key")

vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.delete(project, "rf")
vim.fn.delete(other, "rf")

print(string.format(
  "acp smoke ok: is_chat=%s kind=%s cwd=%s cache_key=%s",
  tostring(ctx.is_chat),
  ctx.scope.kind,
  vim.fn.resolve(project),
  captured.cache_key
))