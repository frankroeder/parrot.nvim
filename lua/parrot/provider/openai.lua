local logger = require("parrot.logger")
local utils = require("parrot.utils")
local Job = require("plenary.job")

---@class Provider
---@field endpoint string
---@field api_key string|table|function
---@field model_endpoint string|table|function
---@field model string|table
---@field name string
---@field headers function|table
---@field preprocess_payload_func function
---@field process_stdout_func function
---@field process_onexit_func function
---@field resolve_api_key_func function
---@field curl_params_func function
---@field get_available_models_func function
local Provider = {}
Provider.__index = Provider

-- Default OpenAI-style implementation
local defaults = {
  headers = function(self)
    return {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. self.api_key,
    }
  end,

  preprocess_payload = function(payload)
    for _, message in ipairs(payload.messages) do
      message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
    end

    -- TODO: Remove later --
    -- Changes according to beta limitations of the OpenAI reasoning API
    if payload.model and string.match(payload.model, "o[134]") then
      -- remove system prompt
      if payload.messages[1] and payload.messages[1].role == "system" then
        table.remove(payload.messages, 1)
      end
      payload.temperature = 1
      payload.top_p = 1
      payload.presence_penalty = 0
      payload.frequency_penalty = 0
      payload.logprobs = nil
      payload.logit_bias = nil
      payload.top_logprobs = nil
    end

    return payload
  end,

  process_stdout = function(response)
    if not response or response == "" then
      return nil
    end

    -- Remove the "data: " prefix if present
    local json_str = response:gsub("^data:%s*", "")
    if json_str == "[DONE]" then
      return nil
    end

    local success, decoded = pcall(vim.json.decode, json_str)
    if success then
      if decoded.error then
        logger.error("API Error: " .. (decoded.error.message or tostring(decoded.error)))
        return nil
      end

      if decoded.choices and decoded.choices[1] and decoded.choices[1].delta and decoded.choices[1].delta.content then
        return decoded.choices[1].delta.content
      elseif decoded.message and decoded.message.content then
        return decoded.message.content
      elseif decoded.delta and decoded.delta.type == "text_delta" and decoded.delta.text then
        return decoded.delta.text
      end
    end

    return nil
  end,

  process_onexit = function(response)
    if not response or response == "" then
      return nil
    end

    local success, decoded = pcall(vim.json.decode, response)
    if not success then
      return nil
    end

    if decoded.error then
      logger.error("Provider error: " .. (decoded.error.message or tostring(decoded.error)))
      return nil
    end

    if decoded.choices and decoded.choices[1] and decoded.choices[1].message then
      return decoded.choices[1].message.content
    elseif decoded.message and decoded.message.content then
      return decoded.message.content
    end

    return nil
  end,

  resolve_api_key = function(self, api_key)
    -- Allow api_key to be provided as a function that returns the key or table
    if type(api_key) == "function" then
      local ok, result = pcall(api_key)
      if not ok then
        logger.error("Error executing api_key function for provider " .. self.name)
        return false
      end
      return self:resolve_api_key(result)
    end

    if type(api_key) == "table" then
      -- reject empty command tables
      if #api_key == 0 then
        logger.error("Error verifying API key for provider " .. self.name)
        return false
      end
      local command = table.concat(api_key, " ")
      local handle = io.popen(command)
      if handle then
        local resolved_key = handle:read("*a"):gsub("%s+", "")
        handle:close()
        return resolved_key
      else
        logger.error("Error verifying API key for provider " .. self.name)
        return false
      end
    elseif api_key and api_key:match("%S") then
      -- Trim surrounding whitespace from API key
      if type(api_key) == "string" then
        return api_key:gsub("^%s*(.-)%s*$", "%1")
      end
      return api_key
    else
      logger.error("Error with API key for provider " .. self.name)
      return false
    end
  end,

  get_available_models = function(self, args)
    local ids = {}
    local job = Job:new({
      command = "curl",
      args = args,
      on_exit = function(job)
        local parsed_response = utils.parse_raw_response(job:result())
        self:process_onexit(parsed_response)
        ids = {}
        local success, decoded = pcall(vim.json.decode, parsed_response)
        if success and decoded.models then
          for _, item in ipairs(decoded.models) do
            if item.name then
              table.insert(ids, string.sub(item.name, 8))
            else
              table.insert(ids, item.id)
            end
          end
        elseif success and decoded.data then
          for _, item in ipairs(decoded.data) do
            table.insert(ids, item.id)
          end
        end
        return ids
      end,
    })
    job:start()
    job:wait()
    return ids
  end,
}

-- Creates a new Provider instance
---@param config table
---@return Provider
function Provider:new(config)
  local self = setmetatable({}, Provider)

  -- Basic configuration
  self.name = config.name or "openai"
  self.endpoint = config.endpoint or "https://api.openai.com/v1/chat/completions"
  self.model_endpoint = config.model_endpoint or ""
  self.api_key = config.api_key
  self.models = config.model or config.models

  -- Function overrides (use defaults if not provided)
  self.headers = config.headers or defaults.headers
  self.preprocess_payload_func = config.preprocess_payload or defaults.preprocess_payload
  self.process_stdout_func = config.process_stdout or defaults.process_stdout
  self.process_onexit_func = config.process_onexit or defaults.process_onexit
  self.resolve_api_key_func = config.resolve_api_key or defaults.resolve_api_key
  self.get_available_models_func = config.get_available_models or defaults.get_available_models

  return self
end

function Provider:set_model(model)
  self._model = model
end

-- Preprocesses the payload before sending to the API
---@param payload table
---@return table
function Provider:preprocess_payload(payload)
  return self.preprocess_payload_func(payload)
end

-- Returns the curl parameters for the API request
---@return table
function Provider:curl_params()
  local api_key = self:resolve_api_key(self.api_key)
  if not api_key then
    return {}
  end

  local hdrs = type(self.headers) == "function" and self.headers(self) or (self.headers or {})
  local endp = type(self.endpoint) == "function" and self.endpoint(self) or self.endpoint
  local args = {
    endp,
  }

  for k, v in pairs(hdrs) do
    table.insert(args, "-H")
    table.insert(args, k .. ": " .. v)
  end
  return args
end

-- Verifies the API key or executes a routine to retrieve it
---@return boolean
function Provider:verify()
  local resolved_key = self:resolve_api_key(self.api_key)
  if resolved_key then
    self.api_key = resolved_key
    return true
  end
  return false
end

-- Resolves an API key, supporting string, table(task), or function generators
---@param api_key string|table|function
---@return string|false trimmed or resolved API key, or false on error
function Provider:resolve_api_key(api_key)
  return self.resolve_api_key_func(self, api_key)
end

-- Processes the stdout from the API response
---@param response string
---@return string|nil
function Provider:process_stdout(response)
  return self.process_stdout_func(response)
end

-- Processes the onexit event from the API response
---@param res string
function Provider:process_onexit(res)
  return self.process_onexit_func(res)
end

-- Returns the list of available models
---@return string[]
function Provider:get_available_models()
  if self.model_endpoint and self:verify() then
    local hdrs = type(self.headers) == "function" and self.headers(self) or (self.headers or {})
    local args = type(self.model_endpoint) == "function" and self.model_endpoint(self) or { self.model_endpoint }
    for k, v in pairs(hdrs) do
      table.insert(args, "-H")
      table.insert(args, k .. ": " .. v)
    end
    return self.get_available_models_func(self, args)
  end
  return self.models
end

return Provider
