local logger = require("parrot.logger")
local utils = require("parrot.utils")

local Mistral = {}
Mistral.__index = Mistral

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

function Mistral:process_stdout(response)
  if response:match("chat%.completion%.chunk") or response:match("chat%.completion") then
    local success, content = pcall(vim.json.decode, response)
    if success and content.choices then
      return content.choices[1].delta.content
    else
      logger.debug("Could not process response " .. response)
    end
  end
end

function Mistral:process_onexit(res)
  local success, parsed = pcall(vim.json.decode, res)
  if success and parsed.message then
    logger.error("Mistral - message: " .. parsed.message)
  end
end

function Mistral:get_available_models()
  return {
    "codestral-latest",
    "mistral-tiny",
    "mistral-small-latest",
    "mistral-medium-latest",
    "mistral-large-latest",
    "open-mistral-7b",
    "open-mixtral-8x7b",
    "open-mixtral-8x22b",
  }
end

return Mistral
