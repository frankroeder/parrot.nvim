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

function Ollama:parse_result(res)
  if res == nil then
    return
  end
  if type(res) == "table" then
    res = table.concat(res, " ")
  end
  if type(res) == "string" then
    local success, parsed = pcall(vim.json.decode, res)
    if success and parsed.error then
      logger.error("Ollama - code: " .. parsed.error)
      return
    end
  end
end

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

function Ollama:add_system_prompt(messages, sys_prompt)
  if sys_prompt ~= "" then
    table.insert(messages, { role = "system", content = sys_prompt })
  end
  return messages
end

function Ollama:process(response)
  if response:match("message") and response:match("content") then
		local success, content = pcall(vim.json.decode, response)
		if not success then
			logger.debug("Could not process response " .. response)
		end
    if content.message and content.message.content then
      return content.message.content
    end
  end
end

function Ollama:check(agent)
  if not self.ollama_installed then
    logger.warning("ollama not found.")
    return false
  end
  local model = type(agent.model) == "string" and agent.model or agent.model.model

  local handle = io.popen("ollama list")
  local result = handle:read("*a")
  handle:close()

  local found_match = false
  for line in result:gmatch("[^\r\n]+") do
    if string.match(line, model) then
      found_match = true
      break
    end
  end

  if not found_match then
    if not pcall(require, "plenary") then
      logger.error("Plenary not installed. Please install nvim-lua/plenary.nvim to use this plugin.")
      return false
    end
    local confirm = vim.fn.confirm("ollama model " .. model .. " not found. Download now?", "&Yes\n&No", 1)
    if confirm == 1 then
      local job = Job:new({
        command = "ollama",
        args = { "pull", model },
        on_exit = function(_, return_val)
          logger.info("Download finished with exit code: " .. return_val)
        end,
        on_stderr = function(j, data)
          print("Downloading, please wait: " .. data)
          if j ~= nil then
            logger.error(vim.inspect(j:result()))
          end
        end,
      })
      job:start()
      return true
    end
  else
    return true
  end
  return false
end

return Ollama
