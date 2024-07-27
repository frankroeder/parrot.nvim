local openai_chat_agents = {
  {
    name = "ChatGPT4o",
    model = { model = "gpt-4o", temperature = 1.1, top_p = 1 },
    provider = "openai",
  },
  {
    name = "ChatGPT4",
    model = { model = "gpt-4-turbo", temperature = 1.1, top_p = 1 },
    provider = "openai",
  },
  {
    name = "ChatGPT3.5",
    model = { model = "gpt-3.5-turbo", temperature = 1.1, top_p = 1 },
    provider = "openai",
  },
  {
    name = "ChatGPT4o-Mini",
    model = { model = "gpt-4o-mini", temperature = 1.1, top_p = 1 },
    provider = "openai",
  },
}

local openai_command_agents = {
  {
    name = "CodeGPT4o",
    model = { model = "gpt-4o", temperature = 1.1, top_p = 1 },
    provider = "openai",
  },
  {
    name = "CodeGPT4",
    model = { model = "gpt-4-turbo", temperature = 1.1, top_p = 1 },
    provider = "openai",
  },
  {
    name = "CodeGPT3.5",
    model = { model = "gpt-3.5-turbo", temperature = 1.1, top_p = 1 },
    provider = "openai",
  },
  {
    name = "CodeGPT4o-Mini",
    model = { model = "gpt-4o-mini", temperature = 1.1, top_p = 1 },
    provider = "openai",
  },
}

return { chat = openai_chat_agents, command = openai_command_agents }
