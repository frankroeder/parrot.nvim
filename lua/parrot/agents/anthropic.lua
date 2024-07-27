local anthropic_chat_agents = {
  {
    name = "Claude-3.5-Sonnet-Chat",
    model = { model = "claude-3-5-sonnet-20240620", max_tokens = 4096 },
    provider = "anthropic",
  },
  {
    name = "Claude-3-Opus-Chat",
    model = { model = "claude-3-opus-20240229", max_tokens = 4096 },
    provider = "anthropic",
  },
  {
    name = "Claude-3-Sonnet-Chat",
    model = { model = "claude-3-sonnet-20240229", max_tokens = 4096 },
    provider = "anthropic",
  },
  {
    name = "Claude-3-Haiku-Chat",
    model = { model = "claude-3-haiku-20240307", max_tokens = 4096 },
    provider = "anthropic",
  },
}

local anthropic_command_agents = {
  {
    name = "Claude-3.5-Sonnet",
    model = { model = "claude-3-5-sonnet-20240620", max_tokens = 4096 },
    provider = "anthropic",
  },
  {
    name = "Claude-3-Opus",
    model = { model = "claude-3-opus-20240229", max_tokens = 4096 },
    provider = "anthropic",
  },
  {
    name = "Claude-3-Sonnet",
    model = { model = "claude-3-sonnet-20240229", max_tokens = 4096 },
    provider = "anthropic",
  },
  {
    name = "Claude-3-Haiku",
    model = { model = "claude-3-haiku-20240307", max_tokens = 4096 },
    provider = "anthropic",
  },
}

return { chat = anthropic_chat_agents, command = anthropic_command_agents }
