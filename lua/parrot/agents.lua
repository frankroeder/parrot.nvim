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

local system_code_prompt = [[
You are an AI specializing in software development
tasks, including code editing, completion, and debugging. Your
responses should strictly pertain to the code provided. Please ensure
that your reply is solely focused on the code snippet in question.
]]

local ollama_chat_agents = {
  {
    name = "Mistal-7B",
    model = { model = "mistral:latest", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    system_prompt = system_chat_prompt,
    provider = "ollama",
  },
  {
    name = "Llama2-7B",
    model = { model = "llama2:latest", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    system_prompt = system_chat_prompt,
    provider = "ollama",
  },
  {
    name = "Llama2-13B",
    model = { model = "llama2:13b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    system_prompt = system_chat_prompt,
    provider = "ollama",
  },
  {
    name = "Llama3-8B",
    model = { model = "llama3:latest", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    system_prompt = system_chat_prompt,
    provider = "ollama",
  },
  {
    name = "Gemma-2B",
    model = { model = "gemma:2b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    system_prompt = system_chat_prompt,
    provider = "ollama",
  },
  {
    name = "Gemma-7B",
    model = { model = "gemma:7b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    system_prompt = system_chat_prompt,
    provider = "ollama",
  },
}

local openai_chat_agents = {
  {
    name = "ChatGPT4o",
    model = { model = "gpt-4o", temperature = 1.1, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "openai",
  },
  {
    name = "ChatGPT4",
    model = { model = "gpt-4-turbo", temperature = 1.1, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "openai",
  },
  {
    name = "ChatGPT3.5",
    model = { model = "gpt-3.5-turbo", temperature = 1.1, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "openai",
  },
}

local pplx_chat_agents = {
  {
    name = "Llama3-Sonar-Small-32k-Chat",
    model = { model = "llama-3-sonar-small-32k-chat", temperature = 1.1, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "pplx",
  },
  {
    name = "Llama3-Sonar-Large-32k-Chat",
    model = { model = "llama-3-sonar-large-32k-chat", temperature = 1.1, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "pplx",
  },
  {
    name = "Mixtral-8x7B",
    model = { model = "mixtral-8x7b-instruct", temperature = 1.1, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "pplx",
  },
  {
    name = "Llama3-8B-Instruct",
    model = { model = "llama-3-8b-instruct", temperature = 1.1, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "pplx",
  },
  {
    name = "Llama3-70B-Instruct",
    model = { model = "llama-3-70b-instruct", temperature = 1.1, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "pplx",
  },
}

local anthropic_chat_agents = {
  {
    name = "Claude-3.5-Sonnet-Chat",
    model = { model = "claude-3-5-sonnet-20240620", max_tokens = 4096, system = system_chat_prompt },
    system_prompt = "",
    provider = "anthropic",
  },
  {
    name = "Claude-3-Opus-Chat",
    model = { model = "claude-3-opus-20240229", max_tokens = 4096, system = system_chat_prompt },
    system_prompt = "",
    provider = "anthropic",
  },
  {
    name = "Claude-3-Sonnet-Chat",
    model = { model = "claude-3-sonnet-20240229", max_tokens = 4096, system = system_chat_prompt },
    system_prompt = "",
    provider = "anthropic",
  },
  {
    name = "Claude-3-Haiku-Chat",
    model = { model = "claude-3-haiku-20240307", max_tokens = 4096, system = system_chat_prompt },
    system_prompt = "",
    provider = "anthropic",
  },
}
local mistral_chat_agents = {
  {
    name = "Codestral",
    model = { model = "codestral-latest", temperature = 1.5, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "mistral",
  },
  {
    name = "Mistral-Tiny",
    model = { model = "mistral-tiny", temperature = 1.5, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "mistral",
  },
  {
    name = "Mistral-Small",
    model = { model = "mistral-small-latest", temperature = 1.5, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "mistral",
  },
  {
    name = "Mistral-Medium",
    model = { model = "mistral-medium-latest", temperature = 1.5, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "mistral",
  },
  {
    name = "Mistral-Large",
    model = { model = "mistral-large-latest", temperature = 1.5, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "mistral",
  },
  {
    name = "Open-Mistral-7B",
    model = { model = "open-mistral-7b", temperature = 1.5, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "mistral",
  },
  {
    name = "Open-Mixtral-8x7B",
    model = { model = "open-mixtral-8x7b", temperature = 1.5, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "mistral",
  },
  {
    name = "Open-Mixtral-8x22B",
    model = { model = "open-mixtral-8x22b", temperature = 1.5, top_p = 1 },
    system_prompt = system_chat_prompt,
    provider = "mistral",
  },
}

local ollama_command_agents = {
  {
    name = "Mistal-7B",
    model = { model = "mistral:latest", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    system_prompt = system_code_prompt,
    provider = "ollama",
  },
  {
    name = "Llama2-7B",
    model = { model = "llama2:latest", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    system_prompt = system_code_prompt,
    provider = "ollama",
  },
  {
    name = "Llama3-8B",
    model = { model = "llama3:latest", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    system_prompt = system_code_prompt,
    provider = "ollama",
  },
  {
    name = "Llama2-13B",
    model = { model = "llama2:13b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    system_prompt = system_code_prompt,
    provider = "ollama",
  },
  {
    name = "Gemma-2B",
    model = { model = "gemma:2b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    system_prompt = system_code_prompt,
    provider = "ollama",
  },
  {
    name = "Gemma-7B",
    model = { model = "gemma:7b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    system_prompt = system_code_prompt,
    provider = "ollama",
  },
}

local openai_command_agents = {
  {
    name = "CodeGPT4o",
    model = { model = "gpt-4o", temperature = 1.1, top_p = 1 },
    system_prompt = system_code_prompt,
    provider = "openai",
  },
  {
    name = "CodeGPT4",
    model = { model = "gpt-4-turbo", temperature = 1.1, top_p = 1 },
    system_prompt = system_code_prompt,
    provider = "openai",
  },
  {
    name = "CodeGPT3.5",
    model = { model = "gpt-3.5-turbo", temperature = 1.1, top_p = 1 },
    system_prompt = system_code_prompt,
    provider = "openai",
  },
}

local pplx_command_agents = {
  {
    name = "Llama3-Sonar-Small-32k--Online",
    model = { model = "llama-3-sonar-small-32k-online", temperature = 0.8, top_p = 1 },
    provider = "pplx",
  },
  {
    name = "Llama3-Sonar-Large-32k--Online",
    model = { model = "llama-3-sonar-large-32k-online", temperature = 0.8, top_p = 1 },
    provider = "pplx",
  },
  {
    name = "Mixtral-8x7B",
    model = { model = "mixtral-8x7b-instruct", temperature = 0.8, top_p = 1 },
    system_prompt = system_code_prompt,
    provider = "pplx",
  },
  {
    name = "Llama3-8B-Instruct",
    model = { model = "llama-3-8b-instruct", temperature = 0.8, top_p = 1 },
    system_prompt = system_code_prompt,
    provider = "pplx",
  },
  {
    name = "Llama3-70B-Instruct",
    model = { model = "llama-3-70b-instruct", temperature = 0.8, top_p = 1 },
    system_prompt = system_code_prompt,
    provider = "pplx",
  },
}

local anthropic_command_agents = {
  {
    name = "Claude-3.5-Sonnet",
    model = { model = "claude-3-5-sonnet-20240620", max_tokens = 4096, system = system_code_prompt },
    provider = "anthropic",
  },
  {
    name = "Claude-3-Opus",
    model = { model = "claude-3-opus-20240229", max_tokens = 4096, system = system_code_prompt },
    provider = "anthropic",
  },
  {
    name = "Claude-3-Sonnet",
    model = { model = "claude-3-sonnet-20240229", max_tokens = 4096, system = system_code_prompt },
    provider = "anthropic",
  },
  {
    name = "Claude-3-Haiku",
    model = { model = "claude-3-haiku-20240307", max_tokens = 4096, system = system_code_prompt },
    provider = "anthropic",
  },
}
local mistral_command_agents = {
  {
    name = "Codestral",
    model = { model = "codestral-latest", temperature = 1.5, top_p = 1 },
    system_prompt = system_code_prompt,
    provider = "mistral",
  },
  {
    name = "Mistral-Tiny",
    model = { model = "mistral-tiny", temperature = 1.5, top_p = 1 },
    system_prompt = system_code_prompt,
    provider = "mistral",
  },
  {
    name = "Mistral-Small",
    model = { model = "mistral-small-latest", temperature = 1.5, top_p = 1 },
    system_prompt = system_code_prompt,
    provider = "mistral",
  },
  {
    name = "Mistral-Medium",
    model = { model = "mistral-medium-latest", temperature = 1.5, top_p = 1 },
    system_prompt = system_code_prompt,
    provider = "mistral",
  },
  {
    name = "Mistral-Large",
    model = { model = "mistral-large-latest", temperature = 1.5, top_p = 1 },
    system_prompt = system_code_prompt,
    provider = "mistral",
  },
  {
    name = "Open-Mistral-7B",
    model = { model = "open-mistral-7b", temperature = 1.5, top_p = 1 },
    system_prompt = system_code_prompt,
    provider = "mistral",
  },
  {
    name = "Open-Mixtral-8x7B",
    model = { model = "open-mixtral-8x7b", temperature = 1.5, top_p = 1 },
    system_prompt = system_code_prompt,
    provider = "mistral",
  },
  {
    name = "Open-Mixtral-8x22B",
    model = { model = "open-mixtral-8x22b", temperature = 1.5, top_p = 1 },
    system_prompt = system_code_prompt,
    provider = "mistral",
  },
}

local M = {}

M.chat_agents = {}
for _, agent in ipairs(ollama_chat_agents) do
  table.insert(M.chat_agents, agent)
end
for _, agent in ipairs(openai_chat_agents) do
  table.insert(M.chat_agents, agent)
end
for _, agent in ipairs(pplx_chat_agents) do
  table.insert(M.chat_agents, agent)
end
for _, agent in ipairs(anthropic_chat_agents) do
  table.insert(M.chat_agents, agent)
end
for _, agent in ipairs(mistral_chat_agents) do
  table.insert(M.chat_agents, agent)
end

M.command_agents = {}
for _, agent in ipairs(ollama_command_agents) do
  table.insert(M.command_agents, agent)
end
for _, agent in ipairs(openai_command_agents) do
  table.insert(M.command_agents, agent)
end
for _, agent in ipairs(pplx_command_agents) do
  table.insert(M.command_agents, agent)
end
for _, agent in ipairs(anthropic_command_agents) do
  table.insert(M.command_agents, agent)
end
for _, agent in ipairs(mistral_command_agents) do
  table.insert(M.command_agents, agent)
end

return M
