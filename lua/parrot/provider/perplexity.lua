local logger = require("parrot.logger")
local utils = require("parrot.utils")

---@class Perplexity
---@field endpoint string
---@field api_key string|table
---@field name string
local Perplexity = {}
Perplexity.__index = Perplexity

-- Available API parameters for Perplexity
-- https://docs.perplexity.ai/api-reference/chat-completions
local AVAILABLE_API_PARAMETERS = {
  -- required
  model = true,
  messages = true,
  -- optional
  max_tokens = true,
  temperature = true,
  top_p = true,
  search_domain_filter = true,
  return_images = true,
  return_related_questions = true,
  search_recency_filter = true,
  top_k = true,
  stream = true,
  presence_penalty = true,
  frequency_penalty = true,
}

-- Creates a new Perplexity instance
---@param endpoint string
---@param api_key string|table
---@return Perplexity
function Perplexity:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "pplx",
  }, self)
end

-- Placeholder for setting model (not implemented)
function Perplexity:set_model(_) end

-- Preprocesses the payload before sending to the API
---@param payload table
---@return table
function Perplexity:preprocess_payload(payload)
  for _, message in ipairs(payload.messages) do
    message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
  end
  return utils.filter_payload_parameters(AVAILABLE_API_PARAMETERS, payload)
end

-- Returns the curl parameters for the API request
---@return table
function Perplexity:curl_params()
  return {
    self.endpoint,
    "-H",
    "authorization: Bearer " .. self.api_key,
  }
end

-- Verifies the API key or executes a routine to retrieve it
---@return boolean
function Perplexity:verify()
  if type(self.api_key) == "table" then
    local command = table.concat(self.api_key, " ")
    local handle = io.popen(command)
    if handle then
      self.api_key = handle:read("*a"):gsub("%s+", "")
      handle:close()
      return true
    else
      logger.error("Error verifying API key of " .. self.name)
      return false
    end
  elseif self.api_key and self.api_key:match("%S") then
    return true
  else
    logger.error("Error with API key " .. self.name .. " " .. vim.inspect(self.api_key))
    return false
  end
end

-- Processes the stdout from the API response
---@param response string
---@return string|nil
function Perplexity:process_stdout(response)
  if response:match("chat%.completion%.chunk") or response:match("chat%.completion") then
    local success, content = pcall(vim.json.decode, response)
    if
      success
      and content.choices
      and content.choices[1]
      and content.choices[1].delta
      and content.choices[1].delta.content
    then
      return content.choices[1].delta.content
    else
      logger.debug("Could not process response: " .. response)
    end
  end
end

-- Processes the onexit event from the API response
---@param res string
function Perplexity:process_onexit(res)
  local parsed = res:match("<h1>(.-)</h1>")
  if parsed then
    logger.error("Perplexity - message: " .. parsed)
  end
end

-- Returns the list of available models
---@return string[]
function Perplexity:get_available_models()
  return {
    "sonar",
    "sonar-pro",
    "sonar-reasoning",
    "sonar-reasoning-pro",
  }
end

return Perplexity
