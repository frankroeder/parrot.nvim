local Ollama = require("parrot.provider.ollama")
local OpenAI = require("parrot.provider.openai")
local Anthropic = require("parrot.provider.anthropic")
local Perplexity = require("parrot.provider.perplexity")
local Mistral = require("parrot.provider.mistral")

local M = {}

---@param prov_name string # name of the provider
---@param endpoint string # API endpoint for the provider
---@param api_key string # API key for authentication
---@return table # returns initialized provider instance or nil
M.init_provider = function(prov_name, endpoint, api_key)
  local providers = {
    ollama = Ollama,
    openai = OpenAI,
    anthropic = Anthropic,
    pplx = Perplexity,
    mistral = Mistral,
  }

  local ProviderClass = providers[prov_name]
  if not ProviderClass then
    M.logger.error("Unknown provider " .. prov_name)
    return {}
  end

  return ProviderClass:new(endpoint, api_key)
end

return M
