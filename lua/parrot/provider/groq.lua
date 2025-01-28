local logger = require("parrot.logger")
local utils = require("parrot.utils")
local Job = require("plenary.job")

---@class Groq
---@field endpoint string
---@field api_key string|table
---@field name string
local Groq = {}
Groq.__index = Groq

-- Available API parameters for Groq
-- https://console.groq.com/docs/api-reference#chat-create
local AVAILABLE_API_PARAMETERS = {
  -- required
  model = true,
  messages = true,
  -- optional
  frequency_penalty = true,
  logit_bias = true,
  logprobs = true,
  max_tokens = true,
  n = true,
  parallel_tool_calls = true,
  presence_penalty = true,
  response_format = true,
  seed = true,
  stop = true,
  stream = true,
  stream_options = true,
  temperature = true,
  tool_choice = true,
  tools = true,
  top_logprobs = true,
  top_p = true,
  user = true,
}

-- Creates a new Groq instance
---@param endpoint string
---@param api_key string|table
---@return Groq
function Groq:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "groq",
  }, self)
end

-- Placeholder for setting model (not implemented)
function Groq:set_model(model) end

-- Preprocesses the payload before sending to the API
---@param payload table
---@return table
function Groq:preprocess_payload(payload)
  for _, message in ipairs(payload.messages) do
    message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
  end
  return utils.filter_payload_parameters(AVAILABLE_API_PARAMETERS, payload)
end

-- Returns the curl parameters for the API request
---@return table
function Groq:curl_params()
  return {
    self.endpoint,
    "-H",
    "Authorization: Bearer " .. self.api_key,
  }
end

-- Verifies the API key or executes a routine to retrieve it
---@return boolean
function Groq:verify()
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
function Groq:process_stdout(response)
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
      logger.debug("Could not process response " .. response)
    end
  end
end

-- Processes the onexit event from the API response
---@param res string
function Groq:process_onexit(res)
  local success, parsed = pcall(vim.json.decode, res)
  if success and parsed.error then
    logger.error("Groq - message: " .. parsed.error.message)
  end
end

-- Returns the list of available models
---@param online boolean
---@return string[]
function Groq:get_available_models(online)
  local ids = {
    "deepseek-r1-distill-llama-70b",
    "llama-3.2-3b-preview",
    "distil-whisper-large-v3-en",
    "whisper-large-v3-turbo",
    "llama-3.1-8b-instant",
    "whisper-large-v3",
    "llama3-70b-8192",
    "mixtral-8x7b-32768",
    "llama-guard-3-8b",
    "llama-3.3-70b-specdec",
    "llama3-8b-8192",
    "llama-3.2-1b-preview",
    "gemma2-9b-it",
    "llama-3.2-11b-vision-preview",
    "llama-3.3-70b-versatile",
    "llama-3.2-90b-vision-preview",
  }
  if online and self:verify() then
    local job = Job:new({
      command = "curl",
      args = {
        "https://api.groq.com/openai/v1/models",
        "-H",
        "Authorization: Bearer " .. self.api_key,
        "-H",
        "Content-Type: application/json",
      },
      on_exit = function(job)
        local parsed_response = utils.parse_raw_response(job:result())
        self:process_onexit(parsed_response)
        ids = {}
        for _, item in ipairs(vim.json.decode(parsed_response).data) do
          table.insert(ids, item.id)
        end
        return ids
      end,
    })
    job:start()
    job:wait()
  end
  return ids
end

return Groq
