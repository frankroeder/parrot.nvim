#!/usr/bin/env -S nvim -l
-- Integration verification script for Claude CLI provider
-- Run with: nvim -l tests/verify_integration.lua

package.path = package.path .. ";lua/?.lua"

local function green(text)
  return "\27[32m" .. text .. "\27[0m"
end

local function red(text)
  return "\27[31m" .. text .. "\27[0m"
end

local function yellow(text)
  return "\27[33m" .. text .. "\27[0m"
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

section("Environment Check")

-- Check if Claude CLI exists
local handle = io.popen("command -v claude 2>&1")
local claude_path = handle and handle:read("*a") or ""
if handle then handle:close() end
claude_path = claude_path:gsub("%s+$", "")

local has_claude = claude_path ~= ""
if check(has_claude, "Claude CLI installed") then
  passed = passed + 1
  print("  Path: " .. claude_path)
else
  failed = failed + 1
  print(yellow("  Install: pip install claude-code"))
end

-- Check authentication
local has_auth = false
if has_claude then
  handle = io.popen("echo 'test' | claude -p --output-format text 2>&1")
  local result = handle and handle:read("*a") or ""
  if handle then handle:close() end

  if result:match("Credit balance is too low") then
    print(red("✗") .. " Claude CLI authentication (using API key - needs credits)")
    print(yellow("  Fix: unset ANTHROPIC_API_KEY and use subscription auth"))
    failed = failed + 1
  elseif result:match("authentication") or result:match("unauthorized") then
    print(red("✗") .. " Claude CLI authentication")
    print(yellow("  Fix: run 'claude setup-token'"))
    failed = failed + 1
  else
    has_auth = true
    if check(true, "Claude CLI authenticated") then
      passed = passed + 1
    end
  end
end

section("Module Loading")

-- Load provider modules
local ok, ClaudeCliProvider = pcall(require, "parrot.provider.claude_cli")
if check(ok, "Load ClaudeCliProvider module") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Error: " .. tostring(ClaudeCliProvider))
end

local ok2, init_provider = pcall(require, "parrot.provider.init")
if check(ok2, "Load provider init module") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Error: " .. tostring(init_provider))
end

if not (ok and ok2) then
  print(red("\nCannot continue - module loading failed"))
  os.exit(1)
end

section("Provider Creation")

-- Test basic provider creation
local provider_ok, provider = pcall(ClaudeCliProvider.new, ClaudeCliProvider, {
  name = "test_cli",
  command = "claude",
  models = { "claude-sonnet-4-5" },
})

if check(provider_ok, "Create ClaudeCliProvider") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Error: " .. tostring(provider))
end

-- Test provider via init_provider
local init_ok, init_prov = pcall(init_provider.init_provider, {
  name = "test_cli",
  command = "claude",
  models = { "claude-sonnet-4-5" },
})

if check(init_ok, "Create provider via init_provider") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Error: " .. tostring(init_prov))
end

if not (provider_ok and init_ok) then
  print(red("\nCannot continue - provider creation failed"))
  os.exit(1)
end

section("Provider Interface")

if check(provider:get_command() == "claude", "get_command() returns 'claude'") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Got: " .. tostring(provider:get_command()))
end

if check(provider:uses_json_payload() == false, "uses_json_payload() returns false") then
  passed = passed + 1
else
  failed = failed + 1
end

if check(provider:resolve_api_key(nil) == true, "resolve_api_key() returns true") then
  passed = passed + 1
else
  failed = failed + 1
end

if check(provider:verify() == true, "verify() returns true") then
  passed = passed + 1
else
  failed = failed + 1
end

local models = provider:get_available_models()
if check(#models > 0, "get_available_models() returns models") then
  passed = passed + 1
  print("  Models: " .. table.concat(models, ", "))
else
  failed = failed + 1
end

section("Command Construction")

-- Test without system prompt
local payload1 = {
  messages = {
    { role = "user", content = "Hello" },
  },
}

local args1 = provider:curl_params(payload1)
if check(#args1 == 3, "Basic args count (no system prompt)") then
  passed = passed + 1
  print("  Args: " .. table.concat(args1, " "))
else
  failed = failed + 1
  print("  Expected 3, got " .. #args1)
end

if check(args1[1] == "-p", "First arg is -p") then
  passed = passed + 1
else
  failed = failed + 1
end

if check(args1[2] == "--output-format", "Second arg is --output-format") then
  passed = passed + 1
else
  failed = failed + 1
end

if check(args1[3] == "text", "Third arg is text") then
  passed = passed + 1
else
  failed = failed + 1
end

-- Test with system prompt
local payload2 = {
  messages = {
    { role = "system", content = "You are helpful" },
    { role = "user", content = "Hello" },
  },
}

local args2 = provider:curl_params(payload2)
if check(#args2 == 5, "Args count with system prompt") then
  passed = passed + 1
  print("  Args: " .. table.concat(args2, " "))
else
  failed = failed + 1
  print("  Expected 5, got " .. #args2)
end

if check(args2[4] == "--system-prompt", "System prompt flag present") then
  passed = passed + 1
else
  failed = failed + 1
end

if check(args2[5] == "You are helpful", "System prompt value correct") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Got: " .. tostring(args2[5]))
end

section("Payload Processing")

local stdin1 = provider:preprocess_payload(payload1)
if check(stdin1 == "Hello", "Extract user message") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Expected 'Hello', got '" .. stdin1 .. "'")
end

local stdin2 = provider:preprocess_payload(payload2)
if check(stdin2 == "Hello", "Extract user message (with system)") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Expected 'Hello', got '" .. stdin2 .. "'")
end

-- Test multi-turn
local payload3 = {
  messages = {
    { role = "system", content = "You are helpful" },
    { role = "user", content = "First" },
    { role = "assistant", content = "Response" },
    { role = "user", content = "Second" },
  },
}

local stdin3 = provider:preprocess_payload(payload3)
if check(stdin3 == "Second", "Extract last user message (multi-turn)") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Expected 'Second', got '" .. stdin3 .. "'")
end

section("Output Processing")

local out1 = provider:process_stdout("Hello world")
if check(out1 == "Hello world", "process_stdout returns line") then
  passed = passed + 1
else
  failed = failed + 1
end

local out2 = provider:process_stdout("")
if check(out2 == nil, "process_stdout returns nil for empty") then
  passed = passed + 1
else
  failed = failed + 1
end

local out3 = provider:process_onexit("Some content")
if check(out3 == nil, "process_onexit returns nil (no duplication)") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Got: " .. tostring(out3))
end

-- Real CLI test (if available and authenticated)
if has_claude and has_auth then
  section("Real CLI Execution")

  local test_payload = {
    messages = {
      { role = "user", content = "Say exactly 'OK' and nothing else" },
    },
  }

  local test_args = provider:curl_params(test_payload)
  local test_stdin = provider:preprocess_payload(test_payload)

  -- Build command
  local cmd = "echo '" .. test_stdin:gsub("'", "'\\''") .. "' | claude "
  for _, arg in ipairs(test_args) do
    cmd = cmd .. "'" .. arg:gsub("'", "'\\''") .. "' "
  end
  cmd = cmd .. "2>&1"

  print("  Command: " .. cmd)

  handle = io.popen(cmd)
  if handle then
    local result = handle:read("*a")
    local success = handle:close()

    if check(success == true or success == 0, "Command executed successfully") then
      passed = passed + 1
      print("  Output length: " .. #result .. " bytes")

      -- Check for common error patterns
      if result:match("Credit balance") then
        print(yellow("  Warning: Credit balance issue"))
      elseif result:match("authentication") then
        print(yellow("  Warning: Authentication issue"))
      else
        print(green("  Output: " .. result:sub(1, 100):gsub("\n", " ")))
      end
    else
      failed = failed + 1
      print("  Output: " .. result)
    end
  else
    failed = failed + 1
    print(red("  Failed to execute command"))
  end
else
  print("")
  print(yellow("Skipping real CLI tests (Claude not available or not authenticated)"))
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
  print(green(bold("✓ All checks passed!")))
  os.exit(0)
else
  print("")
  print(red(bold("✗ Some checks failed")))
  os.exit(1)
end
