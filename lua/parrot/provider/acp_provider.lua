local acp_client = require("parrot.acp.client")
local logger = require("parrot.logger")
local utils = require("parrot.utils")

---@class AcpProvider
---@field name string
---@field type string
---@field command string[]
---@field models string[]
---@field _model string|nil
---@field _config table
local AcpProvider = {}
AcpProvider.__index = AcpProvider

local defaults = {
  command = { "grok", "agent", "stdio" },
  cli_command = { "grok" },
  models = { "grok-4.6", "grok-build" },
  always_approve = false,
  show_thoughts = false,
  no_auto_update = false,
  headless = false,
  resume_session = true,
  model_flag = "-m",
  api_key = "acp",
  endpoint = "acp://local",
  model_endpoint = "acp://models",
}

---@param config table
---@return AcpProvider
function AcpProvider:new(config)
  local self = setmetatable({}, AcpProvider)

  assert(config.name, "ACP provider name is required")

  self.name = config.name
  self.type = "acp"
  self.command = config.command or defaults.command
  self.cli_command = config.cli_command or { self.command[1] }
  self.args = config.args or {}
  self.env = config.env
  self.cwd = config.cwd
  self.always_approve = config.always_approve == true
  self.show_thoughts = config.show_thoughts == true
  self.no_auto_update = config.no_auto_update == true
  self.headless = config.headless == true
  self.resume_session = config.resume_session ~= false
  self.auth_method = config.auth_method
  self.model_flag = config.model_flag or defaults.model_flag
  self.mcp_servers = config.mcp_servers or {}

  if config.model then
    self.models = type(config.model) == "string" and { config.model } or config.model
  else
    self.models = config.models or defaults.models
  end

  self.api_key = defaults.api_key
  self.endpoint = defaults.endpoint
  self.model_endpoint = config.model_endpoint or defaults.model_endpoint
  self._model = self.models[1]

  self._config = vim.tbl_extend("force", {}, config, {
    command = self.command,
    cli_command = self.cli_command,
    args = self.args,
    env = self.env,
    cwd = self.cwd,
    always_approve = self.always_approve,
    show_thoughts = self.show_thoughts,
    no_auto_update = self.no_auto_update,
    headless = self.headless,
    resume_session = self.resume_session,
    auth_method = self.auth_method,
    model_flag = self.model_flag,
    mcp_servers = self.mcp_servers,
    models = self.models,
    model = self._model,
  })

  return self
end

function AcpProvider:is_acp()
  return true
end

function AcpProvider:online_model_fetching()
  return true
end

function AcpProvider:set_model(model)
  self._model = model
  self._config.model = model
end

function AcpProvider:verify()
  local cmd = self.command[1]
  if vim.fn.executable(cmd) ~= 1 then
    logger.error("ACP provider command not found: " .. cmd)
    return false
  end
  return true
end

function AcpProvider:resolve_api_key()
  return true
end

function AcpProvider:preprocess_payload(payload)
  return payload
end

function AcpProvider:curl_params()
  return {}
end

function AcpProvider:process_stdout()
  return nil
end

function AcpProvider:process_onexit()
  return nil
end

function AcpProvider:get_runtime_config()
  return self._config
end

---@param callback? fun(models: string[])
---@return string[]
function AcpProvider:get_available_models(callback)
  local runtime = self._config._runtime_models
  if runtime and #runtime > 0 then
    if callback then
      callback(runtime)
    end
    return runtime
  end
  if callback then
    acp_client.fetch_models_from_cli(self.cli_command, function(mods)
      local res = (#mods > 0) and mods or self.models
      callback(res)
    end)
    return {}
  end
  local cli_models = acp_client.fetch_models_from_cli(self.cli_command)
  if #cli_models > 0 then
    return cli_models
  end
  return self.models
end

---@param state table
---@param cache_expiry_hours number
---@param spinner table|nil
---@param callback? fun(models: string[])
---@return string[]
function AcpProvider:get_available_models_cached(state, cache_expiry_hours, spinner, callback)
  local acp_ui = require("parrot.acp.ui")
  local endpoint_hash = utils.generate_endpoint_hash(self)

  local function refresh_slash_async(cb)
    vim.schedule(function()
      acp_ui.refresh_slash_commands_cache(state, self._config, self.name, cache_expiry_hours, cb or function() end)
    end)
  end

  acp_ui.preload_slash_cache_from_state(state, self._config, self.name, cache_expiry_hours)

  local cached_models = state:get_cached_models(self.name, cache_expiry_hours, endpoint_hash)
  if cached_models then
    refresh_slash_async(callback)
    if callback then
      callback(cached_models)
    end
    return cached_models
  end

  local function finish(fresh)
    if spinner then
      spinner:stop()
    end
    if not fresh or #fresh == 0 then
      fresh = self.models
    end
    if #fresh > 0 and not vim.deep_equal(fresh, self.models) then
      state:set_cached_models(self.name, fresh, endpoint_hash)
      state:save()
    end
    refresh_slash_async(callback)
    local out = fresh
    if callback then
      callback(out)
    end
    return out
  end

  -- Gate: in cb/async path use check_internet (no sync has/wait); sync has only for !cb on-demand.
  if callback then
    utils.check_internet(function(online)
      if not online then
        refresh_slash_async(callback)
        return finish(self.models)
      end
      if spinner then
        spinner:start("Fetching models for " .. self.name .. "...")
      end
      self:get_available_models(function(mods)
        finish(mods)
      end)
    end)
    return {}
  end
  if not utils.has_internet(1500) then
    refresh_slash_async(callback)
    return self.models
  end
  if spinner then
    spinner:start("Fetching models for " .. self.name .. "...")
  end
  local fresh_models = self:get_available_models()
  return finish(fresh_models)
end

---@param opts table
function AcpProvider:prompt(opts)
  acp_client.prompt(
    self._config,
    vim.tbl_extend("force", opts, {
      model = self._model,
      state = opts.state,
    })
  )
end

---@param qid string
function AcpProvider:cancel(qid)
  acp_client.cancel(self._config, self._model, qid)
end

function AcpProvider:terminate()
  acp_client.terminate_provider(self._config)
end

---@param model string|nil
function AcpProvider:terminate_connection(model)
  acp_client.terminate_connection(self._config, model or self._model)
end

return AcpProvider
