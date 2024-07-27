local agents = require("parrot.agents")

local topic_prompt = [[
Summarize the topic of our conversation above
in two or three words. Respond only with those words.
]]

local config = {
  providers = {
    pplx = {
      api_key = "",
      endpoint = "https://api.perplexity.ai/chat/completions",
      topic_prompt = topic_prompt,
      topic_model = "llama-3-8b-instruct",
    },
    openai = {
      api_key = "",
      endpoint = "https://api.openai.com/v1/chat/completions",
      topic_prompt = topic_prompt,
      topic_model = "gpt-4o-mini",
    },
    gemini = {
      api_key = "",
      endpoint = "https://generativelanguage.googleapis.com/v1beta/models/",
      topic_prompt = topic_prompt,
      topic_model = { model = "gemini-1.5-flash", maxOutputTokens = 64 },
    },
    ollama = {
      endpoint = "http://localhost:11434/api/chat",
      topic_prompt = [[
			Summarize the chat above and only provide a short headline of 2 to 3
			words without any opening phrase like "Sure, here is the summary",
			"Sure! Here's a shortheadline summarizing the chat" or anything similar.
			]],
      topic_model = "mistral:latest",
    },
    anthropic = {
      api_key = "",
      endpoint = "https://api.anthropic.com/v1/messages",
      topic_prompt = "You only respond with 2 to 3 words to summarize the past conversation.",
      topic_model = { model = "claude-3-sonnet-20240229", max_tokens = 32 },
    },
    mistral = {
      api_key = "",
      endpoint = "https://api.mistral.ai/v1/chat/completions",
      topic_prompt = [[
			Summarize the chat above and only provide a short headline of 2 to 3
			words without any opening phrase like "Sure, here is the summary",
			"Sure! Here's a shortheadline summarizing the chat" or anything similar.
			]],
      topic_model = "mistral-medium-latest",
    },
  },
  cmd_prefix = "Prt",
  curl_params = {},
  state_dir = vim.fn.stdpath("data"):gsub("/$", "") .. "/parrot/persisted",
  chat_dir = vim.fn.stdpath("data"):gsub("/$", "") .. "/parrot/chats",
  agents = agents,
  chat_user_prefix = "🗨:",
  chat_confirm_delete = true,
  chat_shortcut_respond = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g><C-g>" },
  chat_shortcut_delete = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>d" },
  chat_shortcut_stop = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>s" },
  chat_shortcut_new = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>c" },
  chat_free_cursor = false,
  chat_prompt_buf_type = false,
  toggle_target = "vsplit",
  user_input_ui = "native",
  style_popup_border = "single",
  style_popup_margin_bottom = 8,
  style_popup_margin_left = 1,
  style_popup_margin_right = 2,
  style_popup_margin_top = 2,
  style_popup_max_width = 160,
  command_prompt_prefix_template = "🤖 {{agent}} ~ ",
  command_auto_select_response = true,
  fzf_lua_opts = {
    ["--ansi"] = true,
    ["--sort"] = "",
    ["--info"] = "inline",
    ["--layout"] = "reverse",
    ["--preview-window"] = "nohidden:right:75%",
  },
  enable_spinner = true,
  spinner_type = "dots",
  -- templates
  chat_template = [[
  # topic: ?

  ---

  %s]],
  template_selection = [[
	I have the following content from {{filename}}:

	```{{filetype}}
	{{selection}}
	```

	{{command}}
	]],
  template_rewrite = [[
  I have the following content from {{filename}}:

  ```{{filetype}}
  {{selection}}
  ```

  {{command}}
  Respond exclusively with the snippet that should replace the selection above.
  DO NOT RESPOND WITH ANY TYPE OF COMMENTS, JUST THE CODE!!!
  ]],
  template_append = [[
	I have the following content from {{filename}}:

	```{{filetype}}
	{{selection}}
	```

	{{command}}
	Respond exclusively with the snippet that should be appended after the selection above.
	DO NOT RESPOND WITH ANY TYPE OF COMMENTS, JUST THE CODE!!!
	DO NOT REPEAT ANY CODE FROM ABOVE!!!
	]],
  template_prepend = [[
	I have the following content from {{filename}}:

	```{{filetype}}
	{{selection}}
	```

	{{command}}
	Respond exclusively with the snippet that should be prepended before the selection above.
	DO NOT RESPOND WITH ANY TYPE OF COMMENTS, JUST THE CODE!!!
	DO NOT REPEAT ANY CODE FROM ABOVE!!!
	]],
  template_command = "{{command}}",

  hooks = {
    Info = function(plugin, params)
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
    -- PrtImplement rewrites the provided selection/range based on comments in it
    Implement = function(parrot, params)
      local template = [[
			Consider the following content from {{filename}}:

			```{{filetype}}
			{{selection}}
			```

			Please rewrite this according to the contained instructions.
			Respond exclusively with the snippet that should replace the selection above.
			]]
      local agent = parrot.get_command_agent()
      parrot.logger.info("Implementing selection with agent: " .. agent.name)

      parrot.Prompt(
        params,
        parrot.ui.Target.rewrite,
        nil, -- command will run directly without any prompting for user input
        agent.model,
        template,
        agent.system_prompt,
        agent.provider
      )
    end,
    -- PrtAsk simply asks a question that should be answered shortly and precisely.
    Ask = function(parrot, params)
      local template = [[
			In light of your existing knowledge base, please generate a response that
			is succinct and directly addresses the question posed. Prioritize accuracy
			and relevance in your answer, drawing upon the most recent information
			available to you. Aim to deliver your response in a concise manner,
			focusing on the essence of the inquiry.
			Question: {{command}}
			]]
      local agent = parrot.get_command_agent()
      parrot.logger.info("Asking agent: " .. vim.inspect(agent.name))
      parrot.Prompt(params, parrot.ui.Target.popup, "🤖 Ask ~ ", agent.model, template, "", agent.provider)
    end,
  },
}

return config
