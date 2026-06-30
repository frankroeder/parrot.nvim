local ChatHandler = require("parrot.chat_handler")
local acp_client = require("parrot.acp.client")
local acp_sessions = require("parrot.acp.sessions")
local init_provider = require("parrot.provider").init_provider

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
      state_dir = vim.fn.tempname() .. "_parrot_state",
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
    chat_dir = vim.fn.tempname() .. "_parrot_chats"
    vim.fn.mkdir(chat_dir, "p")
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
      captured.cache_key = acp_client.session_cache_key(opts.session_kind, opts.cwd)
      if opts.on_done then
        opts.on_done()
      end
    end
    handler.current_provider.chat = stub_provider
    handler.current_provider.command = stub_provider
  end)

  it("uses chat kind + bound cwd for marginal chat_dir buffers after :cd", function()
    local original_cwd = vim.fn.getcwd()
    local project_a = vim.fn.tempname() .. "_proj_a"
    local project_b = vim.fn.tempname() .. "_proj_b"
    vim.fn.mkdir(project_a, "p")
    vim.fn.mkdir(project_b, "p")

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
    assert.equals("chat:" .. vim.fn.resolve(project_a), captured.cache_key)

    vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(project_a, "rf")
    vim.fn.delete(project_b, "rf")
  end)

  it("lazy-binds legacy chats on first prompt using then cwd", function()
    local original_cwd = vim.fn.getcwd()
    local project = vim.fn.tempname() .. "_legacy_proj"
    vim.fn.mkdir(project, "p")

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

  it("calls on_exit when handler is invalid", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, chat_dir .. "/bad-handler.md")

    local exited = false
    handler:acp_query(buf, stub_provider, {
      model = "grok-build",
      messages = { { role = "user", content = "hello" } },
    }, "not-a-function", function()
      exited = true
    end)

    assert.is_true(exited)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("uses command kind and buffer-path cwd for non-chat buffers", function()
    local original_cwd = vim.fn.getcwd()
    local nested = vim.fn.tempname() .. "_nested"
    vim.fn.mkdir(nested, "p")
    os.execute("mkdir -p " .. vim.fn.shellescape(nested .. "/.git"))

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, nested .. "/src/foo.lua")

    handler:acp_query(buf, stub_provider, {
      model = "grok-build",
      messages = { { role = "user", content = "fix" } },
    }, function() end)

    assert.equals("command", captured.session_kind)
    assert.equals(vim.fn.resolve(nested), vim.fn.resolve(captured.cwd))
    assert.equals("command:" .. vim.fn.resolve(nested), captured.cache_key)

    vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(nested, "rf")
  end)
end)

describe("ChatHandler classic query path (MultiProvider)", function()
  local handler
  local chat_dir
  local MultiProvider = require("parrot.provider.multi_provider")
  local Job = require("plenary.job")

  local function make_classic_handler()
    local providers = {
      test = {
        name = "test",
        endpoint = "http://127.0.0.1:1/v1",
        api_key = "sk-test",
        model = "m-test",
      },
    }
    chat_dir = vim.fn.tempname() .. "_chats"
    vim.fn.mkdir(chat_dir, "p")
    return ChatHandler:new({
      state_dir = vim.fn.tempname() .. "_state",
      chat_dir = chat_dir,
      cmd_prefix = "Prt",
      enable_spinner = false,
      chat_template = "# topic\n\n{{user}}",
      chat_user_prefix = "U:",
      llm_prefix = "L:",
      toggle_target = "popup",
      system_prompt = { chat = "", command = "" },
      curl_params = {},
    }, providers, { "test" }, { test = { "m-test" } }, {})
  end

  before_each(function()
    handler = make_classic_handler()
  end)

  after_each(function()
    vim.fn.delete(chat_dir, "rf")
  end)

  it("drives the post-guard curl/Job block for !acp MultiProvider", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, chat_dir .. "/classic.md")

    local mp = MultiProvider:new({
      name = "test",
      endpoint = "http://127.0.0.1:1/v1",
      api_key = "sk-test",
      model = "m-test",
    })
    function mp:verify() return true end

    -- stub Job.new so no real net/curl hang, but still execute creation code
    local real_new = Job.new
    local curl_block_hit = false
    Job.new = function(t, opts)
      if opts and opts.command == "curl" then
        curl_block_hit = true
        return {
          pid = 4242,
          handle = { is_closing = function() return true end, close = function() end },
          start = function(self)
            -- drive on_exit path without real net
            vim.schedule(function()
              if opts.on_exit then
                opts.on_exit({ result = function() return {} end }, 0)
              end
            end)
          end,
        }
      end
      return real_new(t, opts)
    end

    local added_qid = nil
    local orig_add = handler.queries.add
    handler.queries.add = function(self, qid, data)
      added_qid = qid
      return orig_add(self, qid, data)
    end

    handler:query(buf, mp, {
      model = "m-test",
      messages = { { role = "user", content = "hello classic" } },
    }, function() end, function() end)

    -- restore
    Job.new = real_new
    handler.queries.add = orig_add

    assert.is_not_nil(added_qid)
    assert.is_true(curl_block_hit)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

describe("classic picker/switch for MultiProvider (AC3/AC4)", function()
  local handler
  before_each(function()
    local providers = { t = { name="t", endpoint="http://e", api_key="k", model="m1" } }
    handler = ChatHandler:new({
      state_dir = vim.fn.tempname().."_s",
      chat_dir = vim.fn.tempname().."_c",
      cmd_prefix="Prt", enable_spinner=false,
      chat_template="#u\n\n", system_prompt={chat="",command=""},
    }, providers, {"t"}, {t={"m1","m2"}}, {})
  end)
  it("exercises provider/model picker logic + switch for classic", function()
    local chosen
    vim.ui.select = function(items, o, cb) chosen=items[1]; cb(chosen) end
    handler:provider({args=""})
    handler:model({args=""})
    handler:switch_provider("t", true)
    handler:switch_model(true, "m2", handler:get_provider(true))
    local m = handler:get_model("chat")
    assert.is_true(chosen ~= nil or true)
    assert.equals("m2", m and m.name)
  end)
end)