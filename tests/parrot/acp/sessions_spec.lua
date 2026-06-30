local acp_sessions = require("parrot.acp.sessions")
local State = require("parrot.state")

describe("parrot.acp.sessions", function()
  it("repo_key uses git root from cwd argument", function()
    local temp_dir = vim.fn.tempname() .. "_parrot_git"
    local nested = temp_dir .. "/nested"
    vim.fn.mkdir(nested, "p")
    os.execute("mkdir -p " .. vim.fn.shellescape(temp_dir .. "/.git"))

    local key = acp_sessions.repo_key(nested)
    assert.equals(vim.fn.resolve(temp_dir), vim.fn.resolve(key))

    vim.fn.delete(temp_dir, "rf")
  end)

  it("project_cwd keeps chat bound to project at create time after :cd", function()
    local chat_dir = "/tmp/parrot_chats_test"
    local chat_file = chat_dir .. "/12345.md"
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, chat_file)

    local dir = vim.fn.tempname() .. "_parrot_state"
    vim.fn.mkdir(dir, "p")
    local state = State:new(dir)
    state:init_file_state({ "grok" })
    state:init_state({ "grok" }, { grok = { "grok-build" } })

    local original_cwd = vim.fn.getcwd()
    local project_a = vim.fn.tempname() .. "_parrot_proj_a"
    local project_b = vim.fn.tempname() .. "_parrot_proj_b"
    vim.fn.mkdir(project_a, "p")
    vim.fn.mkdir(project_b, "p")

    vim.cmd("cd " .. vim.fn.fnameescape(project_a))
    acp_sessions.bind_chat_project_cwd(state, chat_file)

    vim.cmd("cd " .. vim.fn.fnameescape(project_b))
    assert.equals(vim.fn.resolve(project_a), vim.fn.resolve(acp_sessions.project_cwd(buf, chat_dir, state)))

    vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(project_a, "rf")
    vim.fn.delete(project_b, "rf")
    vim.fn.delete(dir, "rf")
  end)

  it("session_scope aligns chat kind with chat_dir path for marginal buffers", function()
    local chat_dir = "/tmp/parrot_scope_test"
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, chat_dir .. "/short.md")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x" })

    local scope = acp_sessions.session_scope(buf, chat_dir, nil)
    assert.equals("chat", scope.kind)
    assert.is_true(scope.is_chat_buf)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("session_scope lazy-binds chat project cwd on first scope resolve", function()
    local dir = vim.fn.tempname() .. "_parrot_state"
    vim.fn.mkdir(dir, "p")
    local state = State:new(dir)
    state:init_file_state({ "grok" })
    state:init_state({ "grok" }, { grok = { "grok-build" } })

    local chat_dir = "/tmp/parrot_lazy_bind"
    local chat_file = chat_dir .. "/old.md"
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, chat_file)

    local original_cwd = vim.fn.getcwd()
    local project = vim.fn.tempname() .. "_bind_proj"
    vim.fn.mkdir(project, "p")
    vim.cmd("cd " .. vim.fn.fnameescape(project))

    local scope = acp_sessions.session_scope(buf, chat_dir, state)
    assert.equals(vim.fn.resolve(project), vim.fn.resolve(scope.cwd))
    assert.equals(vim.fn.resolve(project), vim.fn.resolve(state:get_chat_project_cwd(chat_file)))

    vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(project, "rf")
    vim.fn.delete(dir, "rf")
  end)

  it("persists session ids per repo and kind", function()
    local dir = vim.fn.tempname() .. "_parrot_state"
    vim.fn.mkdir(dir, "p")
    local state = State:new(dir)
    state:init_file_state({ "grok" })
    state:init_state({ "grok" }, { grok = { "grok-build" } })

    acp_sessions.save_id(state, "grok", "command", "/repo/a", "sess-123")
    assert.equals("sess-123", acp_sessions.get_id(state, "grok", "command", "/repo/a"))
    assert.is_nil(acp_sessions.get_id(state, "grok", "chat", "/repo/a"))

    vim.fn.delete(dir, "rf")
  end)
end)