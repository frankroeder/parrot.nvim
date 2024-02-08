-- The perplexity.ai API for Neovim
-- https://github.com/frankroeder/pplx.nvim/

--------------------------------------------------------------------------------
-- Default config
--------------------------------------------------------------------------------
local system_chat_prompt = "You are a versatile AI assistant with capabilities\n"
	.. "extending to general knowledge and coding support. When engaging\n"
	.. "with users, please adhere to the following guidelines to ensure\n"
	.. "the highest quality of interaction:\n\n"
	.. "- Admit when unsure by saying 'I don't know.'\n"
	.. "- Ask for clarification when needed.\n"
	.. "- Use first principles thinking to analyze queries.\n"
	.. "- Start with the big picture, then focus on details.\n"
	.. "- Apply the Socratic method to enhance understanding.\n"
	.. "- Include all necessary code in your responses."
	.. "- Stay calm and confident with each task.\n"

local system_code_prompt = "You are an AI specializing in software development"
	.. "tasks, including code editing, completion, and debugging. Your"
	.. "responses should strictly pertain to the code provided. Please"
	.. "ensure that your reply is solely focused on the code snippet in question.\n\n"

local config = {
  providers = {
    pplx = {
	    api_key = "",
      endpoint = "https://api.perplexity.ai/chat/completions",
    },
    openai = {
	    api_key = "",
      endpoint = "https://api.openai.com/v1/chat/completions",
    }
  },
	-- prefix for all commands
	cmd_prefix = "Pplx",
	-- optional curl parameters (for proxy, etc.)
	-- curl_params = { "--proxy", "http://X.X.X.X:XXXX" }
	curl_params = {},

	-- directory for persisting state dynamically changed by user (like model or persona)
	state_dir = vim.fn.stdpath("data"):gsub("/$", "") .. "/pplx/persisted",

	agents = {
		chat = {
			-- openai
			{
				name = "ChatGPT4",
				model = { model = "gpt-4-0125-preview", temperature = 1.1, top_p = 1 },
				system_prompt = system_chat_prompt,
        provider = "openai"
			},
			{
				name = "CodeGPT3.5",
				model = { model = "gpt-3.5-turbo-0125", temperature = 1.1, top_p = 1 },
				system_prompt = system_chat_prompt,
        provider = "openai"
			},
			-- pplx
			{
				name = "Perplexity-7b",
				model = { model = "pplx-7b-chat", temperature = 1.1, top_p = 1 },
				system_prompt = system_chat_prompt,
        provider = "pplx"
			},
			{
				name = "Perplexity-70b",
				model = { model = "pplx-70b-chat", temperature = 1.1, top_p = 1 },
				system_prompt = system_chat_prompt,
        provider = "pplx"
			},
			{
				name = "Perplexity-7b-Online",
				model = { model = "pplx-7b-online", temperature = 1.1, top_p = 1 },
				system_prompt = system_chat_prompt, -- ignored by online models
        provider = "pplx"
			},
			{
				name = "Perplexity-70b-Online",
				model = { model = "pplx-70b-online", temperature = 1.1, top_p = 1 },
				system_prompt = system_chat_prompt, -- ignored by online models
        provider = "pplx"
			},
			{
				name = "Llama2-70b",
				model = { model = "llama-2-70b-chat", temperature = 1.1, top_p = 1 },
				system_prompt = system_chat_prompt,
        provider = "pplx"
			},
			{
				name = "CodeLlama-34b",
				model = { model = "codellama-34b-instruct", temperature = 1.1, top_p = 1 },
				system_prompt = system_chat_prompt,
        provider = "pplx"
			},
			{
				name = "CodeLlama-70b",
				model = { model = "codellama-70b-instruct", temperature = 1.1, top_p = 1 },
				system_prompt = system_chat_prompt,
        provider = "pplx"
			},
			{
				name = "Mistral-7b",
				model = { model = "mistral-7b-instruct", temperature = 1.1, top_p = 1 },
				system_prompt = system_chat_prompt,
        provider = "pplx"
			},
			{
				name = "Mistral-8x7b",
				model = { model = "mixtral-8x7b-instruct", temperature = 1.1, top_p = 1 },
				system_prompt = system_chat_prompt,
        provider = "pplx"
			},
		},
		command = {
			-- openai
			{
				name = "CodeGPT4",
				model = { model = "gpt-4-0125-preview", temperature = 1.1, top_p = 1 },
				system_prompt = system_code_prompt,
        provider = "openai"
			},
			{
				name = "CodeGPT3.5",
				model = { model = "gpt-3.5-turbo-0125", temperature = 1.1, top_p = 1 },
				system_prompt = system_code_prompt,
        provider = "openai"
			},
			-- pplx
			{
				name = "Perplexity-7b",
				model = { model = "pplx-7b-chat", temperature = 0.8, top_p = 1 },
				system_prompt = system_code_prompt,
        provider = "pplx"
			},
			{
				name = "Perplexity-70b",
				model = { model = "pplx-70b-chat", temperature = 0.8, top_p = 1 },
				system_prompt = system_code_prompt,
        provider = "pplx"
			},
			{
				name = "Perplexity-7b-Online",
				model = { model = "pplx-7b-online", temperature = 0.8, top_p = 1 },
				system_prompt = system_code_prompt, -- ignored by online models
        provider = "pplx"
			},
			{
				name = "Perplexity-70b-Online",
				model = { model = "pplx-70b-online", temperature = 0.8, top_p = 1 },
				system_prompt = system_code_prompt, -- ignored by online models
        provider = "pplx"
			},
			{
				name = "Llama2-70b",
				model = { model = "llama-2-70b-chat", temperature = 0.8, top_p = 1 },
				system_prompt = system_code_prompt,
        provider = "pplx"
			},
			{
				name = "CodeLlama-34b",
				model = { model = "codellama-34b-instruct", temperature = 0.8, top_p = 1 },
				system_prompt = system_code_prompt,
        provider = "pplx"
			},
			{
				name = "CodeLlama-70b",
				model = { model = "codellama-70b-instruct", temperature = 0.8, top_p = 1 },
				system_prompt = system_code_prompt,
        provider = "pplx"
			},
			{
				name = "Mistral-7b",
				model = { model = "mistral-7b-instruct", temperature = 0.8, top_p = 1 },
				system_prompt = system_code_prompt,
        provider = "pplx"
			},
			{
				name = "Mistral-8x7b",
				model = { model = "mixtral-8x7b-instruct", temperature = 0.8, top_p = 1 },
				system_prompt = system_code_prompt,
        provider = "pplx"
			},

		},
	},
	-- directory for storing chat files
	chat_dir = vim.fn.stdpath("data"):gsub("/$", "") .. "/pplx/chats",
	-- chat user prompt prefix
	chat_user_prefix = "🗨:",
	-- chat assistant prompt prefix (static string or a table {static, template})
	-- first string has to be static, second string can contain template {{agent}}
	-- just a static string is legacy and the [{{agent}}] element is added automatically
	-- if you really want just a static string, make it a table with one element { "🤖:" }
	chat_assistant_prefix = { "🤖:", "[{{agent}}]" },
	-- chat topic generation prompt
	chat_topic_gen_prompt = "Summarize the topic of our conversation above"
		.. " in two or three words. Respond only with those words.",
	-- chat topic model (string with model name or table with model name and parameters)
  chat_topic_gen_model = "gpt-3.5-turbo-16k",
	-- explicitly confirm deletion of a chat file
	chat_confirm_delete = true,
	-- conceal model parameters in chat
	chat_conceal_model_params = true,
	-- local shortcuts bound to the chat buffer
	-- (be careful to choose something which will work across specified modes)
	chat_shortcut_respond = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g><C-g>" },
	chat_shortcut_delete = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>d" },
	chat_shortcut_stop = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>s" },
	chat_shortcut_new = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>c" },
	-- default search term when using :PplxChatFinder
	chat_finder_pattern = "topic ",
	-- if true, finished ChatResponder won't move the cursor to the end of the buffer
	chat_free_cursor = false,
	-- use prompt buftype for chats (:h prompt-buffer)
	chat_prompt_buf_type = false,

	-- how to display PplxChatToggle or PplxContext: popup / split / vsplit / tabnew
	toggle_target = "vsplit",

	-- styling for chatfinder
	-- border can be "single", "double", "rounded", "solid", "shadow", "none"
	style_chat_finder_border = "single",
	-- margins are number of characters or lines
	style_chat_finder_margin_bottom = 8,
	style_chat_finder_margin_left = 1,
	style_chat_finder_margin_right = 2,
	style_chat_finder_margin_top = 2,
	-- how wide should the preview be, number between 0.0 and 1.0
	style_chat_finder_preview_ratio = 0.5,

	-- styling for popup
	-- border can be "single", "double", "rounded", "solid", "shadow", "none"
	style_popup_border = "single",
	-- margins are number of characters or lines
	style_popup_margin_bottom = 8,
	style_popup_margin_left = 1,
	style_popup_margin_right = 2,
	style_popup_margin_top = 2,
	style_popup_max_width = 160,

	-- command config and templates bellow are used by commands like PplxRewrite, PplxEnew, etc.
	-- command prompt prefix for asking user for input (supports {{agent}} template variable)
	command_prompt_prefix_template = "🤖 {{agent}} ~ ",
	-- auto select command response (easier chaining of commands)
	-- if false it also frees up the buffer cursor for further editing elsewhere
	command_auto_select_response = true,

	-- templates
	template_selection = "I have the following from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}",
	template_rewrite = "I have the following from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}"
		.. "\n\nRespond exclusively with the snippet that should replace the selection above."
		.. "\nDO NOT RESPOND WITH ANY TYPE OF COMMENTS, JUST THE CODE!!!",
	template_append = "I have the following from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}"
		.. "\n\nRespond exclusively with the snippet that should be appended after the selection above."
		.. "\nDO NOT RESPOND WITH ANY TYPE OF COMMENTS, JUST THE CODE!!!",
	template_prepend = "I have the following from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}"
		.. "\n\nRespond exclusively with the snippet that should be prepended before the selection above."
		.. "\nDO NOT RESPOND WITH ANY TYPE OF COMMENTS, JUST THE CODE!!!",
	template_command = "{{command}}",

	-- example hook functions (see Extend functionality section in the README)
	hooks = {
		InspectPlugin = function(plugin, params)
			local bufnr = vim.api.nvim_create_buf(false, true)
			local copy = vim.deepcopy(plugin)
      for provider, _ in pairs(copy.providers) do
				local s = copy.providers[provider].api_key
				if s and type(s) == "string" then
					copy.providers[provider].api_key = s:sub(1, 3) .. string.rep("*", #s - 6) .. s:sub(-3)
				end
			end
			local plugin_info = string.format("Plugin structure:\n%s", vim.inspect(copy))
			local params_info = string.format("Command params:\n%s", vim.inspect(params))
			local lines = vim.split(plugin_info .. "\n" .. params_info, "\n")
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
			vim.api.nvim_win_set_buf(0, bufnr)
		end,
		-- PplxImplement rewrites the provided selection/range based on comments in it
		Implement = function(pplx, params)
			local template = "Consider the following content from {{filename}}:\n\n"
				.. "```{{filetype}}\n{{selection}}\n```\n\n"
				.. "Please rewrite this according to the contained instructions."
				.. "\n\nRespond exclusively with the snippet that should replace the selection above."

			local agent = pplx.get_command_agent()
			pplx.logger.info("Implementing selection with agent: " .. agent.name)

			pplx.Prompt(
				params,
				pplx.Target.rewrite,
				nil, -- command will run directly without any prompting for user input
				agent.model,
				template,
				agent.system_prompt
			)
		end,
	},
}

return config
