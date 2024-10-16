local logger = require("parrot.logger")
local utils = require("parrot.utils")
local Job = require("plenary.job")

---@class Nvidia
---@field endpoint string
---@field api_key string|table
---@field name string
local Nvidia = {}
Nvidia.__index = Nvidia

-- Available API parameters for Nvidia
local AVAILABLE_API_PARAMETERS = {
  -- required
  messages = true,
  model = true,
  -- optional
  temperature = true,
  top_p = true,
  stream = true,
  max_tokens = true,
  frequency_penalty = true,
  presence_penalty = true,
  seed = true,
  stop = true,
}

-- Creates a new Nvidia instance
---@param endpoint string
---@param api_key string|table
---@return Nvidia
function Nvidia:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "nvidia",
  }, self)
end

-- Placeholder for setting model (not implemented)
function Nvidia:set_model(_) end

-- Preprocesses the payload before sending to the API
---@param payload table
---@return table
function Nvidia:preprocess_payload(payload)
  for _, message in ipairs(payload.messages) do
    message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
  end
  return utils.filter_payload_parameters(AVAILABLE_API_PARAMETERS, payload)
end

-- Returns the curl parameters for the API request
---@return table
function Nvidia:curl_params()
  return {
    self.endpoint,
    "-H",
    "Authorization: Bearer " .. self.api_key,
  }
end

-- Verifies the API key or executes a routine to retrieve it
---@return boolean
function Nvidia:verify()
  if type(self.api_key) == "table" then
    local command = table.concat(self.api_key, " ")
    local handle = io.popen(command)
    if handle then
      self.api_key = handle:read("*a"):gsub("%s+", "")
      handle:close()
      return true
    else
      logger.error("Error verifying API key of " .. self.name)
      return false
    end
  elseif self.api_key and self.api_key:match("%S") then
    return true
  else
    logger.error("Error with API key " .. self.name .. " " .. vim.inspect(self.api_key))
    return false
  end
end

-- Processes the stdout from the API response
---@param response string
---@return string|nil
function Nvidia:process_stdout(response)
  if response:match("chat%.completion%.chunk") or response:match("chat%.completion") then
    local success, content = pcall(vim.json.decode, response)
    if
      success
      and content.choices
      and content.choices[1]
      and content.choices[1].delta
      and content.choices[1].delta.content
    then
      return content.choices[1].delta.content
    else
      logger.debug("Could not process response: " .. response)
    end
  end
end

-- Processes the onexit event from the API response
---@param res string
function Nvidia:process_onexit(res)
  local success, parsed = pcall(vim.json.decode, res)
  if success and parsed.data and parsed.data.detail then
    logger.error(
      string.format(
        "Nvidia - code: %s title %s message: %s type: %s",
        parsed.data.status,
        parsed.data.title,
        parsed.data.detail[1].msg,
        parsed.data.type
      )
    )
  end
end

-- Returns the list of available models
---@param online boolean Whether to fetch models online
---@return string[]
function Nvidia:get_available_models(online)
  if online and self:verify() then
    Job:new({
      command = "curl",
      args = {
        "https://integrate.api.nvidia.com/v1/models",
        "-H",
        "Authorization: Bearer " .. self.api_key,
      },
      on_exit = function(job)
        local parsed_response = utils.parse_raw_response(job:result())
        self:process_onexit(parsed_response)
        local ids = {}
        local success, decoded = pcall(vim.json.decode, parsed_response)
        if success and decoded.data then
          for _, item in ipairs(decoded.data) do
            table.insert(ids, item.id)
          end
        end
        return ids
      end,
    }):start()
  end
  return {
    "nvidia/llama-3.1-nemotron-70b-instruct",
    "01-ai/yi-large",
    "abacusai/dracarys-llama-3.1-70b-instruct",
    "adept/fuyu-8b",
    "ai21labs/jamba-1.5-large-instruct",
    "ai21labs/jamba-1.5-mini-instruct",
    "aisingapore/sea-lion-7b-instruct",
    "baai/bge-m3",
    "baichuan-inc/baichuan2-13b-chat",
    "bigcode/starcoder2-15b",
    "bigcode/starcoder2-7b",
    "databricks/dbrx-instruct",
    "deepseek-ai/deepseek-coder-6.7b-instruct",
    "google/codegemma-1.1-7b",
    "google/codegemma-7b",
    "google/deplot",
    "google/gemma-2-27b-it",
    "google/gemma-2-2b-it",
    "google/gemma-2-9b-it",
    "google/gemma-2b",
    "google/gemma-7b",
    "google/paligemma",
    "google/recurrentgemma-2b",
    "google/shieldgemma-9b",
    "ibm/granite-34b-code-instruct",
    "ibm/granite-8b-code-instruct",
    "institute-of-science-tokyo/llama-3.1-swallow-70b-instruct-v0.1",
    "institute-of-science-tokyo/llama-3.1-swallow-8b-instruct-v0.1",
    "mediatek/breeze-7b-instruct",
    "meta/codellama-70b",
    "meta/llama-3.1-405b-instruct",
    "meta/llama-3.1-405b-instruct-turbo",
    "meta/llama-3.1-70b-instruct",
    "meta/llama-3.1-70b-instruct-turbo",
    "meta/llama-3.1-8b-instruct",
    "meta/llama-3.1-8b-instruct-turbo",
    "meta/llama-3.2-1b-instruct",
    "meta/llama-3.2-3b-instruct",
    "meta/llama2-70b",
    "meta/llama3-70b-instruct",
    "meta/llama3-8b-instruct",
    "microsoft/kosmos-2",
    "microsoft/phi-3-medium-128k-instruct",
    "microsoft/phi-3-medium-4k-instruct",
    "microsoft/phi-3-mini-128k-instruct",
    "microsoft/phi-3-mini-4k-instruct",
    "microsoft/phi-3-small-128k-instruct",
    "microsoft/phi-3-small-8k-instruct",
    "microsoft/phi-3-vision-128k-instruct",
    "microsoft/phi-3.5-mini-instruct",
    "microsoft/phi-3.5-moe-instruct",
    "microsoft/phi-3.5-vision-instruct",
    "mistralai/codestral-22b-instruct-v0.1",
    "mistralai/mamba-codestral-7b-v0.1",
    "mistralai/mathstral-7b-v0.1",
    "mistralai/mistral-7b-instruct-v0.2",
    "mistralai/mistral-7b-instruct-v0.3",
    "mistralai/mistral-large",
    "mistralai/mistral-large-2-instruct",
    "mistralai/mixtral-8x22b-instruct-v0.1",
    "mistralai/mixtral-8x22b-v0.1",
    "mistralai/mixtral-8x7b-instruct-v0.1",
    "mistralai/mixtral-8x7b-instruct-v0.1-turbo",
    "nv-mistralai/mistral-nemo-12b-instruct",
    "nvidia/embed-qa-4",
    "nvidia/llama-3.1-nemotron-51b-instruct",
    "nvidia/llama-3.1-nemotron-70b-reward",
    "nvidia/llama3-chatqa-1.5-70b",
    "nvidia/llama3-chatqa-1.5-8b",
    "nvidia/mistral-nemo-minitron-8b-8k-instruct",
    "nvidia/mistral-nemo-minitron-8b-base",
    "nvidia/nemotron-4-340b-instruct",
    "nvidia/nemotron-4-340b-reward",
    "nvidia/nemotron-mini-4b-instruct",
    "nvidia/neva-22b",
    "nvidia/nv-embed-v1",
    "nvidia/nv-embedqa-e5-v5",
    "nvidia/nv-embedqa-mistral-7b-v2",
    "nvidia/nvclip",
    "nvidia/usdcode-llama3-70b-instruct",
    "nvidia/vila",
    "qwen/qwen2-7b-instruct",
    "rakuten/rakutenai-7b-chat",
    "rakuten/rakutenai-7b-instruct",
    "snowflake/arctic-embed-l",
    "thudm/chatglm3-6b",
    "tokyotech-llm/llama-3-swallow-70b-instruct-v0.1",
    "upstage/solar-10.7b-instruct",
    "writer/palmyra-fin-70b-32k",
    "writer/palmyra-med-70b",
    "writer/palmyra-med-70b-32k",
    "yentinglin/llama-3-taiwan-70b-instruct",
    "zyphra/zamba2-7b-instruct",
  }
end

return Nvidia
