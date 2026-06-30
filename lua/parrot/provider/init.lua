local MultiProvider = require("parrot.provider.multi_provider")
local AcpProvider = require("parrot.provider.acp_provider")
local logger = require("parrot.logger")

local M = {}

local function is_acp_config(config)
  return config.type == "acp" or (config.command and not config.endpoint)
end

local function validate_http_provider_config(config)
  local errors = {}

  if not config or type(config) ~= "table" then
    logger.critical("Provider configuration is missing or invalid", { provided_config = config })
    return false
  end

  if not config.name then
    table.insert(errors, "name: Required to identify the provider (e.g., 'openai', 'anthropic')")
  end

  if not config.endpoint then
    table.insert(errors, "endpoint: Required API endpoint URL (e.g., 'https://api.openai.com/v1/chat/completions')")
  end

  if not config.api_key then
    table.insert(errors, "api_key: required for authentication — should be your API key, command, or function")
  end

  if not config.model and not config.models then
    table.insert(errors, "model/models: Required to specify which model(s) to use (e.g., 'gpt-4' or a table of models)")
  end

  if #errors > 0 then
    local provider_name = config.name or "unnamed provider"
    logger.error(
      string.format(
        "Provider '%s' configuration validation failed:\n• %s",
        provider_name,
        table.concat(errors, "\n• ")
      ),
      {
        provided_config = config,
        missing_fields = errors,
        hint = "Check your provider configuration in your Neovim setup",
      }
    )
    return false
  end

  logger.debug("Provider configuration validated successfully", { provider = config.name })
  return true
end

local function validate_acp_provider_config(config)
  local errors = {}

  if not config.name then
    table.insert(errors, "name: Required to identify the provider (e.g., 'grok')")
  end

  local command = config.command or { "grok", "agent", "stdio" }
  if type(command) ~= "table" or #command == 0 then
    table.insert(errors, "command: Required ACP agent command (e.g., { 'grok', 'agent', 'stdio' })")
  end

  if not config.model and not config.models then
    table.insert(errors, "model/models: Required fallback model list for the ACP agent")
  end

  if #errors > 0 then
    logger.error(
      string.format(
        "ACP provider '%s' configuration validation failed:\n• %s",
        config.name or "unnamed provider",
        table.concat(errors, "\n• ")
      )
    )
    return false
  end

  if vim.fn.executable(command[1]) ~= 1 then
    logger.warning("ACP provider command not executable yet: " .. command[1])
  end

  return true
end

---@param config table # Provider configuration
---@return table # returns initialized provider
M.init_provider = function(config)
  if is_acp_config(config) then
    if not validate_acp_provider_config(config) then
      error("Invalid ACP provider configuration - check the error messages for details")
    end
    return AcpProvider:new(config)
  end

  if not validate_http_provider_config(config) then
    logger.critical("Cannot initialize provider due to configuration errors. Please fix the issues above.")
    error("Invalid provider configuration - check the error messages for details")
  end
  return MultiProvider:new(config)
end

return M
