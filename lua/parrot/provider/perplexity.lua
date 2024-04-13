local logger = require("parrot.logger")

local Perplexity = {}
Perplexity.__index = Perplexity

function Perplexity:new(endpoint, api_key)
  local o = { endpoint = endpoint, api_key = api_key, name = "pplx" }
  setmetatable(o, self)
  self.__index = self
  return o
end

function Perplexity:curl_params()
  return {
    self.endpoint,
    "-H",
    "authorization: Bearer " .. self.api_key,
  }
end

function Perplexity:verify()
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

function Perplexity:preprocess_messages(messages)
  return messages
end

function Perplexity:add_system_prompt(messages, sys_prompt)
  if sys_prompt ~= "" then
    table.insert(messages, { role = "system", content = sys_prompt })
  end
  return messages
end

function Perplexity:process(line)
  if line:match("chat%.completion%.chunk") or line:match("chat%.completion") then
    line = vim.json.decode(line)
    return line.choices[1].delta.content
  end
end

function Perplexity:check(agent)
  local available_models = {
    "sonar-small-chat",
    "sonar-small-online",
    "sonar-medium-chat",
    "sonar-medium-online",
    "codellama-70b-instruct",
    "mistral-7b-instruct",
    "mixtral-8x7b-instruct",
  }
  local valid_model = false
  local model = ""
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

return Perplexity
