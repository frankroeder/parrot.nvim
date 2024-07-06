local config_utils = require("parrot.config_utils")

describe("config_utils", function()
  describe("merge_providers", function()
    it("should merge default and user providers", function()
      local default_providers = {
        pplx = {
          api_key = "",
          endpoint = "https://api.perplexity.ai/chat/completions",
          topic_prompt = "default prompt",
          topic_model = "llama-3-8b-instruct",
        },
        openai = {
          api_key = "",
          endpoint = "https://api.openai.com/v1/chat/completions",
          topic_prompt = "default prompt",
          topic_model = "gpt-3.5-turbo",
        },
        ollama = {
          endpoint = "http://localhost:11434/api/chat",
          topic_prompt = "Summarize the chat above in max 3 words",
          topic_model = "mistral:latest",
        },
      }
      local user_providers = {
        pplx = { api_key = "123" },
        ollama = { endpoint = "http://localhost:8000/api/chat" },
      }

      local result = config_utils.merge_providers(default_providers, user_providers)

      assert.are.same({
        pplx = {
          api_key = "123",
          endpoint = "https://api.perplexity.ai/chat/completions",
          topic_prompt = "default prompt",
          topic_model = "llama-3-8b-instruct",
        },
        ollama = {
          endpoint = "http://localhost:8000/api/chat",
          topic_prompt = "Summarize the chat above in max 3 words",
          topic_model = "mistral:latest",
        },
      }, result)
    end)
  end)

  describe('merge_agent_type', function()
    it('should merge default and user agents', function()
      local default_agents = {
        {
          name = "ChatGPT4",
          model = { model = "gpt-4-turbo", temperature = 1.1, top_p = 1 },
          system_prompt = "You are a versatile AI assistant",
          provider = "openai",
        },
        {
          name = "ChatGPT3.5",
          model = { model = "gpt-3.5-turbo", temperature = 1.1, top_p = 1 },
          system_prompt = "You are a versatile AI assistant",
          provider = "openai",
        },
        {
          name = "Codestral",
          model = { model = "codestral-latest", temperature = 1.5, top_p = 1 },
          system_prompt = "You are a versatile AI assistant",
          provider = "mistral",
        },
        {
          name = "Mistral-Tiny",
          model = { model = "mistral-tiny", temperature = 1.5, top_p = 1 },
          system_prompt = "You are a versatile AI assistant",
          provider = "mistral",
        },
      }
      local user_agents = {
        {
          name = "CustomChatGPT4",
          model = { model = "gpt-4-turbo", temperature = 1.2 },
          system_prompt = "You are an AI assistant",
          provider = "openai",
        },
      }
      local user_providers = {
        openai = { api_key = '123' },
      }

      local result = config_utils.merge_agent_type(default_agents, user_agents, user_providers)

      assert.are.same({
        {
          name = "CustomChatGPT4",
          model = { model = "gpt-4-turbo", temperature = 1.2 },
          system_prompt = "You are an AI assistant",
          provider = "openai",
        },
        {
          name = "ChatGPT4",
          model = { model = "gpt-4-turbo", temperature = 1.1, top_p = 1 },
          system_prompt = "You are a versatile AI assistant",
          provider = "openai",
        },
        {
          name = "ChatGPT3.5",
          model = { model = "gpt-3.5-turbo", temperature = 1.1, top_p = 1 },
          system_prompt = "You are a versatile AI assistant",
          provider = "openai",
        },
      }, result)
    end)
  end)
end)
