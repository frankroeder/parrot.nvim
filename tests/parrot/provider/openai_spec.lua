local assert = require("luassert")
local mock = require("luassert.mock")

-- Mock the required modules
local logger_mock = mock(require("parrot.logger"), true)

local Provider = require("parrot.provider.openai")

describe("Provider", function()
  local provider

  before_each(function()
    provider = Provider:new({
      name = "openai",
      endpoint = "https://api.openai.com/v1/chat/completions",
      api_key = "test_api_key",
      model = "gpt-4o"
    })
    assert.are.same(provider.name, "openai")
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

      provider:process_onexit(input)

      assert.spy(logger_mock.error).was_called_with(
        "Provider error: Incorrect API key provided: sk-nkA3C********************************************sdas. You can find your API key at https://platform.openai.com/account/api-keys."
      )
    end)

    it("should handle invalid JSON gracefully", function()
      local input = "invalid json"

      provider:process_onexit(input)

      assert.spy(logger_mock.error).was_not_called()
    end)
  end)

  describe("process_stdout", function()
    it("should extract content from a valid chat.completion.chunk response", function()
      local input = 'data: {"id":"chatcmpl-9le9RfPtnfSdO84duGZ42emCzH41s","object":"chat.completion.chunk","created":1721142785,"model":"gpt-3.5-turbo-0125","system_fingerprint":null,"choices":[{"index":0,"delta":{"content":" Assistant"},"logprobs":null,"finish_reason":null}]}'

      local result = provider:process_stdout(input)

      assert.equals(" Assistant", result)
    end)

    it("should handle responses without content", function()
      local input = 'data: {"id":"chatcmpl-9le9RfPtnfSdO84duGZ42emCzH41s","object":"chat.completion.chunk","created":1721142785,"model":"gpt-3.5-turbo-0125","system_fingerprint":null,"choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}'

      local result = provider:process_stdout(input)

      assert.equals("", result)
    end)

    it("should return nil for non-matching responses", function()
      local input = 'data: {"type":"other_response"}'

      local result = provider:process_stdout(input)

      assert.is_nil(result)
    end)

    it("should return nil for [DONE] message", function()
      local input = 'data: [DONE]'

      local result = provider:process_stdout(input)

      assert.is_nil(result)
    end)
  end)

  describe("preprocess_payload", function()
    it("should trim whitespace from message content", function()
      local payload = {
        messages = {
          { role = "user", content = "  Hello, AI!  " },
          { role = "assistant", content = " How can I help?  " },
        },
      }

      local result = provider:preprocess_payload(payload)

      assert.equals("Hello, AI!", result.messages[1].content)
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

      local result = provider:preprocess_payload(input)
      assert.are.same(result, expected)
    end)
  end)

  describe("verify", function()
    it("should return true for a valid API key", function()
      assert.is_true(provider:verify())
    end)

    it("should return false and log an error for an invalid API key", function()
      provider.api_key = ""
      assert.is_false(provider:verify())
      assert.spy(logger_mock.error).was_called()
    end)
  end)

  describe("predefined models", function()
    it("should return predefined list of available models.", function()
      local my_models = {
        "o1-preview",
        "gpt-4-turbo",
        "o1",
        "gpt-4",
      }
      provider = Provider:new({
        name = "openai",
        endpoint = "https://api.openai.com/v1/chat/completions",
        api_key = "test_api_key",
        model = my_models
      })
      assert.are.same(provider.models, my_models)
      assert.are.same(provider:get_available_models(false), my_models)
    end)
  end)

  describe("setup as custom provider", function()
    it("should return predefined list of available models.", function()
      local custom_name = "agi_company"
      local custom_models = {
        "custom-bar",
        "agi-v1",
        "agi-system-2",
      }
      provider = Provider:new({
        name = custom_name,
        endpoint = "https://api.example.com/v1/chat/completions",
        api_key = "test_api_key",
        model = custom_models
      })
      assert.are.same(provider.models, custom_models)
      assert.are.same(provider:get_available_models(false), custom_models)
      assert.are.same(provider.name, custom_name)
    end)
  end)

  describe("custom functions", function()
    it("should use custom headers function", function()
      local custom_provider = Provider:new({
        name = "custom",
        endpoint = "https://api.custom.com/v1/chat/completions",
        api_key = "test_key",
        headers = function(api_key)
          return {
            ["Content-Type"] = "application/json",
            ["X-API-Key"] = api_key,
            ["X-Custom"] = "custom-value",
          }
        end
      })

      local curl_params = custom_provider:curl_params()
      local found_custom_header = false
      for i, param in ipairs(curl_params) do
        if param == "X-Custom: custom-value" then
          found_custom_header = true
          break
        end
      end
      assert.is_true(found_custom_header)
    end)

    it("should use custom process_stdout function", function()
      local custom_provider = Provider:new({
        name = "custom",
        endpoint = "https://api.custom.com/v1/chat/completions",
        api_key = "test_key",
        process_stdout = function(response)
          if response:match("custom_content") then
            local decoded = vim.json.decode(response)
            return decoded.custom_content
          end
          return nil
        end
      })

      local response = '{"custom_content": "Hello from custom provider"}'
      local result = custom_provider:process_stdout(response)
      assert.equals("Hello from custom provider", result)
    end)
  end)
end)
