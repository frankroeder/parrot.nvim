local logger = require("parrot.logger")

local Mistral = {}
Mistral.__index = Mistral

local available_model_set = {
  ["codestral-latest"] = true,
  ["mistral-tiny"] = true,
  ["mistral-small-latest"] = true,
  ["mistral-medium-latest"] = true,
  ["mistral-large-latest"] = true,
  ["open-mistral-7b"] = true,
  ["open-mixtral-8x7b"] = true,
  ["open-mixtral-8x22b"] = true,
}

function Mistral:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "mistral",
  }, self)
end

function Mistral:curl_params()
  return {
    self.endpoint,
    "-H",
    "authorization: Bearer " .. self.api_key,
  }
end

function Mistral:verify()
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

function Mistral:preprocess_messages(messages)
  return messages
end

function Mistral:add_system_prompt(messages, sys_prompt)
  if sys_prompt ~= "" then
    table.insert(messages, { role = "system", content = sys_prompt })
  end
  return messages
end

function Mistral:process(line)
  if line:match("chat%.completion%.chunk") or line:match("chat%.completion") then
    line = vim.json.decode(line)
    return line.choices[1].delta.content
  end
end

function Mistral:check(agent)
  local model = type(agent.model) == "string" and agent.model or agent.model.model
  return available_model_set[model]
end

return Mistral
