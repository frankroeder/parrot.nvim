local assert = require("luassert")
local spy = require("luassert.spy")
local mock = require("luassert.mock")

-- Mock the required modules
local logger_mock = mock(require("parrot.logger"), true)
local utils_mock = mock(require("parrot.utils"), true)

-- Load the OpenAI class
local OpenAI = require("parrot.provider.openai")

describe("OpenAI", function()
  local openai

  before_each(function()
    openai = OpenAI:new("https://api.openai.com/v1/chat/completions", "test_api_key")
    -- Reset mocks
    logger_mock.error:clear()
    logger_mock.debug:clear()
  end)

  describe("process_onexit", function()
    it("should log an error message when there's an API error", function()
      local input = vim.json.encode({
        error = {
          message = "Incorrect API key provided: sk-nkA3C********************************************sdas. You can find your API key at https://platform.openai.com/account/api-keys.",
          type = "invalid_request_error",
          param = vim.NIL,
          code = "invalid_api_key"
        }
      })

      openai:process_onexit(input)

      assert.spy(logger_mock.error).was_called_with(
        "OpenAI - code: invalid_api_key message:Incorrect API key provided: sk-nkA3C********************************************sdas. You can find your API key at https://platform.openai.com/account/api-keys. type:invalid_request_error"
      )
    end)

    it("should not log anything for successful responses", function()
      local input = vim.json.encode({ success = true })

      openai:process_onexit(input)

      assert.spy(logger_mock.error).was_not_called()
    end)

    it("should handle invalid JSON gracefully", function()
      local input = "invalid json"

      openai:process_onexit(input)

      assert.spy(logger_mock.error).was_not_called()
    end)
  end)

  describe("process_stdout", function()
    it("should extract content from a valid chat.completion.chunk response", function()
      local input = '{"id":"chatcmpl-9le9RfPtnfSdO84duGZ42emCzH41s","object":"chat.completion.chunk","created":1721142785,"model":"gpt-3.5-turbo-0125","system_fingerprint":null,"choices":[{"index":0,"delta":{"content":" Assistant"},"logprobs":null,"finish_reason":null}]}'

      local result = openai:process_stdout(input)

      assert.equals(" Assistant", result)
    end)

    it("should handle responses without content", function()
      local input = '{"id":"chatcmpl-9le9RfPtnfSdO84duGZ42emCzH41s","object":"chat.completion.chunk","created":1721142785,"model":"gpt-3.5-turbo-0125","system_fingerprint":null,"choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}'

      local result = openai:process_stdout(input)

      assert.equals("", result)
    end)

    it("should return nil for non-matching responses", function()
      local input = '{"type":"other_response"}'

      local result = openai:process_stdout(input)

      assert.is_nil(result)
    end)

    it("should handle invalid JSON gracefully", function()
      local input = "invalid json"

      local result = openai:process_stdout(input)

      assert.is_nil(result)
      assert.spy(logger_mock.debug).was_called()
    end)
  end)

  describe("preprocess_payload", function()
    it("should trim whitespace from message content", function()
      local payload = {
        messages = {
          { role = "user", content = "  Hello, OpenAI!  " },
          { role = "assistant", content = " How can I help?  " }
        }
      }

      local result = openai:preprocess_payload(payload)

      assert.equals("Hello, OpenAI!", result.messages[1].content)
      assert.equals("How can I help?", result.messages[2].content)
    end)

    it("should filter payload parameters", function()
      utils_mock.filter_payload_parameters.returns({ filtered = true })

      local payload = { messages = {}, temperature = 0.7, invalid_param = "test" }

      local result = openai:preprocess_payload(payload)

      assert.is_true(result.filtered)
      assert.spy(utils_mock.filter_payload_parameters).was_called_with(available_api_parameters, payload)
    end)
  end)

  describe("verify", function()
    it("should return true for a valid API key", function()
      assert.is_true(openai:verify())
    end)

    it("should return false and log an error for an invalid API key", function()
      openai.api_key = ""
      assert.is_false(openai:verify())
      assert.spy(logger_mock.error).was_called()
    end)

    it("should return false and log an error for an unresolved API key", function()
      openai.api_key = { unresolved = true }
      assert.is_false(openai:verify())
      assert.spy(logger_mock.error).was_called()
    end)
  end)

  describe("add_system_prompt", function()
    it("should add a system prompt to messages if provided", function()
      local messages = {
        { role = "user", content = "Hello" }
      }
      local sys_prompt = "You are a helpful assistant."

      local result = openai:add_system_prompt(messages, sys_prompt)

      assert.equals(2, #result)
      assert.same({ role = "system", content = sys_prompt }, result[1])
    end)

    it("should not add a system prompt if empty", function()
      local messages = {
        { role = "user", content = "Hello" }
      }
      local sys_prompt = ""

      local result = openai:add_system_prompt(messages, sys_prompt)

      assert.equals(1, #result)
      assert.same(messages, result)
    end)
  end)

  describe("check", function()
    it("should return true for supported models", function()
      assert.is_true(openai:check({ model = "gpt-4" }))
      assert.is_true(openai:check({ model = "gpt-3.5-turbo" }))
    end)

    it("should return false for unsupported models", function()
      assert.is_false(openai:check({ model = "unsupported-model" }))
    end)

    it("should handle model as a string or table", function()
      assert.is_true(openai:check("gpt-4"))
      assert.is_true(openai:check({ model = "gpt-4" }))
    end)
  end)
end)
