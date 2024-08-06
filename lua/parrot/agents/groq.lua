local groq_chat_agents = {
  {
    name = "Llama3.1-405b-reasoning",
    model = { model = "llama-3.1-405b-reasoning", temperature = 1.5, top_p = 1 },
    provider = "groq",
  },
  {
    name = "Llama3.1-70B-versatile",
    model = { model = "llama-3.1-70b-versatile", temperature = 1.5, top_p = 1 },
    provider = "groq",
  },
  {
    name = "Llama3.1-8B-instant",
    model = { model = "llama-3.1-8b-instant", temperature = 1.5, top_p = 1 },
    provider = "groq",
  },
}

local groq_command_agents = {
  {
    name = "Llama3.1-405b-reasoning",
    model = { model = "llama-3.1-405b-reasoning", temperature = 1.5, top_p = 1 },
    provider = "groq",
  },
  {
    name = "Llama3.1-70B-versatile",
    model = { model = "llama-3.1-70b-versatile", temperature = 1.5, top_p = 1 },
    provider = "groq",
  },
  {
    name = "Llama3.1-8B-instant",
    model = { model = "llama-3.1-8b-instant", temperature = 1.5, top_p = 1 },
    provider = "groq",
  },
}

return { chat = groq_chat_agents, command = groq_command_agents }
