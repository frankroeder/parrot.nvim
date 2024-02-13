local M = {}

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

		for key, provider in ipairs(parrot.providers) do
			local api_key = provider.api_key
			if api_key or provider == "ollama" then
				vim.health.ok(key, "api_key is set")
			else
				vim.health.error(
					"require('parrot').setup({provider {.."
						.. key
						.. "..: {api_key: ???}}) is not set: "
						.. vim.inspect(api_key)
				)
			end

			local endpoint = provider.endpoint
			if endpoint and string.match(endpoint, "%S") then
				vim.health.ok("config.api_endpoint is set")
			else
				vim.health.error(
					"require('parrot').setup({provider {.."
						.. key
						.. "..: {endpoint: ???}}) is not set: "
						.. vim.inspect(api_key)
				)
			end
		end
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
