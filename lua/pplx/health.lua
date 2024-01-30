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

		---@diagnostic disable-next-line: undefined-field
		local api_key = pplx.config.api_key

		if type(api_key) == "table" then
			vim.health.error(
				"require('pplx').setup({api_key: ???}) is still an unresolved command: " .. vim.inspect(api_key)
			)
		elseif api_key and string.match(api_key, "%S") then
			vim.health.ok("config.api_key is set")
		else
			vim.health.error("require('pplx').setup({api_key: ???}) is not set: " .. vim.inspect(api_key))
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

	if #pplx._deprecated > 0 then
		local msg = "deprecated config option(s) in setup():"
		for _, v in ipairs(pplx._deprecated) do
			msg = msg .. "\n\n- " .. v.msg
		end
		vim.health.warn(msg)
	else
		vim.health.ok("no deprecated config options")
	end
end

return M
