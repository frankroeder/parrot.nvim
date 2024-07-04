local M = {}

M.merge_providers = function(default_providers, user_providers)
  local result = {}
  for provider, prov_config in pairs(default_providers) do
    result[provider] = prov_config
  end
  for uprovider, uprov_config in pairs(user_providers) do
    result[uprovider] = vim.tbl_deep_extend("force", result[uprovider], uprov_config)
  end
  return result
end

M.merge_agent_type = function(default_agents, user_agents, providers)
  local merged = {}
  for _, default_agent in ipairs(default_agents) do
    if providers[default_agent.provider] then
      merged[default_agent.name] = default_agent
    end
  end
  if user_agents then
    for _, user_agent in ipairs(user_agents) do
      if user_agent and providers[user_agent.provider] then
        if merged[user_agent.name] then
          merged[user_agent.name] = vim.tbl_deep_extend("force", merged[user_agent.name], user_agent)
        else
          merged[user_agent.name] = user_agent
        end
      end
    end
  end
  return merged
end

M.merge_agents = function(default_agents, user_agents, user_providers)
  return {
    command = M.merge_agent_type(default_agents.command or {}, user_agents.command, user_providers),
    chat = M.merge_agent_type(default_agents.chat or {}, user_agents.chat, user_providers),
  }
end

return M
