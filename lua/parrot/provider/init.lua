local Ollama = require("parrot.provider.ollama")
local OpenAI = require("parrot.provider.openai")
local Gemini = require("parrot.provider.gemini")
local Anthropic = require("parrot.provider.anthropic")
local Perplexity = require("parrot.provider.perplexity")
local Mistral = require("parrot.provider.mistral")
local Groq = require("parrot.provider.groq")
local logger = require("parrot.logger")

local M = {}

---@param prov_name string # name of the provider
---@param endpoint string # API endpoint for the provider
---@param api_key string|table # API key or routine for authentication
---@return table # returns initialized provider
M.init_provider = function(prov_name, endpoint, api_key)
  local providers = {
    ollama = Ollama,
    openai = OpenAI,
    gemini = Gemini,
    anthropic = Anthropic,
    pplx = Perplexity,
    mistral = Mistral,
    groq = Groq,
  }

  local ProviderClass = providers[prov_name]
  if not ProviderClass then
    logger.error("Unknown provider " .. prov_name)
    return {}
  end
  return ProviderClass:new(endpoint, api_key)
end

return M
