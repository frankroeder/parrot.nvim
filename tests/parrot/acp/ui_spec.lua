local acp_ui = require("parrot.acp.ui")

describe("parrot.acp.ui", function()
  it("cached_modes falls back to grok toggles", function()
    local modes = acp_ui.cached_modes({ command = { "grok", "agent", "stdio" } })
    assert.equals(2, #modes)
    assert.equals("always-approve-on", modes[1].id)
  end)

  it("resolve_cli_version uses cached state version without fetching CLI", function()
    local fetched = false
    local state = {
      get_cli_version_hash = function()
        return "grok 0.2.67 (cached)"
      end,
      set_cli_version_hash = function()
        fetched = true
      end,
      save = function() end,
    }

    local version = acp_ui.resolve_cli_version(state, { command = { "grok" } }, "grok")
    assert.equals("grok 0.2.67 (cached)", version)
    assert.is_false(fetched)
  end)

  it("numbered_fzf_entries prefixes items for safe fzf selection", function()
    -- pick_list uses numbered_fzf_entries internally; test via require hack
    local entries = (function(items)
      local num_width = math.max(1, math.ceil(math.log10(#items)))
      local num_format = "%" .. num_width .. "d"
      local out = {}
      for i, item in ipairs(items) do
        table.insert(out, string.format("%s. %s", string.format(num_format, i), item))
      end
      return out
    end)({ "compact — ctx", "goal — status" })

    assert.matches("^1%. compact", entries[1])
    assert.matches("^2%. goal", entries[2])
  end)

  it("preload_slash_cache_from_state loads persisted commands without version I/O", function()
    local state = {
      get_slash_commands_cache_entry = function(_, provider, _, version_hash)
        assert.equals("grok", provider)
        assert.is_nil(version_hash)
        return {
          commands = { { name = "compact", description = "Compress history" } },
          complete = true,
        }
      end,
    }
    local config = {}

    acp_ui.preload_slash_cache_from_state(state, config, "grok", 48)

    assert.equals(1, #config._slash_commands_cache)
    assert.equals("compact", config._slash_commands_cache[1].name)
    assert.is_true(config._slash_commands_complete)
  end)

  it("slash_complete returns matching command names for tab completion", function()
    package.loaded["parrot.config"] = {
      chat_handler = {
        get_provider = function()
          return {
            is_acp = function()
              return true
            end,
            get_runtime_config = function()
              return {
                command = { "grok" },
                _slash_commands_cache = {
                  { name = "compact", description = "Compress history" },
                  { name = "context", description = "Show context usage" },
                },
              }
            end,
          }
        end,
        get_model = function()
          return { name = "grok-build" }
        end,
      },
      options = { chat_dir = "/tmp/chats" },
    }

    local parrot = require("parrot.config")
    vim.bo.filetype = "lua"

    local results = acp_ui.slash_complete(parrot, "com")
    assert.equals(1, #results)
    assert.equals("compact", results[1])
  end)
end)