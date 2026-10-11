local acp_client = require("parrot.acp.client")
local logger = require("parrot.logger")
local MultiProvider = require("parrot.provider.multi_provider")

-- AcpProvider class - Talks to an agent over the Agent Client Protocol (e.g. `grok agent stdio`)
---@class AcpProvider
---@field name string
---@field type string
---@field command string[]
---@field cli_command string[]
---@field models string[]
---@field model_endpoint string
---@field _config table # Runtime config shared with parrot.acp.client
local AcpProvider = {}
AcpProvider.__index = AcpProvider

---@param config table
---@return AcpProvider
function AcpProvider:new(config)
  local command = config.command or { "grok", "agent", "stdio" }
  local cli_command = config.cli_command or { command[1] }
  local models = config.models or { "grok-4.7", "grok-4.6" }
  if config.model then
    models = type(config.model) == "string" and { config.model } or config.model
  end

  return setmetatable({
    name = config.name,
    type = "acp",
    command = command,
    cli_command = cli_command,
    models = models,
    -- configured models are part of the cache key: editing them triggers a refetch
    model_endpoint = "acp://models?" .. table.concat(models, ","),
    -- command_reasoning_effort = false keeps the agent's own default effort
    _config = vim.tbl_extend("force", { command_reasoning_effort = "low" }, config, {
      command = command,
      cli_command = cli_command,
      models = models,
      model = models[1],
    }),
  }, self)
end

function AcpProvider:online_model_fetching()
  return true
end

function AcpProvider:set_model(model)
  self._config.model = model
end

function AcpProvider:verify()
  if vim.fn.executable(self.command[1]) ~= 1 then
    logger.error("ACP provider command not found: " .. self.command[1])
    return false
  end
  return true
end

function AcpProvider:get_runtime_config()
  return self._config
end

-- The models of `grok models`; get_available_models_cached falls back to the configured ones.
-- (grok silently runs its default model for an id it does not list)
---@param callback? fun(models: string[])
---@return string[]
function AcpProvider:get_available_models(callback)
  return acp_client.fetch_models_from_cli(self.cli_command, callback)
end

AcpProvider.get_available_models_cached = MultiProvider.get_available_models_cached

---@param opts table
function AcpProvider:prompt(opts)
  acp_client.prompt(self._config, opts)
end

return AcpProvider
