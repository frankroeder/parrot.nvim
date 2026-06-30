#!/usr/bin/env -S nvim -u tests/minimal_init.lua -l
-- MANUAL ONLY — not run by `make test`. Spawns `grok agent stdio` (can hang without auth).
-- Usage: nvim -u tests/minimal_init.lua -l tests/live_acp_slash.lua
if vim.fn.executable("grok") ~= 1 then
  print("SKIP: grok CLI not installed")
  os.exit(0)
end

local State = require("parrot.state")
local acp_ui = require("parrot.acp.ui")
local init_provider = require("parrot.provider").init_provider

local dir = vim.fn.tempname() .. "_parrot_live"
vim.fn.mkdir(dir, "p")

local state = State:new(dir)
state:init_file_state({ "grok" })
state:init_state({ "grok" }, { grok = { "grok-build" } })

local provider = init_provider({
  type = "acp",
  name = "grok",
  command = { "grok", "agent", "stdio" },
  cli_command = { "grok" },
  models = { "grok-build" },
  resume_session = false,
})

local runtime = provider:get_runtime_config()
local done = false
local min_expected = 5

acp_ui.refresh_slash_commands_cache(state, runtime, "grok", 48, function(err, commands)
  done = true
  if err then
    print("FAIL: warm cache error: " .. tostring(err))
    os.exit(1)
  end

  local count = #(commands or {})
  print("slash commands cached:", count)
  for _, cmd in ipairs(commands or {}) do
    print("  -", cmd.name, cmd.description or cmd.hint or "")
  end

  if count < min_expected then
    print(string.format("FAIL: expected at least %d slash commands, got %d", min_expected, count))
    os.exit(1)
  end

  if not state:is_slash_commands_cache_valid("grok", 48, state:get_cli_version_hash("grok")) then
    print("FAIL: slash commands cache not marked complete in state")
    os.exit(1)
  end

  local persisted = state:get_cached_slash_commands("grok", 48, state:get_cli_version_hash("grok"), true)
  if not persisted or #persisted < min_expected then
    print("FAIL: slash commands not persisted to state")
    os.exit(1)
  end

  print("PASS: live ACP slash command cache")
  vim.fn.delete(dir, "rf")
  os.exit(0)
end)

local ok = vim.wait(30000, function()
  return done
end)

if not ok or not done then
  print("FAIL: timed out after 30s waiting for slash command cache warm")
  os.exit(1)
end