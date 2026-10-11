local acp_ui = require("parrot.acp.ui")

describe("parrot.acp.ui", function()
  local function fake_parrot(config, cached)
    local prov = {
      name = "grok",
      type = "acp",
      set_model = function() end,
      get_runtime_config = function()
        return config
      end,
    }
    return {
      chat_handler = {
        state = {
          get_cached_slash_commands = function()
            return cached
          end,
        },
        get_provider = function()
          return prov
        end,
        get_model = function()
          return { name = "grok-build" }
        end,
      },
      options = { chat_dir = "/tmp/chats", model_cache_expiry_hours = 48 },
    }
  end

  it("offers the grok permission toggles as modes", function()
    local modes = acp_ui.modes({ command = { "grok", "agent", "stdio" } })
    assert.equals(2, #modes)
    assert.equals("always-approve-on", modes[1].id)
    assert.equals(2, #acp_ui.modes({ command = { "/home/u/.grok/bin/grok", "agent", "stdio" } }))
    assert.same({}, acp_ui.modes({ command = { "other-agent" } }))
  end)

  it("slash_complete returns the matching cached command names", function()
    local parrot = fake_parrot({ command = { "grok" } }, {
      { name = "compact", description = "Compress history" },
      { name = "context", description = "Show context usage" },
    })
    assert.same({ "compact" }, acp_ui.slash_complete(parrot, "com"))
    assert.same({ "compact", "context" }, acp_ui.slash_complete(parrot, "/co"))
  end)

  it("opens the slash command picker from the cache without starting an agent", function()
    local acp_client = require("parrot.acp.client")
    local orig_warm, orig_select = acp_client.warm_session_cache, vim.ui.select
    local warmed, items = false, nil
    acp_client.warm_session_cache = function()
      warmed = true
    end
    vim.ui.select = function(list)
      items = list
    end
    acp_ui.select_slash_command(
      fake_parrot({ command = { "grok" } }, { { name = "goal", input = { hint = "x" } } }),
      {}
    )
    acp_client.warm_session_cache, vim.ui.select = orig_warm, orig_select
    assert.is_false(warmed)
    assert.same({ "goal" }, items)
  end)
end)
