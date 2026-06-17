# Claude CLI Provider Examples

This directory contains example scripts demonstrating how to use CLI-based providers with parrot.nvim.

## Overview

The Claude CLI Provider allows you to integrate command-line tools with parrot.nvim instead of using HTTP APIs directly. This is useful for:

- Running local LLM tools
- Using custom wrapper scripts
- Integrating with tools that don't have HTTP APIs
- Testing and development

## Example Scripts

### 1. `claude_api_wrapper.py` - Full Claude API Integration

A production-ready wrapper that interfaces with the Claude API via the `anthropic` Python package.

**Installation:**
```bash
pip install anthropic
```

**Usage:**
```bash
export ANTHROPIC_API_KEY="your-api-key"
echo "Hello Claude" | python claude_api_wrapper.py --stream
```

**Parrot.nvim Configuration:**
```lua
require("parrot").setup {
  providers = {
    claude_cli = {
      name = "claude_cli",
      -- For actual Claude CLI (no API key needed)
      command = "claude",
      models = {
        "claude-sonnet-4-5",
        "claude-opus-4-5",
        "claude-haiku-4",
      },
    },
  },
}
```

### 2. `claude_cli_wrapper.py` - Simple Demo Wrapper

A minimal example showing the stdin/stdout interface pattern.

**Usage:**
```bash
echo "Test prompt" | python claude_cli_wrapper.py --stream
```

## How CLI Providers Work

CLI providers differ from HTTP providers in several ways:

1. **Command Execution**: Instead of making HTTP requests, they execute a subprocess
2. **Input**: Messages are formatted as plain text and sent via stdin
3. **Output**: Responses are read from stdout line-by-line
4. **Streaming**: Supported via flush on each output chunk

### Interface Contract

Your CLI script should:

1. Read input from stdin (formatted prompt text)
2. Process the input (call API, run model, etc.)
3. Write output to stdout
4. Support `--stream` flag for streaming output (optional)
5. Exit with code 0 on success

### Input Format

The CLI provider converts OpenAI-style messages to this format:

```
System: [system prompt if any]

User: [user message]```

### Output Format

For streaming (`--stream` flag):
- Write output character by character or line by line
- Flush stdout after each write
- The CLI provider reads each line via `on_stdout`

For non-streaming:
- Write complete response to stdout
- The CLI provider reads on `on_exit`

## Creating Your Own CLI Provider

To create a custom CLI wrapper:

1. **Create a script** that follows the interface contract
2. **Handle stdin/stdout** for communication
3. **Support streaming** if needed (via flush)
4. **Configure in parrot.nvim** using the `command` field

Example minimal wrapper:

```python
#!/usr/bin/env python3
import sys

# Read from stdin
prompt = sys.stdin.read().strip()

# Process (your logic here)
response = process_prompt(prompt)

# Write to stdout
print(response, flush=True)
```

## Testing

Test your CLI wrapper:

```bash
# Test stdin/stdout
echo "Hello" | python your_wrapper.py

# Test streaming
echo "Tell me a story" | python your_wrapper.py --stream

# Test with visual selection (simulated)
echo -e "User: Fix this code\n\nfunc() { return 1 }" | python your_wrapper.py --stream
```

## Troubleshooting

**Script not executing:**
- Check file permissions: `chmod +x your_script.py`
- Verify command path in config
- Check logs: `:PrtInfo` for provider details

**No output:**
- Ensure script writes to stdout, not stderr
- Check for proper flush on streaming output
- Verify exit code is 0

**API key issues:**
- Set environment variable before starting Neovim
- Or use command/function in api_key field

## Advanced: Chat History Support

The CLI provider automatically includes chat history when calling from a chat buffer. The input format includes previous messages:

```
System: You are a helpful assistant

User: What is Python?
Assistant: Python is a high-level programming language

User: Tell me more

[Previous conversation continues...]
```

Your wrapper should handle multi-turn conversations if needed, or simply respond to the full context as a single prompt.

## License

Same as parrot.nvim (MIT)

