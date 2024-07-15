local logger = require("parrot.logger")
local utils = require("parrot.utils")

local Gemini = {}
Gemini.__index = Gemini

local available_model_set = {
  ["gemini-1.5-flash"] = true,
  ["gemini-1.5-pro"] = true,
}

-- https://ai.google.dev/gemini-api/docs/models/generative-models#model_parameters
local available_api_parameters = {
  ["contents"] = true,
  ["system_instruction"] = true,
  ["generationConfig"] = {
    ["stopSequences"] = true,
    ["temperature"] = true,
    ["maxOutputTokens"] = true,
    ["topP"] = true,
    ["topK"] = true,
  },
}

function Gemini:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "gemini",
    _model = nil,
  }, self)
end

function Gemini:set_model(model)
  local _model = type(model) == "string" and model or model.model
  self._model = _model
end

function Gemini:curl_params()
  return {
    self.endpoint .. self._model .. ":streamGenerateContent?alt=sse",
    "-H",
    "x-goog-api-key: " .. self.api_key,
    "-X",
    "POST",
  }
end

function Gemini:parse_result(res)
  if res == nil then
    return
  end
  if type(res) == "table" then
    res = table.concat(res, " ")
  end
  if type(res) == "string" then
    local success, parsed = pcall(vim.json.decode, res)
    if success and parsed.error and parsed.error.message then
      logger.error(
        "GEMINI - code: "
          .. parsed.error.code
          .. " message:"
          .. parsed.error.message
          .. " status:"
          .. parsed.error.status
      )
      return
    end
  end
end

function Gemini:preprocess_payload(payload)
  local new_messages = {}
  for _, message in ipairs(payload.messages) do
    -- restrive system prompt from messages and inject it into the payload
    -- remove this message
    if message.role == "system" then
      if message.parts and message.parts.text then
        payload.system_instruction = { parts = { text = message.parts.text:gsub("^%s*(.-)%s*$", "%1") } }
      elseif message.content then
        payload.system_instruction = { parts = { text = message.content:gsub("^%s*(.-)%s*$", "%1") } }
      end
    else
      local _role = ""
      if message.role == "assistant" then
        _role = "model"
      else
        _role = message.role
      end
      if message.content then
        table.insert(new_messages, { parts = { { text = message.content:gsub("^%s*(.-)%s*$", "%1") } }, role = _role })
      end
    end
  end
  payload.contents = vim.deepcopy(new_messages)
  return utils.filter_payload_parameters(available_api_parameters, payload)
end

function Gemini:verify()
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

function Gemini:add_system_prompt(messages, _)
  return messages
end

function Gemini:process(line)
  local pattern = '"text":'
  if line:match(pattern) then
    local content = vim.json.decode(line)
    if content.candidates then
      local candidate = content.candidates[1]
      if candidate and candidate.content and candidate.content.parts then
        local part = candidate.content.parts[1]
        if part and part.text then
          return part.text
        end
      end
    end
  end
end

function Gemini:check(agent)
  local model = type(agent.model) == "string" and agent.model or agent.model.model
  return available_model_set[model]
end

return Gemini
