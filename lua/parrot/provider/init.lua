local MultiProvider = require("parrot.provider.multi_provider")
local logger = require("parrot.logger")

local M = {}

local function validate_provider_config(config)
  local errors = {}

  -- Check if config exists at all
  if not config or type(config) ~= "table" then
    logger.critical("Provider configuration is missing or invalid", { provided_config = config })
    return false
  end

  -- Validate required fields
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

  -- If there are validation errors, log them with context
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

---@param config table # Provider configuration
---@return table # returns initialized provider
M.init_provider = function(config)
  if not validate_provider_config(config) then
    logger.critical("Cannot initialize provider due to configuration errors. Please fix the issues above.")
    error("Invalid provider configuration - check the error messages for details")
  end
  return MultiProvider:new(config)
end

return M
