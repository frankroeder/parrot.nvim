local acp_client = require("parrot.acp.client")

describe("parrot.acp.client", function()
  describe("messages_to_prompt", function()
    it("converts chat messages to ACP text blocks", function()
      local blocks = acp_client.messages_to_prompt({
        { role = "system", content = "Be helpful" },
        { role = "user", content = "Hello" },
      })

      assert.equals(2, #blocks)
      assert.equals("text", blocks[1].type)
      assert.matches("Be helpful", blocks[1].text)
      assert.equals("Hello", blocks[2].text)
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

    it("prefers xai.api_key when XAI_API_KEY is set", function()
      local old = os.getenv("XAI_API_KEY")
      vim.env.XAI_API_KEY = "test-key"

      local method_id = acp_client.resolve_auth_method_id({ authMethods = auth_methods }, {})
      assert.equals("xai.api_key", method_id)

      if old then
        vim.env.XAI_API_KEY = old
      else
        vim.env.XAI_API_KEY = nil
      end
    end)

    it("falls back to cached_token without API key", function()
      local old = os.getenv("XAI_API_KEY")
      vim.env.XAI_API_KEY = nil

      local method_id = acp_client.resolve_auth_method_id({ authMethods = auth_methods }, {})
      assert.equals("cached_token", method_id)

      if old then
        vim.env.XAI_API_KEY = old
      end
    end)

    it("honors explicit auth_method override", function()
      local method_id = acp_client.resolve_auth_method_id({ authMethods = auth_methods }, {
        auth_method = "cached_token",
      })
      assert.equals("cached_token", method_id)
    end)
  end)

  describe("normalize_slash_commands", function()
    it("handles vim.NIL input from JSON null", function()
      local normalized = acp_client.normalize_slash_commands({
        { name = "context", description = "stats", input = vim.NIL },
        { name = "compact", description = "compress", input = { hint = "preserve notes" } },
      })
      assert.equals(2, #normalized)
      assert.equals("context", normalized[1].name)
      assert.is_nil(normalized[1].hint)
      assert.equals("preserve notes", normalized[2].hint)
    end)

    it("deduplicates commands and accepts map-shaped payloads", function()
      local normalized = acp_client.normalize_slash_commands({
        compact = { name = "compact", description = "compress" },
        context = { name = "context", description = "stats" },
        goal = { name = "goal", description = "goal mode" },
        ["session-info"] = { name = "session-info", description = "session" },
        ["always-approve"] = { name = "always-approve", description = "approve" },
        duplicate = { name = "compact", description = "ignored" },
      })
      assert.equals(5, #normalized)
    end)
  end)

  describe("warm_session_cache", function()
    local acp_sessions = require("parrot.acp.sessions")
    local orig_get_connection

    before_each(function()
      orig_get_connection = acp_client.get_connection
    end)

    after_each(function()
      acp_client.get_connection = orig_get_connection
    end)

    it("finishes when slash_commands_complete becomes true after session ensure", function()
      local cwd = vim.fn.tempname() .. "_warm"
      vim.fn.mkdir(cwd, "p")
      local cache_key = "command:" .. acp_sessions.repo_key(cwd)
      local connection = {
        config = {},
        slash_commands = {},
        slash_commands_complete = false,
        sessions = { [cache_key] = "sess-1" },
        rpc = {},
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
      local cache_key = "command:" .. acp_sessions.repo_key(cwd)
      local connection = {
        config = {},
        slash_commands = {},
        slash_commands_complete = false,
        sessions = { [cache_key] = "sess-1" },
        rpc = {},
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
    it("parses grok models output when available", function()
      if vim.fn.executable("grok") ~= 1 then
        pending("grok CLI not installed")
        return
      end
      local models = acp_client.fetch_models_from_cli({ "grok" })
      assert.is_true(#models > 0)
      assert.is_true(vim.tbl_contains(models, "grok-build") or vim.tbl_contains(models, "grok-composer-2.5-fast"))
    end)
  end)
end)