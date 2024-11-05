local logger = require("parrot.logger")
local utils = require("parrot.utils")

---@class Anthropic
---@field endpoint string
---@field api_key string|table
---@field name string
local Anthropic = {}
Anthropic.__index = Anthropic

-- Available API parameters for Anthropic
-- https://docs.anthropic.com/en/api/messages
local AVAILABLE_API_PARAMETERS = {
  -- required
  model = true,
  messages = true,
  max_tokens = true,
  -- optional
  metadata = true,
  stop_sequences = true,
  stream = true,
  system = true,
  temperature = true,
  tool_choice = true,
  tools = true,
  top_k = true,
  top_p = true,
}

-- Creates a new Anthropic instance
---@param endpoint string
---@param api_key string|table
---@return Anthropic
function Anthropic:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "anthropic",
  }, self)
end

-- Placeholder for setting model (not implemented)
function Anthropic:set_model(_) end

-- Preprocesses the payload before sending to the API
---@param payload table
---@return table
function Anthropic:preprocess_payload(payload)
  for _, message in ipairs(payload.messages) do
    message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
  end
  if payload.messages[1] and payload.messages[1].role == "system" then
    -- remove the first message that serves as the system prompt as anthropic
    -- expects the system prompt to be part of the API call body and not the messages
    payload.system = payload.messages[1].content
    table.remove(payload.messages, 1)
  end
  return utils.filter_payload_parameters(AVAILABLE_API_PARAMETERS, payload)
end

-- Returns the curl parameters for the API request
---@return table
function Anthropic:curl_params()
  return {
    self.endpoint,
    "-H",
    "x-api-key: " .. self.api_key,
    "-H",
    "anthropic-version: 2023-06-01",
  }
end

-- Verifies the API key or executes a routine to retrieve it
---@return boolean
function Anthropic:verify()
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
function Anthropic:process_stdout(response)
  if response:match("content_block_delta") and response:match("text_delta") then
    local success, decoded_line = pcall(vim.json.decode, response)
    if success and decoded_line.delta and decoded_line.delta.type == "text_delta" and decoded_line.delta.text then
      return decoded_line.delta.text
    else
      logger.debug("Could not process response: " .. response)
    end
  end
end

-- Processes the onexit event from the API response
---@param res string
function Anthropic:process_onexit(res)
  local success, parsed = pcall(vim.json.decode, res)
  if success and parsed.error and parsed.error.message then
    logger.error(string.format("Anthropic - message: %s type: %s", parsed.error.message, parsed.error.type))
  end
end

-- Returns the list of available models
---@return string[]
function Anthropic:get_available_models()
  return {
    "claude-3-5-sonnet-latest",
    "claude-3-5-sonnet-20241022",
    "claude-3-5-sonnet-20240620",
    "claude-3-5-haiku-latest",
    "claude-3-5-haiku-20241022",
    "claude-3-sonnet-20240229",
    "claude-3-haiku-20240307",
    "claude-3-opus-20240229",
    "claude-3-opus-latest",
  }
end

return Anthropic
