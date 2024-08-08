local logger = require("parrot.logger")
local utils = require("parrot.utils")
local Job = require("plenary.job")

local OpenAI = {}
OpenAI.__index = OpenAI

-- https://platform.openai.com/docs/api-reference/chat/create
local available_api_parameters = {
  -- required
  ["messages"] = true,
  ["model"] = true,
  -- optional
  ["frequency_penalty"] = true,
  ["logit_bias"] = true,
  ["logprobs"] = true,
  ["top_logprobs"] = true,
  ["max_tokens"] = true,
  ["presence_penalty"] = true,
  ["seed"] = true,
  ["stop"] = true,
  ["stream"] = true,
  ["temperature"] = true,
  ["top_p"] = true,
  ["tools"] = true,
  ["tool_choice"] = true,
}

function OpenAI:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "openai",
  }, self)
end

function OpenAI:set_model(_) end

function OpenAI:preprocess_payload(payload)
  for _, message in ipairs(payload.messages) do
    -- strip whitespace from ends of content
    message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
  end
  return utils.filter_payload_parameters(available_api_parameters, payload)
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

function OpenAI:process_stdout(response)
  if response:match("chat%.completion%.chunk") or response:match("chat%.completion") then
    local success, content = pcall(vim.json.decode, response)
    if success and content.choices then
      return content.choices[1].delta.content
    else
      logger.debug("Could not process response " .. response)
    end
  end
end

function OpenAI:process_onexit(res)
  local success, parsed = pcall(vim.json.decode, res)
  if success and parsed.error and parsed.error.message then
    logger.error(
      "OpenAI - code: " .. parsed.error.code .. " message:" .. parsed.error.message .. " type:" .. parsed.error.type
    )
  end
end

function OpenAI:get_available_models(online)
  -- curl https://api.openai.com/v1/models -H "Authorization: Bearer $OPENAI_API_KEY"
  if online and self:verify() then
    Job:new({
      command = "curl",
      args = {
        "https://api.openai.com/v1/models",
        "-H",
        "Authorization: Bearer " .. self.api_key,
      },
      on_exit = function(job)
        local parsed_response = utils.parse_raw_response(job:result())
        self:process_onexit(parsed_response)
        local ids = {}
        for _, item in ipairs(vim.json.decode(parsed_response).data) do
          table.insert(ids, item.id)
        end
        return ids
      end,
    }):start()
  end
  return {
    "gpt-3.5-turbo",
    "gpt-3.5-turbo-0125",
    "gpt-3.5-turbo-1106",
    "gpt-3.5-turbo-16k",
    "gpt-3.5-turbo-instruct",
    "gpt-3.5-turbo-instruct-0914",
    "gpt-4",
    "gpt-4-0125-preview",
    "gpt-4-0613",
    "gpt-4-1106-preview",
    "gpt-4-turbo",
    "gpt-4-turbo-2024-04-09",
    "gpt-4-turbo-preview",
    "gpt-4o",
    "gpt-4o-2024-05-13",
    "gpt-4o-mini",
    "gpt-4o-mini-2024-07-18",
  }
end

return OpenAI
