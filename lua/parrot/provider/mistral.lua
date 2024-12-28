local logger = require("parrot.logger")
local utils = require("parrot.utils")

---@class Mistral
---@field endpoint string
---@field api_key string|table
---@field name string
local Mistral = {}
Mistral.__index = Mistral

-- Available API parameters for Mistral
-- https://docs.mistral.ai/api/
local AVAILABLE_API_PARAMETERS = {
  -- required
  model = true,
  messages = true,
  -- optional
  temperature = true,
  top_p = true,
  max_tokens = true,
  min_tokens = true,
  stream = true,
  stop = true,
  random_seed = true,
  response_format = true,
  safe_prompt = true,
  tools = true,
  tool_choice = true,
  presence_penalty = true,
  frequency_penalty = true,
  n = true,
}

-- Creates a new Mistral instance
---@param endpoint string
---@param api_key string|table
---@return Mistral
function Mistral:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "mistral",
  }, self)
end

---Placeholder for setting model (not implemented)
function Mistral:set_model(_) end

-- Preprocesses the payload before sending to the API
---@param payload table
---@return table
function Mistral:preprocess_payload(payload)
  for _, message in ipairs(payload.messages) do
    message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
  end
  return utils.filter_payload_parameters(AVAILABLE_API_PARAMETERS, payload)
end

-- Returns the curl parameters for the API request
---@return table
function Mistral:curl_params()
  return {
    self.endpoint,
    "-H",
    "authorization: Bearer " .. self.api_key,
  }
end

-- Verifies the API key or executes a routine to retrieve it
---@return boolean
function Mistral:verify()
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
function Mistral:process_stdout(response)
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
function Mistral:process_onexit(res)
  local success, parsed = pcall(vim.json.decode, res)
  if success and parsed.message then
    logger.error("Mistral - message: " .. parsed.message)
  end
end

-- Returns the list of available models
---@return string[]
function Mistral:get_available_models(online)
  local ids = {
    "mistral-large-latest",
    "ministral-3b-2410",
    "ministral-3b-latest",
    "ministral-8b-2410",
    "ministral-8b-latest",
    "open-mistral-7b",
    "mistral-tiny",
    "mistral-tiny-2312",
    "open-mistral-nemo",
    "open-mistral-nemo-2407",
    "mistral-tiny-2407",
    "mistral-tiny-latest",
    "open-mixtral-8x7b",
    "mistral-small",
    "mistral-small-2312",
    "open-mixtral-8x22b",
    "open-mixtral-8x22b-2404",
    "mistral-small-2402",
    "mistral-small-2409",
    "mistral-small-latest",
    "mistral-medium-2312",
    "mistral-medium",
    "mistral-medium-latest",
    "mistral-large-2402",
    "mistral-large-2407",
    "mistral-large-2411",
    "pixtral-large-2411",
    "pixtral-large-latest",
    "codestral-2405",
    "codestral-latest",
    "codestral-mamba-2407",
    "open-codestral-mamba",
    "codestral-mamba-latest",
    "pixtral-12b-2409",
    "pixtral-12b",
    "pixtral-12b-latest",
    "mistral-embed",
    "mistral-moderation-2411",
    "mistral-moderation-latest",
  }
  if online and self:verify() then
    local job = Job:new({
      command = "curl",
      args = {
        "https://api.mistral.ai/v1/models",
        "-H",
        "Authorization: Bearer " .. self.api_key,
      },
      on_exit = function(job)
        local parsed_response = utils.parse_raw_response(job:result())
        self:process_onexit(parsed_response)
        ids = {}
        local success, decoded = pcall(vim.json.decode, parsed_response)
        if success and decoded.data then
          for _, item in ipairs(decoded.data) do
            table.insert(ids, item.id)
          end
        end
        return ids
      end,
    })
    job:start()
    job:wait()
  end
  return ids
end

return Mistral
