local assert = require("luassert")
local spy = require("luassert.spy")
local mock = require("luassert.mock")

-- Mock the required modules
local logger_mock = mock(require("parrot.logger"), true)
local utils_mock = mock(require("parrot.utils"), true)
local Job_mock = mock(require("plenary.job"), true)

-- Load the Ollama class
local Ollama = require("parrot.provider.ollama")

describe("Ollama", function()
  local ollama

  before_each(function()
    ollama = Ollama:new("http://localhost:11434/api/generate", "")
    -- Reset mocks
    logger_mock.error:clear()
    logger_mock.warning:clear()
    logger_mock.info:clear()
    logger_mock.debug:clear()
  end)

  describe("process_onexit", function()
    it("should log an error message when there's an API error", function()
      local input = vim.json.encode({
        error = "model 'llama5:latest' not found, try pulling it first"
      })

      ollama:process_onexit(input)

      assert.spy(logger_mock.error).was_called_with("Ollama - code: model 'llama5:latest' not found, try pulling it first")
    end)

    it("should not log anything for successful responses", function()
      local input = vim.json.encode({ success = true })

      ollama:process_onexit(input)

      assert.spy(logger_mock.error).was_not_called()
    end)

    it("should handle invalid JSON gracefully", function()
      local input = "invalid json"

      ollama:process_onexit(input)

      assert.spy(logger_mock.error).was_not_called()
    end)
  end)

  describe("process_stdout", function()
    it("should extract content from a valid response", function()
      local input = '{"model":"llama3:latest","created_at":"2024-07-16T15:07:15.378379Z","message":{"role":"assistant","content":","},"done":false}'

      local result = ollama:process_stdout(input)

      assert.equals(",", result)
    end)

    it("should handle responses without content", function()
      local input = '{"model":"mistral:latest","created_at":"2024-07-16T15:07:27.808873Z","message":{"role":"assistant","content":""},"done_reason":"stop","done":true,"total_duration":9668777042,"load_duration":8020184084,"prompt_eval_count":414,"prompt_eval_duration":1276782000,"eval_count":13,"eval_duration":366249000}'

      local result = ollama:process_stdout(input)

      assert.equals("", result)
    end)

    it("should return nil for non-matching responses", function()
      local input = '{"type":"other_response"}'

      local result = ollama:process_stdout(input)

      assert.is_nil(result)
    end)

    it("should handle invalid JSON gracefully", function()
      local input = "invalid json"

      local result = ollama:process_stdout(input)

      assert.is_nil(result)
      assert.spy(logger_mock.debug).was_called()
    end)
  end)

  describe("preprocess_payload", function()
    it("should trim whitespace from message content", function()
      local payload = {
        messages = {
          { role = "user", content = "  Hello, Ollama!  " },
          { role = "assistant", content = " How can I help?  " }
        }
      }

      local result = ollama:preprocess_payload(payload)

      assert.equals("Hello, Ollama!", result.messages[1].content)
      assert.equals("How can I help?", result.messages[2].content)
    end)

    it("should filter payload parameters", function()
      utils_mock.filter_payload_parameters.returns({ filtered = true })

      local payload = { messages = {}, temperature = 0.7, invalid_param = "test" }

      local result = ollama:preprocess_payload(payload)

      assert.is_true(result.filtered)
      assert.spy(utils_mock.filter_payload_parameters).was_called_with(available_api_parameters, payload)
    end)
  end)

  describe("verify", function()
    it("should always return true", function()
      assert.is_true(ollama:verify())
    end)
  end)

  describe("add_system_prompt", function()
    it("should add a system prompt to messages if provided", function()
      local messages = {
        { role = "user", content = "Hello" }
      }
      local sys_prompt = "You are a helpful assistant."

      local result = ollama:add_system_prompt(messages, sys_prompt)

      assert.equals(2, #result)
      assert.same({ role = "system", content = sys_prompt }, result[1])
    end)

    it("should not add a system prompt if empty", function()
      local messages = {
        { role = "user", content = "Hello" }
      }
      local sys_prompt = ""

      local result = ollama:add_system_prompt(messages, sys_prompt)

      assert.equals(1, #result)
      assert.same(messages, result)
    end)
  end)

  -- describe("check", function()
  --   before_each(function()
  --     -- Mock vim.fn.executable
  --     _G.vim = _G.vim or {}
  --     _G.vim.fn = _G.vim.fn or {}
  --     _G.vim.fn.executable = function(cmd) return cmd == "ollama" end
  --
  --     -- Mock io.popen
  --     _G.io.popen = function()
  --       return {
  --         read = function() return "model1\nmodel2\nmodel3" end,
  --         close = function() end
  --       }
  --     end
  --
  --     -- Mock vim.fn.confirm
  --     _G.vim.fn.confirm = function() return 1 end
  --   end)
  --
  --   it("should return false if ollama is not installed", function()
  --     ollama.ollama_installed = false
  --     assert.is_false(ollama:check({ model = "model1" }))
  --     assert.spy(logger_mock.warning).was_called_with("ollama not found.")
  --   end)
  --
  --   it("should return true if the model is found", function()
  --     assert.is_true(ollama:check({ model = "model2" }))
  --   end)
  --
  --   it("should prompt to download if the model is not found", function()
  --     Job_mock.new.returns({ start = function() end })
  --     assert.is_true(ollama:check({ model = "new_model" }))
  --     assert.spy(logger_mock.info).was_called()
  --   end)
  --
  --   it("should handle plenary not being installed", function()
  --     package.loaded["plenary"] = nil
  --     assert.is_false(ollama:check({ model = "new_model" }))
  --     assert.spy(logger_mock.error).was_called_with("Plenary not installed. Please install nvim-lua/plenary.nvim to use this plugin.")
  --   end)
  -- end)

end)
