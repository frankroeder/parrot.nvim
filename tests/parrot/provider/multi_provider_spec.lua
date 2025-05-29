local assert = require("luassert")
local mock = require("luassert.mock")

-- Mock the required modules
local logger_mock = mock(require("parrot.logger"), true)

-- MultiProvider tests - This provider is based on OpenAI's API format
-- and is designed to work with OpenAI and other OpenAI-compatible APIs
local MultiProvider = require("parrot.provider.multi_provider")

describe("MultiProvider", function()
  local provider

  before_each(function()
    provider = MultiProvider:new({
      name = "openai",
      endpoint = "https://api.openai.com/v1/chat/completions",
      api_key = "test_api_key",
      model = { "gpt-4o" },
    })
    assert.are.same(provider.name, "openai")
    -- Reset mocks
    logger_mock.error:clear()
    logger_mock.debug:clear()
  end)

  describe("validation", function()
    it("should validate required fields", function()
      assert.has_error(function()
        MultiProvider:new({})
      end, "Provider name is required")

      assert.has_error(function()
        MultiProvider:new({ name = "test" })
      end, "Provider endpoint is required")

      assert.has_error(function()
        MultiProvider:new({ name = "test", endpoint = "https://api.test.com" })
      end, "Provider API key is required")

      assert.has_error(function()
        MultiProvider:new({ name = "test", endpoint = "https://api.test.com", api_key = "test" })
      end, "Provider model(s) are required")
    end)

    it("should validate endpoint format", function()
      assert.has_error(function()
        MultiProvider:new({
          name = "test",
          endpoint = "invalid-url",
          api_key = "test",
          model = { "test-model" },
        })
      end, "Invalid endpoint format: invalid-url for provider test")
    end)

    it("should accept both http and https endpoints", function()
      local http_provider = MultiProvider:new({
        name = "test-http",
        endpoint = "http://api.test.com",
        api_key = "test",
        model = { "test-model" },
      })
      assert.equals("test-http", http_provider.name)

      local https_provider = MultiProvider:new({
        name = "test-https",
        endpoint = "https://api.test.com",
        api_key = "test",
        model = { "test-model" },
      })
      assert.equals("test-https", https_provider.name)
    end)

    it("should validate model endpoint format", function()
      assert.has_error(function()
        MultiProvider:new({
          name = "test",
          endpoint = "https://api.test.com",
          model_endpoint = "invalid-url",
          api_key = "test",
          model = { "test-model" },
        })
      end, "Invalid model endpoint format: invalid-url for provider test")
    end)

    it("should accept both http and https model endpoints", function()
      local http_provider = MultiProvider:new({
        name = "test-http-model",
        endpoint = "https://api.test.com",
        model_endpoint = "http://api.test.com/models",
        api_key = "test",
        model = { "test-model" },
      })
      assert.equals("test-http-model", http_provider.name)

      local https_provider = MultiProvider:new({
        name = "test-https-model",
        endpoint = "https://api.test.com",
        model_endpoint = "https://api.test.com/models",
        api_key = "test",
        model = { "test-model" },
      })
      assert.equals("test-https-model", https_provider.name)
    end)

    it("should allow empty model endpoint", function()
      local provider_no_model_endpoint = MultiProvider:new({
        name = "test-no-model-endpoint",
        endpoint = "https://api.test.com",
        model_endpoint = "",
        api_key = "test",
        model = { "test-model" },
      })
      assert.equals("test-no-model-endpoint", provider_no_model_endpoint.name)
    end)

    it("should validate models is a table", function()
      assert.has_error(function()
        MultiProvider:new({
          name = "test",
          endpoint = "https://api.test.com",
          api_key = "test",
          model = "single-model-string",
        })
      end, "Models must be provided as a table for provider test")
    end)

    it("should validate models table is not empty", function()
      assert.has_error(function()
        MultiProvider:new({
          name = "test",
          endpoint = "https://api.test.com",
          api_key = "test",
          model = {},
        })
      end, "Models table cannot be empty for provider test")
    end)
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
      assert.spy(logger_mock.error).was_called_with("Failed to decode API response: invalid json")
    end)
  end)

  describe("process_stdout", function()
    it("should extract content from a valid chat.completion.chunk response", function()
      local input =
        'data: {"id":"chatcmpl-9le9RfPtnfSdO84duGZ42emCzH41s","object":"chat.completion.chunk","created":1721142785,"model":"gpt-3.5-turbo-0125","system_fingerprint":null,"choices":[{"index":0,"delta":{"content":" Assistant"},"logprobs":null,"finish_reason":null}]}'

      local result = provider:process_stdout(input)

      assert.equals(" Assistant", result)
    end)

    it("should handle responses without content", function()
      local input =
        'data: {"id":"chatcmpl-9le9RfPtnfSdO84duGZ42emCzH41s","object":"chat.completion.chunk","created":1721142785,"model":"gpt-3.5-turbo-0125","system_fingerprint":null,"choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}'

      local result = provider:process_stdout(input)

      assert.equals("", result)
    end)

    it("should return nil for non-matching responses", function()
      local input = 'data: {"type":"other_response"}'

      local result = provider:process_stdout(input)

      assert.is_nil(result)
    end)

    it("should return nil for [DONE] message", function()
      local input = "data: [DONE]"

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
      local test_provider = MultiProvider:new({
        name = "openai",
        endpoint = "https://api.openai.com/v1/chat/completions",
        api_key = "test_api_key",
        model = my_models,
      })
      assert.are.same(test_provider.models, my_models)
      assert.are.same(test_provider:get_available_models(), my_models)
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
      local test_provider = MultiProvider:new({
        name = custom_name,
        endpoint = "https://api.example.com/v1/chat/completions",
        api_key = "test_api_key",
        model = custom_models,
      })
      assert.are.same(test_provider.models, custom_models)
      assert.are.same(test_provider:get_available_models(), custom_models)
      assert.are.same(test_provider.name, custom_name)
    end)
  end)

  describe("custom functions", function()
    it("should use custom headers function", function()
      local custom_provider = MultiProvider:new({
        name = "custom",
        endpoint = "https://api.custom.com/v1/chat/completions",
        api_key = "test_key",
        model = { "test-model" },
        headers = function(api_key)
          return {
            ["Content-Type"] = "application/json",
            ["X-API-Key"] = api_key,
            ["X-Custom"] = "custom-value",
          }
        end,
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
      local custom_provider = MultiProvider:new({
        name = "custom",
        endpoint = "https://api.custom.com/v1/chat/completions",
        api_key = "test_key",
        model = { "test-model" },
        process_stdout = function(response)
          if response:match("custom_content") then
            local decoded = vim.json.decode(response)
            return decoded.custom_content
          end
          return nil
        end,
      })

      local response = '{"custom_content": "Hello from custom provider"}'
      local result = custom_provider:process_stdout(response)
      assert.equals("Hello from custom provider", result)
    end)
  end)
end)
