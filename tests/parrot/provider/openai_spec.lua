local assert = require("luassert")
local mock = require("luassert.mock")

-- Mock the required modules
local logger_mock = mock(require("parrot.logger"), true)

local OpenAI = require("parrot.provider.openai")

describe("OpenAI", function()
  local openai

  before_each(function()
    openai = OpenAI:new("https://api.openai.com/v1/chat/completions", "test_api_key")
    assert.are.same(openai.name, "openai")
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
          code = "invalid_api_key",
        },
      })

      openai:process_onexit(input)

      assert.spy(logger_mock.error).was_called_with(
        "OpenAI - code: invalid_api_key message:Incorrect API key provided: sk-nkA3C********************************************sdas. You can find your API key at https://platform.openai.com/account/api-keys. type:invalid_request_error"
      )
    end)

    it("should handle invalid JSON gracefully", function()
      local input = "invalid json"

      openai:process_onexit(input)

      assert.spy(logger_mock.error).was_not_called()
    end)
  end)

  describe("process_stdout", function()
    it("should extract content from a valid chat.completion.chunk response", function()
      local input =
        '{"id":"chatcmpl-9le9RfPtnfSdO84duGZ42emCzH41s","object":"chat.completion.chunk","created":1721142785,"model":"gpt-3.5-turbo-0125","system_fingerprint":null,"choices":[{"index":0,"delta":{"content":" Assistant"},"logprobs":null,"finish_reason":null}]}'

      local result = openai:process_stdout(input)

      assert.equals(" Assistant", result)
    end)

    it("should handle responses without content", function()
      local input =
        '{"id":"chatcmpl-9le9RfPtnfSdO84duGZ42emCzH41s","object":"chat.completion.chunk","created":1721142785,"model":"gpt-3.5-turbo-0125","system_fingerprint":null,"choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}'

      local result = openai:process_stdout(input)

      assert.equals("", result)
    end)

    it("should return nil for non-matching responses", function()
      local input = '{"type":"other_response"}'

      local result = openai:process_stdout(input)

      assert.is_nil(result)
    end)
  end)

  describe("preprocess_payload", function()
    it("should trim whitespace from message content", function()
      local payload = {
        messages = {
          { role = "user", content = "  Hello, OpenAI!  " },
          { role = "assistant", content = " How can I help?  " },
        },
      }

      local result = openai:preprocess_payload(payload)

      assert.equals("Hello, OpenAI!", result.messages[1].content)
      assert.equals("How can I help?", result.messages[2].content)
    end)

    it("should filter payload parameters", function()
      local input = {
        messages = {
          {
            content = "You are a versatile AI assistant with capabilities",
            role = "system",
          },
          {
            content = " Who are you?",
            role = "user",
          },
        },
        model = "gpt-3.5-turbo",
        stream = true,
        temperature = 1.1,
        top_p = 1,
      }

      local expected = {
        messages = {
          {
            content = "You are a versatile AI assistant with capabilities",
            role = "system",
          },
          {
            content = "Who are you?",
            role = "user",
          },
        },
        model = "gpt-3.5-turbo",
        stream = true,
        temperature = 1.1,
        top_p = 1,
      }

      local result = openai:preprocess_payload(input)
      assert.are.same(result, expected)
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
  end)

  describe("check", function()
    it("should handle model as a string or table", function()
      assert.is_true(openai:check("gpt-4"))
    end)

    it("should return false for unsupported models", function()
      assert.is_nil(openai:check("unsupported-model"))
    end)
  end)
end)
