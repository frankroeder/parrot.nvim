local ChatHandler = require("parrot.chat_handler")
local acp_sessions = require("parrot.acp.sessions")
local init_provider = require("parrot.provider").init_provider

local function temp_dir(suffix)
  local dir = vim.fn.tempname() .. suffix
  vim.fn.mkdir(dir, "p")
  return dir
end

describe("ChatHandler acp_query session scope", function()
  local handler
  local chat_dir
  local captured
  local stub_provider

  local function make_handler()
    local providers = {
      grok = {
        type = "acp",
        name = "grok",
        command = { "grok", "agent", "stdio" },
        cli_command = { "grok" },
        models = { "grok-build" },
      },
    }
    return ChatHandler:new({
      state_dir = temp_dir("_parrot_state"),
      chat_dir = chat_dir,
      cmd_prefix = "Prt",
      enable_spinner = false,
      chat_template = "# {{user}}\n\n",
      chat_user_prefix = "User",
      toggle_target = "popup",
      system_prompt = { chat = "", command = "" },
    }, providers, { "grok" }, { grok = { "grok-build" } }, {})
  end

  before_each(function()
    chat_dir = temp_dir("_parrot_chats")
    captured = {}
    handler = make_handler()

    stub_provider = init_provider({
      type = "acp",
      name = "grok",
      command = { "grok", "agent", "stdio" },
      models = { "grok-build" },
    })
    function stub_provider:verify()
      return true
    end
    function stub_provider:prompt(opts)
      captured.cwd = opts.cwd
      captured.session_kind = opts.session_kind
      captured.session_key = opts.session_key
      if opts.on_done then
        opts.on_done()
      end
    end
    handler.current_provider.chat = stub_provider
    handler.current_provider.command = stub_provider
  end)

  it("uses chat kind + bound cwd for marginal chat_dir buffers after :cd", function()
    local original_cwd = vim.fn.getcwd()
    local project_a = temp_dir("_proj_a")
    local project_b = temp_dir("_proj_b")

    local chat_file = chat_dir .. "/legacy-short.md"
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, chat_file)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "draft" })

    vim.cmd("cd " .. vim.fn.fnameescape(project_a))
    acp_sessions.bind_chat_project_cwd(handler.state, chat_file)

    vim.cmd("cd " .. vim.fn.fnameescape(project_b))
    handler:acp_query(buf, stub_provider, {
      model = "grok-build",
      messages = { { role = "user", content = "hello" } },
    }, function() end)

    assert.equals("chat", captured.session_kind)
    assert.equals(vim.fn.resolve(project_a), vim.fn.resolve(captured.cwd))
    assert.equals(vim.fn.resolve(chat_file), captured.session_key)

    vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(project_a, "rf")
    vim.fn.delete(project_b, "rf")
  end)

  it("lazy-binds unbound chats on first prompt using then cwd", function()
    local original_cwd = vim.fn.getcwd()
    local project = temp_dir("_legacy_proj")

    local chat_file = chat_dir .. "/unbound.md"
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, chat_file)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "old chat" })

    vim.cmd("cd " .. vim.fn.fnameescape(project))
    handler:acp_query(buf, stub_provider, {
      model = "grok-build",
      messages = { { role = "user", content = "resume" } },
    }, function() end)

    assert.equals("chat", captured.session_kind)
    assert.equals(vim.fn.resolve(project), vim.fn.resolve(captured.cwd))
    assert.equals(vim.fn.resolve(project), vim.fn.resolve(handler.state:get_chat_project_cwd(chat_file)))

    vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(project, "rf")
  end)

  it("calls on_exit when verify fails so spinners stop", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, chat_dir .. "/verify-fail.md")

    function stub_provider:verify()
      return false
    end

    local exited = false
    handler:acp_query(buf, stub_provider, {
      model = "grok-build",
      messages = { { role = "user", content = "hello" } },
    }, function() end, function()
      exited = true
    end)

    assert.is_true(exited)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("stop() cancels a running ACP prompt", function()
    local acp_client = require("parrot.acp.client")
    local orig_cancel = acp_client.cancel
    local cancelled
    acp_client.cancel = function(qid)
      cancelled = qid
    end
    function stub_provider:prompt(opts)
      captured.qid = opts.qid -- never finishes
    end

    handler:acp_query(nil, stub_provider, {
      model = "grok-build",
      messages = { { role = "user", content = "hello" } },
    }, function() end)
    handler:stop({ notify = false })
    acp_client.cancel = orig_cancel

    assert.is_not_nil(captured.qid)
    assert.equals(captured.qid, cancelled)
    assert.is_true(handler.pool:is_empty())
  end)

  it("uses command kind and buffer-path cwd for non-chat buffers", function()
    local original_cwd = vim.fn.getcwd()
    local nested = temp_dir("_nested")
    vim.fn.mkdir(nested .. "/.git", "p")

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, nested .. "/src/foo.lua")

    handler:acp_query(buf, stub_provider, {
      model = "grok-build",
      messages = { { role = "user", content = "fix" } },
    }, function() end)

    assert.equals("command", captured.session_kind)
    assert.equals(vim.fn.resolve(nested), vim.fn.resolve(captured.cwd))
    assert.is_nil(captured.session_key)

    vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(nested, "rf")
  end)

  it("runs commands writing elsewhere (popup) in the edited file's repo", function()
    local nested = temp_dir("_nested")
    vim.fn.mkdir(nested .. "/.git", "p")
    local src = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(src, nested .. "/src/foo.lua")

    handler:acp_query(nil, stub_provider, {
      model = "grok-build",
      messages = { { role = "user", content = "explain" } },
      acp_cwd_buf = src,
    }, function() end)

    assert.equals("command", captured.session_kind)
    assert.equals(vim.fn.resolve(nested), vim.fn.resolve(captured.cwd))
    vim.api.nvim_buf_delete(src, { force = true })
    vim.fn.delete(nested, "rf")
  end)
end)

describe("ChatHandler classic query path (MultiProvider)", function()
  local handler
  local chat_dir
  local real_system = vim.system
  local MultiProvider = require("parrot.provider.multi_provider")

  before_each(function()
    chat_dir = temp_dir("_chats")
    handler = ChatHandler:new({
      state_dir = temp_dir("_state"),
      chat_dir = chat_dir,
      cmd_prefix = "Prt",
      enable_spinner = false,
      chat_template = "# topic\n\n{{user}}",
      chat_user_prefix = "U:",
      llm_prefix = "L:",
      toggle_target = "popup",
      system_prompt = { chat = "", command = "" },
      curl_params = {},
    }, { test = { name = "test", endpoint = "http://127.0.0.1:1/v1", api_key = "sk-test", model = "m-test" } }, {
      "test",
    }, { test = { "m-test", "m-2" } }, {})
  end)

  after_each(function()
    vim.system = real_system
    vim.fn.delete(chat_dir, "rf")
  end)

  it("streams curl output split across chunks through vim.system", function()
    local mp = MultiProvider:new({
      name = "test",
      endpoint = "http://127.0.0.1:1/v1",
      api_key = "sk-test",
      model = "m-test",
    })

    vim.system = function(cmd, opts, on_exit)
      assert.equals("curl", cmd[1])
      vim.schedule(function()
        -- one SSE line split mid-way, the last line without a trailing newline
        opts.stdout(nil, 'data: {"choices":[{"delta":{"con')
        opts.stdout(nil, 'tent":"hi"}}]}\ndata: {"choices":[{"delta":{"content":" there"}}]}')
        opts.stdout(nil, nil)
        on_exit({ code = 0, signal = 0 })
      end)
      return {
        pid = 4242,
        is_closing = function()
          return true
        end,
        kill = function() end,
      }
    end

    local chunks, exited = {}, false
    handler:query(nil, mp, {
      model = "m-test",
      messages = { { role = "user", content = "hello classic" } },
    }, function(_, chunk)
      table.insert(chunks, chunk)
    end, function()
      exited = true
    end)
    vim.wait(1000, function()
      return exited
    end)

    assert.same({ "hi", " there" }, chunks)
    assert.is_true(handler.pool:is_empty())
  end)

  it("switch_model updates the chat model of a classic provider", function()
    handler:switch_model(true, "m-2", handler:get_provider(true))
    assert.equals("m-2", handler:get_model("chat").name)
  end)
end)
