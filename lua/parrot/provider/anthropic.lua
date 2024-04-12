local logger = require("parrot.logger")

local Anthropic = {}
Anthropic.__index = Anthropic

function Anthropic:new(endpoint, api_key)
	local o = { endpoint = endpoint, api_key = api_key, name = "anthropic" }
	setmetatable(o, self)
	self.__index = self
	return o
end

function Anthropic:curl_params()
	return { self.endpoint, "-H", "x-api-key: " .. self.api_key, "-H", "anthropic-version: 2023-06-01" }
end

function Anthropic:verify()
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

function Anthropic:preprocess_messages(messages)
	table.remove(messages, 1)
	return messages
end

function Anthropic:add_system_prompt(messages, sys_prompt)
	return messages
end

function Anthropic:process(line)
	if line:match("content_block_delta") and line:match("text_delta") then
		line = vim.json.decode(line)
		if line.delta and line.delta.type == "text_delta" and line.delta.text then
			return line.delta.text
		end
	end
end

function Anthropic:check(agent)
	local available_models = {
		"claude-3-opus-20240229",
		"claude-3-sonnet-20240229",
		"claude-3-haiku-20240307",
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

return Anthropic
