local anthropic_agents = require("parrot.agents.anthropic")
local pplx_agents = require("parrot.agents.perplexity")
local openai_agents = require("parrot.agents.openai")
local ollama_agents = require("parrot.agents.ollama")
local mistral_agents = require("parrot.agents.mistral")
local gemini_agents = require("parrot.agents.gemini")

local system_chat_prompt = [[
You are a versatile AI assistant with capabilities
extending to general knowledge and coding support. When engaging
with users, please adhere to the following guidelines to ensure
the highest quality of interaction:

- Admit when unsure by saying 'I don't know.'
- Ask for clarification when needed.
- Use first principles thinking to analyze queries.
- Start with the big picture, then focus on details.
- Apply the Socratic method to enhance understanding.
- Include all necessary code in your responses.
- Stay calm and confident with each task.
]]

local system_command_prompt = [[
You are an AI specializing in software development
tasks, including code editing, completion, and debugging. Your
responses should strictly pertain to the code provided. Please ensure
that your reply is solely focused on the code snippet in question.
]]

local M = {
  chat = {},
  command = {},
}

local inject_prompt = function(agent, agent_type)
  if agent_type == "chat" then
    agent.system_prompt = system_chat_prompt
  elseif agent_type == "command" then
    agent.system_prompt = system_command_prompt
  end
  return agent
end

for _, agent_type in ipairs({ "chat", "command" }) do
  for _, agent in ipairs(anthropic_agents[agent_type]) do
    table.insert(M[agent_type], inject_prompt(agent, agent_type))
  end
  for _, agent in ipairs(pplx_agents[agent_type]) do
    table.insert(M[agent_type], inject_prompt(agent, agent_type))
  end
  for _, agent in ipairs(openai_agents[agent_type]) do
    table.insert(M[agent_type], inject_prompt(agent, agent_type))
  end
  for _, agent in ipairs(ollama_agents[agent_type]) do
    table.insert(M[agent_type], inject_prompt(agent, agent_type))
  end
  for _, agent in ipairs(mistral_agents[agent_type]) do
    table.insert(M[agent_type], inject_prompt(agent, agent_type))
  end
  for _, agent in ipairs(gemini_agents[agent_type]) do
    table.insert(M[agent_type], inject_prompt(agent, agent_type))
  end
end

return M
