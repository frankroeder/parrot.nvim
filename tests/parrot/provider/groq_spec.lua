local assert = require("luassert")
local spy = require("luassert.spy")
local stub = require("luassert.stub")
local mock = require("luassert.mock")

-- Mock the required modules
local logger_mock = mock(require("parrot.logger"), true)
local utils_mock = mock(require("parrot.utils"), true)

-- Load the Groq class
local Groq = require("parrot.provider.groq")

describe("Groq", function()
  local groq

  before_each(function()
    groq = Groq:new("https://api.groq.com/openai/v1/chat/completions", "test_api_key")
    assert.are.same(groq.name, "groq")
  end)

  describe("process_onexit", function()
    it("should log an error message when there's an API error", function()
      local input = vim.json.encode({
        error = {
          message = "Invalid API Key",
          type = "invalid_request_error",
          code = "invalid_api_key",
        },
      })
      groq:process_onexit(input)
      assert.spy(logger_mock.error).was_called_with("Groq - message: Invalid API Key")
    end)
  end)

  describe("process_stdout", function()
    it("should extract content from chat.completion.chunk", function()
      local input =
        '{"id":"cmpl-1234","object":"chat.completion.chunk","created":1679801880,"model":"llama-3.1-70b-versatile","choices":[{"delta":{"content":"Hello"},"index":0,"finish_reason":null}]}'
      local result = groq:process_stdout(input)
      assert.equals("Hello", result)
    end)

    it("should extract content from chat.completion", function()
      local input =
        '{"id":"cmpl-5678","object":"chat.completion","created":1679801881,"model":"llama-3.1-70b-versatile","choices":[{"delta":{"content":"World"},"index":0,"finish_reason":"stop"}]}'
      local result = groq:process_stdout(input)
      assert.equals("World", result)
    end)

    it("should return nil for non-matching responses", function()
      local input = '{"type":"other_response"}'
      local result = groq:process_stdout(input)
      assert.is_nil(result)
    end)

    it("should handle invalid JSON gracefully", function()
      local input = "invalid json"
      local result = groq:process_stdout(input)
      assert.is_nil(result)
    end)
  end)

  describe("preprocess_payload", function()
    it("should trim whitespace from message content", function()
      local payload = {
        messages = {
          { role = "user", content = "  Hello, Groq!  " },
          { role = "assistant", content = " How can I help?  " },
        },
      }

      utils_mock.filter_payload_parameters.returns(payload)
      local result = groq:preprocess_payload(payload)
      assert.equals("Hello, Groq!", result.messages[1].content)
      assert.equals("How can I help?", result.messages[2].content)
    end)

    it("should filter payload parameters", function()
      local payload = { messages = {}, temperature = 0.7, invalid_param = "test" }
      utils_mock.filter_payload_parameters.returns({ filtered = true })
      local result = groq:preprocess_payload(payload)
      assert.is_true(result.filtered)
      -- assert.spy(utils_mock.filter_payload_parameters).was_called(1)
      -- assert.spy(utils_mock.filter_payload_parameters).was_called_with(assert.is_table(), payload)
    end)
  end)

  describe("verify", function()
    it("should return true for a valid API key", function()
      assert.is_true(groq:verify())
    end)

    it("should return false and log an error for an invalid API key", function()
      groq.api_key = ""
      assert.is_false(groq:verify())
      assert.spy(logger_mock.error).was_called()
    end)

    it("should handle API key as a table", function()
      groq.api_key = { "echo", "test_key" }
      local mock_handle = {
        read = function()
          return "test_key"
        end,
        close = function() end,
      }
      stub(io, "popen").returns(mock_handle)

      assert.is_true(groq:verify())
      assert.are.equal("test_key", groq.api_key)

      io.popen:revert()
    end)
  end)
end)
