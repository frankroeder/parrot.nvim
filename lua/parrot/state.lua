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
      self.file_state[prov] = { chat_agent = nil, command_agent = nil }
    end
  end
end

--- Initializes state for a specific provider if it's not already initialized.
--- @param provider string # Provider name to initialize state.
function State:init_provider_state(provider)
  self._state[provider] = self._state[provider] or { chat_agent = nil, command_agent = nil }
end

--- Loads agents for the specified provider and agent type.
--- @param provider string # Name of the provider.
--- @param agent_type string # Type of agent (e.g., "chat_agent", "command_agent").
--- @param available_provider_agents table # A table containing available agents for all providers.
function State:load_agents(provider, agent_type, available_provider_agents)
  local state_agent = self.file_state and self.file_state[provider] and self.file_state[provider][agent_type]
  local is_valid_agent = false

  if agent_type == "chat_agent" then
    is_valid_agent = utils.contains(available_provider_agents[provider].chat, state_agent)
  elseif agent_type == "command_agent" then
    is_valid_agent = utils.contains(available_provider_agents[provider].command, state_agent)
  end

  if self._state[provider][agent_type] == nil then
    if state_agent and is_valid_agent then
      self._state[provider][agent_type] = state_agent
    else
      self._state[provider][agent_type] = agent_type == "chat_agent" and available_provider_agents[provider].chat[1]
        or available_provider_agents[provider].command[1]
    end
  end
end

--- Refreshes the state with available providers and their agents.
--- @param available_providers table # Available providers.
--- @param available_provider_agents table # Available provider agents.
function State:refresh(available_providers, available_provider_agents)
  self:init_file_state(available_providers)
  for _, provider in ipairs(available_providers) do
    self:init_provider_state(provider)
    self:load_agents(provider, "chat_agent", available_provider_agents)
    self:load_agents(provider, "command_agent", available_provider_agents)
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

--- Sets the agent for a specific provider and agent type.
--- @param provider string # Provider name.
--- @param agent table # Agent details.
--- @param atype string # Type of the agent ('chat' or 'command').
function State:set_agent(provider, agent, atype)
  if atype == "chat" then
    self._state[provider].chat_agent = agent
  elseif atype == "command" then
    self._state[provider].command_agent = agent
  end
end

--- Gets the current provider.
--- @return string|nil # Returns the current provider name, or nil if not set.
function State:get_provider()
  return self._state.provider
end

--- Gets the agent for a specific provider and agent type.
--- @param provider string # Provider name.
--- @param atype string # Type of agent ('chat' or 'command').
--- @return table|nil # Returns the agent table or nil if not found.
function State:get_agent(provider, atype)
  if atype == "chat" then
    return self._state[provider].chat_agent
  elseif atype == "command" then
    return self._state[provider].command_agent
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
