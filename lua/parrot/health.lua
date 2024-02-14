local M = {}

local check_provider = function(parrot, prov_key)
	local providers = parrot.providers

	if prov_key ~= "ollama" then
		local api_key = providers[prov_key].api_key
		if api_key then
			vim.health.ok(prov_key .. " api_key is set")
		else
			vim.health.error(
				"require('parrot').setup({provider {.."
					.. prov_key
					.. "..: {api_key: ???}}) is not set: "
					.. vim.inspect(api_key)
			)
		end
	end

	local endpoint = providers[prov_key].endpoint
	if endpoint and string.match(endpoint, "%S") then
		vim.health.ok(prov_key .. " endpoint is set")
	else
		vim.health.error(
			"require('parrot').setup({provider {.."
				.. prov_key
				.. "..: {endpoint: ???}}) is not set: "
				.. vim.inspect(endpoint)
		)
	end

	local topic_prompt = providers[prov_key].topic_prompt
	if topic_prompt and string.match(topic_prompt, "%S") then
		vim.health.ok(prov_key .. " topic_prompt is set")
	else
		vim.health.error(
			"require('parrot').setup({provider {.."
				.. prov_key
				.. "..: {topic_prompt: ???}}) is not set: "
				.. vim.inspect(topic_prompt)
		)
	end
end

function M.check()
	vim.health.start("parrot.nvim checks")

	local ok, parrot = pcall(require, "parrot")
	if not ok then
		vim.health.error("require('parrot') failed")
	else
		vim.health.ok("require('parrot') succeeded")

		if parrot._setup_called then
			vim.health.ok("require('parrot').setup() has been called")
		else
			vim.health.error("require('parrot').setup() has not been called")
		end
		check_provider(parrot, "openai")
		check_provider(parrot, "ollama")
		check_provider(parrot, "pplx")
	end

	if vim.fn.executable("curl") == 1 then
		vim.health.ok("curl is installed")
	else
		vim.health.error("curl is not installed")
	end

	if vim.fn.executable("grep") == 1 then
		vim.health.ok("grep is installed")
	else
		vim.health.error("grep is not installed")
	end

	if vim.fn.executable("ln") == 1 then
		vim.health.ok("ln is installed")
	else
		vim.health.error("ln is not installed")
	end
end

return M
