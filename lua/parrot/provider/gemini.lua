local logger = require("parrot.logger")
local utils = require("parrot.utils")
local Job = require("plenary.job")

---@class Gemini
---@field endpoint string
---@field api_key string|table
---@field models table|nil
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
function Gemini:new(endpoint, api_key, models)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    models = models,
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
function Gemini:get_available_models(online)
  if self.models then
    return self.models
  end
  local ids = {
    "gemini-2.5-flash-preview-04-17",
    "gemini-2.5-pro-preview-05-06",
    "chat-bison-001",
    "text-bison-001",
    "gemini-1.5-pro-latest",
    "gemini-1.5-pro-001",
    "gemini-1.5-pro-002",
    "gemini-1.5-pro",
    "gemini-1.5-flash-latest",
    "gemini-1.5-flash-001",
    "gemini-1.5-flash-001-tuning",
    "gemini-1.5-flash",
    "gemini-1.5-flash-002",
    "gemini-1.5-flash-8b",
    "gemini-1.5-flash-8b-001",
    "gemini-1.5-flash-8b-latest",
    "gemini-1.5-flash-8b-exp-0827",
    "gemini-1.5-flash-8b-exp-0924",
    "gemini-2.5-pro-exp-03-25",
    "gemini-2.0-flash-exp",
    "gemini-2.0-flash",
    "gemini-2.0-flash-001",
    "gemini-2.0-flash-lite-001",
    "gemini-2.0-flash-lite",
    "gemini-2.0-flash-lite-preview-02-05",
    "gemini-2.0-flash-lite-preview",
    "gemini-2.0-pro-exp",
    "gemini-2.0-pro-exp-02-05",
    "gemini-exp-1206",
    "gemini-2.0-flash-thinking-exp-01-21",
    "gemini-2.0-flash-thinking-exp",
    "gemini-2.0-flash-thinking-exp-1219",
    "learnlm-1.5-pro-experimental",
    "learnlm-2.0-flash-experimental",
    "gemma-3-1b-it",
    "gemma-3-4b-it",
    "gemma-3-12b-it",
    "gemma-3-27b-it",
    "aqa",
  }
  if online and self:verify() then
    local job = Job:new({
      command = "curl",
      args = { "https://generativelanguage.googleapis.com/v1beta/models?key=" .. self.api_key },
      on_exit = function(job)
        local parsed_response = utils.parse_raw_response(job:result())
        self:process_onexit(parsed_response)
        ids = {}
        local success, decoded = pcall(vim.json.decode, parsed_response)
        if success and decoded.models then
          for _, item in ipairs(decoded.models) do
            table.insert(ids, string.sub(item.name, 8))
          end
        end
      end,
    })
    job:start()
    job:wait()
  end
  return ids
end

return Gemini
