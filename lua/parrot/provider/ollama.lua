local logger = require("parrot.logger")
local Job = require("plenary.job")

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

function Ollama:curl_params()
  return { self.endpoint }
end

function Ollama:verify()
  return true
end

function Ollama:preprocess_messages(messages)
  return messages
end

function Ollama:add_system_prompt(messages, sys_prompt)
  if sys_prompt ~= "" then
    table.insert(messages, { role = "system", content = sys_prompt })
  end
  return messages
end

function Ollama:process(line)
  if line:match("message") and line:match("content") then
    line = vim.json.decode(line)
    if line.message and line.message.content then
      return line.message.content
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
