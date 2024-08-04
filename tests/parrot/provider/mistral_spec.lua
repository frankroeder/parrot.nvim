local assert = require("luassert")
local spy = require("luassert.spy")
local mock = require("luassert.mock")

-- Mock the required modules
local logger_mock = mock(require("parrot.logger"), true)
local utils_mock = mock(require("parrot.utils"), true)

-- Load the Mistral class
local Mistral = require("parrot.provider.mistral")

describe("Mistral", function()
  local mistral

  before_each(function()
    mistral = Mistral:new("https://api.mistral.ai/v1/chat/completions", "test_api_key")
    assert.are.same(mistral.name, "mistral")
  end)

  describe("process_onexit", function()
    it("should log an error message when there's an API error", function()
      local input = vim.json.encode({
        message = "Unauthorized",
        request_id = "1f1fcascasca",
      })

      mistral:process_onexit(input)

      assert.spy(logger_mock.error).was_called_with("Mistral - message: Unauthorized")
    end)
  end)

  describe("process_stdout", function()
    it("should extract content from chat.completion.chunk", function()
      local input =
        '{"id":"cmpl-1234","object":"chat.completion.chunk","created":1679801880,"model":"mistral-medium","choices":[{"delta":{"content":"Hello"},"index":0,"finish_reason":null}]}'

      local result = mistral:process_stdout(input)

      assert.equals("Hello", result)
    end)

    it("should extract content from chat.completion", function()
      local input =
        '{"id":"cmpl-5678","object":"chat.completion","created":1679801881,"model":"mistral-medium","choices":[{"delta":{"content":"World"},"index":0,"finish_reason":"stop"}]}'

      local result = mistral:process_stdout(input)

      assert.equals("World", result)
    end)

    it("should return nil for non-matching responses", function()
      local input = '{"type":"other_response"}'

      local result = mistral:process_stdout(input)

      assert.is_nil(result)
    end)

    it("should handle invalid JSON gracefully", function()
      local input = "invalid json"

      local result = mistral:process_stdout(input)

      assert.is_nil(result)
    end)
  end)

  describe("preprocess_payload", function()
    -- it("should trim whitespace from message content", function()
    --   local payload = {
    --     messages = {
    --       { role = "user", content = "  Hello, Mistral!  " },
    --       { role = "assistant", content = " How can I help?  " }
    --     }
    --   }
    --
    --   local result = mistral:preprocess_payload(payload)
    --   assert.equals("Hello, Mistral!", result.messages[1].content)
    --   assert.equals("How can I help?", result.messages[2].content)
    -- end)

    it("should filter payload parameters", function()
      utils_mock.filter_payload_parameters.returns({ filtered = true })

      local payload = { messages = {}, temperature = 0.7, invalid_param = "test" }

      local result = mistral:preprocess_payload(payload)

      assert.is_true(result.filtered)
      -- assert.spy(utils_mock.filter_payload_parameters).was_called_with(available_api_parameters, payload)
    end)
  end)

  describe("verify", function()
    it("should return true for a valid API key", function()
      assert.is_true(mistral:verify())
    end)

    it("should return false and log an error for an invalid API key", function()
      mistral.api_key = ""
      assert.is_false(mistral:verify())
      assert.spy(logger_mock.error).was_called()
    end)
  end)

  describe("check", function()
    it("should return true for supported models", function()
      assert.is_true(mistral:check({ model = "mistral-medium-latest" }))
      assert.is_true(mistral:check({ model = "open-mixtral-8x7b" }))
    end)

    it("should return false for unsupported models", function()
      assert.is_nil(mistral:check({ model = "unsupported-model" }))
    end)
  end)
end)
