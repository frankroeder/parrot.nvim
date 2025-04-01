local assert = require("luassert")
local mock = require("luassert.mock")

-- Mock the required modules
local logger_mock = mock(require("parrot.logger"), true)

local Nvidia = require("parrot.provider.nvidia")

describe("Nvidia", function()
  local nvidia

  before_each(function()
    nvidia = Nvidia:new("https://integrate.api.nvidia.com/v1/chat/completions", "test_api_key")
    assert.are.same(nvidia.name, "nvidia")
    -- Reset mocks
    logger_mock.error:clear()
    logger_mock.debug:clear()
  end)

  describe("process_onexit", function()
    it("should log an error message when there's an API error", function()
      -- { "data:{\"type\":\"urn:inference-service:problem-details:bad-request\",\"title\":\"Bad Request\",\"status\":400,\"detail\":\"[{'type': 'string_too_short', 'loc': ('body', 'messages', 2, 'content'), 'msg': 'String should have at least 1 character', 'input': '', 'ctx': {'min_length': 1}}]\",\"instance\":\"/v2/nvcf/pexec/functions/9b96341b-9791-4db9-a00d-4e43aa192a39\",\"requestId\":\"2176a5ed-bdd4-4cf0-a835-ee055b17725c\"}", "" }
      local input = vim.json.encode({
        data = {
          type = "urn:inference-service:problem-details:bad-request",
          title = "Bad Request",
          status = 400,
          detail = {
            {
              type = "string_too_short",
              loc = { "body", "messages", 2, "content" },
              msg = "String should have at least 1 character",
              input = "",
              ctx = { min_length = 1 },
            },
          },
          instance = "/v2/nvcf/pexec/functions/9b96341b-9791-4db9-a00d-4e43aa192a39",
          requestId = "2176a5ed-bdd4-4cf0-a835-ee055b17725c",
        },
      })

      nvidia:process_onexit(input)

      assert.spy(logger_mock.error).was_called_with(
        "Nvidia - code: 400 title Bad Request message: String should have at least 1 character type: urn:inference-service:problem-details:bad-request"
      )
    end)

    it("should handle invalid JSON gracefully", function()
      local input = "invalid json"

      nvidia:process_onexit(input)

      assert.spy(logger_mock.error).was_not_called()
    end)
  end)

  describe("process_stdout", function()
    it("should extract content from a valid chat.completion.chunk response", function()
      local input =
        '{"id":"chat-ade745b94fa342f39bbfd832c70d5ee4","object":"chat.completion.chunk","created":1729106490,"model":"nvidia/llama-3.1-nemotron-70b-instruct","choices":[{"index":0,"delta":{"role":null,"content":" like"},"logprobs":null,"finish_reason":null}]}'

      local result = nvidia:process_stdout(input)

      assert.equals(" like", result)
    end)

    it("should handle responses without content", function()
      local input =
        '{ "id": "chat-90c70063686e46b9abc0a2823fd9e582", "object": "chat.completion.chunk", "created": 1729107730, "model": "nvidia/llama-3.1-nemotron-70b-instruct", "choices": [ { "index": 0, "delta": { "role": "assistant", "content": null }, "logprobs": null, "finish_reason": null } ] }'

      local result = nvidia:process_stdout(input)

      assert.equals(nil, result)
    end)

    it("should return nil for non-matching responses", function()
      local input = '{"type":"other_response"}'

      local result = nvidia:process_stdout(input)

      assert.is_nil(result)
    end)
  end)

  describe("preprocess_payload", function()
    it("should trim whitespace from message content", function()
      local payload = {
        messages = {
          { role = "user", content = "  Hello, Nvidia!  " },
          { role = "assistant", content = " How can I help?  " },
        },
      }

      local result = nvidia:preprocess_payload(payload)

      assert.equals("Hello, Nvidia!", result.messages[1].content)
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
        model = "nvidia/llama-3.1-nemotron-70b-instruct",
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
        model = "nvidia/llama-3.1-nemotron-70b-instruct",
        stream = true,
        temperature = 1.1,
        top_p = 1,
      }

      local result = nvidia:preprocess_payload(input)
      assert.are.same(result, expected)
    end)
  end)

  describe("verify", function()
    it("should return true for a valid API key", function()
      assert.is_true(nvidia:verify())
    end)

    it("should return false and log an error for an invalid API key", function()
      nvidia.api_key = ""
      assert.is_false(nvidia:verify())
      assert.spy(logger_mock.error).was_called()
    end)
  end)
  describe("predefined models", function()
    it("should return predefined list of available models.", function()
      local my_models = {
        "nvidia/llama-3.1-nemotron-70b-instruct",
        "01-ai/yi-large",
      }
      nvidia = Nvidia:new("https://integrate.api.nvidia.com/v1/chat/completions", "test_api_key", my_models)
      assert.are.same(nvidia.models, my_models)
      assert.are.same(nvidia:get_available_models(false), my_models)
    end)
  end)
end)
