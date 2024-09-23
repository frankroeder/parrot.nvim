local logger = require("parrot.logger")
local utils = require("parrot.utils")
local Job = require("plenary.job")

---@class OpenAI
---@field endpoint string
---@field api_key string|table
---@field name string
local OpenAI = {}
OpenAI.__index = OpenAI

-- Available API parameters for OpenAI
-- https://platform.openai.com/docs/api-reference/chat
local AVAILABLE_API_PARAMETERS = {
  -- required
  messages = true,
  model = true,
  -- optional
  frequency_penalty = true,
  logit_bias = true,
  logprobs = true,
  top_logprobs = true,
  max_tokens = true,
  presence_penalty = true,
  seed = true,
  stop = true,
  stream = true,
  temperature = true,
  top_p = true,
  tools = true,
  tool_choice = true,
}

-- Creates a new OpenAI instance
---@param endpoint string
---@param api_key string|table
---@return OpenAI
function OpenAI:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "openai",
  }, self)
end

-- Placeholder for setting model (not implemented)
function OpenAI:set_model(_) end

-- Preprocesses the payload before sending to the API
---@param payload table
---@return table
function OpenAI:preprocess_payload(payload)
  for _, message in ipairs(payload.messages) do
    message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
  end
  return utils.filter_payload_parameters(AVAILABLE_API_PARAMETERS, payload)
end

-- Returns the curl parameters for the API request
---@return table
function OpenAI:curl_params()
  return {
    self.endpoint,
    "-H",
    "authorization: Bearer " .. self.api_key,
  }
end

-- Verifies the API key or executes a routine to retrieve it
---@return boolean
function OpenAI:verify()
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
function OpenAI:process_stdout(response)
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
function OpenAI:process_onexit(res)
  local success, parsed = pcall(vim.json.decode, res)
  if success and parsed.error and parsed.error.message then
    logger.error(
      string.format(
        "OpenAI - code: %s message: %s type: %s",
        parsed.error.code,
        parsed.error.message,
        parsed.error.type
      )
    )
  end
end

-- Returns the list of available models
---@param online boolean Whether to fetch models online
---@return string[]
function OpenAI:get_available_models(online)
  if online and self:verify() then
    Job:new({
      command = "curl",
      args = {
        "https://api.openai.com/v1/models",
        "-H",
        "Authorization: Bearer " .. self.api_key,
      },
      on_exit = function(job)
        local parsed_response = utils.parse_raw_response(job:result())
        self:process_onexit(parsed_response)
        local ids = {}
        local success, decoded = pcall(vim.json.decode, parsed_response)
        if success and decoded.data then
          for _, item in ipairs(decoded.data) do
            table.insert(ids, item.id)
          end
        end
        return ids
      end,
    }):start()
  end
  return {
    "gpt-4o",
    "gpt-3.5-turbo",
    "gpt-3.5-turbo-0125",
    "gpt-4-1106-preview",
    "gpt-4-turbo",
    "gpt-4o-2024-05-13",
    "gpt-4-0125-preview",
    "gpt-4-turbo-2024-04-09",
    "gpt-4-turbo-preview",
    "gpt-3.5-turbo-16k",
    "gpt-4o-2024-08-06",
    "gpt-3.5-turbo-1106",
    "gpt-3.5-turbo-instruct-0914",
    "gpt-4o-mini-2024-07-18",
    "gpt-4o-mini",
    "gpt-4",
    "gpt-4-0613",
    "gpt-3.5-turbo-instruct",
    "chatgpt-4o-latest",
  }
end

return OpenAI
