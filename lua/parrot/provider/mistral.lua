local logger = require("parrot.logger")
local utils = require("parrot.utils")

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

-- https://docs.mistral.ai/api/#operation/createChatCompletion
local available_api_parameters = {
  -- required
  ["model"] = true,
  ["messages"] = true,
  -- optional
  ["temperature"] = true,
  ["top_p"] = true,
  ["max_tokens"] = true,
  ["stream"] = true,
  ["safe_prompt"] = true,
  ["random_seed"] = true,
}

function Mistral:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "mistral",
  }, self)
end

function Mistral:set_model(_) end

function Mistral:process_onexit(res)
  if res == nil then
    return
  end
  if type(res) == "table" then
    res = table.concat(res, " ")
  end
  if type(res) == "string" then
    local success, parsed = pcall(vim.json.decode, res)
    if success and parsed.message then
      logger.error("Mistral - message: " .. parsed.message)
      return
    end
  end
end

function Mistral:preprocess_payload(payload)
  for _, message in ipairs(payload.messages) do
    message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
  end
  return utils.filter_payload_parameters(available_api_parameters, payload)
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

function Mistral:add_system_prompt(messages, sys_prompt)
  if sys_prompt ~= "" then
    table.insert(messages, { role = "system", content = sys_prompt })
  end
  return messages
end

function Mistral:process_stdout(response)
  if response:match("chat%.completion%.chunk") or response:match("chat%.completion") then
		local success, content = pcall(vim.json.decode, response)
		if not success then
			logger.debug("Could not process response " .. response)
		end
    return content.choices[1].delta.content
  end
end

function Mistral:check(agent)
  local model = type(agent.model) == "string" and agent.model or agent.model.model
  return available_model_set[model]
end

return Mistral
