local config = require("parrot.config")
local utils = require("parrot.utils")
local ui = require("parrot.ui")

local _H = {}
local M = {
	_H = _H, -- helper functions
	_plugin_name = "parrot.nvim",
	_handles = {}, -- handles for running processes
	_queries = {}, -- table of latest queries
	_state = {}, -- table of state variables
	providers = {},
	agents = { -- table of agents
		chat = {},
		command = {},
	},
	cmd = {}, -- default command functions
	config = {}, -- config variables
	hooks = {}, -- user defined command functions
	logger = require("parrot.logger"),
}
M.logger._plugin_name = M._plugin_name

--------------------------------------------------------------------------------
-- Generic helper functions
--------------------------------------------------------------------------------

-- stop receiving gpt responses for all processes and clean the handles
---@param signal number | nil # signal to send to the process
M.cmd.Stop = function(signal)
	if M._handles == {} then
		return
	end

	for _, handle_info in ipairs(M._handles) do
		if handle_info.handle ~= nil and not handle_info.handle:is_closing() then
			vim.loop.kill(handle_info.pid, signal or 15)
		end
	end

	M._handles = {}
end

-- add a process handle and its corresponding pid to the _handles table
---@param handle userdata # the Lua uv handle
---@param pid number # the process id
---@param buf number | nil # buffer number
M.add_handle = function(handle, pid, buf)
	table.insert(M._handles, { handle = handle, pid = pid, buf = buf })
end

--- Check if there is no other pid running for the given buffer
---@param buf number | nil # buffer number
---@return boolean
M.can_handle = function(buf)
	if buf == nil then
		return true
	end
	for _, handle_info in ipairs(M._handles) do
		if handle_info.buf == buf then
			return false
		end
	end
	return true
end

-- remove a process handle from the _handles table using its pid
---@param pid number # the process id to find the corresponding handle
M.remove_handle = function(pid)
	for i, handle_info in ipairs(M._handles) do
		if handle_info.pid == pid then
			table.remove(M._handles, i)
			return
		end
	end
end

---@param buf number | nil # buffer number
---@param cmd string # command to execute
---@param args table # arguments for command
---@param callback function | nil # exit callback function(code, signal, stdout_data, stderr_data)
---@param out_reader function | nil # stdout reader function(err, data)
---@param err_reader function | nil # stderr reader function(err, data)
_H.process = function(buf, cmd, args, callback, out_reader, err_reader)
	local handle, pid
	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)
	local stdout_data = ""
	local stderr_data = ""

	if not M.can_handle(buf) then
		M.logger.warning("Another parrot process is already running for this buffer.")
		return
	end

	local on_exit = utils.once(vim.schedule_wrap(function(code, signal)
		stdout:read_stop()
		stderr:read_stop()
		stdout:close()
		stderr:close()
		if handle and not handle:is_closing() then
			handle:close()
		end
		if callback then
			callback(code, signal, stdout_data, stderr_data)
		end
		M.remove_handle(pid)
	end))

	handle, pid = vim.loop.spawn(cmd, {
		args = args,
		stdio = { nil, stdout, stderr },
		hide = true,
		detach = true,
	}, on_exit)

	M.add_handle(handle, pid, buf)

	vim.loop.read_start(stdout, function(err, data)
		if err then
			M.logger.error("Error reading stdout: " .. vim.inspect(err))
		end
		if data then
			stdout_data = stdout_data .. data
		end
		if out_reader then
			out_reader(err, data)
		end
	end)

	vim.loop.read_start(stderr, function(err, data)
		if err then
			M.logger.error("Error reading stderr: " .. vim.inspect(err))
		end
		if data then
			stderr_data = stderr_data .. data
		end
		if err_reader then
			err_reader(err, data)
		end
	end)
end

---@param buf number | nil # buffer number
---@param directory string # directory to search in
---@param pattern string # pattern to search for
---@param callback function # callback function(results, regex)
-- results: table of elements with file, lnum and line
-- regex: string - final regex used for search
_H.grep_directory = function(buf, directory, pattern, callback)
	pattern = pattern or ""
	-- replace spaces with wildcards
	pattern = pattern:gsub("%s+", ".*")
	-- strip leading and trailing non alphanumeric characters
	local re = pattern:gsub("^%W*(.-)%W*$", "%1")

	_H.process(buf, "grep", { "-irEn", "--null", pattern, directory }, function(c, _, stdout, _)
		local results = {}
		if c ~= 0 then
			callback(results, re)
			return
		end
		for _, line in ipairs(vim.split(stdout, "\n")) do
			line = line:gsub("^%s*(.-)%s*$", "%1")
			-- line contains non whitespace characters
			if line:match("%S") then
				-- extract file path (until zero byte)
				local file = line:match("^(.-)%z")
				-- substract dir from file
				local filename = vim.fn.fnamemodify(file, ":t")
				local line_number = line:match("%z(%d+):")
				local line_text = line:match("%z%d+:(.*)")
				table.insert(results, {
					file = filename,
					lnum = line_number,
					line = line_text,
				})
				-- extract line number
			end
		end
		table.sort(results, function(a, b)
			if a.file == b.file then
				return a.lnum < b.lnum
			else
				return a.file > b.file
			end
		end)
		callback(results, re)
	end)
end

--------------------------------------------------------------------------------
-- Module helper functions and variables
--------------------------------------------------------------------------------

---@param file_path string # the file path from where to read the json into a table
---@return table | nil # the table read from the file, or nil if an error occurred
M.file_to_table = function(file_path)
	local file, err = io.open(file_path, "r")
	if not file then
		M.logger.warning("Failed to open file for reading: " .. file_path .. "\nError: " .. err)
		return nil
	end
	local content = file:read("*a")
	file:close()

	if content == nil or content == "" then
		M.logger.warning("Failed to read any content from file: " .. file_path)
		return nil
	end

	local tbl = vim.json.decode(content)
	return tbl
end

---@param params table # table with command args
---@param origin_buf number # selection origin buffer
---@param target_buf number # selection target buffer
M.append_selection = function(params, origin_buf, target_buf)
	-- prepare selection
	local lines = vim.api.nvim_buf_get_lines(origin_buf, params.line1 - 1, params.line2, false)
	local selection = table.concat(lines, "\n")
	if selection ~= "" then
		local filetype = utils.get_filetype(origin_buf)
		local fname = vim.api.nvim_buf_get_name(origin_buf)
		local rendered = utils.template_render(M.config.template_selection, "", selection, filetype, fname)
		if rendered then
			selection = rendered
		end
	end

	-- delete whitespace lines at the end of the file
	local last_content_line = utils.last_content_line(target_buf)
	vim.api.nvim_buf_set_lines(target_buf, last_content_line, -1, false, {})

	-- insert selection lines
	lines = vim.split("\n" .. selection, "\n")
	vim.api.nvim_buf_set_lines(target_buf, last_content_line, -1, false, lines)
end

-- setup function
M._setup_called = false
---@param opts table | nil # table with options
M.setup = function(opts)
	M._setup_called = true

	math.randomseed(os.time())

	-- make sure opts is a table
	opts = opts or {}
	if type(opts) ~= "table" then
		M.logger.error(string.format("setup() expects table, but got %s:\n%s", type(opts), vim.inspect(opts)))
		opts = {}
	end

	-- reset M.config
	M.config = vim.deepcopy(config)

	-- merge nested tables
	local mergeTables = { "hooks", "agents", "providers" }
	local mergeAgentTables = { "chat", "command" }
	for _, tbl in ipairs(mergeTables) do
		M[tbl] = M[tbl] or {}
		---@diagnostic disable-next-line: param-type-mismatch
		for k, v in pairs(M.config[tbl]) do
			if tbl == "hooks" or tbl == "providers" then
				M[tbl][k] = v
			elseif tbl == "agents" then
				for _, _tbl in ipairs(mergeAgentTables) do
					for _, _v in pairs(M.config[tbl][_tbl]) do
						M[tbl][_tbl][_v.name] = _v
					end
				end
			end
		end
		M.config[tbl] = nil

		opts[tbl] = opts[tbl] or {}
		for k, v in pairs(opts[tbl]) do
			if tbl == "hooks" then
				M[tbl][k] = v
			elseif tbl == "providers" then
				M[tbl][k] = M[tbl][k] or {}
				for pk, pv in pairs(v) do
					M[tbl][k][pk] = pv
				end
				if next(v) == nil then
					M[tbl][k] = nil
				end
			elseif tbl == "agents" then
				for _, _tbl in ipairs(mergeAgentTables) do
					for _, _v in pairs(M.config[tbl][_tbl]) do
						M[tbl][_tbl][_v.name] = _v
					end
				end
			end
		end
		opts[tbl] = nil
	end

	for k, v in pairs(opts) do
		M.config[k] = v
	end

	-- make sure _dirs exists
	for k, v in pairs(M.config) do
		if k:match("_dir$") and type(v) == "string" then
			local dir = v:gsub("/$", "")
			M.config[k] = dir
			if vim.fn.isdirectory(dir) == 0 then
				vim.fn.mkdir(dir, "p")
			end
		end
	end

	-- remove invalid agents
	for name, agent in pairs(M.agents.chat) do
		if type(agent) ~= "table" or not agent.model or not agent.system_prompt or not agent.provider then
			M.agents.chat[name] = nil
		end
	end
	for name, agent in pairs(M.agents.command) do
		if type(agent) ~= "table" or not agent.model or not agent.system_prompt or not agent.provider then
			M.agents.command[name] = nil
		end
	end

	-- remove invalid providers
	for name, provider in pairs(M.providers) do
		if type(provider) ~= "table" or not provider.endpoint then
			M.providers[name] = nil
		end
	end

	-- prepare agent completions
	M._chat_agents = {}
	M._command_agents = {}
	M._available_providers = {}
	M._available_provider_agents = {}

	for name, _ in pairs(M.agents.command) do
		table.insert(M._command_agents, name)
	end

	for name, _ in pairs(M.agents.chat) do
		table.insert(M._chat_agents, name)
	end

	for name, _ in pairs(M.providers) do
		table.insert(M._available_providers, name)
		M._available_provider_agents[name] = { chat = {}, command = {} }
	end

	for agt_name, agt in pairs(M.agents.chat) do
		table.insert(M._available_provider_agents[agt.provider].chat, agt_name)
	end

	for agt_name, agt in pairs(M.agents.command) do
		table.insert(M._available_provider_agents[agt.provider].command, agt_name)
	end

	table.sort(M._chat_agents)
	table.sort(M._command_agents)
	table.sort(M._available_providers)
	table.sort(M._available_provider_agents)

	M.refresh_state()

	-- register user commands
	for hook, _ in pairs(M.hooks) do
		vim.api.nvim_create_user_command(M.config.cmd_prefix .. hook, function(params)
			M.call_hook(hook, params)
		end, { nargs = "?", range = true, desc = "GPT Prompt plugin" })
	end

	local completions = {
		ChatNew = { "popup", "split", "vsplit", "tabnew" },
		ChatToggle = { "popup", "split", "vsplit", "tabnew" },
		Context = { "popup", "split", "vsplit", "tabnew" },
	}

	-- register default commands
	for cmd, _ in pairs(M.cmd) do
		if M.hooks[cmd] == nil then
			vim.api.nvim_create_user_command(M.config.cmd_prefix .. cmd, function(params)
				M.cmd[cmd](params)
			end, {
				nargs = "?",
				range = true,
				desc = "GPT Prompt plugin",
				complete = function()
					if completions[cmd] then
						return completions[cmd]
					end

					if cmd == "Agent" then
						local buf = vim.api.nvim_get_current_buf()
						local file_name = vim.api.nvim_buf_get_name(buf)
						return M.get_provider_agents(utils.is_chat(buf, file_name, M.config.chat_dir))
					elseif cmd == "Provider" then
						return M._available_providers
					end
					return {}
				end,
			})
		end
	end

	M.buf_handler()

	if vim.fn.executable("curl") == 0 then
		M.logger.error("curl is not installed, run :checkhealth parrot")
	end

	for prov, val in pairs(M.providers) do
		if type(val.api_key) == "table" then
			local command = table.concat(val.api_key, " ")
			local handle = io.popen(command)
			if handle then
				M.providers[prov].api_key = handle:read("*a"):gsub("%s+", "")
			else
				M.providers[prov].api_key = nil
			end
			handle:close()
			M.valid_api_key(prov)
		end
	end
end

M.valid_api_key = function(current_provider)
	if current_provider == "ollama" then
		return true
	end
	local api_key = M.providers[current_provider].api_key

	if type(api_key) == "table" then
		M.logger.error("api_key is still an unresolved command: " .. vim.inspect(api_key))
		return false
	end

	if api_key and string.match(api_key, "%S") then
		return true
	end

	M.logger.error(
		"config.providers["
			.. current_provider
			.. "].api_key is not set: "
			.. vim.inspect(api_key)
			.. " run :checkhealth parrot"
	)
	return false
end

M.refresh_state = function()
	local state_file = M.config.state_dir .. "/state.json"
	local state = {}
	if vim.fn.filereadable(state_file) ~= 0 then
		state = M.file_to_table(state_file) or {}
	end

	if next(state) == nil then
		for _, prov in pairs(M._available_providers) do
			state[prov] = { chat_agent = nil, command_agent = nil }
		end
	end

	for _, prov in pairs(M._available_providers) do
		if not M._state[prov] then
			M._state[prov] = { chat_agent = nil, command_agent = nil }
		end

		if M._state[prov].chat_agent == nil then
			if state[prov].chat_agent == nil then
				M._state[prov].chat_agent = M._available_provider_agents[prov].chat[1]
			else
				M._state[prov].chat_agent = state[prov].chat_agent
			end
		end

		if M._state[prov].command_agent == nil then
			if state[prov].command_agent == nil then
				M._state[prov].command_agent = M._available_provider_agents[prov].command[1]
			else
				M._state[prov].command_agent = state[prov].command_agent
			end
		end
	end

	M._state.provider = M._state.provider or state.provider or nil
	if M._state.provider == nil then
		M._state.provider = M._available_providers[1]
	end

	utils.table_to_file(M._state, state_file)

	M.prepare_commands()
end

M.Target = {
	rewrite = 0, -- for replacing the selection, range or the current line
	append = 1, -- for appending after the selection, range or the current line
	prepend = 2, -- for prepending before the selection, range or the current line
	popup = 3, -- for writing into the popup window

	-- for writing into a new buffer
	---@param filetype nil | string # nil = same as the original buffer
	---@return table # a table with type=4 and filetype=filetype
	enew = function(filetype)
		return { type = 4, filetype = filetype }
	end,

	--- for creating a new horizontal split
	---@param filetype nil | string # nil = same as the original buffer
	---@return table # a table with type=5 and filetype=filetype
	new = function(filetype)
		return { type = 5, filetype = filetype }
	end,

	--- for creating a new vertical split
	---@param filetype nil | string # nil = same as the original buffer
	---@return table # a table with type=6 and filetype=filetype
	vnew = function(filetype)
		return { type = 6, filetype = filetype }
	end,

	--- for creating a new tab
	---@param filetype nil | string # nil = same as the original buffer
	---@return table # a table with type=7 and filetype=filetype
	tabnew = function(filetype)
		return { type = 7, filetype = filetype }
	end,
}

-- creates prompt commands for each target
M.prepare_commands = function()
	for name, target in pairs(M.Target) do
		-- uppercase first letter
		local command = name:gsub("^%l", string.upper)

		local agent = M.get_command_agent()
		-- popup is like ephemeral one off chat
		if target == M.Target.popup then
			agent = M.get_chat_agent()
		end

		local cmd = function(params)
			-- template is chosen dynamically based on mode in which the command is called
			local template = M.config.template_command
			if params.range == 2 then
				template = M.config.template_selection
				-- rewrite needs custom template
				if target == M.Target.rewrite then
					template = M.config.template_rewrite
				end
				if target == M.Target.append then
					template = M.config.template_append
				end
				if target == M.Target.prepend then
					template = M.config.template_prepend
				end
			end
			M.Prompt(params, target, agent.cmd_prefix, agent.model, template, agent.system_prompt, agent.provider)
		end

		M.cmd[command] = function(params)
			cmd(params)
		end
	end
end

-- hook caller
M.call_hook = function(name, params)
	if M.hooks[name] ~= nil then
		return M.hooks[name](M, params)
	end
	M.logger.error("The hook '" .. name .. "' does not exist.")
end

---@param N number # number of queries to keep
---@param age number # age of queries to keep in seconds
function M.cleanup_old_queries(N, age)
	local current_time = os.time()

	local query_count = 0
	for _ in pairs(M._queries) do
		query_count = query_count + 1
	end

	if query_count <= N then
		return
	end

	for qid, query_data in pairs(M._queries) do
		if current_time - query_data.timestamp > age then
			M._queries[qid] = nil
		end
	end
end

---@param qid string # query id
---@return table | nil # query data
function M.get_query(qid)
	if not M._queries[qid] then
		M.logger.error("Query with ID " .. tostring(qid) .. " not found.")
		return nil
	end
	return M._queries[qid]
end

-- gpt query
---@param buf number | nil # buffer number
---@param payload table # payload for api
---@param handler function # response handler
---@param on_exit function | nil # optional on_exit handler
M.query = function(buf, provider, payload, handler, on_exit)
	-- make sure handler is a function
	if type(handler) ~= "function" then
		M.logger.error(
			string.format("query() expects a handler function, but got %s:\n%s", type(handler), vim.inspect(handler))
		)
		return
	end

	if not M.valid_api_key(provider) then
		return
	end

	local qid = utils.uuid()
	M._queries[qid] = {
		timestamp = os.time(),
		buf = buf,
		provider = provider,
		payload = payload,
		handler = handler,
		on_exit = on_exit,
		raw_response = "",
		response = "",
		first_line = -1,
		last_line = -1,
		ns_id = nil,
		ex_id = nil,
	}

	M.cleanup_old_queries(8, 60)

	local out_reader = function()
		local buffer = ""

		---@param lines_chunk string
		local function process_lines(lines_chunk)
			local qt = M.get_query(qid)
			if not qt then
				return
			end

			local lines = vim.split(lines_chunk, "\n")
			for _, line in ipairs(lines) do
				if line ~= "" and line ~= nil then
					qt.raw_response = qt.raw_response .. line .. "\n"
				end
				line = line:gsub("^data: ", "")
				local content = ""

				if line:match("chat%.completion%.chunk") or line:match("chat%.completion") then
					line = vim.json.decode(line)
					content = line.choices[1].delta.content
				end

				if provider == "ollama" and line:match("message") and line:match("content") then
					line = vim.json.decode(line)
					if line.message and line.message.content then
						content = line.message.content
					end
				end

				if content ~= nil then
					qt.response = qt.response .. content
					handler(qid, content)
				end
			end
		end

		-- closure for vim.loop.read_start(stdout, fn)
		return function(err, chunk)
			local qt = M.get_query(qid)
			if not qt then
				return
			end

			if err then
				M.logger.error(qt.provider .. " API query stdout error: " .. vim.inspect(err))
			elseif chunk then
				-- add the incoming chunk to the buffer
				buffer = buffer .. chunk
				local last_newline_pos = buffer:find("\n[^\n]*$")
				if last_newline_pos then
					local complete_lines = buffer:sub(1, last_newline_pos - 1)
					-- save the rest of the buffer for the next chunk
					buffer = buffer:sub(last_newline_pos + 1)

					process_lines(complete_lines)
				end
			-- chunk is nil when EOF is reached
			else
				-- if there's remaining data in the buffer, process it
				if #buffer > 0 then
					process_lines(buffer)
				end

				if qt.response == "" then
					M.logger.error(
						qt.provider .. " API query response is empty in close: \n" .. vim.inspect(qt.raw_response)
					)
				end

				-- optional on_exit handler
				if type(on_exit) == "function" then
					on_exit(qid)
					if qt.ns_id and qt.buf then
						vim.schedule(function()
							vim.api.nvim_buf_clear_namespace(qt.buf, qt.ns_id, 0, -1)
						end)
					end
				end
			end
		end
	end

	local endpoint = M.providers[provider].endpoint
	local api_key = M.providers[provider].api_key
	local curl_params = vim.deepcopy(M.config.curl_params or {})
	local args = {
		"--no-buffer",
		"-s",
		endpoint,
		"-H",
		"accept: application/json",
		"-H",
		"content-type: application/json",
		"-d",
		vim.json.encode(payload),
	}
	if provider ~= "ollama" then
		table.insert(args, "-H")
		table.insert(args, "authorization: Bearer " .. api_key)
	end

	for _, arg in ipairs(args) do
		table.insert(curl_params, arg)
	end

	M._H.process(buf, "curl", curl_params, nil, out_reader(), nil)
end

-- response handler
---@param buf number | nil # buffer to insert response into
---@param win number | nil # window to insert response into
---@param line number | nil # line to insert response into
---@param first_undojoin boolean | nil # whether to skip first undojoin
---@param prefix string | nil # prefix to insert before each response line
---@param cursor boolean # whether to move cursor to the end of the response
M.create_handler = function(buf, win, line, first_undojoin, prefix, cursor)
	buf = buf or vim.api.nvim_get_current_buf()
	prefix = prefix or ""
	local first_line = line or vim.api.nvim_win_get_cursor(win)[1] - 1
	local finished_lines = 0
	local skip_first_undojoin = not first_undojoin

	local hl_handler_group = "PrtHandlerStandout"
	vim.cmd("highlight default link " .. hl_handler_group .. " CursorLine")

	local ns_id = vim.api.nvim_create_namespace("PrtHandler_" .. utils.uuid())

	local ex_id = vim.api.nvim_buf_set_extmark(buf, ns_id, first_line, 0, {
		strict = false,
		right_gravity = false,
	})

	local response = ""
	return vim.schedule_wrap(function(qid, chunk)
		local qt = M.get_query(qid)
		if not qt then
			return
		end
		-- if buf is not valid, stop
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		-- undojoin takes previous change into account, so skip it for the first chunk
		if skip_first_undojoin then
			skip_first_undojoin = false
		else
			utils.undojoin(buf)
		end

		if not qt.ns_id then
			qt.ns_id = ns_id
		end

		if not qt.ex_id then
			qt.ex_id = ex_id
		end

		first_line = vim.api.nvim_buf_get_extmark_by_id(buf, ns_id, ex_id, {})[1]

		-- clean previous response
		local line_count = #vim.split(response, "\n")
		vim.api.nvim_buf_set_lines(buf, first_line + finished_lines, first_line + line_count, false, {})

		-- append new response
		response = response .. chunk
		utils.undojoin(buf)

		-- prepend prefix to each line
		local lines = vim.split(response, "\n")
		for i, l in ipairs(lines) do
			lines[i] = prefix .. l
		end

		local unfinished_lines = {}
		for i = finished_lines + 1, #lines do
			table.insert(unfinished_lines, lines[i])
		end

		vim.api.nvim_buf_set_lines(
			buf,
			first_line + finished_lines,
			first_line + finished_lines,
			false,
			unfinished_lines
		)

		local new_finished_lines = math.max(0, #lines - 1)
		for i = finished_lines, new_finished_lines do
			vim.api.nvim_buf_add_highlight(buf, qt.ns_id, hl_handler_group, first_line + i, 0, -1)
		end
		finished_lines = new_finished_lines

		local end_line = first_line + #vim.split(response, "\n")
		qt.first_line = first_line
		qt.last_line = end_line - 1

		-- move cursor to the end of the response
		if cursor then
			utils.cursor_to_line(end_line, buf, win)
		end
	end)
end

--------------------
-- Chat logic
--------------------

M.chat_template = [[
# topic: ?

- file: %s
%s
Write your queries after %s. Use `%s` or :%sChatRespond to generate a response.
Response generation can be terminated by using `%s` or :%sChatStop command.
Chats are saved automatically. To delete this chat, use `%s` or :%sChatDelete.
Be cautious of very long chats. Start a fresh chat by using `%s` or :%sChatNew.

---

%s]]

M._toggle = {}

M._toggle_kind = {
	unknown = 0, -- unknown toggle
	chat = 1, -- chat toggle
	popup = 2, -- popup toggle
	context = 3, -- context toggle
}

---@param kind number # kind of toggle
---@return boolean # true if toggle was closed
M._toggle_close = function(kind)
	if
		M._toggle[kind]
		and M._toggle[kind].win
		and M._toggle[kind].buf
		and M._toggle[kind].close
		and vim.api.nvim_win_is_valid(M._toggle[kind].win)
		and vim.api.nvim_buf_is_valid(M._toggle[kind].buf)
		and vim.api.nvim_win_get_buf(M._toggle[kind].win) == M._toggle[kind].buf
	then
		if #vim.api.nvim_list_wins() == 1 then
			M.logger.warning("Can't close the last window.")
		else
			M._toggle[kind].close()
			M._toggle[kind] = nil
		end
		return true
	end
	M._toggle[kind] = nil
	return false
end

---@param kind number # kind of toggle
---@param toggle table # table containing `win`, `buf`, and `close` information
M._toggle_add = function(kind, toggle)
	M._toggle[kind] = toggle
end

---@param kind string # string representation of the toggle kind
---@return number # numeric kind of the toggle
M._toggle_resolve = function(kind)
	kind = kind:lower()
	if kind == "chat" then
		return M._toggle_kind.chat
	elseif kind == "popup" then
		return M._toggle_kind.popup
	elseif kind == "context" then
		return M._toggle_kind.context
	end
	M.logger.warning("Unknown toggle kind: " .. kind)
	return M._toggle_kind.unknown
end

---@param buf number | nil # buffer number
M.prep_md = function(buf)
	-- disable swapping for this buffer and set filetype to markdown
	vim.api.nvim_command("setlocal noswapfile")
	-- better text wrapping
	vim.api.nvim_command("setlocal wrap linebreak")
	-- auto save on TextChanged, InsertLeave
	vim.api.nvim_command("autocmd TextChanged,InsertLeave <buffer=" .. buf .. "> silent! write")

	-- register shortcuts local to this buffer
	buf = buf or vim.api.nvim_get_current_buf()

	-- ensure normal mode
	vim.api.nvim_command("stopinsert")
	utils.feedkeys("<esc>", "xn")
end

M.prep_chat = function(buf, file_name)
	if not utils.is_chat(buf, file_name, M.config.chat_dir) then
		return
	end

	if buf ~= vim.api.nvim_get_current_buf() then
		return
	end

	M.prep_md(buf)

	if M.config.chat_prompt_buf_type then
		vim.api.nvim_buf_set_option(buf, "buftype", "prompt")
		vim.fn.prompt_setprompt(buf, "")
		vim.fn.prompt_setcallback(buf, function()
			M.cmd.ChatRespond({ args = "" })
		end)
	end

	-- setup chat specific commands
	local range_commands = {
		{
			command = "ChatRespond",
			modes = M.config.chat_shortcut_respond.modes,
			shortcut = M.config.chat_shortcut_respond.shortcut,
			comment = "GPT prompt Chat Respond",
		},
		{
			command = "ChatNew",
			modes = M.config.chat_shortcut_new.modes,
			shortcut = M.config.chat_shortcut_new.shortcut,
			comment = "GPT prompt Chat New",
		},
	}
	for _, rc in ipairs(range_commands) do
		local cmd = M.config.cmd_prefix .. rc.command .. "<cr>"
		for _, mode in ipairs(rc.modes) do
			if mode == "n" or mode == "i" then
				utils.set_keymap({ buf }, mode, rc.shortcut, function()
					vim.api.nvim_command(M.config.cmd_prefix .. rc.command)
					-- go to normal mode
					vim.api.nvim_command("stopinsert")
					utils.feedkeys("<esc>", "xn")
				end, rc.comment)
			else
				utils.set_keymap({ buf }, mode, rc.shortcut, ":<C-u>'<,'>" .. cmd, rc.comment)
			end
		end
	end

	local ds = M.config.chat_shortcut_delete
	utils.set_keymap({ buf }, ds.modes, ds.shortcut, M.cmd.ChatDelete, "GPT prompt Chat Delete")

	local ss = M.config.chat_shortcut_stop
	utils.set_keymap({ buf }, ss.modes, ss.shortcut, M.cmd.Stop, "GPT prompt Chat Stop")

	-- conceal parameters in model header so it's not distracting
	if M.config.chat_conceal_model_params then
		vim.opt_local.conceallevel = 2
		vim.opt_local.concealcursor = ""
		vim.fn.matchadd("Conceal", [[^- model: .*model.:.[^"]*\zs".*\ze]], 10, -1, { conceal = "…" })
		vim.fn.matchadd("Conceal", [[^- model: \zs.*model.:.\ze.*]], 10, -1, { conceal = "…" })
		vim.fn.matchadd("Conceal", [[^- role: .\{64,64\}\zs.*\ze]], 10, -1, { conceal = "…" })
		vim.fn.matchadd("Conceal", [[^- role: .[^\\]*\zs\\.*\ze]], 10, -1, { conceal = "…" })
	end

	-- make last.md a symlink to the last opened chat file
	local last = M.config.chat_dir .. "/last.md"
	if file_name ~= last then
		os.execute("ln -sf " .. file_name .. " " .. last)
	end
end

M.prep_context = function(buf, file_name)
	if not utils.ends_with(file_name, ".parrot.md") then
		return
	end

	if buf ~= vim.api.nvim_get_current_buf() then
		return
	end

	M.prep_md(buf)
end

M.buf_handler = function()
	local gid = utils.create_augroup("PrtBufHandler", { clear = true })

	utils.autocmd({ "BufEnter" }, nil, function(event)
		local buf = event.buf

		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		local file_name = vim.api.nvim_buf_get_name(buf)

		M.prep_chat(buf, file_name)
		M.prep_context(buf, file_name)
	end, gid)
end

M.BufTarget = {
	current = 0, -- current window
	popup = 1, -- popup window
	split = 2, -- split window
	vsplit = 3, -- vsplit window
	tabnew = 4, -- new tab
}

---@param params table | string # table with args or string args
---@return number # buf target
M.resolve_buf_target = function(params)
	local args = ""
	if type(params) == "table" then
		args = params.args or ""
	else
		args = params
	end

	if args == "popup" then
		return M.BufTarget.popup
	elseif args == "split" then
		return M.BufTarget.split
	elseif args == "vsplit" then
		return M.BufTarget.vsplit
	elseif args == "tabnew" then
		return M.BufTarget.tabnew
	else
		return M.BufTarget.current
	end
end

---@param file_name string
---@param target number | nil # buf target
---@param kind number # nil or a toggle kind
---@param toggle boolean # whether to toggle
---@return number # buffer number
M.open_buf = function(file_name, target, kind, toggle)
	target = target or M.BufTarget.current

	-- close previous popup if it exists
	M._toggle_close(M._toggle_kind.popup)

	if toggle then
		M._toggle_close(kind)
	end

	local close, buf, win

	if target == M.BufTarget.popup then
		local old_buf = utils.get_buffer(file_name)

		buf, win, close, _ = ui.create_popup(
			old_buf,
			M._plugin_name .. " Popup",
			function(w, h)
				local top = M.config.style_popup_margin_top or 2
				local bottom = M.config.style_popup_margin_bottom or 8
				local left = M.config.style_popup_margin_left or 1
				local right = M.config.style_popup_margin_right or 1
				local max_width = M.config.style_popup_max_width or 160
				local ww = math.min(w - (left + right), max_width)
				local wh = h - (top + bottom)
				return ww, wh, top, (w - ww) / 2
			end,
			{ on_leave = false, escape = false, persist = true, keep_buf = true },
			{ border = M.config.style_popup_border or "single" }
		)

		if not toggle then
			M._toggle_add(M._toggle_kind.popup, { win = win, buf = buf, close = close })
		end

		if old_buf == nil then
			-- read file into buffer and force write it
			vim.api.nvim_command("silent 0read " .. file_name)
			vim.api.nvim_command("silent file " .. file_name)
		else
			-- move cursor to the beginning of the file and scroll to the end
			utils.feedkeys("ggG", "xn")
		end

		-- delete whitespace lines at the end of the file
		local last_content_line = utils.last_content_line(buf)
		vim.api.nvim_buf_set_lines(buf, last_content_line, -1, false, {})
		-- insert a new line at the end of the file
		vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
		vim.api.nvim_command("silent write! " .. file_name)
	elseif target == M.BufTarget.split then
		vim.api.nvim_command("split " .. file_name)
	elseif target == M.BufTarget.vsplit then
		vim.api.nvim_command("vsplit " .. file_name)
	elseif target == M.BufTarget.tabnew then
		vim.api.nvim_command("tabnew " .. file_name)
	else
		-- is it already open in a buffer?
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_get_name(b) == file_name then
				for _, w in ipairs(vim.api.nvim_list_wins()) do
					if vim.api.nvim_win_get_buf(w) == b then
						vim.api.nvim_set_current_win(w)
						return b
					end
				end
			end
		end

		-- open in new buffer
		vim.api.nvim_command("edit " .. file_name)
	end

	buf = vim.api.nvim_get_current_buf()
	win = vim.api.nvim_get_current_win()
	close = close or function() end

	if not toggle then
		return buf
	end

	if target == M.BufTarget.split or target == M.BufTarget.vsplit then
		close = function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end
	end

	if target == M.BufTarget.tabnew then
		close = function()
			if vim.api.nvim_win_is_valid(win) then
				local tab = vim.api.nvim_win_get_tabpage(win)
				vim.api.nvim_set_current_tabpage(tab)
				vim.api.nvim_command("tabclose")
			end
		end
	end

	M._toggle_add(kind, { win = win, buf = buf, close = close })

	return buf
end

---@param params table # table with args
---@param model string | table | nil # model to use
---@param system_prompt string | nil # system prompt to use
---@param toggle boolean # whether chat is toggled
---@return number # buffer number
M.new_chat = function(params, model, system_prompt, toggle)
	M._toggle_close(M._toggle_kind.popup)

	-- prepare filename
	local time = os.date("%Y-%m-%d.%H-%M-%S")
	local stamp = tostring(math.floor(vim.loop.hrtime() / 1000000) % 1000)
	-- make sure stamp is 3 digits
	while #stamp < 3 do
		stamp = "0" .. stamp
	end
	time = time .. "." .. stamp
	local filename = M.config.chat_dir .. "/" .. time .. ".md"

	-- local chat_agent = M.get_chat_agent()
	--
	-- if system_prompt == nil then
	--   system_prompt = chat_agent.system_prompt
	-- end
	--
	-- if model == nil then
	--   model = chat_agent.model
	-- end

	-- encode as json if model is a table
	if model and type(model) == "table" then
		model = "- model: " .. vim.json.encode(model) .. "\n"
	elseif model then
		model = "- model: " .. model .. "\n"
	else
		model = ""
	end

	-- display system prompt as single line with escaped newlines
	if system_prompt then
		system_prompt = "- role: " .. system_prompt:gsub("\n", "\\n") .. "\n"
	else
		system_prompt = ""
	end

	local template = string.format(
		M.chat_template,
		string.match(filename, "([^/]+)$"),
		model .. system_prompt,
		M.config.chat_user_prefix,
		M.config.chat_shortcut_respond.shortcut,
		M.config.cmd_prefix,
		M.config.chat_shortcut_stop.shortcut,
		M.config.cmd_prefix,
		M.config.chat_shortcut_delete.shortcut,
		M.config.cmd_prefix,
		M.config.chat_shortcut_new.shortcut,
		M.config.cmd_prefix,
		M.config.chat_user_prefix
	)

	-- escape underscores (for markdown)
	template = template:gsub("_", "\\_")

	local cbuf = vim.api.nvim_get_current_buf()

	-- strip leading and trailing newlines
	template = template:gsub("^%s*(.-)%s*$", "%1") .. "\n"

	-- create chat file
	vim.fn.writefile(vim.split(template, "\n"), filename)
	local target = M.resolve_buf_target(params)
	local buf = M.open_buf(filename, target, M._toggle_kind.chat, toggle)

	if params.range == 2 then
		M.append_selection(params, cbuf, buf)
	end
	utils.feedkeys("G", "xn")
	return buf
end

---@return number # buffer number
M.cmd.ChatNew = function(params, model, system_prompt)
	-- if chat toggle is open, close it and start a new one
	if M._toggle_close(M._toggle_kind.chat) then
		params.args = params.args or ""
		if params.args == "" then
			params.args = M.config.toggle_target
		end
		return M.new_chat(params, model, system_prompt, true)
	end

	return M.new_chat(params, model, system_prompt, false)
end

M.cmd.ChatToggle = function(params, model, system_prompt)
	M._toggle_close(M._toggle_kind.popup)
	if M._toggle_close(M._toggle_kind.chat) and params.range ~= 2 then
		return
	end

	-- create new chat file otherwise
	params.args = params.args or ""
	if params.args == "" then
		params.args = M.config.toggle_target
	end

	-- if the range is 2, we want to create a new chat file with the selection
	if params.range ~= 2 then
		-- check if last.md chat file exists and open it
		local last = M.config.chat_dir .. "/last.md"
		if vim.fn.filereadable(last) == 1 then
			-- resolve symlink
			last = vim.fn.resolve(last)
			M.open_buf(last, M.resolve_buf_target(params), M._toggle_kind.chat, true)
			return
		end
	end

	M.new_chat(params, model, system_prompt, true)
end

M.cmd.ChatDelete = function()
	-- get buffer and file
	local buf = vim.api.nvim_get_current_buf()
	local file_name = vim.api.nvim_buf_get_name(buf)

	-- check if file is in the chat dir
	if not utils.starts_with(file_name, M.config.chat_dir) then
		M.logger.warning("File " .. vim.inspect(file_name) .. " is not in chat dir")
		return
	end

	-- delete without confirmation
	if not M.config.chat_confirm_delete then
		utils.delete_file(file_name)
		return
	end

	-- ask for confirmation
	vim.ui.input({ prompt = "Delete " .. file_name .. "? [y/N] " }, function(input)
		if input and input:lower() == "y" then
			utils.delete_file(file_name)
		end
	end)
end

M.chat_respond = function(params)
	local buf = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()

	local agent = M.get_chat_agent()
	local agent_name = agent.name
	local agent_provider = agent.provider

	if not M.valid_api_key(agent.provider) then
		return
	end

	if not M.can_handle(buf) then
		M.logger.warning("Another parrot process is already running for this buffer.")
		return
	end

	-- go to normal mode
	vim.cmd("stopinsert")

	-- get all lines
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

	-- check if file looks like a chat file
	local file_name = vim.api.nvim_buf_get_name(buf)
	if not utils.is_chat(buf, file_name, M.config.chat_dir) then
		M.logger.warning("File " .. vim.inspect(file_name) .. " does not look like a chat file")
		return
	end

	-- headers are fields before first ---
	local headers = {}
	local header_end = nil
	local line_idx = 0
	---parse headers
	for _, line in ipairs(lines) do
		-- first line starts with ---
		if line:sub(1, 3) == "---" then
			header_end = line_idx
			break
		end
		-- parse header fields
		local key, value = line:match("^[-#] (%w+): (.*)")
		if key ~= nil then
			headers[key] = value
		end

		line_idx = line_idx + 1
	end

	if header_end == nil then
		M.logger.error("Error while parsing headers: --- not found. Check your chat template.")
		return
	end

	-- message needs role and content
	local messages = {}
	local role = ""
	local content = ""

	-- iterate over lines
	local start_index = header_end + 1
	local end_index = #lines
	if params.range == 2 then
		start_index = math.max(start_index, params.line1)
		end_index = math.min(end_index, params.line2)
	end

	-- if model contains { } then it is a json string otherwise it is a model name
	if headers.model and headers.model:match("{.*}") then
		-- unescape underscores before decoding json
		headers.model = headers.model:gsub("\\_", "_")
		headers.model = vim.json.decode(headers.model)
	end

	if headers.model and type(headers.model) == "table" then
		agent_name = headers.model.model
	elseif headers.model and headers.model:match("%S") then
		agent_name = headers.model
	end

	if headers.role and headers.role:match("%S") then
		---@diagnostic disable-next-line: cast-local-type
		agent_name = agent_name .. " & custom role"
	end

	local agent_prefix = config.chat_assistant_prefix[1]
	local agent_suffix = config.chat_assistant_prefix[2]
	if type(M.config.chat_assistant_prefix) == "string" then
		---@diagnostic disable-next-line: cast-local-type
		agent_prefix = M.config.chat_assistant_prefix
	elseif type(M.config.chat_assistant_prefix) == "table" then
		agent_prefix = M.config.chat_assistant_prefix[1]
		agent_suffix = M.config.chat_assistant_prefix[2] or ""
	end
	---@diagnostic disable-next-line: cast-local-type
	agent_suffix =
		utils.template_render_from_list(agent_suffix, { ["{{agent}}"] = agent_name .. " - " .. agent_provider })

	for index = start_index, end_index do
		local line = lines[index]
		if line:sub(1, #M.config.chat_user_prefix) == M.config.chat_user_prefix then
			table.insert(messages, { role = role, content = content })
			role = "user"
			content = line:sub(#M.config.chat_user_prefix + 1)
		elseif line:sub(1, #agent_prefix) == agent_prefix then
			table.insert(messages, { role = role, content = content })
			role = "assistant"
			content = ""
		elseif role ~= "" then
			content = content .. "\n" .. line
		end
	end
	-- insert last message not handled in loop
	table.insert(messages, { role = role, content = content })

	-- replace first empty message with system prompt
	content = ""
	if headers.role and headers.role:match("%S") then
		content = headers.role
	else
		content = agent.system_prompt
	end
	if content:match("%S") then
		-- make it multiline again if it contains escaped newlines
		content = content:gsub("\\n", "\n")
		messages[1] = { role = "system", content = content }
	end

	-- strip whitespace from ends of content
	for _, message in ipairs(messages) do
		message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
	end

	-- write assistant prompt
	local last_content_line = utils.last_content_line(buf)
	vim.api.nvim_buf_set_lines(
		buf,
		last_content_line,
		last_content_line,
		false,
		{ "", agent_prefix .. agent_suffix, "" }
	)

	-- call the model and write response
	M.query(
		buf,
		agent.provider,
		utils.prepare_payload(messages, headers.model, agent.model),
		M.create_handler(buf, win, utils.last_content_line(buf), true, "", not M.config.chat_free_cursor),
		vim.schedule_wrap(function(qid)
			local qt = M.get_query(qid)
			if not qt then
				return
			end

			-- write user prompt
			last_content_line = utils.last_content_line(buf)
			utils.undojoin(buf)
			vim.api.nvim_buf_set_lines(
				buf,
				last_content_line,
				last_content_line,
				false,
				{ "", "", M.config.chat_user_prefix, "" }
			)

			-- delete whitespace lines at the end of the file
			last_content_line = utils.last_content_line(buf)
			utils.undojoin(buf)
			vim.api.nvim_buf_set_lines(buf, last_content_line, -1, false, {})
			-- insert a new line at the end of the file
			utils.undojoin(buf)
			vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })

			-- if topic is ?, then generate it
			if headers.topic == "?" then
				-- insert last model response
				table.insert(messages, { role = "assistant", content = qt.response })

				-- ask model to generate topic/title for the chat
				table.insert(messages, { role = "user", content = M.providers[M.get_provider()].topic_prompt })

				-- prepare invisible buffer for the model to write to
				local topic_buf = vim.api.nvim_create_buf(false, true)
				local topic_handler = M.create_handler(topic_buf, nil, 0, false, "", false)

				local topic_prov = M.get_provider()

				-- call the model
				M.query(
					nil,
					topic_prov,
					-- utils.prepare_payload(messages, current_agent_topic.model, nil),
					utils.prepare_payload(messages, M.providers[topic_prov].topic_model, nil),
					topic_handler,
					vim.schedule_wrap(function()
						-- get topic from invisible buffer
						local topic = vim.api.nvim_buf_get_lines(topic_buf, 0, -1, false)[1]
						-- close invisible buffer
						vim.api.nvim_buf_delete(topic_buf, { force = true })
						-- strip whitespace from ends of topic
						topic = topic:gsub("^%s*(.-)%s*$", "%1")
						-- strip dot from end of topic
						topic = topic:gsub("%.$", "")

						-- if topic is empty do not replace it
						if topic == "" then
							return
						end

						-- replace topic in current buffer
						utils.undojoin(buf)
						vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "# topic: " .. topic })
					end)
				)
			end

			if not M.config.chat_free_cursor then
				local line = vim.api.nvim_buf_line_count(buf)
				utils.cursor_to_line(line, buf, win)
			end
			vim.cmd("doautocmd User PrtDone")
		end)
	)
end

M.cmd.ChatRespond = function(params)
	if params.args == "" then
		M.chat_respond(params)
		return
	end

	-- ensure args is a single positive number
	local n_requests = tonumber(params.args)
	if n_requests == nil or math.floor(n_requests) ~= n_requests or n_requests <= 0 then
		M.logger.warning("args for ChatRespond should be a single positive number, not: " .. params.args)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local cur_index = #lines
	while cur_index > 0 and n_requests > 0 do
		if lines[cur_index]:sub(1, #M.config.chat_user_prefix) == M.config.chat_user_prefix then
			n_requests = n_requests - 1
		end
		cur_index = cur_index - 1
	end

	params.range = 2
	params.line1 = cur_index + 1
	params.line2 = #lines
	M.chat_respond(params)
end

M._chat_finder_opened = false
M.cmd.ChatFinder = function()
	if M._chat_finder_opened then
		M.logger.warning("Chat finder is already open")
		return
	end
	M._chat_finder_opened = true

	local dir = M.config.chat_dir

	-- prepare unique group name and register augroup
	local gid = utils.create_augroup("PrtChatFinder", { clear = true })

	-- prepare three popup buffers and windows
	local ratio = M.config.style_chat_finder_preview_ratio or 0.5
	local top = M.config.style_chat_finder_margin_top or 2
	local bottom = M.config.style_chat_finder_margin_bottom or 8
	local left = M.config.style_chat_finder_margin_left or 1
	local right = M.config.style_chat_finder_margin_right or 2
	local picker_buf, picker_win, picker_close, picker_resize = ui.create_popup(
		nil,
		"Picker: j/k <Esc>|exit <Enter>|open dd|del i|srch",
		function(w, h)
			local wh = h - top - bottom - 2
			local ww = w - left - right - 2
			return math.floor(ww * (1 - ratio)), wh, top, left
		end,
		{ gid = gid },
		{ border = M.config.style_chat_finder_border or "single" }
	)

	local preview_buf, preview_win, preview_close, preview_resize = ui.create_popup(
		nil,
		"Preview (edits are ephemeral)",
		function(w, h)
			local wh = h - top - bottom - 2
			local ww = w - left - right - 1
			return ww * ratio, wh, top, left + math.ceil(ww * (1 - ratio)) + 2
		end,
		{ gid = gid },
		{ border = M.config.style_chat_finder_border or "single" }
	)

	vim.api.nvim_buf_set_option(preview_buf, "filetype", "markdown")

	local command_buf, command_win, command_close, command_resize = ui.create_popup(
		nil,
		"Search: <Tab>/<Shift+Tab>|navigate <Esc>|picker <C-c>|exit "
			.. "<Enter>/<C-f>/<C-x>/<C-v>/<C-t>/<C-g>|open/float/split/vsplit/tab/toggle",
		function(w, h)
			return w - left - right, 1, h - bottom, left
		end,
		{ gid = gid },
		{ border = M.config.style_chat_finder_border or "single" }
	)
	-- set initial content of command buffer
	vim.api.nvim_buf_set_lines(command_buf, 0, -1, false, { M.config.chat_finder_pattern })

	local hl_search_group = "PrtExplorerSearch"
	vim.cmd("highlight default link " .. hl_search_group .. " Search ")
	local hl_cursorline_group = "PrtExplorerCursorLine"
	vim.cmd("highlight default " .. hl_cursorline_group .. " gui=standout cterm=standout")

	local picker_pos_id = 0
	local picker_match_id = 0
	local preview_match_id = 0
	local regex = ""

	-- clean up augroup and popup buffers/windows
	local close = utils.once(function()
		vim.api.nvim_del_augroup_by_id(gid)
		picker_close()
		preview_close()
		command_close()
		M._chat_finder_opened = false
	end)

	local resize = function()
		picker_resize()
		preview_resize()
		command_resize()
	end

	-- logic for updating picker and preview
	local picker_files = {}
	local preview_lines = {}

	local refresh = function()
		if not vim.api.nvim_buf_is_valid(picker_buf) then
			return
		end

		-- empty preview buffer
		vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, {})
		vim.api.nvim_win_set_cursor(preview_win, { 1, 0 })

		local index = vim.api.nvim_win_get_cursor(picker_win)[1]
		local file = picker_files[index]
		if not file then
			return
		end

		local lines = {}
		for l in io.lines(file) do
			table.insert(lines, l)
		end
		vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)

		local preview_line = preview_lines[index]
		if preview_line then
			vim.api.nvim_win_set_cursor(preview_win, { preview_line, 0 })
		end

		-- highlight grep results and current line
		if picker_pos_id ~= 0 then
			vim.fn.matchdelete(picker_pos_id, picker_win)
		end
		if picker_match_id ~= 0 then
			vim.fn.matchdelete(picker_match_id, picker_win)
		end
		if preview_match_id ~= 0 then
			vim.fn.matchdelete(preview_match_id, preview_win)
		end

		if regex == "" then
			picker_pos_id = 0
			picker_match_id = 0
			preview_match_id = 0
			return
		end

		picker_match_id = vim.fn.matchadd(hl_search_group, regex, 0, -1, { window = picker_win })
		preview_match_id = vim.fn.matchadd(hl_search_group, regex, 0, -1, { window = preview_win })
		picker_pos_id = vim.fn.matchaddpos(hl_cursorline_group, { { index } }, 0, -1, { window = picker_win })
	end

	local refresh_picker = function()
		-- get last line of command buffer
		local cmd = vim.api.nvim_buf_get_lines(command_buf, -2, -1, false)[1]

		_H.grep_directory(nil, dir, cmd, function(results, re)
			if not vim.api.nvim_buf_is_valid(picker_buf) then
				return
			end

			picker_files = {}
			preview_lines = {}
			local picker_lines = {}
			for _, f in ipairs(results) do
				table.insert(picker_files, dir .. "/" .. f.file)
				local fline = string.format("%s:%s %s", f.file:sub(3, -11), f.lnum, f.line)
				table.insert(picker_lines, fline)
				table.insert(preview_lines, tonumber(f.lnum))
			end

			vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, picker_lines)

			-- prepare regex for highlighting
			regex = re
			if regex ~= "" then
				-- case insensitive
				regex = "\\c" .. regex
			end

			refresh()
		end)
	end

	refresh_picker()
	vim.api.nvim_set_current_win(command_win)
	vim.api.nvim_command("startinsert!")

	-- resize on VimResized
	utils.autocmd({ "VimResized" }, nil, resize, gid)

	-- moving cursor on picker window will update preview window
	utils.autocmd({ "CursorMoved", "CursorMovedI" }, { picker_buf }, function()
		vim.api.nvim_command("stopinsert")
		refresh()
	end, gid)

	-- InsertEnter on picker or preview window will go to command window
	utils.autocmd({ "InsertEnter" }, { picker_buf, preview_buf }, function()
		vim.api.nvim_set_current_win(command_win)
		vim.api.nvim_command("startinsert!")
	end, gid)

	-- InsertLeave on command window will go to picker window
	utils.autocmd({ "InsertLeave" }, { command_buf }, function()
		vim.api.nvim_set_current_win(picker_win)
		vim.api.nvim_command("stopinsert")
	end, gid)

	-- when preview becomes active call some function
	utils.autocmd({ "WinEnter" }, { preview_buf }, function()
		-- go to normal mode
		vim.api.nvim_command("stopinsert")
	end, gid)

	-- when command buffer is written, execute it
	utils.autocmd({ "TextChanged", "TextChangedI", "TextChangedP", "TextChangedT" }, { command_buf }, function()
		vim.api.nvim_win_set_cursor(picker_win, { 1, 0 })
		refresh_picker()
	end, gid)

	-- close on buffer delete
	utils.autocmd({ "BufWipeout", "BufHidden", "BufDelete" }, { picker_buf, preview_buf, command_buf }, close, gid)

	-- close by escape key on any window
	utils.set_keymap({ picker_buf, preview_buf, command_buf }, "n", "<esc>", close)
	utils.set_keymap({ picker_buf, preview_buf, command_buf }, { "i", "n" }, "<C-c>", close)

	---@param target number
	---@param toggle boolean
	local open_chat = function(target, toggle)
		local index = vim.api.nvim_win_get_cursor(picker_win)[1]
		local file = picker_files[index]
		close()
		-- delay so explorer can close before opening file
		vim.defer_fn(function()
			if not file then
				return
			end
			M.open_buf(file, target, M._toggle_kind.chat, toggle)
		end, 200)
	end

	-- enter on picker window will open file
	utils.set_keymap({ picker_buf, preview_buf, command_buf }, { "i", "n", "v" }, "<cr>", open_chat)
	utils.set_keymap({ picker_buf, preview_buf, command_buf }, { "i", "n", "v" }, "<C-f>", function()
		open_chat(M.BufTarget.popup, false)
	end)
	utils.set_keymap({ picker_buf, preview_buf, command_buf }, { "i", "n", "v" }, "<C-x>", function()
		open_chat(M.BufTarget.split, false)
	end)
	utils.set_keymap({ picker_buf, preview_buf, command_buf }, { "i", "n", "v" }, "<C-v>", function()
		open_chat(M.BufTarget.vsplit, false)
	end)
	utils.set_keymap({ picker_buf, preview_buf, command_buf }, { "i", "n", "v" }, "<C-t>", function()
		open_chat(M.BufTarget.tabnew, false)
	end)
	utils.set_keymap({ picker_buf, preview_buf, command_buf }, { "i", "n", "v" }, "<C-g>", function()
		local target = M.resolve_buf_target(M.config.toggle_target)
		open_chat(target, true)
	end)

	-- tab in command window will cycle through lines in picker window
	utils.set_keymap({ command_buf, picker_buf }, { "i", "n" }, "<tab>", function()
		local index = vim.api.nvim_win_get_cursor(picker_win)[1]
		local next_index = index + 1
		if next_index > #picker_files then
			next_index = 1
		end
		vim.api.nvim_win_set_cursor(picker_win, { next_index, 0 })
		refresh()
	end)

	-- shift-tab in command window will cycle through lines in picker window
	utils.set_keymap({ command_buf, picker_buf }, { "i", "n" }, "<s-tab>", function()
		local index = vim.api.nvim_win_get_cursor(picker_win)[1]
		local next_index = index - 1
		if next_index < 1 then
			next_index = #picker_files
		end
		vim.api.nvim_win_set_cursor(picker_win, { next_index, 0 })
		refresh()
	end)

	-- dd on picker or preview window will delete file
	utils.set_keymap({ picker_buf, preview_buf }, "n", "dd", function()
		local index = vim.api.nvim_win_get_cursor(picker_win)[1]
		local file = picker_files[index]

		-- delete without confirmation
		if not M.config.chat_confirm_delete then
			utils.delete_file(file)
			refresh_picker()
			return
		end

		-- ask for confirmation
		vim.ui.input({ prompt = "Delete " .. file .. "? [y/N] " }, function(input)
			if input and input:lower() == "y" then
				utils.delete_file(file)
				refresh_picker()
			end
		end)
	end)
end

--------------------
-- Prompt logic
--------------------
M.cmd.Provider = function(params)
	local provider = string.gsub(params.args, "^%s*(.-)%s*$", "%1")
	local has_fzf, fzf_lua = pcall(require, "fzf-lua")
	if has_fzf then
		fzf_lua.fzf_exec(M._available_providers, {
			prompt = "Provider selection ❯",
			fzf_opts = M.config.fzf_lua_opts,
			complete = function(selection)
				if #selection == 0 then
					M.logger.info(" Current provider: " .. M._state.provider)
					return
				end
				local selected_prov = selection[1]
				M.logger.info("Selected provider: " .. selected_prov)
				M._state.provider = selected_prov
				M.refresh_state()
			end,
		})
	else
		if provider == "" then
			M.logger.info(" Current provider: " .. M._state.provider)
			return
		end
		M._state.provider = provider
		M.refresh_state()
	end
end

M.cmd.Agent = function(params)
	local prov = M.get_provider()
	local buf = vim.api.nvim_get_current_buf()
	local file_name = vim.api.nvim_buf_get_name(buf)
	local is_chat = utils.is_chat(buf, file_name, M.config.chat_dir)

	local has_fzf, fzf_lua = pcall(require, "fzf-lua")
	if has_fzf then
		fzf_lua.fzf_exec(M.get_provider_agents(is_chat), {
			prompt = "Agent selection ❯",
			fzf_opts = M.config.fzf_lua_opts,
			preview = require("fzf-lua").shell.raw_preview_action_cmd(function(items)
				if is_chat then
					return string.format("echo %q", vim.fn.shellescape(vim.json.encode(M.agents.chat[items[1]])))
				else
					return string.format("echo %q", vim.fn.shellescape(vim.json.encode(M.agents.command[items[1]])))
				end
			end),
			complete = function(selection)
				if #selection == 0 then
					M.logger.warning("No agent selected")
					return
				end
				local new_agent = selection[1]
				if is_chat then
					M._state[prov].chat_agent = new_agent
					M.logger.info("Chat agent (" .. prov .. "): " .. new_agent)
				else
					M._state[prov].command_agent = new_agent
					M.logger.info("Command agent (" .. prov .. "): " .. new_agent)
				end
				M.refresh_state()
			end,
		})
	else
		local agent_name = string.gsub(params.args, "^%s*(.-)%s*$", "%1")
		if agent_name == "" then
			M.logger.info(
				" Chat agent: " .. M._state[prov].chat_agent .. "  |  Command agent: " .. M._state[prov].command_agent
			)
			return
		end

		if not M.agents.chat[agent_name] and not M.agents.command[agent_name] then
			M.logger.warning("Unknown agent: " .. agent_name)
			return
		end

		if is_chat and M.agents.chat[agent_name] then
			M._state[prov].chat_agent = agent_name
			M.logger.info("Chat agent: " .. M._state[prov].chat_agent)
		elseif is_chat then
			M.logger.warning(agent_name .. " is not a Chat agent")
		elseif M.agents.command[agent_name] then
			M._state[prov].command_agent = agent_name
			M.logger.info("Command agent: " .. M._state[prov].command_agent)
		else
			M.logger.warning(agent_name .. " is not a Command agent")
		end
		M.refresh_state()
	end
end

---@return table # { cmd_prefix, name, model, system_prompt, provider }
M.get_command_agent = function()
	local template = M.config.command_prompt_prefix_template
	local prov = M.get_provider()
	local cmd_prefix = utils.template_render_from_list(template, { ["{{agent}}"] = M._state[prov].command_agent })
	local name = M._state[prov].command_agent
	local model = M.agents.command[name].model
	local system_prompt = M.agents.command[name].system_prompt
	local provider = M.agents.command[name].provider
	return {
		cmd_prefix = cmd_prefix,
		name = name,
		model = model,
		system_prompt = system_prompt,
		provider = provider,
	}
end

---@return table # { cmd_prefix, name, model, system_prompt, provider }
M.get_chat_agent = function()
	local template = M.config.command_prompt_prefix_template
	local prov = M.get_provider()
	local cmd_prefix = utils.template_render_from_list(template, { ["{{agent}}"] = M._state[prov].chat_agent })
	local name = M._state[prov].chat_agent
	local model = M.agents.chat[name].model
	local system_prompt = M.agents.chat[name].system_prompt
	local provider = M.agents.chat[name].provider
	return {
		cmd_prefix = cmd_prefix,
		name = name,
		model = model,
		system_prompt = system_prompt,
		provider = provider,
	}
end

---@return string
M.get_provider = function()
	return M._state["provider"]
end

M.get_provider_agents = function(is_chat)
	local prov = M.get_provider()
	if is_chat then
		return M._available_provider_agents[prov].chat
	else
		return M._available_provider_agents[prov].command
	end
end

M.cmd.Context = function(params)
	M._toggle_close(M._toggle_kind.popup)
	-- if there is no selection, try to close context toggle
	if params.range ~= 2 then
		if M._toggle_close(M._toggle_kind.context) then
			return
		end
	end

	local cbuf = vim.api.nvim_get_current_buf()

	local file_name = ""
	local buf = utils.get_buffer(".parrot.md")
	if buf then
		file_name = vim.api.nvim_buf_get_name(buf)
	else
		local git_root = utils.find_git_root()
		if git_root == "" then
			M.logger.warning("Not in a git repository")
			return
		end
		file_name = git_root .. "/.parrot.md"
	end

	if vim.fn.filereadable(file_name) ~= 1 then
		vim.fn.writefile({ "Additional context is provided bellow.", "" }, file_name)
	end

	params.args = params.args or ""
	if params.args == "" then
		params.args = M.config.toggle_target
	end
	local target = M.resolve_buf_target(params)
	buf = M.open_buf(file_name, target, M._toggle_kind.context, true)

	if params.range == 2 then
		M.append_selection(params, cbuf, buf)
	end

	utils.feedkeys("G", "xn")
end

M.Prompt = function(params, target, prompt, model, template, system_template, provider)
	-- enew, new, vnew, tabnew should be resolved into table
	if type(target) == "function" then
		target = target()
	end

	target = target or M.Target.enew()

	-- get current buffer
	local buf = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()

	if not M.can_handle(buf) then
		M.logger.warning("Another parrot process is already running for this buffer.")
		return
	end

	-- defaults to normal mode
	local selection = nil
	local prefix = ""
	local start_line = vim.api.nvim_win_get_cursor(0)[1]
	local end_line = start_line

	-- handle range
	if params.range == 2 then
		start_line = params.line1
		end_line = params.line2
		local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)

		local min_indent = nil
		local use_tabs = false
		-- measure minimal common indentation for lines with content
		for i, line in ipairs(lines) do
			lines[i] = line
			-- skip whitespace only lines
			if not line:match("^%s*$") then
				local indent = line:match("^%s*")
				-- contains tabs
				if indent:match("\t") then
					use_tabs = true
				end
				if min_indent == nil or #indent < min_indent then
					min_indent = #indent
				end
			end
		end
		if min_indent == nil then
			min_indent = 0
		end
		prefix = string.rep(use_tabs and "\t" or " ", min_indent)

		for i, line in ipairs(lines) do
			lines[i] = line:sub(min_indent + 1)
		end

		selection = table.concat(lines, "\n")

		if selection == "" then
			M.logger.warning("Please select some text to rewrite")
			return
		end
	end

	M._selection_first_line = start_line
	M._selection_last_line = end_line

	local callback = function(command)
		-- dummy handler
		local handler = function() end
		-- default on_exit strips trailing backticks if response was markdown snippet
		local on_exit = function(qid)
			local qt = M.get_query(qid)
			if not qt then
				return
			end
			-- if buf is not valid, return
			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end

			local flc, llc
			local fl = qt.first_line
			local ll = qt.last_line
			-- remove empty lines from the start and end of the response
			while true do
				-- get content of first_line and last_line
				flc = vim.api.nvim_buf_get_lines(buf, fl, fl + 1, false)[1]
				llc = vim.api.nvim_buf_get_lines(buf, ll, ll + 1, false)[1]

				if not flc or not llc then
					break
				end

				local flm = flc:match("%S")
				local llm = llc:match("%S")

				-- break loop if both lines contain non-whitespace characters
				if flm and llm then
					break
				end

				-- break loop lines are equal
				if fl >= ll then
					break
				end

				if not flm then
					utils.undojoin(buf)
					vim.api.nvim_buf_set_lines(buf, fl, fl + 1, false, {})
				else
					utils.undojoin(buf)
					vim.api.nvim_buf_set_lines(buf, ll, ll + 1, false, {})
				end
				ll = ll - 1
			end

			-- if fl and ll starts with triple backticks, remove these lines
			if flc and llc and flc:match("^%s*```") and llc:match("^%s*```") then
				-- remove first line with undojoin
				utils.undojoin(buf)
				vim.api.nvim_buf_set_lines(buf, fl, fl + 1, false, {})
				-- remove last line
				utils.undojoin(buf)
				vim.api.nvim_buf_set_lines(buf, ll - 1, ll, false, {})
				ll = ll - 2
			end
			qt.first_line = fl
			qt.last_line = ll

			-- option to not select response automatically
			if not M.config.command_auto_select_response then
				return
			end

			-- don't select popup response
			if target == M.Target.popup then
				return
			end

			-- default works for rewrite and enew
			local start = fl
			local finish = ll

			if target == M.Target.append then
				start = M._selection_first_line - 1
			end

			if target == M.Target.prepend then
				finish = M._selection_last_line + ll - fl
			end

			-- select from first_line to last_line
			vim.api.nvim_win_set_cursor(0, { start + 1, 0 })
			vim.api.nvim_command("normal! V")
			vim.api.nvim_win_set_cursor(0, { finish + 1, 0 })
		end

		-- prepare messages
		local messages = {}
		local filetype = utils.get_filetype(buf)
		local filename = vim.api.nvim_buf_get_name(buf)

		local sys_prompt = utils.template_render(system_template, command, selection, filetype, filename)
		sys_prompt = sys_prompt or ""
		table.insert(messages, { role = "system", content = sys_prompt })

		local repo_instructions = utils.find_repo_instructions()
		if repo_instructions ~= "" then
			table.insert(messages, { role = "system", content = repo_instructions })
		end

		local user_prompt = utils.template_render(template, command, selection, filetype, filename)
		table.insert(messages, { role = "user", content = user_prompt })

		-- cancel possible visual mode before calling the model
		utils.feedkeys("<esc>", "xn")

		local cursor = true
		if not M.config.command_auto_select_response then
			cursor = false
		end

		-- mode specific logic
		if target == M.Target.rewrite then
			-- delete selection
			vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line - 1, false, {})
			-- prepare handler
			handler = M.create_handler(buf, win, start_line - 1, true, prefix, cursor)
		elseif target == M.Target.append then
			-- move cursor to the end of the selection
			vim.api.nvim_win_set_cursor(0, { end_line, 0 })
			-- put newline after selection
			vim.api.nvim_put({ "" }, "l", true, true)
			-- prepare handler
			handler = M.create_handler(buf, win, end_line, true, prefix, cursor)
		elseif target == M.Target.prepend then
			-- move cursor to the start of the selection
			vim.api.nvim_win_set_cursor(0, { start_line, 0 })
			-- put newline before selection
			vim.api.nvim_put({ "" }, "l", false, true)
			-- prepare handler
			handler = M.create_handler(buf, win, start_line - 1, true, prefix, cursor)
		elseif target == M.Target.popup then
			M._toggle_close(M._toggle_kind.popup)
			-- create a new buffer
			local popup_close = nil
			buf, win, popup_close, _ = ui.create_popup(
				nil,
				M._plugin_name .. " popup (close with <esc>/<C-c>)",
				function(w, h)
					local top = M.config.style_popup_margin_top or 2
					local bottom = M.config.style_popup_margin_bottom or 8
					local left = M.config.style_popup_margin_left or 1
					local right = M.config.style_popup_margin_right or 1
					local max_width = M.config.style_popup_max_width or 160
					local ww = math.min(w - (left + right), max_width)
					local wh = h - (top + bottom)
					return ww, wh, top, (w - ww) / 2
				end,
				{ on_leave = true, escape = true },
				{ border = M.config.style_popup_border or "single" }
			)
			-- set the created buffer as the current buffer
			vim.api.nvim_set_current_buf(buf)
			-- set the filetype to markdown
			vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
			-- better text wrapping
			vim.api.nvim_command("setlocal wrap linebreak")
			-- prepare handler
			handler = M.create_handler(buf, win, 0, false, "", false)
			M._toggle_add(M._toggle_kind.popup, { win = win, buf = buf, close = popup_close })
		elseif type(target) == "table" then
			if target.type == M.Target.new().type then
				vim.cmd("split")
				win = vim.api.nvim_get_current_win()
			elseif target.type == M.Target.vnew().type then
				vim.cmd("vsplit")
				win = vim.api.nvim_get_current_win()
			elseif target.type == M.Target.tabnew().type then
				vim.cmd("tabnew")
				win = vim.api.nvim_get_current_win()
			end

			buf = vim.api.nvim_create_buf(true, true)
			vim.api.nvim_set_current_buf(buf)

			local group = utils.create_augroup("PrtScratchSave" .. utils.uuid(), { clear = true })
			vim.api.nvim_create_autocmd({ "BufWritePre" }, {
				buffer = buf,
				group = group,
				callback = function(ctx)
					vim.api.nvim_buf_set_option(ctx.buf, "buftype", "")
					vim.api.nvim_buf_set_name(ctx.buf, ctx.file)
					vim.api.nvim_command("w!")
					vim.api.nvim_del_augroup_by_id(ctx.group)
				end,
			})

			local ft = target.filetype or filetype
			vim.api.nvim_buf_set_option(buf, "filetype", ft)

			handler = M.create_handler(buf, win, 0, false, "", cursor)
		end

		-- call the model and write the response
		local agent = M.get_command_agent()
		M.query(
			buf,
			provider,
			utils.prepare_payload(messages, model, agent.model),
			handler,
			vim.schedule_wrap(function(qid)
				on_exit(qid)
				vim.cmd("doautocmd User PrtDone")
			end)
		)
	end

	vim.schedule(function()
		local args = params.args or ""
		if args:match("%S") then
			callback(args)
			return
		end

		-- if prompt is not provided, run the command directly
		if not prompt or prompt == "" then
			callback(nil)
			return
		end

		-- if prompt is provided, ask the user to enter the command
		vim.ui.input({ prompt = prompt }, function(input)
			if not input or input == "" then
				return
			end
			callback(input)
		end)
	end)
end

return M
