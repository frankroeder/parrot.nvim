local pplx_chat_agents = {
  {
    name = "Llama3.1-Sonar-Small-128k-Chat",
    model = { model = "llama-3.1-sonar-small-128k-chat", temperature = 1.1, top_p = 1 },
    provider = "pplx",
  },
  {
    name = "Llama3.1-Sonar-Large-128k-Chat",
    model = { model = "llama-3.1-sonar-large-128k-chat", temperature = 1.1, top_p = 1 },
    provider = "pplx",
  },
  {
    name = "Mixtral-8x7B",
    model = { model = "mixtral-8x7b-instruct", temperature = 1.1, top_p = 1 },
    provider = "pplx",
  },
  {
    name = "Llama3.1-8B-Instruct",
    model = { model = "llama-3.1-8b-instruct", temperature = 1.1, top_p = 1 },
    provider = "pplx",
  },
  {
    name = "Llama3.1-70B-Instruct",
    model = { model = "llama-3.1-70b-instruct", temperature = 1.1, top_p = 1 },
    provider = "pplx",
  },
}

local pplx_command_agents = {
  {
    name = "Llama3.1-Sonar-Small-128k--Online",
    model = { model = "llama-3.1-sonar-small-128k-online", temperature = 0.8, top_p = 1 },
    provider = "pplx",
  },
  {
    name = "Llama3.1-Sonar-Large-128k--Online",
    model = { model = "llama-3.1-sonar-large-128k-online", temperature = 0.8, top_p = 1 },
    provider = "pplx",
  },
  {
    name = "Mixtral-8x7B",
    model = { model = "mixtral-8x7b-instruct", temperature = 0.8, top_p = 1 },
    provider = "pplx",
  },
  {
    name = "Llama3.1-8B-Instruct",
    model = { model = "llama-3.1-8b-instruct", temperature = 0.8, top_p = 1 },
    provider = "pplx",
  },
  {
    name = "Llama3.1-70B-Instruct",
    model = { model = "llama-3.1-70b-instruct", temperature = 0.8, top_p = 1 },
    provider = "pplx",
  },
}
return { chat = pplx_chat_agents, command = pplx_command_agents }
