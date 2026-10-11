local init_provider = require("parrot.provider").init_provider
local acp_client = require("parrot.acp.client")

describe("AcpProvider", function()
  local provider
  local orig_fetch = acp_client.fetch_models_from_cli
  local orig_prompt = acp_client.prompt

  before_each(function()
    provider = init_provider({
      type = "acp",
      name = "grok",
      command = { "grok", "agent", "stdio" },
      cli_command = { "grok" },
      models = { "grok-composer-2.5-fast", "grok-build" },
    })
  end)

  after_each(function()
    acp_client.fetch_models_from_cli = orig_fetch
    acp_client.prompt = orig_prompt
  end)

  it("lists exactly the models of the CLI", function()
    acp_client.fetch_models_from_cli = function()
      return { "grok-4.7", "grok-4.6" }
    end
    assert.same({ "grok-4.7", "grok-4.6" }, provider:get_available_models())
  end)

  it("sets the model of its runtime config", function()
    provider:set_model("grok-build")
    assert.equals("grok-build", provider:get_runtime_config().model)
  end)

  it("keeps command_reasoning_effort = false and defaults it to low", function()
    assert.equals("low", provider:get_runtime_config().command_reasoning_effort)
    local p = init_provider({ type = "acp", name = "grok", command_reasoning_effort = false })
    assert.is_false(p:get_runtime_config().command_reasoning_effort)
  end)

  it("delegates prompt opts to acp client (cwd/kind from caller)", function()
    local captured = {}
    acp_client.prompt = function(_, opts)
      captured = opts
    end

    provider:prompt({
      cwd = "/tmp/parrot-test-repo",
      session_kind = "chat",
      messages = { { role = "user", content = "hello" } },
      state = {},
    })

    assert.equals("/tmp/parrot-test-repo", captured.cwd)
    assert.equals("chat", captured.session_kind)
    assert.is_not_nil(captured.state)
  end)

  describe("get_available_models_cached", function()
    local state_mock = {
      get_cached_models = function()
        return nil
      end,
      set_cached_models = function() end,
      save = function() end,
    }

    it("fetches and caches the CLI models on a cache miss", function()
      local cached
      local state = vim.tbl_extend("force", state_mock, {
        set_cached_models = function(_, _, models)
          cached = models
        end,
      })
      acp_client.fetch_models_from_cli = function()
        return { "grok-4.7" }
      end
      local models = provider:get_available_models_cached(state, 48, nil)
      assert.same({ "grok-4.7" }, models)
      assert.same(models, cached)
    end)

    it("falls back to the configured models when the CLI lists none", function()
      acp_client.fetch_models_from_cli = function()
        return {}
      end
      assert.same({ "grok-composer-2.5-fast", "grok-build" }, provider:get_available_models_cached(state_mock, 48, nil))
    end)

    it("invokes the callback exactly once for cached models", function()
      local cached_state = vim.tbl_extend("force", state_mock, {
        get_cached_models = function()
          return { "grok-4.7" }
        end,
      })
      local calls = {}
      provider:get_available_models_cached(cached_state, 48, nil, function(models)
        table.insert(calls, models)
      end)
      vim.wait(200, function()
        return false
      end)
      assert.same({ { "grok-4.7" } }, calls)
    end)
  end)
end)
