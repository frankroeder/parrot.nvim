local futils = require("parrot.file_utils")
local utils = require("parrot.utils")

local State = {}
State.__index = State

---@param state_dir string # directory where the state file is located
---@return table # returns a new state instance
function State:new(state_dir)
  local state_file = state_dir .. "/state.json"
  local file_state = vim.fn.filereadable(state_file) ~= 0 and futils.file_to_table(state_file) or {}
  return setmetatable({ state_file = state_file, file_state = file_state, _state = {} }, self)
end

--- Initializes file state for each provider if it's empty
---@param available_providers table # A table of available providers
---@return nil
function State:init_file_state(available_providers)
  if next(self.file_state) == nil then
    for _, prov in ipairs(available_providers) do
      self.file_state[prov] = { chat_agent = nil, command_agent = nil }
    end
  end
end

---@param provider string # provider name to initialize state
---@return nil
function State:init_provider_state(provider)
  self._state[provider] = self._state[provider] or { chat_agent = nil, command_agent = nil }
end

---@param provider string # Name of the provider
---@param agent_type string # Type of agent (e.g., "chat_agent", "command_agent")
---@param available_provider_agents table # A table containing available agents for all providers
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
      if agent_type == "chat_agent" then
        self._state[provider][agent_type] = available_provider_agents[provider].chat[1]
      elseif agent_type == "command_agent" then
        self._state[provider][agent_type] = available_provider_agents[provider].command[1]
      end
    end
  end
end

---@param available_providers table # available providers
---@param available_provider_agents table # available provider agents
function State:refresh(available_providers, available_provider_agents)
  self:init_file_state(available_providers)
  for _, provider in ipairs(available_providers) do
    self:init_provider_state(provider)
    self:load_agents(provider, "chat_agent", available_provider_agents)
    self:load_agents(provider, "command_agent", available_provider_agents)
  end
  self._state.provider = self._state.provider or self.file_state.provider or available_providers[1]
  self._state.last_chat = self._state.last_chat or self.file_state.last_chat or nil
  -- if the previous provider is unavailable, switch to default provider
  if not utils.contains(available_providers, self._state.provider) then
    self._state.provider = available_providers[1]
  end
  self:save()
end

---@return nil
function State:save()
  futils.table_to_file(self._state, self.state_file)
end

---@param provider string # Name of the provider to set
function State:set_provider(provider)
  self._state.provider = provider
end

---@param provider string # provider name
---@param agent table # agent details
---@param atype string # type of the agent ('chat' or 'command')
function State:set_agent(provider, agent, atype)
  if atype == "chat" then
    self._state[provider].chat_agent = agent
  elseif atype == "command" then
    self._state[provider].command_agent = agent
  end
end

---@return string | nil # returns the current provider name, or nil if not set
function State:get_provider()
  return self._state.provider
end

---@param provider string # provider name
---@param atype string # type of agent ('chat' or 'command')
---@return table | nil # returns the agent table or nil if not found
function State:get_agent(provider, atype)
  if atype == "chat" then
    return self._state[provider].chat_agent
  elseif atype == "command" then
    return self._state[provider].command_agent
  end
end

---@param chat_file_path string
function State:set_last_chat(chat_file_path)
  self._state.last_chat = chat_file_path
end

---@return string | nil # returns the last opened chat file path
function State:get_last_chat()
  return self._state.last_chat
end

return State
