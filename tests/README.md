# Claude CLI Provider Tests

Comprehensive test suite for the Claude CLI provider integration in parrot.nvim.

## Test Files

### 1. `verify_standalone.lua` - Standalone Logic Tests
Pure Lua tests that don't require Neovim or plenary. Tests command construction logic and can optionally test real CLI execution.

**Run:**
```bash
lua tests/verify_standalone.lua
```

**Tests:**
- Environment check (Claude CLI installed, authenticated)
- Command construction logic (args building)
- Payload processing (extracting user messages, system prompts)
- Edge cases (nil payloads, empty content, etc.)
- Optional: Real CLI execution (if Claude is available and authenticated)

**Output:**
```
=== Environment Check ===
✓ Claude CLI installed
  Path: /opt/homebrew/bin/claude
✓ Claude CLI authenticated

=== Command Construction Logic ===
✓ Basic args: 3 arguments
  -p --output-format text
✓ Basic args correct
✓ Extract user message
...
```

### 2. `verify_nvim.lua` - Neovim Integration Tests
Tests that run within Neovim and verify module loading, provider creation, and interface compliance.

**Run:**
```bash
nvim --headless -c 'luafile tests/verify_nvim.lua' -c 'quit'
```

**Tests:**
- Module loading (ClaudeCliProvider, init_provider)
- Provider creation and configuration
- Interface methods (get_command, uses_json_payload, etc.)
- Payload processing within Neovim
- Provider type detection
- Boolean logic verification (critical bug fix)

**Output:**
```
=== Neovim Module Loading Test ===
✓ Load ClaudeCliProvider
✓ Load init_provider

=== Provider Creation & Interface ===
✓ Create ClaudeCliProvider
✓ get_command()
...

=== Summary ===
Total: 19 checks
Passed: 19
Failed: 0
✓ All Neovim integration tests passed!
```

### 3. `claude_cli_spec.lua` - Plenary Unit Tests
Comprehensive unit tests using plenary.nvim's testing framework. Includes tests for real CLI execution (only if Claude is available).

**Run:**
```bash
# Requires plenary.nvim installed
./tests/run_tests.sh
```

**Tests:**
- Provider creation with various configs
- Interface method compliance
- curl_params generation
- Payload preprocessing
- Output processing
- Provider detection via init_provider
- Real CLI integration tests (conditional)

**Features:**
- Uses plenary's `describe`/`it` syntax
- Organized test suites
- Conditional real CLI tests (only run if `claude` exists and is authenticated)
- Pending tests clearly marked

### 4. `run_tests.sh` - Test Runner Script
Convenience script that checks environment and runs plenary tests.

**Run:**
```bash
chmod +x tests/run_tests.sh
./tests/run_tests.sh
```

**Features:**
- Checks for plenary.nvim
- Detects Claude CLI availability
- Checks authentication status
- Runs all plenary tests
- Provides clear output

## Prerequisites

### Minimal (Standalone Tests)
- Lua 5.1+ or LuaJIT
- Optional: Claude CLI (for real execution tests)

### Neovim Tests
- Neovim 0.10+
- Claude CLI provider files

### Full Test Suite
- Neovim 0.10+
- plenary.nvim
- Optional: Claude CLI (for integration tests)

## Running Tests

### Quick Verification (Recommended)
```bash
# 1. Standalone logic tests (no dependencies)
lua tests/verify_standalone.lua

# 2. Neovim integration tests
nvim --headless -c 'luafile tests/verify_nvim.lua' -c 'quit'
```

### Full Test Suite
```bash
# Requires plenary.nvim
./tests/run_tests.sh
```

### Individual Test Sections
```bash
# Only logic tests (no real CLI)
lua tests/verify_standalone.lua

# Only Neovim module tests
nvim --headless -c 'luafile tests/verify_nvim.lua' -c 'quit'

# Only plenary unit tests
nvim --headless -c "PlenaryBustedDirectory tests/"
```

## Test Coverage

### Unit Tests (Logic)
- ✓ Command construction with/without system prompts
- ✓ Payload preprocessing
- ✓ User message extraction
- ✓ Multi-turn conversation handling
- ✓ Edge cases (nil, empty, whitespace)
- ✓ Command as string vs table
- ✓ Additional command arguments

### Integration Tests (Neovim)
- ✓ Module loading
- ✓ Provider creation
- ✓ Interface compliance
- ✓ Provider type detection (CLI vs HTTP)
- ✓ Boolean logic correctness
- ✓ Output processing
- ✓ No duplication (onexit returns nil)

### Real CLI Tests (Conditional)
- ✓ Command execution
- ✓ System prompt handling
- ✓ Output capture
- ✓ Exit code verification

## Authentication Setup

For real CLI tests to pass, you need proper authentication:

**Using Subscription (Recommended):**
```bash
# 1. Unset API key
unset ANTHROPIC_API_KEY

# 2. Setup subscription token
claude setup-token

# 3. Run tests
lua tests/verify_standalone.lua
```

**In Neovim Config:**
```lua
-- Ensure API key is not set for CLI provider
vim.env.ANTHROPIC_API_KEY = nil

require("parrot").setup {
  providers = {
    claude_cli = {
      name = "claude_cli",
      command = "claude",
      models = { "claude-sonnet-4-5" },
    },
  },
}
```

## Troubleshooting

### Tests Skip Real CLI Execution
**Cause:** Claude CLI not found or not authenticated
**Fix:**
```bash
# Install Claude CLI
pip install claude-code

# Authenticate
claude setup-token

# Verify
echo "test" | claude -p --output-format text
```

### "Credit balance is too low" Error
**Cause:** Using API key instead of subscription
**Fix:**
```bash
# Before running tests/nvim
unset ANTHROPIC_API_KEY

# Or in Neovim config
vim.env.ANTHROPIC_API_KEY = nil
```

### Module Loading Errors
**Cause:** Running outside Neovim or missing plenary
**Fix:**
- Use `verify_standalone.lua` for pure Lua tests
- Use `verify_nvim.lua` within Neovim
- Use `run_tests.sh` with plenary installed

### Plenary Not Found
**Fix:**
```bash
cd /path/to/parrot.nvim/..
git clone https://github.com/nvim-lua/plenary.nvim
cd parrot.nvim
./tests/run_tests.sh
```

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Test Claude CLI Provider

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Install Neovim
        run: |
          wget https://github.com/neovim/neovim/releases/download/v0.10.0/nvim-linux64.tar.gz
          tar xzf nvim-linux64.tar.gz
          echo "$PWD/nvim-linux64/bin" >> $GITHUB_PATH

      - name: Install plenary
        run: git clone https://github.com/nvim-lua/plenary.nvim ../plenary.nvim

      - name: Run tests
        run: |
          # Run unit tests (don't require Claude CLI)
          nvim --headless -c 'luafile tests/verify_nvim.lua' -c 'quit'
```

## Test Output

### Success
```
=== Summary ===
Total: 19 checks
Passed: 19
Failed: 0
✓ All tests passed!
```

### Failure
```
=== Summary ===
Total: 19 checks
Passed: 17
Failed: 2
✗ Some tests failed
```

## Adding New Tests

### To `verify_standalone.lua`
```lua
-- Add to command construction section
local payload_new = {
  messages = {
    { role = "user", content = "New test case" }
  }
}

local args_new = build_args(payload_new, "claude", {})
if check(condition, "Test name") then
  passed = passed + 1
else
  failed = failed + 1
end
```

### To `claude_cli_spec.lua`
```lua
describe("New Test Suite", function()
  it("tests something", function()
    local result = some_function()
    assert.equals(expected, result)
  end)
end)
```

## Summary

- **Quick Check**: `lua tests/verify_standalone.lua`
- **Full Verification**: `nvim --headless -c 'luafile tests/verify_nvim.lua' -c 'quit'`
- **Complete Suite**: `./tests/run_tests.sh` (requires plenary)

All tests verify the critical components of the Claude CLI integration:
1. Command construction is correct
2. Payloads are processed properly
3. Output handling avoids duplication
4. Provider detection works
5. Boolean logic bug is fixed
