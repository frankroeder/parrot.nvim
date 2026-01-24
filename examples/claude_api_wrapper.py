#!/usr/bin/env python3
"""
Claude API CLI wrapper for parrot.nvim

This script provides a stdin/stdout interface to the Claude API,
suitable for use with parrot.nvim's ClaudeCliProvider.

Installation:
  pip install anthropic

Usage:
  export ANTHROPIC_API_KEY="your-api-key"
  echo "Your prompt" | python claude_api_wrapper.py [--stream] [--model MODEL]

Configuration in parrot.nvim:
  providers = {
    claude_cli = {
      name = "claude_cli",
      command = { "python", "/path/to/claude_api_wrapper.py" },
      command_args = { "--stream" },
      api_key = os.getenv("ANTHROPIC_API_KEY"),
      models = {
        "claude-sonnet-4-5",
        "claude-opus-4-5",
        "claude-haiku-4",
      },
    }
  }
"""

import sys
import os
import argparse

def main():
  parser = argparse.ArgumentParser(description='Claude API CLI wrapper')
  parser.add_argument('--stream', action='store_true', help='Enable streaming output')
  parser.add_argument('--model', default='claude-sonnet-4-5-20250929', help='Model to use')
  args = parser.parse_args()

  # Read prompt from stdin
  prompt = sys.stdin.read().strip()

  if not prompt:
    print("Error: No input provided", file=sys.stderr)
    sys.exit(1)

  # Get API key from environment
  api_key = os.getenv('ANTHROPIC_API_KEY')
  if not api_key:
    print("Error: ANTHROPIC_API_KEY environment variable not set", file=sys.stderr)
    sys.exit(1)

  try:
    from anthropic import Anthropic

    client = Anthropic(api_key=api_key)

    if args.stream:
      # Streaming response
      with client.messages.stream(
        model=args.model,
        max_tokens=4096,
        messages=[{"role": "user", "content": prompt}],
      ) as stream:
        for text in stream.text_stream:
          print(text, end='', flush=True)
        print()  # Final newline
    else:
      # Non-streaming response
      message = client.messages.create(
        model=args.model,
        max_tokens=4096,
        messages=[{"role": "user", "content": prompt}],
      )
      print(message.content[0].text)

  except ImportError:
    print("Error: anthropic package not installed. Run: pip install anthropic", file=sys.stderr)
    sys.exit(1)
  except Exception as e:
    print(f"Error: {str(e)}", file=sys.stderr)
    sys.exit(1)

if __name__ == "__main__":
  main()
