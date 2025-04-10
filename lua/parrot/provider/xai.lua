local OpenAI = require("parrot.provider.openai")
local utils = require("parrot.utils")
local Job = require("plenary.job")

local xAI = setmetatable({}, { __index = OpenAI })
xAI.__index = xAI

-- Available API parameters for xAI
-- https://docs.x.ai/docs/api-reference
local AVAILABLE_API_PARAMETERS = {
  -- required
  messages = true,
  model = true,
  -- optional
  frequency_penalty = true,
  logit_bias = true,
  logprobs = true,
  max_tokens = true,
  n = true,
  presence_penalty = true,
  response_format = true,
  seed = true,
  stop = true,
  stream = true,
  stream_options = true,
  temperature = true,
  tool_choice = true,
  tools = true,
  top_logprobs = true,
  top_p = true,
  user = true,
}

function xAI:new(endpoint, api_key, models)
  local instance = OpenAI.new(self, endpoint, api_key, models)
  instance.name = "xai"
  return setmetatable(instance, self)
end

-- Preprocesses the payload before sending to the API
---@param payload table
---@return table
function xAI:preprocess_payload(payload)
  for _, message in ipairs(payload.messages) do
    message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
  end
  return utils.filter_payload_parameters(AVAILABLE_API_PARAMETERS, payload)
end

-- Returns the list of available models
---@param online boolean
---@return string[]
function xAI:get_available_models(online)
  if self.models then
    return self.models
  end
  local ids = {
    "grok-3-beta",
    "grok-3-fast-beta",
    "grok-3-mini-beta",
    "grok-3-mini-fast-beta",
    "grok-2-1212",
    "grok-beta",
  }
  if online and self:verify() then
    local job = Job:new({
      command = "curl",
      args = {
        "https://api.x.ai/v1/language-models",
        "-H",
        "Authorization: Bearer " .. self.api_key,
      },
      on_exit = function(job)
        local parsed_response = utils.parse_raw_response(job:result())
        self:process_onexit(parsed_response)
        ids = {}
        local success, decoded = pcall(vim.json.decode, parsed_response)
        if success and decoded.models then
          for _, item in ipairs(decoded.models) do
            table.insert(ids, item.id)
          end
        end
        return ids
      end,
    })
    job:start()
    job:wait()
  end
  return ids
end

return xAI
