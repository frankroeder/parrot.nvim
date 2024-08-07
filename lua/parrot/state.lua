local futils = require("parrot.file_utils")
local utils = require("parrot.utils")

local State = {}
State.__index = State

--- Creates a new State instance.
--- @param state_dir string # Directory where the state file is located.
--- @return table # Returns a new state instance.
function State:new(state_dir)
  local state_file = state_dir .. "/state.json"
  local file_state = vim.fn.filereadable(state_file) ~= 0 and futils.file_to_table(state_file) or {}
  return setmetatable({ state_file = state_file, file_state = file_state, _state = {} }, self)
end

--- Initializes file state for each provider if it's empty.
--- @param available_providers table # A table of available providers.
function State:init_file_state(available_providers)
  if next(self.file_state) == nil then
    for _, prov in ipairs(available_providers) do
      self.file_state[prov] = { chat_model = nil, command_model = nil }
    end
  end
end

--- Initializes state for a specific provider if it's not already initialized.
--- @param provider string # Provider name to initialize state.
function State:init_provider_state(provider)
  self._state[provider] = self._state[provider] or { chat_model = nil, command_model = nil }
end

--- Loads model for the specified provider and type.
--- @param provider string # Name of the provider.
--- @param model_type string # Type of model (e.g., "chat_model", "command_model").
--- @param available_models table # A table containing available models for all providers.
function State:load_models(provider, model_type, available_models)
  local state_model = self.file_state and self.file_state[provider] and self.file_state[provider][model_type]
  local is_valid_model = false

  if model_type == "chat_model" then
    is_valid_model = utils.contains(available_models[provider], state_model)
  elseif model_type == "command_model" then
    is_valid_model = utils.contains(available_models[provider], state_model)
  end

  if self._state[provider][model_type] == nil then
    if state_model and is_valid_model then
      self._state[provider][model_type] = state_model
    else
      self._state[provider][model_type] = model_type == "chat_model" and available_models[provider][1]
        or available_models[provider][1]
    end
  end
end

--- Refreshes the state with available providers and their models.
--- @param available_providers table # Available providers.
--- @param available_models table # Available models.
function State:refresh(available_providers, available_models)
  self:init_file_state(available_providers)
  for _, provider in ipairs(available_providers) do
    self:init_provider_state(provider)
    self:load_models(provider, "chat_model", available_models)
    self:load_models(provider, "command_model", available_models)
  end
  self._state.provider = self._state.provider or self.file_state.provider or available_providers[1]
  self._state.last_chat = self._state.last_chat or self.file_state.last_chat or nil

  if not utils.contains(available_providers, self._state.provider) then
    self._state.provider = available_providers[1]
  end
  self:save()
end

--- Saves the current state to the state file.
function State:save()
  futils.table_to_file(self._state, self.state_file)
end

--- Sets the current provider.
--- @param provider string # Name of the provider to set.
function State:set_provider(provider)
  self._state.provider = provider
end

--- Sets the model for a specific provider and interaction type.
--- @param provider string # Provider name.
--- @param model table # Model details.
--- @param atype string # Type of the model ('chat' or 'command').
function State:set_model(provider, model, atype)
  if atype == "chat" then
    self._state[provider].chat_model = model
  elseif atype == "command" then
    self._state[provider].command_model = model
  end
end

--- Gets the current provider.
--- @return string|nil # Returns the current provider name, or nil if not set.
function State:get_provider()
  return self._state.provider
end

--- Gets the model for a specific provider and interaction type.
--- @param provider string # Provider name.
--- @param atype string # Type of model ('chat' or 'command').
--- @return table|nil # Returns the model string
function State:get_model(provider, mtype)
  if mtype == "chat" then
    return self._state[provider].chat_model
  elseif mtype == "command" then
    return self._state[provider].command_model
  end
end

--- Sets the last opened chat file path.
--- @param chat_file_path string # Path to the chat file.
function State:set_last_chat(chat_file_path)
  self._state.last_chat = chat_file_path
end

--- Gets the last opened chat file path.
--- @return string|nil # Returns the last opened chat file path.
function State:get_last_chat()
  return self._state.last_chat
end

return State
