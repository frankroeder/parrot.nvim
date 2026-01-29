-- Unit tests for Claude CLI provider integration
-- Run with: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.vim'}"

local ClaudeCliProvider = require("parrot.provider.claude_cli")
local init_provider = require("parrot.provider.init").init_provider

describe("ClaudeCliProvider", function()
  describe("Provider Creation", function()
    it("creates provider with default config", function()
      local provider = ClaudeCliProvider:new({
        name = "test_cli",
        command = "claude",
        models = { "claude-sonnet-4-5" },
      })

      assert.is_not_nil(provider)
      assert.equals("test_cli", provider.name)
      assert.equals("claude", provider.command)
      assert.equals(1, #provider.models)
      assert.equals("claude-sonnet-4-5", provider.models[1])
    end)

    it("creates provider with command as table", function()
      local provider = ClaudeCliProvider:new({
        name = "test_cli",
        command = { "/usr/bin/claude", "--verbose" },
        models = { "claude-sonnet-4-5" },
      })

      assert.equals("/usr/bin/claude", provider:get_command())
    end)

    it("creates provider with default models", function()
      local provider = ClaudeCliProvider:new({
        name = "test_cli",
        command = "claude",
      })

      assert.equals(3, #provider.models)
      assert.is_true(vim.tbl_contains(provider.models, "claude-sonnet-4-5"))
    end)
  end)

  describe("Interface Methods", function()
    local provider

    before_each(function()
      provider = ClaudeCliProvider:new({
        name = "test_cli",
        command = "claude",
        models = { "claude-sonnet-4-5" },
      })
    end)

    it("get_command returns correct command", function()
      assert.equals("claude", provider:get_command())
    end)

    it("uses_json_payload returns false", function()
      assert.is_false(provider:uses_json_payload())
    end)

    it("resolve_api_key returns true (no API key needed)", function()
      assert.is_true(provider:resolve_api_key(nil))
      assert.is_true(provider:resolve_api_key("some-key"))
    end)

    it("verify returns true", function()
      assert.is_true(provider:verify())
    end)

    it("get_available_models returns static models", function()
      local models = provider:get_available_models()
      assert.equals(1, #models)
      assert.equals("claude-sonnet-4-5", models[1])
    end)

    it("online_model_fetching returns false", function()
      assert.is_false(provider:online_model_fetching())
    end)
  end)

  describe("curl_params", function()
    local provider

    before_each(function()
      provider = ClaudeCliProvider:new({
        name = "test_cli",
        command = "claude",
        models = { "claude-sonnet-4-5" },
      })
    end)

    it("returns basic args without system prompt", function()
      local payload = {
        messages = {
          { role = "user", content = "Hello" },
        },
      }

      local args = provider:curl_params(payload)

      assert.equals(3, #args)
      assert.equals("-p", args[1])
      assert.equals("--output-format", args[2])
      assert.equals("text", args[3])
    end)

    it("includes system prompt when present", function()
      local payload = {
        messages = {
          { role = "system", content = "You are helpful" },
          { role = "user", content = "Hello" },
        },
      }

      local args = provider:curl_params(payload)

      assert.equals(5, #args)
      assert.equals("-p", args[1])
      assert.equals("--output-format", args[2])
      assert.equals("text", args[3])
      assert.equals("--system-prompt", args[4])
      assert.equals("You are helpful", args[5])
    end)

    it("trims whitespace from system prompt", function()
      local payload = {
        messages = {
          { role = "system", content = "  You are helpful  " },
          { role = "user", content = "Hello" },
        },
      }

      local args = provider:curl_params(payload)

      assert.equals("You are helpful", args[5])
    end)

    it("filters empty system prompt", function()
      local payload = {
        messages = {
          { role = "system", content = "   " },
          { role = "user", content = "Hello" },
        },
      }

      local args = provider:curl_params(payload)

      assert.equals(3, #args) -- No system prompt args
    end)

    it("handles nil payload", function()
      local args = provider:curl_params(nil)

      assert.equals(3, #args)
      assert.equals("-p", args[1])
    end)

    it("handles payload with nil messages", function()
      local args = provider:curl_params({ messages = nil })

      assert.equals(3, #args)
    end)

    it("includes command_args", function()
      provider.command_args = { "--model", "opus" }

      local payload = {
        messages = {
          { role = "user", content = "Hello" },
        },
      }

      local args = provider:curl_params(payload)

      assert.equals(5, #args)
      assert.equals("--model", args[4])
      assert.equals("opus", args[5])
    end)

    it("handles command as table with extra args", function()
      provider.command = { "/usr/bin/claude", "--verbose" }

      local payload = {
        messages = {
          { role = "user", content = "Hello" },
        },
      }

      local args = provider:curl_params(payload)

      assert.equals(4, #args)
      assert.equals("--verbose", args[1])
      assert.equals("-p", args[2])
    end)
  end)

  describe("preprocess_payload", function()
    local provider

    before_each(function()
      provider = ClaudeCliProvider:new({
        name = "test_cli",
        command = "claude",
        models = { "claude-sonnet-4-5" },
      })
    end)

    it("extracts last user message", function()
      local payload = {
        messages = {
          { role = "system", content = "You are helpful" },
          { role = "user", content = "First question" },
          { role = "assistant", content = "First answer" },
          { role = "user", content = "Second question" },
        },
      }

      local result = provider:preprocess_payload(payload)

      assert.equals("Second question", result)
    end)

    it("trims whitespace from user message", function()
      local payload = {
        messages = {
          { role = "user", content = "  Hello  " },
        },
      }

      local result = provider:preprocess_payload(payload)

      assert.equals("Hello", result)
    end)

    it("handles nil payload", function()
      local result = provider:preprocess_payload(nil)

      assert.equals("", result)
    end)

    it("handles payload with nil messages", function()
      local result = provider:preprocess_payload({ messages = nil })

      assert.equals("", result)
    end)

    it("handles message with nil content", function()
      local payload = {
        messages = {
          { role = "user", content = nil },
        },
      }

      local result = provider:preprocess_payload(payload)

      assert.equals("", result)
    end)

    it("skips system messages", function()
      local payload = {
        messages = {
          { role = "system", content = "System prompt" },
          { role = "user", content = "User question" },
        },
      }

      local result = provider:preprocess_payload(payload)

      assert.equals("User question", result)
    end)
  end)

  describe("process_stdout", function()
    local provider

    before_each(function()
      provider = ClaudeCliProvider:new({
        name = "test_cli",
        command = "claude",
        models = { "claude-sonnet-4-5" },
      })
    end)

    it("returns line as-is", function()
      local result = provider:process_stdout("Hello world")

      assert.equals("Hello world", result)
    end)

    it("returns nil for empty line", function()
      local result = provider:process_stdout("")

      assert.is_nil(result)
    end)

    it("returns nil for nil line", function()
      local result = provider:process_stdout(nil)

      assert.is_nil(result)
    end)
  end)

  describe("process_onexit", function()
    local provider

    before_each(function()
      provider = ClaudeCliProvider:new({
        name = "test_cli",
        command = "claude",
        models = { "claude-sonnet-4-5" },
      })
    end)

    it("returns nil to avoid duplication", function()
      local result = provider:process_onexit("Some content")

      assert.is_nil(result)
    end)

    it("returns nil for empty response", function()
      local result = provider:process_onexit("")

      assert.is_nil(result)
    end)

    it("returns nil for nil response", function()
      local result = provider:process_onexit(nil)

      assert.is_nil(result)
    end)
  end)

  describe("Provider Detection", function()
    it("detects CLI provider via init_provider", function()
      local provider = init_provider({
        name = "test_cli",
        command = "claude",
        models = { "claude-sonnet-4-5" },
      })

      assert.equals("ClaudeCliProvider", getmetatable(provider).__index.__class)
    end)

    it("CLI provider does not require api_key", function()
      -- Should not error
      local provider = init_provider({
        name = "test_cli",
        command = "claude",
        models = { "claude-sonnet-4-5" },
      })

      assert.is_not_nil(provider)
    end)
  end)
end)

describe("Claude CLI Integration", function()
  local function claude_exists()
    local handle = io.popen("command -v claude 2>&1")
    if not handle then
      return false
    end
    local result = handle:read("*a")
    handle:close()
    return result and result:match("%S") ~= nil
  end

  local function has_auth()
    if not claude_exists() then
      return false
    end
    -- Try a simple command
    local handle = io.popen("echo 'test' | claude -p --output-format text 2>&1")
    if not handle then
      return false
    end
    local result = handle:read("*a")
    handle:close()
    -- If we get credit balance error, we have auth issues
    return not result:match("Credit balance is too low") and not result:match("authentication")
  end

  if claude_exists() then
    describe("Real Claude CLI Tests", function()
      local provider

      before_each(function()
        provider = ClaudeCliProvider:new({
          name = "test_cli",
          command = "claude",
          models = { "claude-sonnet-4-5" },
        })
      end)

      it("verify detects claude command", function()
        assert.is_true(provider:verify())
      end)

      if has_auth() then
        pending("executes basic command", function()
          local payload = {
            messages = {
              { role = "user", content = "Say 'test' and nothing else" },
            },
          }

          local args = provider:curl_params(payload)
          local stdin_data = provider:preprocess_payload(payload)

          -- Build command
          local cmd = "echo '" .. stdin_data:gsub("'", "'\\''") .. "' | " .. provider:get_command() .. " "
          for _, arg in ipairs(args) do
            cmd = cmd .. "'" .. arg:gsub("'", "'\\''") .. "' "
          end

          local handle = io.popen(cmd .. " 2>&1")
          assert.is_not_nil(handle)

          local result = handle:read("*a")
          local exit_code = handle:close()

          assert.is_not_nil(result)
          assert.is_true(exit_code == true or exit_code == 0)
          assert.is_true(#result > 0, "Expected non-empty result")
        end)

        pending("handles system prompt", function()
          local payload = {
            messages = {
              { role = "system", content = "You are a test assistant. Only say 'OK'." },
              { role = "user", content = "Respond" },
            },
          }

          local args = provider:curl_params(payload)
          local stdin_data = provider:preprocess_payload(payload)

          assert.is_true(vim.tbl_contains(args, "--system-prompt"))

          -- Build and run command
          local cmd = "echo '" .. stdin_data:gsub("'", "'\\''") .. "' | " .. provider:get_command() .. " "
          for _, arg in ipairs(args) do
            cmd = cmd .. "'" .. arg:gsub("'", "'\\''") .. "' "
          end

          local handle = io.popen(cmd .. " 2>&1")
          assert.is_not_nil(handle)

          local result = handle:read("*a")
          handle:close()

          assert.is_not_nil(result)
          assert.is_true(#result > 0)
        end)
      else
        pending("skipping authenticated tests (no valid auth or credits)")
      end
    end)
  else
    pending("Claude CLI Integration Tests (claude command not found)")
  end
end)
