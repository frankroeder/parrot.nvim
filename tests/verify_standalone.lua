#!/usr/bin/env lua
-- Standalone verification for Claude CLI integration
-- Tests command construction logic without requiring nvim modules

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
    print(yellow("  Fix: unset ANTHROPIC_API_KEY before starting Neovim"))
    print(yellow("  Or add to config: vim.env.ANTHROPIC_API_KEY = nil"))
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

section("Output Formatting")

-- Test that newlines are preserved
local function process_stdout(line)
  if line == nil then
    return nil
  end
  return line .. "\n"
end

local out1 = process_stdout("Hello")
if check(out1 == "Hello\n", "Newline added to non-empty line") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Expected 'Hello\\n', got '" .. (out1 or "nil") .. "'")
end

local out2 = process_stdout("")
if check(out2 == "\n", "Newline added to empty line (preserves blank lines)") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Expected '\\n', got '" .. (out2 or "nil") .. "'")
end

local out3 = process_stdout(nil)
if check(out3 == nil, "Nil line returns nil") then
  passed = passed + 1
else
  failed = failed + 1
end

-- Test multi-line output formatting
local multiline_output = {
  "## Header",
  "",
  "- Item 1",
  "- Item 2",
  "",
  "```lua",
  "code here",
  "```",
}

local formatted = {}
for _, line in ipairs(multiline_output) do
  local processed = process_stdout(line)
  if processed then
    table.insert(formatted, processed)
  end
end

local result = table.concat(formatted, "")
local expected = "## Header\n\n- Item 1\n- Item 2\n\n```lua\ncode here\n```\n"

if check(result == expected, "Multi-line output preserves formatting") then
  passed = passed + 1
  print("  Formatted output:")
  for _, line in ipairs(multiline_output) do
    print("    " .. line)
  end
else
  failed = failed + 1
  print("  Expected:")
  print(expected)
  print("  Got:")
  print(result)
end

section("Command Construction Logic")

-- Simulate curl_params function
local function build_args(payload, command, command_args)
  local args = {}

  -- If command is a table, use remaining elements as base args
  if type(command) == "table" then
    for i = 2, #command do
      if type(command[i]) == "string" then
        args[#args + 1] = command[i]
      end
    end
  end

  -- Add required flags for Claude CLI non-interactive mode
  args[#args + 1] = "-p"
  args[#args + 1] = "--output-format"
  args[#args + 1] = "text"

  -- Extract and add system prompt if present
  if payload and type(payload) == "table" and payload.messages then
    for _, message in ipairs(payload.messages) do
      if type(message) == "table" and message.role == "system" then
        if message.content and type(message.content) == "string" then
          local system_prompt = message.content:gsub("^%s*(.-)%s*$", "%1")
          if system_prompt ~= "" then
            args[#args + 1] = "--system-prompt"
            args[#args + 1] = system_prompt
          end
        end
        break
      end
    end
  end

  -- Add any additional command arguments
  if command_args and type(command_args) == "table" then
    for _, arg in ipairs(command_args) do
      if type(arg) == "string" then
        args[#args + 1] = arg
      end
    end
  end

  return args
end

-- Simulate preprocess_payload function
local function extract_user_message(payload)
  if not payload or type(payload) ~= "table" or not payload.messages then
    return ""
  end

  local user_prompt = ""
  for i = #payload.messages, 1, -1 do
    local message = payload.messages[i]
    if type(message) == "table" and message.role == "user" then
      if message.content and type(message.content) == "string" then
        user_prompt = message.content:gsub("^%s*(.-)%s*$", "%1")
      end
      break
    end
  end

  return user_prompt
end

-- Test 1: Basic payload
local payload1 = {
  messages = {
    { role = "user", content = "Hello" }
  }
}

local args1 = build_args(payload1, "claude", {})
if check(#args1 == 3, "Basic args: 3 arguments") then
  passed = passed + 1
  print("  " .. table.concat(args1, " "))
else
  failed = failed + 1
  print("  Expected 3, got " .. #args1)
end

if check(args1[1] == "-p" and args1[2] == "--output-format" and args1[3] == "text",
        "Basic args correct") then
  passed = passed + 1
else
  failed = failed + 1
end

local stdin1 = extract_user_message(payload1)
if check(stdin1 == "Hello", "Extract user message") then
  passed = passed + 1
else
  failed = failed + 1
end

-- Test 2: With system prompt
local payload2 = {
  messages = {
    { role = "system", content = "You are helpful" },
    { role = "user", content = "Hello" }
  }
}

local args2 = build_args(payload2, "claude", {})
if check(#args2 == 5, "With system prompt: 5 arguments") then
  passed = passed + 1
  print("  " .. table.concat(args2, " "))
else
  failed = failed + 1
  print("  Expected 5, got " .. #args2)
end

if check(args2[4] == "--system-prompt" and args2[5] == "You are helpful",
        "System prompt args correct") then
  passed = passed + 1
else
  failed = failed + 1
end

-- Test 3: Multi-turn conversation
local payload3 = {
  messages = {
    { role = "system", content = "You are helpful" },
    { role = "user", content = "First question" },
    { role = "assistant", content = "First answer" },
    { role = "user", content = "Second question" }
  }
}

local stdin3 = extract_user_message(payload3)
if check(stdin3 == "Second question", "Extract last user message (multi-turn)") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Expected 'Second question', got '" .. stdin3 .. "'")
end

-- Test 4: Command as table
local args4 = build_args(payload1, { "/usr/bin/claude", "--verbose" }, {})
if check(args4[1] == "--verbose", "Command as table: includes extra args") then
  passed = passed + 1
  print("  " .. table.concat(args4, " "))
else
  failed = failed + 1
end

-- Test 5: Additional command args
local args5 = build_args(payload1, "claude", { "--model", "opus" })
if check(args5[4] == "--model" and args5[5] == "opus", "Additional command args") then
  passed = passed + 1
  print("  " .. table.concat(args5, " "))
else
  failed = failed + 1
end

-- Test 6: Edge cases
local stdin_nil = extract_user_message(nil)
if check(stdin_nil == "", "Nil payload returns empty string") then
  passed = passed + 1
else
  failed = failed + 1
end

local stdin_empty = extract_user_message({ messages = {} })
if check(stdin_empty == "", "Empty messages returns empty string") then
  passed = passed + 1
else
  failed = failed + 1
end

local args_empty_system = build_args({
  messages = {
    { role = "system", content = "   " },
    { role = "user", content = "Hi" }
  }
}, "claude", {})
if check(#args_empty_system == 3, "Empty system prompt filtered out") then
  passed = passed + 1
else
  failed = failed + 1
  print("  Expected 3, got " .. #args_empty_system)
end

-- Real CLI test (if available and authenticated)
if has_claude and has_auth then
  section("Real CLI Execution Test")

  local test_payload = {
    messages = {
      { role = "user", content = "Say exactly 'test' and nothing else" }
    }
  }

  local test_args = build_args(test_payload, "claude", {})
  local test_stdin = extract_user_message(test_payload)

  -- Build command
  local cmd = "echo '" .. test_stdin:gsub("'", "'\\''") .. "' | claude "
  for _, arg in ipairs(test_args) do
    cmd = cmd .. "'" .. arg:gsub("'", "'\\''") .. "' "
  end
  cmd = cmd .. "2>&1"

  print("  Executing: " .. cmd)

  handle = io.popen(cmd)
  if handle then
    local result = handle:read("*a")
    local success = handle:close()

    if success then
      if check(true, "Command executed successfully") then
        passed = passed + 1
        local preview = result:sub(1, 100):gsub("\n", " ")
        print(green("  Output: " .. preview))

        -- Verify we got actual output
        if #result > 0 and not result:match("Credit balance") and not result:match("authentication") then
          if check(true, "Received valid output") then
            passed = passed + 1
          end
        else
          failed = failed + 1
          print(red("  Output appears to be an error message"))
        end
      end
    else
      failed = failed + 1
      print(red("  Command failed"))
      print("  Output: " .. result)
    end
  else
    failed = failed + 1
    print(red("  Failed to execute command"))
  end
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

print("")
if failed == 0 then
  print(green(bold("✓ All checks passed!")))
  print("")
  print("Next steps:")
  print("  1. Run full tests: nvim --headless -c 'luafile tests/verify_nvim.lua' -c 'quit'")
  print("  2. Try in Neovim: :PrtChatNew")
  os.exit(0)
else
  print(red(bold("✗ Some checks failed")))
  print("")
  if not has_claude then
    print("Install Claude CLI: pip install claude-code")
  end
  if has_claude and not has_auth then
    print("Fix authentication:")
    print("  1. Unset ANTHROPIC_API_KEY: unset ANTHROPIC_API_KEY")
    print("  2. Use subscription: claude setup-token")
  end
  os.exit(1)
end
