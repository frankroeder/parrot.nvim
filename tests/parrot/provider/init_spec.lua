local init_provider = require("parrot.provider").init_provider

describe("provider.init", function()
  it("routes acp configs to AcpProvider", function()
    local provider = init_provider({
      type = "acp",
      name = "grok",
      command = { "grok", "agent", "stdio" },
      models = { "grok-composer-2.5-fast" },
    })
    assert.is_true(provider.is_acp and provider:is_acp())
  end)

  it("routes command-only configs to AcpProvider", function()
    local provider = init_provider({
      name = "grok",
      command = { "grok", "agent", "stdio" },
      models = { "grok-composer-2.5-fast" },
    })
    assert.is_true(provider:is_acp())
  end)

  it("routes classic http configs to MultiProvider (no is_acp)", function()
    local provider = init_provider({
      name = "openai",
      endpoint = "https://api.openai.com/v1/chat/completions",
      api_key = "sk-test",
      model = "gpt-4o",
    })
    assert.is_falsy(provider.is_acp and provider:is_acp())
    assert.is_truthy(provider.endpoint)
  end)
end)