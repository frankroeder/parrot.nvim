local logger = require("parrot.logger")
local utils = require("parrot.utils")
local Job = require("plenary.job")

-- ClaudeCliProvider class - A provider that uses Claude Code CLI instead of HTTP API
-- This provider executes the Claude CLI tool as a subprocess and communicates via stdin/stdout
-- No API key required - Claude CLI uses local authentication
---@class ClaudeCliProvider
---@field command string|table The CLI command to execute (e.g., "claude")
---@field command_args table Additional arguments for the command
---@field models table Available models (static list for CLI)
---@field name string Provider name
local ClaudeCliProvider = {}
ClaudeCliProvider.__index = ClaudeCliProvider

-- Default implementations for CLI
local defaults = {
  -- Claude CLI expects input via stdin
  -- System prompt is handled via --system-prompt flag
  -- Extract the user's prompt (last user message)
  preprocess_payload = function(payload)
    local user_prompt = ""

    -- Safety check
    if not payload or type(payload) ~= "table" or not payload.messages then
      return ""
    end

    -- Find the last user message (the current prompt)
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
  end,

  -- Process streaming output from Claude CLI
  -- Parrot's streaming works via on_stdout callback processing each line
  -- With --output-format text, Claude outputs plain text line by line
  -- IMPORTANT: vim.split() removes newlines, we must add them back
  process_stdout = function(line)
    -- Return nil only for the very last empty line to avoid trailing newline
    -- But preserve empty lines in the middle (they represent blank lines in output)
    if line == nil then
      return nil
    end

    -- Add newline back (vim.split removes them)
    -- This preserves formatting like code blocks, lists, etc.
    return line .. "\n"
  end,

  -- Process final output (only called if there's leftover data on exit)
  process_onexit = function(response)
    -- For CLI providers, all output comes through on_stdout
    -- Don't process again on exit to avoid duplication
    return nil
  end,

  -- Resolve API key - Not needed for Claude CLI (uses local auth)
  -- But required for provider interface compatibility
  resolve_api_key = function(self, api_key)
    -- Claude CLI doesn't need API key - return true to pass verification
    return true
  end,
}

-- Creates a new ClaudeCliProvider instance
---@param config table
---@return ClaudeCliProvider
function ClaudeCliProvider:new(config)
  local self = setmetatable({}, ClaudeCliProvider)

  -- Basic configuration
  self.name = config.name or "claude_cli"
  self.command = config.command or "claude"
  self.command_args = config.command_args or {}

  -- Models for CLI (static list)
  if config.model then
    self.models = type(config.model) == "string" and { config.model } or config.model
  elseif config.models then
    self.models = config.models
  else
    -- Default models for Claude CLI
    self.models = { "claude-sonnet-4-5", "claude-opus-4-5", "claude-haiku-4" }
  end

  -- Function overrides (use defaults if not provided)
  self.preprocess_payload_func = config.preprocess_payload or defaults.preprocess_payload
  self.process_stdout_func = config.process_stdout or defaults.process_stdout
  self.process_onexit_func = config.process_onexit or defaults.process_onexit
  self.resolve_api_key_func = config.resolve_api_key or defaults.resolve_api_key

  return self
end

-- Returns the command to execute (instead of "curl")
---@return string|table
function ClaudeCliProvider:get_command()
  if type(self.command) == "table" then
    return self.command[1]
  end
  return self.command
end

-- Returns whether this provider uses JSON payload format (CLI uses plain text)
---@return boolean
function ClaudeCliProvider:uses_json_payload()
  return false
end

-- Returns the command arguments (replaces curl_params)
-- Streaming is handled automatically by parrot's on_stdout callback
---@param payload table|nil Optional payload to extract system prompt
---@return table
function ClaudeCliProvider:curl_params(payload)
  local args = {}

  -- If command is a table, use remaining elements as base args
  if type(self.command) == "table" then
    for i = 2, #self.command do
      if type(self.command[i]) == "string" then
        args[#args + 1] = self.command[i]
      end
    end
  end

  -- Add required flags for Claude CLI non-interactive mode
  args[#args + 1] = "-p"  -- Print mode (non-interactive)
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
  if self.command_args and type(self.command_args) == "table" then
    for _, arg in ipairs(self.command_args) do
      if type(arg) == "string" then
        args[#args + 1] = arg
      end
    end
  end

  return args
end

-- Verifies the CLI is available (no API key needed)
---@return boolean
function ClaudeCliProvider:verify()
  local cmd = self:get_command()

  -- Check if the command exists using command -v
  local check_cmd = "command -v " .. cmd .. " 2>&1"
  local handle = io.popen(check_cmd)
  local cmd_path = handle and handle:read("*a") or ""
  if handle then
    handle:close()
  end

  cmd_path = cmd_path:gsub("%s+$", "")

  if cmd_path ~= "" then
    logger.info("Claude CLI verified", {
      command = cmd,
      path = cmd_path
    })
    return true
  else
    logger.error("Claude CLI command not found in PATH", {
      command = cmd,
      hint = "Ensure 'claude' is installed and in PATH. Install via: pip install claude-code",
    })
    -- Still return true to allow user-specified paths
    return true
  end
end

-- Set the current model (interface compatibility)
function ClaudeCliProvider:set_model(model)
  self._model = model
end

-- Preprocesses the payload before sending to CLI
---@param payload table
---@return string
function ClaudeCliProvider:preprocess_payload(payload)
  return self.preprocess_payload_func(payload)
end

-- Processes stdout from CLI
---@param line string
---@return string|nil
function ClaudeCliProvider:process_stdout(line)
  return self.process_stdout_func(line)
end

-- Processes onexit event from CLI
---@param response string
---@return string|nil
function ClaudeCliProvider:process_onexit(response)
  return self.process_onexit_func(response)
end

-- Resolves API key (not needed for CLI, but required for interface)
---@param api_key string|table|function|nil
---@return boolean
function ClaudeCliProvider:resolve_api_key(api_key)
  -- Claude CLI uses local authentication, no API key needed
  return true
end

-- Returns available models (static for CLI)
---@return string[]
function ClaudeCliProvider:get_available_models()
  return self.models
end

-- Returns cached models (no caching for CLI, just return static)
---@param state table
---@param cache_expiry_hours number
---@param spinner table|nil
---@return string[]
function ClaudeCliProvider:get_available_models_cached(state, cache_expiry_hours, spinner)
  return self.models
end

-- Check if online model fetching is enabled (always false for CLI)
function ClaudeCliProvider:online_model_fetching()
  return false
end

return ClaudeCliProvider
