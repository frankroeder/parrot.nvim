local pplx_chat_agents = {
  {
    name = "Llama3-Sonar-Small-32k-Chat",
    model = { model = "llama-3-sonar-small-32k-chat", temperature = 1.1, top_p = 1 },
    provider = "pplx",
  },
  {
    name = "Llama3-Sonar-Large-32k-Chat",
    model = { model = "llama-3-sonar-large-32k-chat", temperature = 1.1, top_p = 1 },
    provider = "pplx",
  },
  {
    name = "Mixtral-8x7B",
    model = { model = "mixtral-8x7b-instruct", temperature = 1.1, top_p = 1 },
    provider = "pplx",
  },
  {
    name = "Llama3-8B-Instruct",
    model = { model = "llama-3-8b-instruct", temperature = 1.1, top_p = 1 },
    provider = "pplx",
  },
  {
    name = "Llama3-70B-Instruct",
    model = { model = "llama-3-70b-instruct", temperature = 1.1, top_p = 1 },
    provider = "pplx",
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
    provider = "pplx",
  },
  {
    name = "Llama3-8B-Instruct",
    model = { model = "llama-3-8b-instruct", temperature = 0.8, top_p = 1 },
    provider = "pplx",
  },
  {
    name = "Llama3-70B-Instruct",
    model = { model = "llama-3-70b-instruct", temperature = 0.8, top_p = 1 },
    provider = "pplx",
  },
}
return { chat = pplx_chat_agents, command = pplx_command_agents }
