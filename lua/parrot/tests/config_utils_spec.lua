local cutils = require("parrot.config_utils")

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

      local result = cutils.merge_providers(default_providers, user_providers)

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
end)
