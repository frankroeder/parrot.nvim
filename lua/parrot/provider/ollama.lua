local logger = require("parrot.logger")
local Job = require("plenary.job")
local utils = require("parrot.utils")

-- https://github.com/ollama/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values
local available_api_parameters = {
  -- required
  ["model"] = true,
  ["messages"] = true,
  -- optional
  ["mirostat"] = true,
  ["mirostat_tau"] = true,
  ["mirostat_tau"] = true,
  ["num_ctx"] = true,
  ["repeat_last_n"] = true,
  ["repeat_penalty"] = true,
  ["temperature"] = true,
  ["seed"] = true,
  ["stop"] = true,
  ["tfs_z"] = true,
  ["num_predict"] = true,
  ["top_k"] = true,
  ["top_p"] = true,
  -- optional (advanced)
  ["format"] = true,
  ["system"] = true,
  ["stream"] = true,
  ["raw"] = true,
  ["keep_alive"] = true,
}

local Ollama = {}
Ollama.__index = Ollama

function Ollama:new(endpoint, api_key)
  return setmetatable({
    endpoint = endpoint,
    api_key = api_key,
    name = "ollama",
    ollama_installed = vim.fn.executable("ollama"),
  }, self)
end

function Ollama:set_model(_) end

function Ollama:preprocess_payload(payload)
  for _, message in ipairs(payload.messages) do
    message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
  end
  return utils.filter_payload_parameters(available_api_parameters, payload)
end

function Ollama:curl_params()
  return { self.endpoint }
end

function Ollama:verify()
  return true
end

function Ollama:process_stdout(response)
  if response:match("message") and response:match("content") then
    local success, content = pcall(vim.json.decode, response)
    if success and content.message and content.message.content then
      return content.message.content
    else
      logger.debug("Could not process response " .. response)
    end
  end
end

function Ollama:process_onexit(res)
  local success, parsed = pcall(vim.json.decode, res)
  if success and parsed.error then
    logger.error("Ollama - code: " .. parsed.error)
    return
  end
end

function Ollama:get_available_models()
  -- curl https://api.openai.com/v1/models -H "Authorization: Bearer $OPENAI_API_KEY"
  if vim.fn.executable("ollama") then
    local job = Job:new({
      command = "curl",
      args = { "-H", "Content-Type: application/json", "http://localhost:11434/api/tags" },
    }):sync()

    local parsed_response = utils.parse_raw_response(job)
    local success, parsed_data = pcall(vim.json.decode, parsed_response)
    if not success then
      logger.error("Error parsing JSON:" .. vim.inspect(parsed_data))
      return {}
    end
    local names = {}
    if parsed_data.models then
      for _, model in ipairs(parsed_data.models) do
        table.insert(names, model.name)
      end
    else
      logger.error("No models found. Please use 'ollama pull' to download one.")
      return {}
    end
    return names
  end
  return {}
end

return Ollama
