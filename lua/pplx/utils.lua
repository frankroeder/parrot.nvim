local M = {}

---@param buf number # buffer number
---@return string # returns filetype of specified buffer
M.get_filetype = function(buf)
	return vim.api.nvim_buf_get_option(buf, "filetype")
end

---@param fn function # function to wrap so it only gets called once
M.once = function(fn)
	local once = false
	return function(...)
		if once then
			return
		end
		once = true
		fn(...)
	end
end

---@param keys string # string of keystrokes
---@param mode string # string of vim mode ('n', 'i', 'c', etc.), default is 'n'
M.feedkeys = function(keys, mode)
	mode = mode or "n"
	keys = vim.api.nvim_replace_termcodes(keys, true, false, true)
	vim.api.nvim_feedkeys(keys, mode, true)
end

---@param buffers table # table of buffers
---@param mode table | string # mode(s) to set keymap for
---@param key string # shortcut key
---@param callback function | string # callback or string to set keymap
---@param desc string | nil # optional description for keymap
M.set_keymap = function(buffers, mode, key, callback, desc)
	for _, buf in ipairs(buffers) do
		vim.keymap.set(mode, key, callback, {
			noremap = true,
			silent = true,
			nowait = true,
			buffer = buf,
			desc = desc,
		})
	end
end

---@param events string | table # events to listen to
---@param buffers table | nil # buffers to listen to (nil for all buffers)
---@param callback function # callback to call
---@param gid number # augroup id
M.autocmd = function(events, buffers, callback, gid)
	if buffers then
		for _, buf in ipairs(buffers) do
			vim.api.nvim_create_autocmd(events, {
				group = gid,
				buffer = buf,
				callback = vim.schedule_wrap(callback),
			})
		end
	else
		vim.api.nvim_create_autocmd(events, {
			group = gid,
			callback = vim.schedule_wrap(callback),
		})
	end
end

---@param file_name string # name of the file for which to delete buffers
M.delete_buffer = function(file_name)
	-- iterate over buffer list and close all buffers with the same name
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == file_name then
			vim.api.nvim_buf_delete(b, { force = true })
		end
	end
end

---@param file string | nil # name of the file to delete
M.delete_file = function(file)
	if file == nil then
		return
	end
	M.delete_buffer(file)
	os.remove(file)
end

---@return string # returns unique uuid
M.uuid = function()
	local random = math.random
	local template = "xxxxxxxx_xxxx_4xxx_yxxx_xxxxxxxxxxxx"
	local result = string.gsub(template, "[xy]", function(c)
		local v = (c == "x") and random(0, 0xf) or random(8, 0xb)
		return string.format("%x", v)
	end)
	return result
end

---@param name string # name of the augroup
---@param opts table | nil # options for the augroup
---@return number # returns augroup id
M.create_augroup = function(name, opts)
	return vim.api.nvim_create_augroup(name .. "_" .. M.uuid(), opts or { clear = true })
end

---@param buf number # buffer number
---@return number # returns the first line with content of specified buffer
M.last_content_line = function(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	-- go from end and return number of last nonwhitespace line
	local line = vim.api.nvim_buf_line_count(buf)
	while line > 0 do
		local content = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
		if content:match("%S") then
			return line
		end
		line = line - 1
	end
	return 0
end


-- returns rendered template with specified key replaced by value
M.template_replace = function(template, key, value)
	if template == nil then
		return nil
	end

	if value == nil then
		return template:gsub(key, "")
	end

	if type(value) == "table" then
		value = table.concat(value, "\n")
	end

	value = value:gsub("%%", "%%%%")
	template = template:gsub(key, value)
	template = template:gsub("%%%%", "%%")
	return template
end

---@param template string | nil # template string
---@param key_value_pairs table # table with key value pairs
---@return string | nil # returns rendered template with keys replaced by values from key_value_pairs
M.template_render = function(template, key_value_pairs)
	if template == nil then
		return nil
	end

	for key, value in pairs(key_value_pairs) do
		template = M.template_replace(template, key, value)
	end

	return template
end

---@param line number # line number
---@param buf number # buffer number
---@param win number | nil # window number
M.cursor_to_line = function(line, buf, win)
	-- don't manipulate cursor if user is elsewhere
	if buf ~= vim.api.nvim_get_current_buf() then
		return
	end

	-- check if win is valid
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end

	-- move cursor to the line
	vim.api.nvim_win_set_cursor(win, { line, 0 })
end

---@param str string # string to check
---@param start string # string to check for
M.starts_with = function(str, start)
	return str:sub(1, #start) == start
end

---@param str string # string to check
---@param ending string # string to check for
M.ends_with = function(str, ending)
	return ending == "" or str:sub(-#ending) == ending
end

return M
