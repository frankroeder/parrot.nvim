local logger = require("parrot.logger")

local OpenAI = {}
OpenAI.__index = OpenAI

function OpenAI:new(endpoint, api_key)
  local o = { endpoint = endpoint, api_key = api_key, name = "openai" }
  setmetatable(o, self)
  self.__index = self
  return o
end

function OpenAI:curl_params()
  return {
    self.endpoint,
    "-H",
    "authorization: Bearer " .. self.api_key,
  }
end

function OpenAI:verify()
  if type(self.api_key) == "table" then
    logger.error("api_key is still an unresolved command: " .. vim.inspect(self.api_key))
    return false
  end

  if self.api_key and string.match(self.api_key, "%S") then
    return true
  end

  logger.error("Error with api key " .. self.name .. " " .. vim.inspect(self.api_key) .. " run :checkhealth parrot")
  return false
end

function OpenAI:preprocess_messages(messages)
  return messages
end

function OpenAI:add_system_prompt(messages, sys_prompt)
  if sys_prompt ~= "" then
    table.insert(messages, { role = "system", content = sys_prompt })
  end
  return messages
end

function OpenAI:process(line)
  if line:match("chat%.completion%.chunk") or line:match("chat%.completion") then
    line = vim.json.decode(line)
    return line.choices[1].delta.content
  end
end

function OpenAI:check(agent)
  local available_models = {
    "gpt-4-turbo-2024-04-09",
    "gpt-4-0613",
    "gpt-4-turbo",
    "gpt-4",
    "gpt-4-1106-vision-preview",
    "gpt-4-1106-preview",
    "gpt-3.5-turbo-16k",
    "gpt-3.5-turbo-0613",
    "gpt-3.5-turbo-0301",
    "gpt-3.5-turbo-instruct-0914",
    "gpt-3.5-turbo-instruct",
    "gpt-4-0125-preview",
    "gpt-3.5-turbo-16k-0613",
    "gpt-4-turbo-preview",
    "gpt-3.5-turbo-0125",
    "gpt-3.5-turbo-1106",
    "gpt-3.5-turbo",
  }
  local valid_model = false
  local model = ""
  -- if model is a string
  if type(agent.model) == "string" then
    model = agent.model
  else
    model = agent.model.model
  end

  for _, available_model in ipairs(available_models) do
    if model == available_model then
      valid_model = true
      break
    end
  end

  return valid_model
end

return OpenAI
