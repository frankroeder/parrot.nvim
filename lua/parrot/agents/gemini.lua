local gemini_chat_agents = {
  {
    name = "Gemini-1.5-Flash-Chat",
    model = { model = "gemini-1.5-flash", temperature = 1.1, topP = 1, topK = 10, maxOutputTokens = 8192 },
    provider = "gemini",
  },
  {
    name = "Gemini-1.5-Pro-Chat",
    model = { model = "gemini-1.5-pro", temperature = 1.1, topP = 1, topK = 10, maxOutputTokens = 8192 },
    provider = "gemini",
  },
}
local gemini_command_agents = {
  {
    name = "Gemini-1.5-Flash",
    model = { model = "gemini-1.5-flash", temperature = 0.8, topP = 1, topK = 10, maxOutputTokens = 8192 },
    provider = "gemini",
  },
  {
    name = "Gemini-1.5-Pro",
    model = { model = "gemini-1.5-pro", temperature = 0.8, topP = 1, topK = 10, maxOutputTokens = 8192 },
    provider = "gemini",
  },
}

return { chat = gemini_chat_agents, command = gemini_command_agents }
