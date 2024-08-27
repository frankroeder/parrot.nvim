local OpenAI = require("parrot.provider.openai")

local GitHub = setmetatable({}, { __index = OpenAI })
GitHub.__index = GitHub

function GitHub:new(endpoint, api_key)
  local instance = OpenAI.new(self, endpoint, api_key)
  instance.name = "github"
  return setmetatable(instance, self)
end

-- Returns the list of available models
---@param online boolean
---@return string[]
function GitHub:get_available_models(online)
  return {
    "AI21-Jamba-Instruct",
    "Cohere-command-r",
    "Cohere-command-r-plus",
    "Meta-Llama-3-70B-Instruct",
    "Meta-Llama-3-8B-Instruct",
    "Meta-Llama-3.1-405B-Instruct",
    "Meta-Llama-3.1-70B-Instruct",
    "Meta-Llama-3.1-8B-Instruct",
    "Mistral-small",
    "Mistral-Nemo",
    "Mistral-large-2407",
    "Mistral-large",
    "gpt-4o-mini",
    "gpt-4o",
    "Phi-3-medium-128k-instruct",
    "Phi-3-medium-4k-instruct",
    "Phi-3-mini-128k-instruct",
    "Phi-3-mini-4k-instruct",
    "Phi-3-small-128k-instruct",
    "Phi-3-small-8k-instruct",
  }
end

return GitHub
