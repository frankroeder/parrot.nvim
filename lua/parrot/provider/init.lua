local Anthropic = require("parrot.provider.anthropic")
local Gemini = require("parrot.provider.gemini")
local Groq = require("parrot.provider.groq")
local Mistral = require("parrot.provider.mistral")
local Nvidia = require("parrot.provider.nvidia")
local Ollama = require("parrot.provider.ollama")
local OpenAI = require("parrot.provider.openai")
local Perplexity = require("parrot.provider.perplexity")
local GitHub = require("parrot.provider.github")
local xAI = require("parrot.provider.xai")
local DeepSeek = require("parrot.provider.deepseek")
local logger = require("parrot.logger")

local M = {}

---@param prov_name string # name of the provider
---@param endpoint string # API endpoint for the provider
---@param api_key string|table # API key or routine for authentication
---@return table # returns initialized provider
M.init_provider = function(prov_name, endpoint, api_key, style, models)
  local providers = {
    anthropic = Anthropic,
    gemini = Gemini,
    github = GitHub,
    groq = Groq,
    mistral = Mistral,
    nvidia = Nvidia,
    ollama = Ollama,
    openai = OpenAI,
    pplx = Perplexity,
    xai = xAI,
    deepseek = DeepSeek,
  }

  if providers[prov_name] then
    return providers[prov_name]:new(endpoint, api_key)
  elseif style and providers[style] then
    return providers[style]:new(endpoint, api_key, models, prov_name)
  end

  logger.error("Unknown provider " .. prov_name)
  return {}
end

return M
