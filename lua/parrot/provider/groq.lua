local logger = require("parrot.logger")
local utils = require("parrot.utils")

local Groq = {}
Groq.__index = Groq

local available_model_set = {
  ["llama-3.1-405b-reasoning"] = true,
  ["llama-3.1-70b-versatile"] = true,
  ["llama-3.1-8b-instant"] = true,
  ["llama3-groq-70b-8192-tool-use-preview"] = true,
  ["llama3-groq-8b-8192-tool-use-preview"] = true,
  ["llama-guard-3-8b"] = true,
  ["llama3-70b-8192"] = true,
  ["llama3-8b-8192"] = true,
  ["mixtral-8x7b-32768"] = true,
  ["gemma-7b-it"] = true,
  ["gemma2-9b-it"] = true,
}

-- https://console.groq.com/docs/api-reference#chat-create
local available_api_parameters = {
  -- required
  ["model"] = true,
  ["messages"] = true,
  -- optional
  ["frequency_penalty"] = true,
  ["logit_bias"] = true,
  ["logprobs"] = true,
  ["max_tokens"] = true,
  ["n"] = true,
  ["parallel_tool_calls"] = true,
  ["presence_penalty"] = true,
  ["response_format"] = true,
  ["seed"] = true,
  ["stop"] = true,
  ["stream"] = true,
  ["stream_options"] = true,
  ["temperature"] = true,
  ["tool_choice"] = true,
  ["tools"] = true,
  ["top_logprobs"] = true,
  ["top_p"] = true,
  ["user"] = true,
}

function Groq:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "groq",
  }, self)
end

function Groq:set_model(_) end

function Groq:preprocess_payload(payload)
  for _, message in ipairs(payload.messages) do
    message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
  end
  return utils.filter_payload_parameters(available_api_parameters, payload)
end

function Groq:curl_params()
  return {
    self.endpoint,
    "-H",
    "Authorization: Bearer " .. self.api_key,
  }
end

function Groq:verify()
  if type(self.api_key) == "table" then
    local command = table.concat(self.api_key, " ")
    local handle = io.popen(command)
    if handle then
      self.api_key = handle:read("*a"):gsub("%s+", "")
    else
      logger.error("Error verifying api key of " .. self.name)
    end
    handle:close()
    return true
  elseif self.api_key and string.match(self.api_key, "%S") then
    return true
  else
    logger.error("Error with api key " .. self.name .. " " .. vim.inspect(self.api_key) .. " run :checkhealth parrot")
    return false
  end
end

function Groq:process_stdout(response)
  if response:match("chat%.completion%.chunk") or response:match("chat%.completion") then
    local success, content = pcall(vim.json.decode, response)
    if success and content.choices then
      return content.choices[1].delta.content
    else
      logger.debug("Could not process response " .. response)
    end
  end
end

function Groq:process_onexit(res)
  -- '{"error":{"message":"Invalid API Key","type":"invalid_request_error","code":"invalid_api_key"}}'
  local success, parsed = pcall(vim.json.decode, res)
  if success and parsed.error then
    logger.error("Groq - message: " .. parsed.error.message)
  end
end

function Groq:check(model)
  return available_model_set[model]
end

function Groq:get_available_models()
  return {
    "llama-3.1-405b-reasoning",
    "llama-3.1-70b-versatile",
    "llama-3.1-8b-instant",
    "llama3-groq-70b-8192-tool-use-preview",
    "llama3-groq-8b-8192-tool-use-preview",
    "llama-guard-3-8b",
    "llama3-70b-8192",
    "llama3-8b-8192",
    "mixtral-8x7b-32768",
    "gemma-7b-it",
    "gemma2-9b-it",
  }
end

return Groq
