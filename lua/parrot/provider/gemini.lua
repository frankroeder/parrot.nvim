local logger = require("parrot.logger")

local Gemini = {}
Gemini.__index = Gemini

local available_model_set = {
  ["gemini-1.5-flash"] = true,
  ["gemini-1.5-pro"] = true,
}

function Gemini:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "gemini",
  }, self)
end

-- TODO: Is okey?
function Gemini:curl_params()
  return {
    self.endpoint .. self.model .. ":generateContent?key=" .. self.api_key,
    "-H",
    "-X",
    "POST",
  }
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

-- FIX: From here
function Gemini:preprocess_messages(messages)
  return messages
end

function Gemini:add_system_prompt(messages, _)
  return messages
end

function Gemini:process(line)
  if line:match("content_block_delta") and line:match("text_delta") then
    local decoded_line = vim.json.decode(line)
    if decoded_line.delta and decoded_line.delta.type == "text_delta" and decoded_line.delta.text then
      return decoded_line.delta.text
    end
  end
end

function Anthropic:check(agent)
  local model = type(agent.model) == "string" and agent.model or agent.model.model
  return available_model_set[model]
end

return Anthropic

