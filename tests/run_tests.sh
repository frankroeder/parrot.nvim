#!/bin/bash
# Test runner for Claude CLI provider tests

set -e

echo "=== Running Claude CLI Provider Tests ==="
echo ""

# Check if plenary is available
if [ ! -d "../plenary.nvim" ]; then
  echo "Error: plenary.nvim not found"
  echo "Please clone it: git clone https://github.com/nvim-lua/plenary.nvim ../plenary.nvim"
  exit 1
fi

# Check if Claude CLI is available
if command -v claude &> /dev/null; then
  echo "✓ Claude CLI found: $(command -v claude)"

  # Check authentication
  if echo "test" | claude -p --output-format text 2>&1 | grep -q "Credit balance is too low"; then
    echo "⚠ Warning: Claude CLI authentication issue (credit balance low)"
    echo "  Real CLI tests will be skipped"
  elif echo "test" | timeout 5 claude -p --output-format text &> /dev/null; then
    echo "✓ Claude CLI authenticated and working"
  else
    echo "⚠ Warning: Claude CLI may not be working properly"
    echo "  Real CLI tests will be skipped"
  fi
else
  echo "⚠ Claude CLI not found - real CLI tests will be skipped"
fi

echo ""
echo "=== Running Unit Tests ==="
echo ""

# Run tests with plenary
nvim --headless --noplugin -u tests/minimal_init.vim \
  -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.vim' }" \
  -c "quitall!"

echo ""
echo "=== Tests Complete ==="
