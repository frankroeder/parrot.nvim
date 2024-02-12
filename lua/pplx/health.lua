local M = {}

function M.check()
	vim.health.start("pplx.nvim checks")

	local ok, pplx = pcall(require, "pplx")
	if not ok then
		vim.health.error("require('pplx') failed")
	else
		vim.health.ok("require('pplx') succeeded")

		if pplx._setup_called then
			vim.health.ok("require('pplx').setup() has been called")
		else
			vim.health.error("require('pplx').setup() has not been called")
		end

		for key, provider in ipairs(pplx.providers) do
			local api_key = provider.api_key
			if api_key or provider == "ollama" then
				vim.health.ok(key, "api_key is set")
			else
				vim.health.error(
					"require('pplx').setup({provider {.."
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
					"require('pplx').setup({provider {.."
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
