local Ollama = require("parrot.provider.ollama")
local OpenAI = require("parrot.provider.openai")
local Gemini = require("parrot.provider.gemini")
local Anthropic = require("parrot.provider.anthropic")
local Perplexity = require("parrot.provider.perplexity")
local Mistral = require("parrot.provider.mistral")

local M = {
  logger = require("parrot.logger"),
}

---@param prov_name string # name of the provider
---@param endpoint string # API endpoint for the provider
---@param api_key string # API key for authentication
---@return table # returns initialized provider instance or nil
M.init_provider = function(prov_name, endpoint, api_key)
  local providers = {
    ollama = Ollama,
    openai = OpenAI,
    gemini = Gemini,
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

M.get_provider = function(state, providers)
  local _state_prov = state:get_provider()
  local endpoint = providers[_state_prov].endpoint
  local api_key = providers[_state_prov].api_key
  return M.init_provider(_state_prov, endpoint, api_key)
end

M.get_provider_agents = function(is_chat, state, providers, available_provider_agents)
  local prov = M.get_provider(state, providers)
  if is_chat then
    return available_provider_agents[prov.name].chat
  else
    return available_provider_agents[prov.name].command
  end
end

return M
