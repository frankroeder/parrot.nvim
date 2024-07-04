local M = {}

M.merge_providers = function(default_providers, user_providers)
  local result = {}
  for provider, config in pairs(user_providers) do
    result[provider] = vim.tbl_deep_extend('force', default_providers[provider] or {}, config)
  end
  return result
end

M.merge_agent_type = function(default_agents, user_agents, user_providers)
  local result = vim.deepcopy(user_agents) or {}
  for _, default_agent in ipairs(default_agents) do
    if user_providers[default_agent.provider] then
      table.insert(result, vim.deepcopy(default_agent))
    end
  end
  return result
end

M.merge_agents = function(default_agents, user_agents, user_providers)
  return {
    command = M.merge_agent_type(default_agents.command or {}, user_agents.command, user_providers),
    chat = M.merge_agent_type(default_agents.chat or {}, user_agents.chat, user_providers),
  }
end

return M
