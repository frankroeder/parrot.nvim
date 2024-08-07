local logger = require("parrot.logger")
local utils = require("parrot.utils")

local OpenAI = {}
OpenAI.__index = OpenAI

local available_model_set = {
  ["gpt-3.5-turbo"] = true,
  ["gpt-3.5-turbo-0125"] = true,
  ["gpt-3.5-turbo-1106"] = true,
  ["gpt-3.5-turbo-16k"] = true,
  ["gpt-3.5-turbo-instruct"] = true,
  ["gpt-3.5-turbo-instruct-0914"] = true,
  ["gpt-4"] = true,
  ["gpt-4-0125-preview"] = true,
  ["gpt-4-0613"] = true,
  ["gpt-4-1106-preview"] = true,
  ["gpt-4-turbo"] = true,
  ["gpt-4-turbo-2024-04-09"] = true,
  ["gpt-4-turbo-preview"] = true,
  ["gpt-4o"] = true,
  ["gpt-4o-2024-05-13"] = true,
  ["gpt-4o-mini"] = true,
  ["gpt-4o-mini-2024-07-18"] = true,
}

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
  -- strip whitespace from ends of content
  for _, message in ipairs(payload.messages) do
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

function OpenAI:check(model)
  return available_model_set[model]
end

function OpenAI:get_available_models()
	-- curl https://api.openai.com/v1/models -H "Authorization: Bearer $OPENAI_API_KEY"
	local Job = require("plenary.job")
	self:verify()
	print("HERE")

	Job:new({
	  command = "curl",
	  args = {
	    "https://api.openai.com/v1/models",
	    "-H", "Authorization: Bearer " .. self.api_key,
	  },
	  on_exit = function(job)
	    print(vim.inspect(job:result()))
	  end,
	}):start()

--   { "{", '  "object": "list",', '  "data": [', "    {", '      "id": "dall-e-3",', '      "object": "model",', '      "created": 1698785189,', '      "owned_by": "system"', "    },", "
-- {", '      "id": "gpt-4-1106-preview",', '      "object": "model",', '      "created": 1698957206,', '      "owned_by": "system"', "    },", "    {", '      "id": "dall-e-2",', '      "o
-- bject": "model",', '      "created": 1698798177,', '      "owned_by": "system"', "    },", "    {", '      "id": "tts-1-hd-1106",', '      "object": "model",', '      "created": 16990535
-- 33,', '      "owned_by": "system"', "    },", "    {", '      "id": "tts-1-hd",', '      "object": "model",', '      "created": 1699046015,', '      "owned_by": "system"', "    },", "
--  {", '      "id": "text-embedding-3-large",', '      "object": "model",', '      "created": 1705953180,', '      "owned_by": "system"', "    },", "    {", '      "id": "gpt-4-0125-previe
-- w",', '      "object": "model",', '      "created": 1706037612,', '      "owned_by": "system"', "    },", "    {", '      "id": "babbage-002",', '      "object": "model",', '      "creat
-- ed": 1692634615,', '      "owned_by": "system"', "    },", "    {", '      "id": "gpt-4-turbo-preview",', '      "object": "model",', '      "created": 1706037777,', '      "owned_by": "
-- system"', "    },", "    {", '      "id": "gpt-4o",', '      "object": "model",', '      "created": 1715367049,', '      "owned_by": "system"', "    },", "    {", '      "id": "gpt-4o-20
-- 24-05-13",', '      "object": "model",', '      "created": 1715368132,', '      "owned_by": "system"', "    },", "    {", '      "id": "text-embedding-3-small",', '      "object": "model
-- ",', '      "created": 1705948997,', '      "owned_by": "system"', "    },", "    {", '      "id": "tts-1",', '      "object": "model",', '      "created": 1681940951,', '      "owned_by
-- ": "openai-internal"', "    },", "    {", '      "id": "gpt-3.5-turbo",', '      "object": "model",', '      "created": 1677610602,', '      "owned_by": "openai"', "    },", "    {", '
--     "id": "whisper-1",', '      "object": "model",', '      "created": 1677532384,', '      "owned_by": "openai-internal"', "    },", "    {", '      "id": "gpt-4o-2024-08-06",', '
-- "object": "model",', '      "created": 1722814719,', '      "owned_by": "system"', "    },", "    {", '      "id": "text-embedding-ada-002",', '      "object": "model",', '      "created
-- ": 1671217299,', '      "owned_by": "openai-internal"', "    },", "    {", '      "id": "gpt-3.5-turbo-16k",', '      "object": "model",', '      "created": 1683758102,', '      "owned_b
-- y": "openai-internal"', "    },", "    {", '      "id": "davinci-002",', '      "object": "model",', '      "created": 1692634301,', '      "owned_by": "system"', "    },", "    {", '
--    "id": "gpt-4-turbo-2024-04-09",', '      "object": "model",', '      "created": 1712601677,', '      "owned_by": "system"', "    },", "    {", '      "id": "tts-1-1106",', '      "obj
-- ect": "model",', '      "created": 1699053241,', '      "owned_by": "system"', "    },", "    {", '      "id": "gpt-3.5-turbo-0125",', '      "object": "model",', '      "created": 17060
-- 48358,', '      "owned_by": "system"', "    },", "    {", '      "id": "gpt-4-turbo",', '      "object": "model",', '      "created": 1712361441,', '      "owned_by": "system"', "    },"
-- , "    {", '      "id": "gpt-3.5-turbo-1106",', '      "object": "model",', '      "created": 1698959748,', '      "owned_by": "system"', "    },", "    {", '      "id": "gpt-3.5-turbo-i
-- nstruct-0914",', '      "object": "model",', '      "created": 1694122472,', '      "owned_by": "system"', "    },", "    {", '      "id": "gpt-3.5-turbo-instruct",', '      "object": "m
-- odel",', '      "created": 1692901427,', '      "owned_by": "system"', "    },", "    {", '      "id": "gpt-4o-mini-2024-07-18",', '      "object": "model",', '      "created": 172117271
-- 7,', '      "owned_by": "system"', "    },", "    {", '      "id": "gpt-4o-mini",', '      "object": "model",', '      "created": 1721172741,', '      "owned_by": "system"', "    },", "
--    {", '      "id": "gpt-4-0613",', '      "object": "model",', '      "created": 1686588896,', '      "owned_by": "openai"', "    },", "    {", '      "id": "gpt-4",', '      "object":
-- "model",', '      "created": 1687882411,', '      "owned_by": "openai"', "    }", "  ]", "}" }


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
