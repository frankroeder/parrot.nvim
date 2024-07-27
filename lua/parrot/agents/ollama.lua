local ollama_chat_agents = {
  {
    name = "Mistal-7B",
    model = { model = "mistral:latest", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    provider = "ollama",
  },
  {
    name = "Llama2-7B",
    model = { model = "llama2:latest", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    provider = "ollama",
  },
  {
    name = "Llama2-13B",
    model = { model = "llama2:13b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    provider = "ollama",
  },
  {
    name = "Llama3-8B",
    model = { model = "llama3:latest", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    provider = "ollama",
  },
  {
    name = "Gemma-2B",
    model = { model = "gemma:2b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    provider = "ollama",
  },
  {
    name = "Gemma-7B",
    model = { model = "gemma:7b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    provider = "ollama",
  },
  {
    name = "Llama3.1-8B",
    model = { model = "llama3.1:8b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    provider = "ollama",
  },
}

local ollama_command_agents = {
  {
    name = "Mistal-7B",
    model = { model = "mistral:latest", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    provider = "ollama",
  },
  {
    name = "Llama2-7B",
    model = { model = "llama2:latest", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    provider = "ollama",
  },
  {
    name = "Llama3-8B",
    model = { model = "llama3:latest", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    provider = "ollama",
  },
  {
    name = "Llama2-13B",
    model = { model = "llama2:13b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    provider = "ollama",
  },
  {
    name = "Gemma-2B",
    model = { model = "gemma:2b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    provider = "ollama",
  },
  {
    name = "Gemma-7B",
    model = { model = "gemma:7b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    provider = "ollama",
  },
  {
    name = "Llama3.1-8B",
    model = { model = "llama3.1:8b", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    provider = "ollama",
  },
}

return { chat = ollama_chat_agents, command = ollama_command_agents }
