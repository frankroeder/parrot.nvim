local futils = require("parrot.file_utils")
local utils = require("parrot.utils")

local State = {}
State.__index = State

--- Creates a new State instance.
--- @param state_dir string # Directory where the state file is located.
--- @return table
function State:new(state_dir)
  local state_file = state_dir .. "/state.json"
  local file_state = vim.fn.filereadable(state_file) ~= 0 and futils.file_to_table(state_file) or {}
  return setmetatable({ state_file = state_file, file_state = file_state, _state = {} }, self)
end

--- Initializes file state for each provider if it's empty.
--- @param available_providers table
function State:init_file_state(available_providers)
  if next(self.file_state) == nil then
    for _, prov in ipairs(available_providers) do
      self.file_state[prov] = {
        chat_model = nil,
        command_model = nil,
        cached_models = {},
      }
    end
  else
    -- Ensure existing providers have cached_models initialized
    for _, prov in ipairs(available_providers) do
      if self.file_state[prov] then
        self.file_state[prov].cached_models = self.file_state[prov].cached_models or {}
      else
        self.file_state[prov] = {
          chat_model = nil,
          command_model = nil,
          cached_models = {},
        }
      end
    end
  end
  self.file_state.current_provider = self.file_state.current_provider or { chat = nil, command = nil }
end

--- Initializes state for a specific provider if it's not already initialized.
--- @param available_providers table
--- @param available_models table
function State:init_state(available_providers, available_models)
  self._state.current_provider = self._state.current_provider or { chat = nil, command = nil }
  for _, provider in ipairs(available_providers) do
    self._state[provider] = self._state[provider]
      or {
        chat_model = nil,
        command_model = nil,
        cached_models = {},
      }

    -- Copy cached_models from file_state if they exist
    if self.file_state[provider] and self.file_state[provider].cached_models then
      self._state[provider].cached_models = self.file_state[provider].cached_models
    end

    -- Only load models if the provider has available models
    if available_models[provider] and #available_models[provider] > 0 then
      self:load_models(provider, "chat_model", available_models)
      self:load_models(provider, "command_model", available_models)
    end
  end
end

--- Loads model for the specified provider and type.
--- @param provider string # Name of the provider.
--- @param model_type string # Type of model (e.g., "chat_model", "command_model").
--- @param available_models table
function State:load_models(provider, model_type, available_models)
  -- Ensure provider exists in available_models and has models
  if not available_models[provider] or not available_models[provider][1] then
    return
  end

  local state_model = self.file_state and self.file_state[provider] and self.file_state[provider][model_type]
  local is_valid_model = state_model and utils.contains(available_models[provider], state_model)

  if self._state[provider][model_type] == nil then
    if state_model and is_valid_model then
      self._state[provider][model_type] = state_model
    else
      self._state[provider][model_type] = available_models[provider][1]
    end
  end
end

--- Refreshes the state with available providers and their models.
--- @param available_providers table
--- @param available_models table
function State:refresh(available_providers, available_models)
  self:init_file_state(available_providers)
  self:init_state(available_providers, available_models)

  local function set_current_provider(key)
    self._state.current_provider[key] = self._state.current_provider[key]
      or self.file_state.current_provider[key]
      or available_providers[1]
    if not utils.contains(available_providers, self._state.current_provider[key]) then
      self._state.current_provider[key] = available_providers[1]
    end
  end

  set_current_provider("chat")
  set_current_provider("command")

  self._state.last_chat = self._state.last_chat or self.file_state.last_chat or nil

  self:save()
end

--- Saves the current state to the state file.
function State:save()
  -- Merge cached_models from file_state into _state before saving
  for provider, data in pairs(self.file_state) do
    if type(data) == "table" and data.cached_models and self._state[provider] then
      self._state[provider].cached_models = data.cached_models
    end
  end

  futils.table_to_file(self._state, self.state_file)
end

--- Sets the current provider.
--- @param provider string # Name of the provider
function State:set_provider(provider, is_chat)
  if is_chat then
    self._state.current_provider.chat = provider
  else
    self._state.current_provider.command = provider
  end
end

--- Gets the current provider.
--- @return string|nil
function State:get_provider(is_chat)
  if is_chat then
    return self.file_state.current_provider.chat or self._state.current_provider.chat
  else
    return self.file_state.current_provider.command or self._state.current_provider.command
  end
end

--- Sets the model for a specific provider and interaction type.
--- @param provider string # Provider name.
--- @param model string # Provider model name
--- @param atype string # Type of the model ('chat' or 'command').
function State:set_model(provider, model, atype)
  if atype == "chat" then
    self._state[provider].chat_model = model
  elseif atype == "command" then
    self._state[provider].command_model = model
  end
end

--- Returns the model for a specific provider and interaction type.
--- @param provider string # Provider name.
--- @param model_type string # Type of model ('chat' or 'command').
--- @return table|nil
function State:get_model(provider, model_type)
  local key = model_type .. "_model"
  return self._state[provider][key] or self.file_state[provider][key]
end

--- Sets the last opened chat file path.
--- @param chat_file_path string # Path to the chat file.
function State:set_last_chat(chat_file_path)
  self._state.last_chat = chat_file_path
end

--- Returns the last opened chat file path.
--- @return string|nil
function State:get_last_chat()
  return self._state.last_chat
end

--- Sets cached models for a provider with timestamp
--- @param provider string # Provider name
--- @param models table # Array of model names
--- @param endpoint_hash string|nil # Hash of the endpoint configuration for validation
function State:set_cached_models(provider, models, endpoint_hash)
  -- Ensure provider exists in file_state
  if not self.file_state[provider] then
    self.file_state[provider] = {
      chat_model = nil,
      command_model = nil,
      cached_models = {},
    }
  end

  -- Ensure cached_models table exists for this provider
  self.file_state[provider].cached_models = self.file_state[provider].cached_models or {}

  local cache_entry = {
    models = models,
    timestamp = os.time(),
    endpoint_hash = endpoint_hash,
  }

  self.file_state[provider].cached_models = cache_entry

  -- Also sync to _state if it exists for immediate availability
  if self._state[provider] then
    self._state[provider].cached_models = cache_entry
  end
end

--- Gets cached models for a provider if they exist and are valid
--- @param provider string # Provider name
--- @param cache_expiry_hours number # Cache expiry time in hours
--- @param endpoint_hash string|nil # Current endpoint hash for validation
--- @return table|nil # Array of cached model names or nil if cache is invalid/expired
function State:get_cached_models(provider, cache_expiry_hours, endpoint_hash)
  if not self.file_state[provider] or not self.file_state[provider].cached_models then
    return nil
  end

  local cached = self.file_state[provider].cached_models
  -- If cached_models is empty table, return nil
  if not cached.models or not cached.timestamp then
    return nil
  end

  local now = os.time()
  local expiry_seconds = cache_expiry_hours * 3600

  -- Check if cache is expired
  -- Note: cache_expiry_hours = 0 means "never expire" (keep cached models forever)
  if cache_expiry_hours > 0 and (now - cached.timestamp) > expiry_seconds then
    return nil
  end

  -- Check if endpoint configuration changed (if hash is provided)
  if endpoint_hash and cached.endpoint_hash and cached.endpoint_hash ~= endpoint_hash then
    return nil
  end

  return cached.models
end

--- Checks if cached models are valid for a provider
--- @param provider string # Provider name
--- @param cache_expiry_hours number # Cache expiry time in hours
--- @param endpoint_hash string|nil # Current endpoint hash for validation
--- @return boolean
function State:is_cache_valid(provider, cache_expiry_hours, endpoint_hash)
  return self:get_cached_models(provider, cache_expiry_hours, endpoint_hash) ~= nil
end

--- Clears cached models for a provider or all providers
--- @param provider string|nil # Provider name, or nil to clear all caches
function State:clear_cache(provider)
  if provider then
    -- Clear cache for specific provider
    if self.file_state[provider] and self.file_state[provider].cached_models then
      self.file_state[provider].cached_models = {}
    end
  else
    -- Clear all caches
    for prov_name, prov_data in pairs(self.file_state) do
      if type(prov_data) == "table" and prov_data.cached_models then
        prov_data.cached_models = {}
      end
    end
  end
end

--- Cleans up cache entries for providers that no longer exist
--- @param available_providers table # Current list of available providers
function State:cleanup_cache(available_providers)
  -- Remove entire provider entries that no longer exist
  for prov_name, _ in pairs(self.file_state) do
    -- Skip special keys like current_provider
    if prov_name ~= "current_provider" and prov_name ~= "last_chat" then
      if not utils.contains(available_providers, prov_name) then
        self.file_state[prov_name] = nil
      end
    end
  end
end

return State
