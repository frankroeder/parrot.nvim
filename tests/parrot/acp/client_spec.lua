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

  describe("load_slash_commands", function()
    local orig_get_connection
    local config = { name = "grok", command = { "grok", "agent", "stdio" }, model = "grok-build" }

    -- answers session/new with a session id, records every request
    local function fake_connection(requests)
      return {
        sessions = {},
        rpc = {
          request = function(method, params, cb)
            table.insert(requests, method)
            cb(nil, method == "session/new" and { sessionId = "warm" } or {})
          end,
        },
      }
    end

    before_each(function()
      orig_get_connection = acp_client.get_connection
    end)

    after_each(function()
      acp_client.get_connection = orig_get_connection
    end)

    it("waits for the commands of a throwaway session, shared by concurrent loads, then deletes it", function()
      local requests = {}
      local connection = fake_connection(requests)
      acp_client.get_connection = function(_, _, cb)
        cb(nil, connection)
      end

      local results = {}
      for _ = 1, 2 do
        acp_client.load_slash_commands(config, function(err, commands)
          table.insert(results, { err = err, commands = commands })
        end)
      end
      assert.same({ "session/new" }, requests)
      assert.same({}, results)

      -- the agent's available_commands_update
      connection.slash_commands = { { name = "compact" } }
      connection._slash_commands_ready()

      assert.same({ { commands = { { name = "compact" } } }, { commands = { { name = "compact" } } } }, results)
      assert.same({ "session/new", "_x.ai/session/delete" }, requests)
    end)

    it("returns known commands without opening a session", function()
      local requests = {}
      local connection = fake_connection(requests)
      connection.slash_commands = { { name = "goal" } }
      acp_client.get_connection = function(_, _, cb)
        cb(nil, connection)
      end

      local got
      acp_client.load_slash_commands(config, function(_, commands)
        got = commands
      end)
      assert.same({ { name = "goal" } }, got)
      assert.same({}, requests)
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
