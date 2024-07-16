local logger = require("parrot.logger")
local utils = require("parrot.utils")

local Perplexity = {}
Perplexity.__index = Perplexity

local available_model_set = {
  ["llama-3-8b-instruct"] = true,
  ["llama-3-70b-instruct"] = true,
  ["mixtral-8x7b-instruct"] = true,
  ["llama-3-sonar-small-32k-chat"] = true,
  ["llama-3-sonar-small-32k-online"] = true,
  ["llama-3-sonar-large-32k-chat"] = true,
  ["llama-3-sonar-large-32k-online"] = true,
}

-- https://docs.perplexity.ai/reference/post_chat_completions
local available_api_parameters = {
  -- required
  ["messages"] = true,
  ["model"] = true,
  -- optional
  ["max_tokens"] = true,
  ["temperature"] = true,
  ["top_p"] = true,
  ["return_citations"] = true,
  ["top_k"] = true,
  ["stream"] = true,
  ["presence_penalty"] = true,
  ["frequency_penalty"] = true,
}

function Perplexity:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "pplx",
  }, self)
end

function Perplexity:set_model(_) end

function Perplexity:preprocess_payload(payload)
  -- strip whitespace from ends of content
  for _, message in ipairs(payload.messages) do
    message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
  end
  return utils.filter_payload_parameters(available_api_parameters, payload)
end

function Perplexity:curl_params()
  return {
    self.endpoint,
    "-H",
    "authorization: Bearer " .. self.api_key,
    "content-type: text/event-stream",
  }
end

function Perplexity:verify()
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

function Perplexity:add_system_prompt(messages, sys_prompt)
  if sys_prompt ~= "" then
    table.insert(messages, { role = "system", content = sys_prompt })
  end
  return messages
end

function Perplexity:process(response)
  if response:match("chat%.completion%.chunk") or response:match("chat%.completion") then
		local success, content = pcall(vim.json.decode, response)
		if not success then
			logger.debug("Could not process response " .. response)
		end
    return content.choices[1].delta.content
  end
end

function Perplexity:check(agent)
  local model = type(agent.model) == "string" and agent.model or agent.model.model
  return available_model_set[model]
end

return Perplexity
