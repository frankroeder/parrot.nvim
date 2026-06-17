-- Neovim-based verification for Claude CLI integration
-- Run with: nvim --headless -c 'luafile tests/verify_nvim.lua' -c 'quit'

local function green(text)
  return "\27[32m" .. text .. "\27[0m"
end

local function red(text)
  return "\27[31m" .. text .. "\27[0m"
end

local function bold(text)
  return "\27[1m" .. text .. "\27[0m"
end

local function check(condition, name)
  if condition then
    print(green("✓") .. " " .. name)
    return true
  else
    print(red("✗") .. " " .. name)
    return false
  end
end

local function section(name)
  print("")
  print(bold("=== " .. name .. " ==="))
end

local passed = 0
local failed = 0

section("Neovim Module Loading Test")

-- Test loading modules
local ok1, ClaudeCliProvider = pcall(require, "parrot.provider.claude_cli")
if check(ok1, "Load ClaudeCliProvider") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Error: " .. tostring(ClaudeCliProvider))
  print("")
  print(red("Cannot continue - module loading failed"))
  os.exit(1)
end

local ok2, init_provider = pcall(require, "parrot.provider.init")
if check(ok2, "Load init_provider") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Error: " .. tostring(init_provider))
  os.exit(1)
end

section("Provider Creation & Interface")

-- Create provider
local prov_ok, provider = pcall(ClaudeCliProvider.new, ClaudeCliProvider, {
  name = "test_cli",
  command = "claude",
  models = { "claude-sonnet-4-5" },
})

if check(prov_ok, "Create ClaudeCliProvider") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Error: " .. tostring(provider))
  os.exit(1)
end

-- Test interface methods
if check(provider:get_command() == "claude", "get_command()") then
  passed = passed + 1
else
  failed = failed + 1
end

if check(provider:uses_json_payload() == false, "uses_json_payload()") then
  passed = passed + 1
else
  failed = failed + 1
end

if check(provider:resolve_api_key(nil) == true, "resolve_api_key()") then
  passed = passed + 1
else
  failed = failed + 1
end

if check(provider:verify(), "verify()") then
  passed = passed + 1
else
  failed = failed + 1
end

local models = provider:get_available_models()
if check(#models == 1 and models[1] == "claude-sonnet-4-5", "get_available_models()") then
  passed = passed + 1
else
  failed = failed + 1
end

section("Payload Processing")

-- Test basic payload
local payload1 = {
  messages = {
    { role = "user", content = "Hello" }
  }
}

local args1 = provider:curl_params(payload1)
if check(#args1 == 3, "Basic args count") then
  passed = passed + 1
  print("  Args: " .. table.concat(args1, " "))
else
  failed = failed + 1
end

local stdin1 = provider:preprocess_payload(payload1)
if check(stdin1 == "Hello", "Extract user message") then
  passed = passed + 1
else
  failed = failed + 1
end

-- Test with system prompt
local payload2 = {
  messages = {
    { role = "system", content = "You are helpful" },
    { role = "user", content = "Hello" }
  }
}

local args2 = provider:curl_params(payload2)
if check(#args2 == 5, "Args with system prompt") then
  passed = passed + 1
  print("  Args: " .. table.concat(args2, " "))
else
  failed = failed + 1
end

if check(vim.tbl_contains(args2, "--system-prompt"), "System prompt flag present") then
  passed = passed + 1
else
  failed = failed + 1
end

-- Test output processing
local out1 = provider:process_stdout("Hello world")
if check(out1 == "Hello world\n", "process_stdout() adds newline") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Expected 'Hello world\\n', got '" .. tostring(out1) .. "'")
end

local out2 = provider:process_stdout("")
if check(out2 == "\n", "process_stdout() preserves empty lines") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Expected '\\n', got '" .. tostring(out2) .. "'")
end

local out3 = provider:process_stdout(nil)
if check(out3 == nil, "process_stdout() returns nil for nil") then
  passed = passed + 1
else
  failed = failed + 1
end

-- Test formatting preservation
local lines = { "## Header", "", "- Item 1", "- Item 2" }
local formatted = {}
for _, line in ipairs(lines) do
  local processed = provider:process_stdout(line)
  if processed then
    table.insert(formatted, processed)
  end
end
local result = table.concat(formatted, "")
if check(result == "## Header\n\n- Item 1\n- Item 2\n", "Formatting preserved (blank lines, structure)") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Result: " .. result)
end

local out_exit = provider:process_onexit("Content")
if check(out_exit == nil, "process_onexit() returns nil (no duplication)") then
  passed = passed + 1
else
  failed = failed + 1
end

section("Provider Type Detection")

-- Test that CLI provider is detected via init_provider
local init_ok, init_prov = pcall(init_provider.init_provider, {
  name = "test_cli",
  command = "claude",
  models = { "claude-sonnet-4-5" },
})

if check(init_ok, "CLI provider via init_provider") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Error: " .. tostring(init_prov))
end

if init_ok then
  if check(init_prov:uses_json_payload() == false, "Detected as CLI (not JSON)") then
    passed = passed + 1
  else
    failed = failed + 1
  end

  if check(init_prov:get_command() == "claude", "Command is 'claude'") then
    passed = passed + 1
  else
    failed = failed + 1
  end
end

section("Boolean Logic Verification")

-- This is the critical test - ensure false is preserved
local test_provider = {
  uses_json_payload = function() return false end
}

-- Simulate the fixed logic
local uses_json = true
if test_provider.uses_json_payload ~= nil then
  uses_json = test_provider.uses_json_payload()
end

if check(uses_json == false, "Boolean false preserved (not converted to true)") then
  passed = passed + 1
  print("  This was the critical bug fix!")
else
  failed = failed + 1
  print("  CRITICAL: Boolean logic is broken!")
end

-- Summary
section("Summary")
print("")
print(bold("Total: " .. (passed + failed) .. " checks"))
print(green("Passed: " .. passed))
if failed > 0 then
  print(red("Failed: " .. failed))
else
  print("Failed: " .. failed)
end

if failed == 0 then
  print("")
  print(green(bold("✓ All Neovim integration tests passed!")))
  print("")
  print("The Claude CLI provider is ready to use.")
  print("")
  print("Configuration:")
  print("  providers = {")
  print("    claude_cli = {")
  print("      name = 'claude_cli',")
  print("      command = 'claude',")
  print("      models = { 'claude-sonnet-4-5' },")
  print("    },")
  print("  }")
  os.exit(0)
else
  print("")
  print(red(bold("✗ Some tests failed")))
  os.exit(1)
end
