local init_provider = require("parrot.provider").init_provider

describe("AcpProvider", function()
  local provider

  before_each(function()
    provider = init_provider({
      type = "acp",
      name = "grok",
      command = { "grok", "agent", "stdio" },
      cli_command = { "grok" },
      models = { "grok-composer-2.5-fast", "grok-build" },
    })
  end)

  it("is detected as an ACP provider", function()
    assert.is_true(provider:is_acp())
    assert.equals("acp", provider.type)
  end)

  it("supports online model fetching", function()
    assert.is_true(provider:online_model_fetching())
  end)

  it("uses grok models CLI when available", function()
    if vim.fn.executable("grok") ~= 1 then
      pending("grok CLI not installed")
      return
    end
    local models = provider:get_available_models()
    assert.is_true(#models >= 2)
  end)

  it("sets and tracks the active model", function()
    provider:set_model("grok-build")
    assert.equals("grok-build", provider._model)
    assert.equals("grok-build", provider:get_runtime_config().model)
  end)

  it("does not require HTTP endpoint configuration", function()
    assert.equals("acp://local", provider.endpoint)
    assert.is_true(provider:verify() == (vim.fn.executable("grok") == 1))
  end)

  it("delegates terminate_connection to acp client for a model", function()
    local acp_client = require("parrot.acp.client")
    local terminated = nil
    local orig = acp_client.terminate_connection
    acp_client.terminate_connection = function(_, model)
      terminated = model
    end

    provider:set_model("grok-build")
    provider:terminate_connection("grok-build")

    acp_client.terminate_connection = orig
    assert.equals("grok-build", terminated)
  end)

  it("delegates prompt opts to acp client (cwd/kind from caller)", function()
    local acp_client = require("parrot.acp.client")
    local captured = {}
    local orig_prompt = acp_client.prompt
    acp_client.prompt = function(_, opts)
      captured = opts
    end

    provider:prompt({
      cwd = "/tmp/parrot-test-repo",
      session_kind = "chat",
      messages = { { role = "user", content = "hello" } },
      state = {},
    })

    acp_client.prompt = orig_prompt
    assert.equals("/tmp/parrot-test-repo", captured.cwd)
    assert.equals("chat", captured.session_kind)
    assert.is_not_nil(captured.state)
  end)

  describe("get_available_models_cached offline gate", function()
    local utils = require("parrot.utils")
    local state_mock = {
      get_cached_models = function() return nil end,
      set_cached_models = function() end,
      save = function() end,
      get_slash_commands_cache_entry = function() return nil end,
    }

    it("returns static without calling cli fetch when has_internet false", function()
      local orig = utils.has_internet
      utils.has_internet = function() return false end
      local fetch_called = false
      local orig_fetch = require("parrot.acp.client").fetch_models_from_cli
      require("parrot.acp.client").fetch_models_from_cli = function()
        fetch_called = true
        return { "cli-only" }
      end
      local models = provider:get_available_models_cached(state_mock, 48, nil)
      utils.has_internet = orig
      require("parrot.acp.client").fetch_models_from_cli = orig_fetch
      assert.are.same({ "grok-composer-2.5-fast", "grok-build" }, models)
      assert.is_false(fetch_called)
    end)
  end)
end)