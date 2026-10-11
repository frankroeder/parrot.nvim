-- MANUAL ONLY — not run by `make test`. Spawns `grok agent stdio` (can hang without auth).
-- Usage: nvim -u tests/minimal_init.lua -l tests/live_acp_slash.lua
if vim.fn.executable("grok") ~= 1 then
  print("SKIP: grok CLI not installed")
  os.exit(0)
end

local acp_client = require("parrot.acp.client")
local provider = require("parrot.provider").init_provider({ type = "acp", name = "grok", models = { "grok-4.7" } })

local function finish(code, msg)
  print(msg)
  acp_client.terminate_all()
  os.exit(code)
end

local done, err, commands = false, nil, nil
acp_client.load_slash_commands(provider:get_runtime_config(), function(e, c)
  done, err, commands = true, e, c
end)
if not vim.wait(30000, function()
  return done
end) then
  finish(1, "FAIL: timed out after 30s waiting for the slash commands")
end
-- let the deletion of the throwaway session finish before the agent is terminated
vim.wait(1000)

if err then
  finish(1, "FAIL: " .. tostring(err))
end
for _, cmd in ipairs(commands or {}) do
  print("  -", cmd.name, cmd.description or cmd.hint or "")
end
if #(commands or {}) < 5 then
  finish(1, string.format("FAIL: expected at least 5 slash commands, got %d", #(commands or {})))
end
finish(0, "PASS: live ACP slash commands")
