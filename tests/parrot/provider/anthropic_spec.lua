local assert = require("luassert")
local mock = require("luassert.mock")

-- Mock the required modules
local logger_mock = mock(require("parrot.logger"), true)

-- Load the Anthropic class
local Anthropic = require("lua.parrot.provider.anthropic")

describe("Anthropic", function()
  local anthropic

  before_each(function()
    anthropic = Anthropic:new("https://api.anthropic.com", "test_api_key")
    assert.are.same(anthropic.name, "anthropic")
  end)

  describe("preprocess_payload", function()
    it("should handle payload with system message correctly", function()
      local input = {
        max_tokens = 4096,
        messages = {
          {
            content = "You are a versatile AI assistant with capabilities\nextending to general knowledge and coding support. When engaging\nwith users, please adhere to the following guidelines to ensure\nthe highest quality of interaction:\n\n- Admit when unsure by saying 'I don't know.'\n- Ask for clarification when needed.\n- Use first principles thinking to analyze queries.\n- Start with the big picture, then focus on details.\n- Apply the Socratic method to enhance understanding.\n- Include all necessary code in your responses.\n- Stay calm and confident with each task.\n",
            role = "system",
          },
          { content = "Who are you?", role = "user" },
        },
        model = "claude-3-haiku-20240307",
        stream = true,
      }

      local expected = {
        max_tokens = 4096,
        messages = {
          { content = "Who are you?", role = "user" },
        },
        model = "claude-3-haiku-20240307",
        stream = true,
        system = "You are a versatile AI assistant with capabilities\nextending to general knowledge and coding support. When engaging\nwith users, please adhere to the following guidelines to ensure\nthe highest quality of interaction:\n\n- Admit when unsure by saying 'I don't know.'\n- Ask for clarification when needed.\n- Use first principles thinking to analyze queries.\n- Start with the big picture, then focus on details.\n- Apply the Socratic method to enhance understanding.\n- Include all necessary code in your responses.\n- Stay calm and confident with each task.",
      }

      local result = anthropic:preprocess_payload(input)

      assert.are.same(expected, result)
    end)
  end)

  describe("verify", function()
    it("should return true for a valid API key", function()
      assert.is_true(anthropic:verify())
    end)

    it("should return false and log an error for an invalid API key", function()
      anthropic.api_key = ""
      assert.is_false(anthropic:verify())
      assert.spy(logger_mock.error).was_called()
    end)
  end)

  describe("process_onexit", function()
    it("should log an error message when there's an API error", function()
      local input = vim.json.encode({
        type = "error",
        error = { type = "authentication_error", message = "invalid x-api-key" },
      })

      anthropic:process_onexit(input)

      assert.spy(logger_mock.error).was_called_with("Anthropic - message: invalid x-api-key type: authentication_error")
    end)
  end)

  describe("process_stdout", function()
    it("should extract text from content_block_delta with text_delta", function()
      local input = '{"delta":{"type":"text_delta","text":"Hello, world!"}}'

      local result = anthropic:process_stdout(input)

      assert.equals("Hello, world!", result)
    end)

    it("should return nil for non-text_delta messages", function()
      local input = '{"delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":8}}'

      local result = anthropic:process_stdout(input)

      assert.is_nil(result)
    end)

    it("should handle invalid JSON gracefully", function()
      local input = "invalid json"

      local result = anthropic:process_stdout(input)

      assert.is_nil(result)
    end)

    it("should handle empty input gracefully", function()
      local input = ""

      local result = anthropic:process_stdout(input)

      assert.is_nil(result)
    end)

    it("should fail to decode", function()
      local input = "{ content_block_delta text_delta }"

      local result = anthropic:process_stdout(input)

      assert.is_nil(result)
    end)

    it("should accumulate thinking tokens in the floating window for reasoning", function()
      -- Simulate two consecutive streaming events with reasoning tokens.
      local stream1 = '{"delta": {"type": "thinking_delta", "thinking": "To calculate 27"}}'
      local stream2 = '{"delta": {"type": "thinking_delta", "thinking": " * 453, I\'ll multiply these"}}'
      anthropic:process_stdout(stream1)
      anthropic:process_stdout(stream2)
      -- Wait a short time to allow the scheduled callback to run.
      vim.wait(50)
      assert.equals("To calculate 27 * 453, I'll multiply these", anthropic._thinking_output)
    end)
  end)
  describe("predefined models", function()
    it("should return predefined list of available models.", function()
      local my_models = {
        "claude-3-haiku-20240307",
        "claude-3-opus-20240229",
        "claude-3-sonnet-20240229",
      }
      anthropic = Anthropic:new("https://api.anthropic.com", "test_api_key", my_models)
      assert.are.same(anthropic.models, my_models)
      assert.are.same(anthropic:get_available_models(false), my_models)
    end)
  end)
end)
