#!/usr/bin/env python3
"""
Example wrapper for Claude Code CLI integration with parrot.nvim

This script demonstrates how to create a CLI interface that works with
the ClaudeCliProvider. It reads from stdin, processes the input, and
writes to stdout with optional streaming.

Usage:
  echo "Your prompt here" | python claude_cli_wrapper.py [--stream]

To use with parrot.nvim:
  providers = {
    claude_cli = {
      name = "claude_cli",
      command = { "python", "/path/to/claude_cli_wrapper.py" },
      command_args = { "--stream" },
      models = { "claude-sonnet-4-5" },
    }
  }
"""

import sys
import time

def main():
  # Check for streaming flag
  streaming = "--stream" in sys.argv

  # Read input from stdin
  prompt = sys.stdin.read().strip()

  if not prompt:
    print("Error: No input provided", file=sys.stderr)
    sys.exit(1)

  # Here you would call the actual Claude Code CLI or API
  # For demonstration, we'll simulate a response

  # Example: Call claude-code if available
  # Uncomment and modify based on actual Claude Code CLI interface
  """
  import subprocess
  result = subprocess.run(
    ['claude', '--prompt', prompt],
    capture_output=True,
    text=True
  )
  response = result.stdout
  """

  # Simulated response for demonstration
  response = f"Claude response to: {prompt[:50]}..."

  if streaming:
    # Simulate streaming output
    for char in response:
      print(char, end='', flush=True)
      time.sleep(0.01)  # Small delay to simulate streaming
    print()  # Final newline
  else:
    # Non-streaming: output all at once
    print(response)

  sys.exit(0)

if __name__ == "__main__":
  main()
