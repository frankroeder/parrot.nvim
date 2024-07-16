local logger = require("parrot.logger")
local utils = require("parrot.utils")

local Anthropic = {}
Anthropic.__index = Anthropic

local available_model_set = {
  ["claude-3-5-sonnet-20240620"] = true,
  ["claude-3-opus-20240229"] = true,
  ["claude-3-sonnet-20240229"] = true,
  ["claude-3-haiku-20240307"] = true,
}

-- https://docs.anthropic.com/en/api/messages
local available_api_parameters = {
  -- required
  ["model"] = true,
  ["messages"] = true,
  -- optional
  ["max_tokens"] = true,
  ["metadata"] = true,
  ["stop_sequences"] = true,
  ["stream"] = true,
  ["system"] = true,
  ["temperature"] = true,
  ["tool_choice"] = true,
  ["tools"] = true,
  ["top_k"] = true,
  ["top_p"] = true,
}

function Anthropic:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "anthropic",
  }, self)
end

function Anthropic:set_model(_) end

function Anthropic:preprocess_payload(payload)
  for _, message in ipairs(payload.messages) do
    message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
  end
  if payload.messages[1].role == "system" then
    local system_prompt = payload.messages[1].content
    -- remove the first message that serves as the system prompt as anthropic
    -- expects the system prompt to be part of the curl request and not the messages
    table.remove(payload.messages, 1)
    payload.system = system_prompt
  end
  return utils.filter_payload_parameters(available_api_parameters, payload)
end

function Anthropic:curl_params()
  return {
    self.endpoint,
    "-H",
    "x-api-key: " .. self.api_key,
    "-H",
    "anthropic-version: 2023-06-01",
  }
end

function Anthropic:verify()
  if type(self.api_key) == "table" then
    logger.error("api_key is still an unresolved command: " .. vim.inspect(self.api_key))
    return false
  elseif self.api_key and string.match(self.api_key, "%S") then
    return true
  else
    logger.error("Error with api key " .. self.name .. " " .. vim.inspect(self.api_key) .. " run :checkhealth parrot")
    return false
  end
end

function Anthropic:process_stdout(response)
  if response:match("content_block_delta") and response:match("text_delta") then
    local success, decoded_line = pcall(vim.json.decode, response)
    if success and decoded_line.delta and decoded_line.delta.type == "text_delta" and decoded_line.delta.text then
      return decoded_line.delta.text
    end
  end
end

function Anthropic:process_onexit(res)
  local success, parsed = pcall(vim.json.decode, res)
  if success and parsed.error and parsed.error.message then
    logger.error("Anthropic - message:" .. parsed.error.message .. " type:" .. parsed.error.type)
    return
  end
end

function Anthropic:check(agent)
  local model = type(agent.model) == "string" and agent.model or agent.model.model
  return available_model_set[model]
end

return Anthropic
