local OpenAI = require("parrot.provider.openai")
local logger = require("parrot.logger")

local M = {}

---@param config table # Provider configuration or legacy parameters
---@return table # returns initialized provider
M.init_provider = function(config)
  assert(config.name, "config.name is required")
  assert(config.endpoint, "config.endpoint is required")
  assert(config.api_key, "config.api_key is required")
  assert(config.models, "config.model or config.models required")
  return OpenAI:new(config)
end

return M
