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

    it("should accept function endpoints", function()
      local function_provider = MultiProvider:new({
        name = "test-function",
        endpoint = function(self)
          return "https://api.test.com/v1/" .. (self._model or "default")
        end,
        api_key = "test",
        model = { "test-model" },
      })
      assert.equals("test-function", function_provider.name)
    end)

    it("should reject invalid endpoint types", function()
      assert.has_error(function()
        MultiProvider:new({
          name = "test",
          endpoint = 123,
          api_key = "test",
          model = { "test-model" },
        })
      end, "Endpoint must be a string or function for provider test")
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

    it("should accept function model endpoints", function()
      local function_provider = MultiProvider:new({
        name = "test-function-model",
        endpoint = "https://api.test.com",
        model_endpoint = function(self)
          return "https://api.test.com/models?key=" .. self.api_key
        end,
        api_key = "test",
        model = { "test-model" },
      })
      assert.equals("test-function-model", function_provider.name)
    end)

    it("should reject invalid model endpoint types", function()
      assert.has_error(function()
        MultiProvider:new({
          name = "test",
          endpoint = "https://api.test.com",
          model_endpoint = 123,
          api_key = "test",
          model = { "test-model" },
        })
      end, "Model endpoint must be a string or function for provider test")
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
          models = "single-model-string",
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

    it("should validate headers type", function()
      assert.has_error(function()
        MultiProvider:new({
          name = "test",
          endpoint = "https://api.test.com",
          api_key = "test",
          model = { "test-model" },
          headers = "invalid-headers",
        })
      end, "Headers must be a function or table for provider test")
    end)

    it("should accept function headers", function()
      local provider = MultiProvider:new({
        name = "test",
        endpoint = "https://api.test.com",
        api_key = "test",
        model = { "test-model" },
        headers = function(self)
          return { ["Authorization"] = "Bearer " .. self.api_key }
        end,
      })
      assert.equals("test", provider.name)
    end)

    it("should accept table headers", function()
      local provider = MultiProvider:new({
        name = "test",
        endpoint = "https://api.test.com",
        api_key = "test",
        model = { "test-model" },
        headers = { ["Content-Type"] = "application/json" },
      })
      assert.equals("test", provider.name)
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

    -- it("should handle invalid JSON gracefully", function()
    --   local input = "invalid json"
    --   provider:process_onexit(input)
    --   assert.spy(logger_mock.error).was_called_with("Failed to decode API response: invalid json")
    -- end)
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

    it("should return false for nil API key", function()
      provider.api_key = nil
      assert.is_false(provider:verify())
      assert.spy(logger_mock.error).was_called()
    end)

    it("should return false for whitespace-only API key", function()
      provider.api_key = "   \t\n  "
      assert.is_false(provider:verify())
      assert.spy(logger_mock.error).was_called()
    end)

    it("should handle API key functions that return valid keys", function()
      provider.api_key = function()
        return "valid_key_from_function"
      end
      assert.is_true(provider:verify())
      assert.equals("valid_key_from_function", provider.api_key)
    end)

    it("should handle API key functions that throw errors", function()
      provider.api_key = function()
        error("Function failed")
      end
      assert.is_false(provider:verify())
      assert.spy(logger_mock.error).was_called()
    end)

    it("should handle command tables that return valid keys", function()
      -- Create a custom provider with a mock resolve_api_key function for testing
      local test_provider = MultiProvider:new({
        name = "test",
        endpoint = "https://api.test.com",
        api_key = { "mock_command", "arg1" },
        model = { "test-model" },
        resolve_api_key = function(self, api_key)
          if type(api_key) == "table" and api_key[1] == "mock_command" then
            return "test_key_from_command"
          end
          return false
        end,
      })
      assert.is_true(test_provider:verify())
      assert.equals("test_key_from_command", test_provider.api_key)
    end)

    it("should reject empty command tables", function()
      provider.api_key = {}
      assert.is_false(provider:verify())
      assert.spy(logger_mock.error).was_called()
    end)

    it("should reject command tables with non-string arguments", function()
      provider.api_key = { "echo", 123 }
      assert.is_false(provider:verify())
      assert.spy(logger_mock.error).was_called()
    end)

    it("should handle commands that fail", function()
      provider.api_key = { "false" } -- This command always fails
      assert.is_false(provider:verify())
      assert.spy(logger_mock.error).was_called()
    end)

    it("should handle commands that return empty output", function()
      -- Create a test provider with a mock that returns false for empty output
      local test_provider = MultiProvider:new({
        name = "test",
        endpoint = "https://api.test.com",
        api_key = { "mock_empty_command" },
        model = { "test-model" },
        resolve_api_key = function(self, api_key)
          if type(api_key) == "table" and api_key[1] == "mock_empty_command" then
            return false -- Simulate the real behavior: empty output results in false
          end
          return false
        end,
      })
      assert.is_false(test_provider:verify())
    end)

    it("should trim whitespace from command output", function()
      -- Create a test provider with a mock that returns whitespace-padded string
      local test_provider = MultiProvider:new({
        name = "test",
        endpoint = "https://api.test.com",
        api_key = { "mock_whitespace_command" },
        model = { "test-model" },
        resolve_api_key = function(self, api_key)
          if type(api_key) == "table" and api_key[1] == "mock_whitespace_command" then
            return "  key_with_spaces  "
          end
          return false
        end,
      })
      assert.is_true(test_provider:verify())
      assert.equals("  key_with_spaces  ", test_provider.api_key)
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

  describe("curl_params", function()
    it("should return curl parameters for valid provider", function()
      local params = provider:curl_params()
      assert.is_not_nil(params)
      assert.is_true(#params > 0)
      assert.equals("https://api.openai.com/v1/chat/completions", params[1])
    end)

    it("should return empty table when API key verification fails", function()
      provider.api_key = ""
      local params = provider:curl_params()
      assert.are.same({}, params)
    end)

    it("should handle function endpoints", function()
      local function_provider = MultiProvider:new({
        name = "test-function",
        endpoint = function(self)
          return "https://api.test.com/v1/" .. (self._model or "default")
        end,
        api_key = "test",
        model = { "test-model" },
      })
      function_provider:set_model("gpt-4")
      local params = function_provider:curl_params()
      assert.equals("https://api.test.com/v1/gpt-4", params[1])
    end)

    it("should handle failing function endpoints", function()
      local failing_provider = MultiProvider:new({
        name = "test-failing",
        endpoint = function(self)
          error("Endpoint function failed")
        end,
        api_key = "test",
        model = { "test-model" },
      })
      local params = failing_provider:curl_params()
      assert.are.same({}, params)
      assert.spy(logger_mock.error).was_called()
    end)

    it("should handle endpoints that return invalid values", function()
      local invalid_provider = MultiProvider:new({
        name = "test-invalid",
        endpoint = function(self)
          return 123 -- Invalid return type
        end,
        api_key = "test",
        model = { "test-model" },
      })
      local params = invalid_provider:curl_params()
      assert.are.same({}, params)
      assert.spy(logger_mock.error).was_called()
    end)
  end)

  describe("get_available_models", function()
    it("should return predefined models when no model_endpoint", function()
      local models = provider:get_available_models()
      assert.are.same({ "gpt-4o" }, models)
    end)

    it("should handle function model endpoints", function()
      local function_provider = MultiProvider:new({
        name = "test-function-model",
        endpoint = "https://api.test.com",
        model_endpoint = function(self)
          return "https://api.test.com/models?key=" .. self.api_key
        end,
        api_key = "test",
        model = { "test-model" },
        -- Override the get_available_models to avoid real HTTP calls
        get_available_models = function(self, args)
          -- Mock implementation that just returns predefined models
          return self.models
        end,
      })
      local models = function_provider:get_available_models()
      assert.are.same({ "test-model" }, models)
    end)

    it("should handle failing function model endpoints", function()
      local failing_provider = MultiProvider:new({
        name = "test-failing-model",
        endpoint = "https://api.test.com",
        model_endpoint = function(self)
          error("Model endpoint function failed")
        end,
        api_key = "test",
        model = { "test-model" },
      })
      local models = failing_provider:get_available_models()
      assert.are.same({ "test-model" }, models)
      assert.spy(logger_mock.error).was_called()
    end)

    it("should return predefined models when API verification fails", function()
      provider.api_key = ""
      local models = provider:get_available_models()
      assert.are.same({ "gpt-4o" }, models)
    end)
  end)
  describe("get_available_models_cached", function()
    local mock_state

    before_each(function()
      mock_state = {
        get_cached_models = function()
          return nil
        end,
        set_cached_models = function() end,
        save = function() end,
      }
    end)

    it("should return predefined models when no model_endpoint", function()
      local provider_no_endpoint = MultiProvider:new({
        name = "test-no-endpoint",
        endpoint = "https://api.test.com",
        api_key = "test",
        model = { "test-model" },
      })

      local models = provider_no_endpoint:get_available_models_cached(mock_state, 48, nil)
      assert.are.same({ "test-model" }, models)
    end)

    it("should return cached models when available and valid", function()
      local cached_models = { "cached-model1", "cached-model2" }
      mock_state.get_cached_models = function()
        return cached_models
      end

      local provider_with_endpoint = MultiProvider:new({
        name = "test-cached",
        endpoint = "https://api.test.com",
        model_endpoint = "https://api.test.com/models",
        api_key = "test",
        model = { "test-model" },
      })

      local models = provider_with_endpoint:get_available_models_cached(mock_state, 48, nil)
      assert.are.same(cached_models, models)
    end)

    it("should fetch fresh models when cache is invalid", function()
      mock_state.get_cached_models = function()
        return nil
      end -- Cache miss
      local set_cached_called = false
      local save_called = false

      mock_state.set_cached_models = function()
        set_cached_called = true
      end
      mock_state.save = function()
        save_called = true
      end

      local provider_with_endpoint = MultiProvider:new({
        name = "test-fresh",
        endpoint = "https://api.test.com",
        model_endpoint = "https://api.test.com/models",
        api_key = "test",
        model = { "original-model" },
        get_available_models = function(self, args)
          return { "fresh-model1", "fresh-model2" }
        end,
      })

      local models = provider_with_endpoint:get_available_models_cached(mock_state, 48, nil)
      assert.are.same({ "fresh-model1", "fresh-model2" }, models)
      assert.is_true(set_cached_called)
      assert.is_true(save_called)
    end)

    it("should not cache models if they are the same as predefined", function()
      mock_state.get_cached_models = function()
        return nil
      end
      local set_cached_called = false

      mock_state.set_cached_models = function()
        set_cached_called = true
      end

      local provider_same_models = MultiProvider:new({
        name = "test-same",
        endpoint = "https://api.test.com",
        model_endpoint = "https://api.test.com/models",
        api_key = "test",
        model = { "same-model" },
        get_available_models = function(self, args)
          return { "same-model" } -- Same as predefined
        end,
      })

      local models = provider_same_models:get_available_models_cached(mock_state, 48, nil)
      assert.are.same({ "same-model" }, models)
      assert.is_false(set_cached_called)
    end)

    it("should handle spinner start and stop", function()
      mock_state.get_cached_models = function()
        return nil
      end

      local spinner_started = false
      local spinner_stopped = false
      local mock_spinner = {
        start = function()
          spinner_started = true
        end,
        stop = function()
          spinner_stopped = true
        end,
      }

      local provider_with_spinner = MultiProvider:new({
        name = "test-spinner",
        endpoint = "https://api.test.com",
        model_endpoint = "https://api.test.com/models",
        api_key = "test",
        model = { "test-model" },
        get_available_models = function(self, args)
          return { "fresh-model" }
        end,
      })

      local models = provider_with_spinner:get_available_models_cached(mock_state, 48, mock_spinner)
      assert.are.same({ "fresh-model" }, models)
      assert.is_true(spinner_started)
      assert.is_true(spinner_stopped)
    end)

    it("should work without spinner", function()
      mock_state.get_cached_models = function()
        return nil
      end

      local provider_no_spinner = MultiProvider:new({
        name = "test-no-spinner",
        endpoint = "https://api.test.com",
        model_endpoint = "https://api.test.com/models",
        api_key = "test",
        model = { "test-model" },
        get_available_models = function(self, args)
          return { "fresh-model" }
        end,
      })

      local models = provider_no_spinner:get_available_models_cached(mock_state, 48, nil)
      assert.are.same({ "fresh-model" }, models)
    end)
  end)
  describe("resolve_api_key", function()
    describe("string api_key", function()
      it("should return the API key as-is when it's a valid string", function()
        local result = provider:resolve_api_key("valid_api_key")
        assert.equals("valid_api_key", result)
      end)

      it("should trim whitespace from string API keys", function()
        local result = provider:resolve_api_key("  api_key_with_spaces  ")
        assert.equals("api_key_with_spaces", result)
      end)

      it("should handle strings with mixed whitespace", function()
        local result = provider:resolve_api_key(" \t api_key \n ")
        assert.equals("api_key", result)
      end)

      it("should return false for empty strings", function()
        local result = provider:resolve_api_key("")
        assert.equals(false, result)
        assert.spy(logger_mock.error).was_called()
      end)

      it("should return false for whitespace-only strings", function()
        local result = provider:resolve_api_key("   \t\n  ")
        assert.equals(false, result)
        assert.spy(logger_mock.error).was_called()
      end)

      it("should return false for nil", function()
        local result = provider:resolve_api_key(nil)
        assert.equals(false, result)
        assert.spy(logger_mock.error).was_called()
      end)
    end)

    describe("function api_key", function()
      it("should call function and return result for valid API key function", function()
        local api_key_func = function()
          return "function_generated_key"
        end
        local result = provider:resolve_api_key(api_key_func)
        assert.equals("function_generated_key", result)
      end)

      it("should handle functions that return strings with whitespace", function()
        local api_key_func = function()
          return "  function_key_with_spaces  "
        end
        local result = provider:resolve_api_key(api_key_func)
        assert.equals("function_key_with_spaces", result)
      end)

      it("should handle functions that return empty strings", function()
        local api_key_func = function()
          return ""
        end
        local result = provider:resolve_api_key(api_key_func)
        assert.equals(false, result)
        assert.spy(logger_mock.error).was_called()
      end)

      it("should handle functions that return nil", function()
        local api_key_func = function()
          return nil
        end
        local result = provider:resolve_api_key(api_key_func)
        assert.equals(false, result)
        assert.spy(logger_mock.error).was_called()
      end)

      it("should handle functions that throw errors", function()
        local failing_func = function()
          error("Function execution failed")
        end
        local result = provider:resolve_api_key(failing_func)
        assert.equals(false, result)
        assert.spy(logger_mock.error).was_called()
      end)

      it("should recursively resolve functions that return other functions", function()
        local nested_func = function()
          return function()
            return "nested_key"
          end
        end
        local result = provider:resolve_api_key(nested_func)
        assert.equals("nested_key", result)
      end)

      it("should handle functions that return commands (tables)", function()
        local func_returning_table = function()
          return { "echo", "command_from_function" }
        end
        -- Mock the command execution for this test
        local test_provider = MultiProvider:new({
          name = "test",
          endpoint = "https://api.test.com",
          api_key = func_returning_table,
          model = { "test-model" },
          resolve_api_key = function(self, api_key)
            if type(api_key) == "function" then
              local ok, result = pcall(api_key)
              if not ok then
                return false
              end
              return self:resolve_api_key(result)
            elseif type(api_key) == "table" then
              return "mocked_command_result"
            else
              return api_key
            end
          end,
        })
        local result = test_provider:resolve_api_key(func_returning_table)
        assert.equals("mocked_command_result", result)
      end)
    end)

    describe("table api_key (commands)", function()
      it("should execute simple echo command", function()
        local echo_command = { "echo", "test_api_key" }
        local result = provider:resolve_api_key(echo_command)
        assert.equals("test_api_key", result)
      end)

      it("should trim whitespace from command output", function()
        local echo_command = { "echo", "  key_with_spaces  " }
        local result = provider:resolve_api_key(echo_command)
        assert.equals("key_with_spaces", result)
      end)

      it("should handle commands with multiple arguments", function()
        local printf_command = { "printf", "%s", "multi_arg_key" }
        local result = provider:resolve_api_key(printf_command)
        assert.equals("multi_arg_key", result)
      end)

      it("should return false for empty command tables", function()
        local result = provider:resolve_api_key({})
        assert.equals(false, result)
        assert.spy(logger_mock.error).was_called()
      end)

      it("should return false for commands with non-string arguments", function()
        local invalid_command = { "echo", 123 }
        local result = provider:resolve_api_key(invalid_command)
        assert.equals(false, result)
        assert.spy(logger_mock.error).was_called()
      end)

      it("should return false for commands with mixed argument types", function()
        local mixed_command = { "echo", "valid", 456, "also_valid" }
        local result = provider:resolve_api_key(mixed_command)
        assert.equals(false, result)
        assert.spy(logger_mock.error).was_called()
      end)

      it("should handle commands that return empty output", function()
        local empty_command = { "true" } -- true command returns success but no output
        local result = provider:resolve_api_key(empty_command)
        assert.equals(false, result)
        assert.spy(logger_mock.error).was_called()
      end)

      it("should handle failing commands", function()
        local failing_command = { "false" } -- false command always fails
        local result = provider:resolve_api_key(failing_command)
        assert.equals(false, result)
        assert.spy(logger_mock.error).was_called()
      end)

      it("should handle commands that don't exist", function()
        local nonexistent_command = { "nonexistent_command_12345" }
        local result = provider:resolve_api_key(nonexistent_command)
        assert.equals(false, result)
        assert.spy(logger_mock.error).was_called()
      end)

      it("should handle complex shell commands", function()
        -- Test with a command that uses shell features
        local shell_command = { "printf", "shell_key" }
        local result = provider:resolve_api_key(shell_command)
        assert.equals("shell_key", result)
      end)

      it("should handle commands with special characters in output", function()
        local special_command = { "echo", "key-with-special_chars.123" }
        local result = provider:resolve_api_key(special_command)
        assert.equals("key-with-special_chars.123", result)
      end)
    end)

    describe("edge cases and invalid types", function()
      it("should return false for number types", function()
        local result = provider:resolve_api_key(123)
        assert.equals(false, result)
        assert.spy(logger_mock.error).was_called()
      end)

      it("should return false for boolean types", function()
        local result = provider:resolve_api_key(true)
        assert.equals(false, result)
        assert.spy(logger_mock.error).was_called()
      end)

      it("should return false for boolean false", function()
        local result = provider:resolve_api_key(false)
        assert.equals(false, result)
        assert.spy(logger_mock.error).was_called()
      end)

      it("should handle deeply nested function calls", function()
        local deep_func = function()
          return function()
            return function()
              return "deep_key"
            end
          end
        end
        local result = provider:resolve_api_key(deep_func)
        assert.equals("deep_key", result)
      end)

      -- Note: We don't test infinite recursion as it would cause real stack overflow
      -- In practice, Lua would throw a stack overflow error for truly infinite recursion
    end)
  end)
end)
