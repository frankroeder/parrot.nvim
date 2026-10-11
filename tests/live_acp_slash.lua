#!/usr/bin/env -S nvim -u tests/minimal_init.lua -l
-- MANUAL ONLY — not run by `make test`. Spawns `grok agent stdio` (can hang without auth).
-- Usage: nvim -u tests/minimal_init.lua -l tests/live_acp_slash.lua
if vim.fn.executable("grok") ~= 1 then
  print("SKIP: grok CLI not installed")
  os.exit(0)
end

local State = require("parrot.state")
local acp_client = require("parrot.acp.client")
local init_provider = require("parrot.provider").init_provider

local dir = vim.fn.tempname() .. "_parrot_live"
vim.fn.mkdir(dir, "p")

local state = State:new(dir)
state:refresh({ "grok" }, { grok = { "grok-4.7" } })

local provider = init_provider({
  type = "acp",
  name = "grok",
  command = { "grok", "agent", "stdio" },
  cli_command = { "grok" },
  models = { "grok-4.7" },
  resume_session = false,
  no_auto_update = true,
})

local runtime = provider:get_runtime_config()
runtime._slash_cache_state = state
local done = false
local min_expected = 5

local function finish(code, msg)
  print(msg)
  acp_client.terminate_all()
  vim.fn.delete(dir, "rf")
  os.exit(code)
end

local warm_err
acp_client.warm_session_cache(runtime, function(err)
  done, warm_err = true, err
end)

if not vim.wait(30000, function()
  return done
end) then
  finish(1, "FAIL: timed out after 30s waiting for slash command cache warm")
end
-- let the deletion of the warm-up session finish before the agent is terminated
vim.wait(1000)

if warm_err then
  finish(1, "FAIL: warm cache error: " .. tostring(warm_err))
end

local commands = state:get_cached_slash_commands("grok", 48) or {}
print("slash commands cached:", #commands)
for _, cmd in ipairs(commands) do
  print("  -", cmd.name, cmd.description or cmd.hint or "")
end

if #commands < min_expected then
  finish(1, string.format("FAIL: expected at least %d slash commands in state.json, got %d", min_expected, #commands))
end

finish(0, "PASS: live ACP slash command cache")
