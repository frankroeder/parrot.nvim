local mistral_chat_agents = {
  {
    name = "Codestral",
    model = { model = "codestral-latest", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
  {
    name = "Mistral-Tiny",
    model = { model = "mistral-tiny", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
  {
    name = "Mistral-Small",
    model = { model = "mistral-small-latest", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
  {
    name = "Mistral-Medium",
    model = { model = "mistral-medium-latest", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
  {
    name = "Mistral-Large",
    model = { model = "mistral-large-latest", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
  {
    name = "Open-Mistral-7B",
    model = { model = "open-mistral-7b", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
  {
    name = "Open-Mixtral-8x7B",
    model = { model = "open-mixtral-8x7b", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
  {
    name = "Open-Mixtral-8x22B",
    model = { model = "open-mixtral-8x22b", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
}

local mistral_command_agents = {
  {
    name = "Codestral",
    model = { model = "codestral-latest", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
  {
    name = "Mistral-Tiny",
    model = { model = "mistral-tiny", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
  {
    name = "Mistral-Small",
    model = { model = "mistral-small-latest", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
  {
    name = "Mistral-Medium",
    model = { model = "mistral-medium-latest", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
  {
    name = "Mistral-Large",
    model = { model = "mistral-large-latest", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
  {
    name = "Open-Mistral-7B",
    model = { model = "open-mistral-7b", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
  {
    name = "Open-Mixtral-8x7B",
    model = { model = "open-mixtral-8x7b", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
  {
    name = "Open-Mixtral-8x22B",
    model = { model = "open-mixtral-8x22b", temperature = 1.5, top_p = 1 },
    provider = "mistral",
  },
}

return { chat = mistral_chat_agents, command = mistral_command_agents }
