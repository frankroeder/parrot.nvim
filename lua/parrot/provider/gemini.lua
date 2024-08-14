local logger = require("parrot.logger")
local utils = require("parrot.utils")

---@class Gemini
---@field endpoint string
---@field api_key string|table
---@field name string
---@field _model string|nil
local Gemini = {}
Gemini.__index = Gemini

-- Available API parameters for Gemini
-- https://ai.google.dev/gemini-api/docs/models/generative-models#model_parameters
local AVAILABLE_API_PARAMETERS = {
  contents = true,
  system_instruction = true,
  generationConfig = {
    stopSequences = true,
    temperature = true,
    maxOutputTokens = true,
    topP = true,
    topK = true,
  },
}

-- Creates a new Gemini instance
---@param endpoint string
---@param api_key string|table
---@return Gemini
function Gemini:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "gemini",
    _model = nil,
  }, self)
end

-- Sets the model for the actual API request
---@param model string
function Gemini:set_model(model)
  self._model = model
end

-- Preprocesses the payload before sending to the API
---@param payload table
---@return table
function Gemini:preprocess_payload(payload)
  local new_messages = {}
  for _, message in ipairs(payload.messages) do
    if message.role == "system" then
      payload.system_instruction = {
        parts = {
          text = (message.parts and message.parts.text or message.content):gsub("^%s*(.-)%s*$", "%1"),
        },
      }
    else
      local _role = message.role == "assistant" and "model" or message.role
      if message.content then
        table.insert(new_messages, {
          parts = { { text = message.content:gsub("^%s*(.-)%s*$", "%1") } },
          role = _role,
        })
      end
    end
  end
  payload.contents = vim.deepcopy(new_messages)
  return utils.filter_payload_parameters(AVAILABLE_API_PARAMETERS, payload)
end

-- Returns the curl parameters for the API request
---@return table
function Gemini:curl_params()
  return {
    self.endpoint .. self._model .. ":streamGenerateContent?alt=sse",
    "-H",
    "x-goog-api-key: " .. self.api_key,
    "-X",
    "POST",
  }
end

-- Verifies the API key or executes a routine to retrieve it
---@return boolean
function Gemini:verify()
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

---Processes the stdout from the API response
---@param response string
---@return string|nil
function Gemini:process_stdout(response)
  if response:match('"text":') then
    local success, content = pcall(vim.json.decode, response)
    if
      success
      and content.candidates
      and content.candidates[1]
      and content.candidates[1].content
      and content.candidates[1].content.parts
      and content.candidates[1].content.parts[1]
      and content.candidates[1].content.parts[1].text
    then
      return content.candidates[1].content.parts[1].text
    else
      logger.debug("Could not process response: " .. response)
    end
  end
end

---Processes the onexit event from the API response
---@param res string
function Gemini:process_onexit(res)
  local success, parsed = pcall(vim.json.decode, res)
  if success and parsed.error and parsed.error.message then
    logger.error(
      string.format(
        "GEMINI - code: %s message: %s status: %s",
        parsed.error.code,
        parsed.error.message,
        parsed.error.status
      )
    )
  end
end

---Returns the list of available models
---@return string[]
function Gemini:get_available_models()
  return {
    "gemini-1.5-flash",
    "gemini-1.5-pro",
    "gemini-1.0-pro",
  }
end

return Gemini
