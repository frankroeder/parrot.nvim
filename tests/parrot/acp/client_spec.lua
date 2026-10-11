local acp_client = require("parrot.acp.client")

describe("parrot.acp.client", function()
  describe("messages_to_prompt", function()
    it("converts chat messages to ACP text blocks, skipping system prompts", function()
      local blocks = acp_client.messages_to_prompt({
        { role = "system", content = "Be helpful" },
        { role = "user", content = "Hello" },
      })

      assert.same({ { type = "text", text = "Hello" } }, blocks)
    end)

    it("labels turns when replaying a transcript", function()
      local blocks = acp_client.messages_to_prompt({
        { role = "user", content = "Hi" },
        { role = "assistant", content = "Hello" },
      })
      assert.equals("user:\nHi", blocks[1].text)
      assert.equals("assistant:\nHello", blocks[2].text)
    end)

    it("skips empty messages", function()
      local blocks = acp_client.messages_to_prompt({
        { role = "user", content = "   " },
        { role = "assistant", content = "Hi" },
      })
      assert.equals(1, #blocks)
      assert.equals("Hi", blocks[1].text)
    end)
  end)

  describe("resolve_auth_method_id", function()
    local auth_methods = {
      { id = "xai.api_key", name = "xai.api_key" },
      { id = "cached_token", name = "cached_token" },
      { id = "grok.com", name = "Grok" },
    }

    it("prefers cached_token even when XAI_API_KEY is set", function()
      local old = os.getenv("XAI_API_KEY")
      vim.env.XAI_API_KEY = "test-key"

      local method_id = acp_client.resolve_auth_method_id({ authMethods = auth_methods }, {})
      assert.equals("cached_token", method_id)

      if old then
        vim.env.XAI_API_KEY = old
      else
        vim.env.XAI_API_KEY = nil
      end
    end)

    it("honors agent defaultAuthMethodId from _meta", function()
      local method_id = acp_client.resolve_auth_method_id({
        authMethods = auth_methods,
        _meta = { defaultAuthMethodId = "cached_token" },
      }, {})
      assert.equals("cached_token", method_id)
    end)

    it("falls back to xai.api_key when only that and API key available", function()
      local old = os.getenv("XAI_API_KEY")
      vim.env.XAI_API_KEY = "test-key"

      local method_id = acp_client.resolve_auth_method_id({
        authMethods = { { id = "xai.api_key" }, { id = "grok.com" } },
      }, {})
      assert.equals("xai.api_key", method_id)

      if old then
        vim.env.XAI_API_KEY = old
      else
        vim.env.XAI_API_KEY = nil
      end
    end)

    it("honors explicit auth_method override", function()
      local method_id = acp_client.resolve_auth_method_id({ authMethods = auth_methods }, {
        auth_method = "xai.api_key",
      })
      assert.equals("xai.api_key", method_id)
    end)
  end)

  describe("format_rpc_error", function()
    it("includes data when present", function()
      local msg = acp_client.format_rpc_error({
        message = "Internal error",
        data = { detail = "auth failed" },
      })
      assert.matches("Internal error", msg)
      assert.matches("auth failed", msg)
    end)
  end)

  describe("warm_session_cache", function()
    local orig_get_connection

    before_each(function()
      orig_get_connection = acp_client.get_connection
    end)

    after_each(function()
      acp_client.get_connection = orig_get_connection
    end)

    it("finishes when slash_commands_complete becomes true after session creation", function()
      local cwd = vim.fn.tempname() .. "_warm"
      vim.fn.mkdir(cwd, "p")
      local connection = {
        config = {},
        slash_commands = {},
        slash_commands_complete = false,
        sessions = {},
        rpc = { request = function() end },
      }

      local get_calls = 0
      acp_client.get_connection = function(_, _, cb)
        get_calls = get_calls + 1
        cb(nil, connection)
      end

      local done = false
      local err = "pending"
      acp_client.warm_session_cache({
        command = { "grok", "agent", "stdio" },
        model = "grok-build",
        cwd = cwd,
      }, function(e)
        err = e
        done = true
      end)

      assert.is_not_nil(connection._slash_warm_cb)
      connection.slash_commands = { { name = "compact" } }
      connection.slash_commands_complete = true
      connection._slash_warm_cb()

      vim.wait(1000, function()
        return done
      end)

      assert.is_true(done)
      assert.is_nil(err)
      assert.equals(1, get_calls)

      vim.fn.delete(cwd, "rf")
    end)

    it("coalesces concurrent warm requests for the same connection", function()
      local cwd = vim.fn.tempname() .. "_coalesce"
      vim.fn.mkdir(cwd, "p")
      local connection = {
        config = {},
        slash_commands = {},
        slash_commands_complete = false,
        sessions = {},
        rpc = { request = function() end },
      }

      local get_calls = 0
      acp_client.get_connection = function(_, _, cb)
        get_calls = get_calls + 1
        cb(nil, connection)
      end

      local done = 0
      local config = {
        command = { "grok", "agent", "stdio" },
        model = "grok-build",
        cwd = cwd,
      }

      acp_client.warm_session_cache(config, function()
        done = done + 1
      end)
      acp_client.warm_session_cache(config, function()
        done = done + 1
      end)

      assert.equals(1, get_calls)
      assert.is_not_nil(connection._slash_warm_cb)

      connection.slash_commands = { { name = "context" } }
      connection.slash_commands_complete = true
      connection._slash_warm_cb()

      vim.wait(1000, function()
        return done == 2
      end)

      assert.equals(2, done)

      vim.fn.delete(cwd, "rf")
    end)
  end)

  describe("fetch_models_from_cli", function()
    it("parses the model list of `grok models`", function()
      local real_system = vim.system
      local ran
      vim.system = function(cmd)
        ran = cmd
        return {
          wait = function()
            return { code = 0, stdout = "Available models:\n  * grok-4.6 (default)\n  - grok-build\nnot a model\n" }
          end,
        }
      end
      local models = acp_client.fetch_models_from_cli({ "sh" })
      vim.system = real_system
      assert.same({ "sh", "models" }, ran)
      assert.same({ "grok-4.6", "grok-build" }, models)
    end)
  end)
end)
