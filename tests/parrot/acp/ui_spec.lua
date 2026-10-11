local acp_client = require("parrot.acp.client")
local acp_ui = require("parrot.acp.ui")

describe("parrot.acp.ui", function()
  local orig_slash_commands, orig_load

  local function fake_parrot(commands)
    acp_client.slash_commands = function()
      return commands
    end
    local prov = {
      name = "grok",
      type = "acp",
      set_model = function() end,
      get_runtime_config = function()
        return { command = { "grok" } }
      end,
    }
    return {
      chat_handler = {
        get_provider = function()
          return prov
        end,
        get_model = function()
          return { name = "grok-build" }
        end,
      },
      options = { chat_dir = "/tmp/chats" },
    }
  end

  before_each(function()
    orig_slash_commands, orig_load = acp_client.slash_commands, acp_client.load_slash_commands
  end)

  after_each(function()
    acp_client.slash_commands, acp_client.load_slash_commands = orig_slash_commands, orig_load
  end)

  it("completes the permission modes", function()
    local parrot = fake_parrot(nil)
    assert.same({ "always-approve-off", "always-approve-on" }, acp_ui.mode_complete(parrot, ""))
    assert.same({ "always-approve-on" }, acp_ui.mode_complete(parrot, "always-approve-on"))
  end)

  it("slash_complete returns the matching known command names", function()
    local parrot = fake_parrot({
      { name = "compact", description = "Compress history" },
      { name = "context", description = "Show context usage" },
    })
    assert.same({ "compact" }, acp_ui.slash_complete(parrot, "com"))
    assert.same({ "compact", "context" }, acp_ui.slash_complete(parrot, "/co"))
  end)

  it("opens the slash command picker from known commands without loading them", function()
    local orig_select = vim.ui.select
    local loaded, items = false, nil
    acp_client.load_slash_commands = function()
      loaded = true
    end
    vim.ui.select = function(list)
      items = list
    end
    acp_ui.select_slash_command(fake_parrot({ { name = "goal", hint = "x" } }), {})
    vim.ui.select = orig_select
    assert.is_false(loaded)
    assert.same({ "goal — x" }, items)
  end)

  it("loads unknown slash commands before opening the picker", function()
    local orig_select = vim.ui.select
    local items
    acp_client.load_slash_commands = function(_, cb)
      cb(nil, { { name = "compact" } })
    end
    vim.ui.select = function(list)
      items = list
    end
    acp_ui.select_slash_command(fake_parrot(nil), {})
    vim.ui.select = orig_select
    assert.same({ "compact" }, items)
  end)
end)
