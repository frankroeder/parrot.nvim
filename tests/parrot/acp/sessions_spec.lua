local acp_sessions = require("parrot.acp.sessions")
local State = require("parrot.state")

describe("parrot.acp.sessions", function()
  local state, state_dir, original_cwd

  before_each(function()
    original_cwd = vim.fn.getcwd()
    state_dir = vim.fn.tempname() .. "_parrot_state"
    vim.fn.mkdir(state_dir, "p")
    state = State:new(state_dir)
    state:refresh({ "grok" }, { grok = { "grok-build" } })
  end)

  after_each(function()
    vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
    vim.fn.delete(state_dir, "rf")
  end)

  local function chat_buf(file)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, file)
    return buf
  end

  it("keeps a chat bound to its project after :cd", function()
    local chat_dir = "/tmp/parrot_chats_test"
    local chat_file = chat_dir .. "/12345.md"
    local buf = chat_buf(chat_file)
    local project_a = vim.fn.tempname() .. "_parrot_proj_a"
    local project_b = vim.fn.tempname() .. "_parrot_proj_b"
    vim.fn.mkdir(project_a, "p")
    vim.fn.mkdir(project_b, "p")

    vim.cmd("cd " .. vim.fn.fnameescape(project_a))
    acp_sessions.bind_chat_project_cwd(state, chat_file)

    vim.cmd("cd " .. vim.fn.fnameescape(project_b))
    local scope = acp_sessions.session_scope(buf, chat_dir, state)
    assert.equals(vim.fn.resolve(project_a), vim.fn.resolve(scope.cwd))

    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(project_a, "rf")
    vim.fn.delete(project_b, "rf")
  end)

  it("session_scope uses the chat kind for any file under chat_dir and binds it lazily", function()
    local chat_dir = "/tmp/parrot_scope_test"
    local buf = chat_buf(chat_dir .. "/short.md")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x" })
    local project = vim.fn.tempname() .. "_bind_proj"
    vim.fn.mkdir(project, "p")
    vim.cmd("cd " .. vim.fn.fnameescape(project))

    local scope = acp_sessions.session_scope(buf, chat_dir, state)
    assert.equals("chat", scope.kind)
    assert.equals(vim.fn.resolve(chat_dir .. "/short.md"), scope.key)
    assert.equals(vim.fn.resolve(project), vim.fn.resolve(scope.cwd))
    assert.equals(vim.fn.resolve(project), vim.fn.resolve(state:get_chat_project_cwd(chat_dir .. "/short.md")))

    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(project, "rf")
  end)

  it("session_scope without a buffer is a command scope in Neovim's cwd", function()
    local scope = acp_sessions.session_scope(nil, "/tmp/parrot_scope_test", state)
    assert.equals("command", scope.kind)
    assert.is_nil(scope.key)
    assert.is_truthy(scope.cwd)
  end)

  it("persists chat session entries per chat file", function()
    local entry = { id = "sess-123", n = 3, hash = "abc" }
    state:set_acp_session("grok", "/chats/a.md", entry)
    assert.same(entry, state:get_acp_session("grok", "/chats/a.md"))
    assert.is_nil(state:get_acp_session("grok", "/chats/b.md"))

    -- survives a refresh and a reload from disk
    state:refresh({ "grok" }, { grok = { "grok-build" } })
    assert.same(entry, state:get_acp_session("grok", "/chats/a.md"))
    local reloaded = State:new(state_dir)
    reloaded:refresh({ "grok" }, { grok = { "grok-build" } })
    assert.same(entry, reloaded:get_acp_session("grok", "/chats/a.md"))

    state:set_acp_session("grok", "/chats/a.md", nil)
    assert.is_nil(state:get_acp_session("grok", "/chats/a.md"))
  end)

  it("is_chat_dir_file does not match sibling directories", function()
    assert.is_true(acp_sessions.is_chat_dir_file("/tmp/x_chats/a.md", "/tmp/x_chats"))
    assert.is_true(acp_sessions.is_chat_dir_file("/tmp/x_chats/a.md", "/tmp/x_chats/"))
    assert.is_false(acp_sessions.is_chat_dir_file("/tmp/x_chats_old/a.md", "/tmp/x_chats"))
    assert.is_false(acp_sessions.is_chat_dir_file("", "/tmp/x_chats"))
  end)
end)
