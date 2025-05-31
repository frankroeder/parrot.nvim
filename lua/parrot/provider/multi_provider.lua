local logger = require("parrot.logger")
local utils = require("parrot.utils")
local Job = require("plenary.job")

-- MultiProvider class - A universal provider based on OpenAI's API format
-- This provider is designed to work with OpenAI and other OpenAI-compatible APIs
-- that follow the OpenAI chat completions standard.
---@class MultiProvider
---@field endpoint string
---@field api_key string|table|function
---@field model_endpoint string|table|function
---@field models table
---@field name string
---@field headers function|table
---@field preprocess_payload_func function
---@field process_stdout_func function
---@field process_onexit_func function
---@field resolve_api_key_func function
---@field curl_params_func function
---@field get_available_models_func function
local MultiProvider = {}
MultiProvider.__index = MultiProvider

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

    local json_str = response:gsub("^data:%s*", "")
    if json_str == "[DONE]" then
      return nil
    end

    local success, decoded = pcall(vim.json.decode, json_str)
    if not success then
      -- FIXME --
      -- logger.error("Failed to decode API response: " .. json_str)
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
    elseif decoded.content and decoded.content[1] and decoded.content[1].text then
      return decoded.content[1].text
    end

    return nil
  end,

  resolve_api_key = function(self, api_key)
    -- Allow api_key to be provided as a function that returns the key or table
    if type(api_key) == "function" then
      local ok, result = pcall(api_key)
      if not ok then
        logger.error("Error executing api_key function for provider " .. self.name .. ": " .. tostring(result))
        return false
      end
      return self:resolve_api_key(result)
    end

    if type(api_key) == "table" then
      -- reject empty command tables
      if #api_key == 0 then
        logger.error("Error verifying API key for provider " .. self.name .. ": empty command table")
        return false
      end

      -- Validate that all table elements are strings
      for i, arg in ipairs(api_key) do
        if type(arg) ~= "string" then
          logger.error(
            "Error verifying API key for provider " .. self.name .. ": command argument " .. i .. " is not a string"
          )
          return false
        end
      end

      local command = table.concat(api_key, " ")
      -- Use a timeout to prevent hanging on command execution
      local handle = io.popen(command) -- Capture stderr as well
      if handle then
        local resolved_key = handle:read("*a")
        handle:close()

        -- Clean up the resolved key
        resolved_key = resolved_key:gsub("%s+$", ""):gsub("^%s+", "")
        if resolved_key == "" then
          logger.error("Error verifying API key for provider " .. self.name .. ": command returned empty result")
          return false
        end

        return resolved_key
      else
        logger.error("Error verifying API key for provider " .. self.name .. ": failed to execute command")
        return false
      end
    elseif type(api_key) == "string" and api_key:match("%S") then
      -- Trim surrounding whitespace from API key
      return api_key:gsub("^%s*(.-)%s*$", "%1")
    else
      logger.error("Error with API key for provider " .. self.name .. ": API key is nil, empty, or whitespace-only")
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
      end,
    })
    job:start()
    job:wait()
    return ids
  end,
}

-- Creates a new MultiProvider instance
---@param config table
---@return MultiProvider
function MultiProvider:new(config)
  local self = setmetatable({}, MultiProvider)

  -- Validate required fields
  assert(config.name, "Provider name is required")
  assert(config.endpoint, "Provider endpoint is required")
  assert(config.api_key, "Provider API key is required")
  assert(config.model or config.models, "Provider model(s) are required")

  -- Basic configuration
  self.name = config.name
  self.endpoint = config.endpoint
  self.model_endpoint = config.model_endpoint or ""
  self.api_key = config.api_key
  if config.model then
    self.models = type(config.model) == "string" and { config.model } or config.model
  else
    self.models = config.models
  end

  -- Function overrides (use defaults if not provided)
  self.headers = config.headers or defaults.headers
  self.preprocess_payload_func = config.preprocess_payload or defaults.preprocess_payload
  self.process_stdout_func = config.process_stdout or defaults.process_stdout
  self.process_onexit_func = config.process_onexit or defaults.process_onexit
  self.resolve_api_key_func = config.resolve_api_key or defaults.resolve_api_key
  self.get_available_models_func = config.get_available_models or defaults.get_available_models

  self:validate_config()
  return self
end

function MultiProvider:online_model_fetching()
  return self.model_endpoint and self.model_endpoint ~= ""
end

-- Validates the MultiProvider configuration
function MultiProvider:validate_config()
  local logger = require("parrot.logger")

  -- Validate endpoint format (allow functions)
  if type(self.endpoint) == "string" and not self.endpoint:match("^https?://") then
    logger.error(vim.inspect({
      msg = "Invalid endpoint format for provider",
      method = "MultiProvider:validate_config",
      provider = self.name,
      endpoint = self.endpoint,
      expected = "URL must start with http:// or https://",
    }))
    error("Invalid endpoint format: " .. self.endpoint .. " for provider " .. self.name)
  elseif type(self.endpoint) ~= "string" and type(self.endpoint) ~= "function" then
    logger.error(vim.inspect({
      msg = "Invalid endpoint type for provider",
      method = "MultiProvider:validate_config",
      provider = self.name,
      endpoint_type = type(self.endpoint),
      expected = "Endpoint must be a string (URL) or function",
    }))
    error("Endpoint must be a string or function for provider " .. self.name)
  end

  -- Validate model endpoint format if provided (allow functions)
  if self:online_model_fetching() then
    if type(self.model_endpoint) == "string" and not self.model_endpoint:match("^https?://") then
      logger.error(vim.inspect({
        msg = "Invalid model endpoint format for provider",
        method = "MultiProvider:validate_config",
        provider = self.name,
        model_endpoint = self.model_endpoint,
        expected = "URL must start with http:// or https://",
      }))
      error("Invalid model endpoint format: " .. self.model_endpoint .. " for provider " .. self.name)
    elseif type(self.model_endpoint) ~= "string" and type(self.model_endpoint) ~= "function" then
      logger.error(vim.inspect({
        msg = "Invalid model endpoint type for provider",
        method = "MultiProvider:validate_config",
        provider = self.name,
        model_endpoint_type = type(self.model_endpoint),
        expected = "Model endpoint must be a string (URL) or function",
      }))
      error("Model endpoint must be a string or function for provider " .. self.name)
    end
  end

  -- Validate models
  if type(self.models) ~= "table" then
    logger.error(vim.inspect({
      msg = "Invalid models configuration for provider",
      method = "MultiProvider:validate_config",
      provider = self.name,
      models_type = type(self.models),
      models_value = self.models,
      expected = "Models must be provided as a table/array",
    }))
    error("Models must be provided as a table for provider " .. self.name)
  end

  -- Validate models table is not empty
  if #self.models == 0 then
    logger.error(vim.inspect({
      msg = "Empty models configuration for provider",
      method = "MultiProvider:validate_config",
      provider = self.name,
      models = self.models,
      expected = "Models table must contain at least one model",
    }))
    error("Models table cannot be empty for provider " .. self.name)
  end

  -- Validate headers if provided
  if self.headers ~= nil and type(self.headers) ~= "function" and type(self.headers) ~= "table" then
    logger.error(vim.inspect({
      msg = "Invalid headers type for provider",
      method = "MultiProvider:validate_config",
      provider = self.name,
      headers_type = type(self.headers),
      expected = "Headers must be a function or table",
    }))
    error("Headers must be a function or table for provider " .. self.name)
  end
end

function MultiProvider:set_model(model)
  self._model = model
end

-- Preprocesses the payload before sending to the API
---@param payload table
---@return table
function MultiProvider:preprocess_payload(payload)
  return self.preprocess_payload_func(payload)
end

-- Returns the curl parameters for the API request
---@return table
function MultiProvider:curl_params()
  local api_key = self:resolve_api_key(self.api_key)
  if not api_key then
    return {}
  end

  local hdrs = type(self.headers) == "function" and self.headers(self) or (self.headers or {})

  -- Handle endpoint as function or string
  local endp
  if type(self.endpoint) == "function" then
    local ok, result = pcall(self.endpoint, self)
    if not ok then
      logger.error("Error executing endpoint function for provider " .. self.name .. ": " .. tostring(result))
      return {}
    end
    endp = result
  else
    endp = self.endpoint
  end

  -- Validate the resolved endpoint
  if type(endp) ~= "string" or endp == "" then
    logger.error("Invalid endpoint resolved for provider " .. self.name .. ": " .. tostring(endp))
    return {}
  end

  local args = {
    endp,
  }

  for k, v in pairs(hdrs) do
    table.insert(args, "-H")
    -- TODO: Check if this really makes sense to be a table --
    local header_value = type(v) == "table" and table.concat(v, " ") or tostring(v)
    table.insert(args, k .. ": " .. header_value)
  end
  return args
end

-- Verifies the API key or executes a routine to retrieve it
---@return boolean
function MultiProvider:verify()
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
function MultiProvider:resolve_api_key(api_key)
  return self.resolve_api_key_func(self, api_key)
end

-- Processes the stdout from the API response
---@param response string
---@return string|nil
function MultiProvider:process_stdout(response)
  return self.process_stdout_func(response)
end

-- Processes the onexit event from the API response
---@param res string
function MultiProvider:process_onexit(res)
  return self.process_onexit_func(res)
end

-- Returns the list of available models
---@return string[]
function MultiProvider:get_available_models()
  if self:online_model_fetching() and self:verify() then
    local hdrs = type(self.headers) == "function" and self.headers(self) or (self.headers or {})

    -- Handle model_endpoint as function or string/table
    local args
    if type(self.model_endpoint) == "function" then
      local ok, result = pcall(self.model_endpoint, self)
      if not ok then
        logger.error("Error executing model_endpoint function for provider " .. self.name .. ": " .. tostring(result))
        return self.models
      end
      args = type(result) == "table" and result or { result }
    else
      args = type(self.model_endpoint) == "table" and self.model_endpoint or { self.model_endpoint }
    end

    -- Add headers to args
    for k, v in pairs(hdrs) do
      table.insert(args, "-H")
      -- TODO: Check if this really makes sense to be a table --
      local header_value = type(v) == "table" and table.concat(v, " ") or tostring(v)
      table.insert(args, k .. ": " .. header_value)
    end

    return self.get_available_models_func(self, args)
  end
  return self.models
end

-- Returns the list of available models with caching support
---@param state table # State object for caching
---@param cache_expiry_hours number # Cache expiry time in hours
---@param spinner table|nil # Optional spinner for loading indication
---@return string[]
function MultiProvider:get_available_models_cached(state, cache_expiry_hours, spinner)
  -- Only use caching if model_endpoint is configured
  -- otherwise return fallback models
  if not self:online_model_fetching() and cache_expiry_hours == 0 then
    return self.models
  end

  -- Generate endpoint hash for cache validation
  local endpoint_hash = utils.generate_endpoint_hash(self)

  -- Try to get from cache first
  local cached_models = state:get_cached_models(self.name, cache_expiry_hours, endpoint_hash)
  if cached_models then
    return cached_models
  end

  -- Cache miss or expired - fetch fresh models
  if spinner then
    spinner:start("Fetching models for " .. self.name .. "...")
  end

  local fresh_models = self:get_available_models()

  if spinner then
    spinner:stop()
  end

  -- Ensure we always have models - fallback to static if fresh fetch failed
  if not fresh_models or #fresh_models == 0 then
    fresh_models = self.models
  end

  -- Cache the fresh models if we successfully fetched from API and they differ from static
  if #fresh_models > 0 and not vim.deep_equal(fresh_models, self.models) then
    state:set_cached_models(self.name, fresh_models, endpoint_hash)
    state:save()
  end

  -- Final safety check - always return at least static models
  return fresh_models and #fresh_models > 0 and fresh_models or self.models
end

return MultiProvider
