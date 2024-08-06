local utils = require("parrot.utils")
local Chat = require("parrot.chat_handler")
local get_provider_agents = require("parrot.provider").get_provider_agents

local M = {
  ui = require("parrot.ui"),
  logger = require("parrot.logger"),
}

local topic_prompt = [[
Summarize the topic of our conversation above
in two or three words. Respond only with those words.
]]

local defaults = {
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
  state_dir = vim.fn.stdpath("data") .. "/parrot/persisted",
  chat_dir = vim.fn.stdpath("data") .. "/parrot/chats",
  agents = require("parrot.agents"),
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
  chat_template = [[
  # topic: ?
  {{optional}}
  ---

  {{user}}]],
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
    Log = function(parrot, _)
      vim.cmd("edit " .. vim.fn.fnameescape(parrot.logger._logfile))
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
      parrot.Prompt(params, parrot.ui.Target.rewrite, agent, nil, template)
    end,
    -- PrtAsk simply provides an answer to a question within a popup window
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
      parrot.Prompt(params, parrot.ui.Target.popup, agent, "🤖 Ask ~ ", template)
    end,
  },
}

M.merge_providers = function(default_providers, user_providers)
  local result = {}
  for provider, config in pairs(user_providers) do
    result[provider] = vim.tbl_deep_extend("force", default_providers[provider] or {}, config)
  end
  return result
end

M.merge_agent_type = function(default_agents, user_agents, user_providers)
  local result = vim.deepcopy(user_agents) or {}
  for _, default_agent in ipairs(default_agents) do
    if user_providers[default_agent.provider] then
      table.insert(result, vim.deepcopy(default_agent))
    end
  end
  return result
end

M.merge_agents = function(default_agents, user_agents, user_providers)
  return {
    command = M.merge_agent_type(default_agents.command or {}, user_agents.command, user_providers),
    chat = M.merge_agent_type(default_agents.chat or {}, user_agents.chat, user_providers),
  }
end

M.index_agents_by_name = function(_agents)
  local result = {}
  for category, agent_list in pairs(_agents) do
    result[category] = {}
    for _, agent in ipairs(agent_list) do
      result[category][agent.name] = agent
    end
  end
  return result
end

M.loaded = false
M.options = nil
M.providers = nil
M.agents = nil
M.hooks = nil

function M.setup(opts)
  if vim.fn.has("nvim-0.9.4") == 0 then
    return vim.notify("parrot.nvim requires Neovim >= 0.9.4", vim.log.levels.ERROR)
  end

  math.randomseed(os.time())

  local valid_provider_names = vim.tbl_keys(defaults.providers)
  if not utils.has_valid_key(opts.providers, valid_provider_names) then
    return vim.notify("Invalid provider configuration", vim.log.levels.ERROR)
  end

  M.options = vim.tbl_deep_extend("force", {}, defaults, opts or {})
  M.providers = M.merge_providers(defaults.providers, opts.providers)
  M.options.providers = nil
  local agents = M.merge_agents(defaults.agents or {}, opts.agents or {}, M.providers)
  M.agents = M.index_agents_by_name(agents)
  M.options.agents = nil
  M.hooks = M.options.hooks
  M.options.hooks = nil

  -- resolve symlinks
  local stat = vim.uv.fs_lstat(M.options.chat_dir)
  if stat and stat.type == "link" then
    M.options.chat_dir = vim.fn.resolve(M.options.chat_dir)
  end
  local stat = vim.uv.fs_lstat(M.options.state_dir)
  if stat and stat.type == "link" then
    M.options.state_dir = vim.fn.resolve(M.options.state_dir)
  end

  -- Create directories for all config entries ending with "_dir"
  for k, v in pairs(M.options) do
    if type(v) == "string" and k:match("_dir$") then
      local dir = v:gsub("/$", "")
      M.options[k] = dir
      vim.fn.mkdir(dir, "p")
    end
  end

  M.available_providers = vim.tbl_keys(M.providers)
  M.available_provider_agents = vim.tbl_map(function()
    return { chat = {}, command = {} }
  end, M.providers)

  for type, agts in pairs(M.agents) do
    for agt_name, agt in pairs(agts) do
      table.insert(M.available_provider_agents[agt.provider][type], agt_name)
    end
  end

  table.sort(M.available_providers)
  table.sort(M.available_provider_agents)
  M.register_hooks(M.hooks, M.options)

  M.cmd = {
    ChatFinder = "chat_finder",
    ChatStop = "stop",
    ChatNew = "chat_new",
    ChatToggle = "chat_toggle",
    ChatPaste = "chat_paste",
    ChatDelete = "chat_delete",
    ChatResponde = "chat_respond",
    Context = "context",
    Agent = "agent",
    Provider = "provider",
  }
  M.chat_handler = Chat:new(M.options, M.providers, M.agents, M.available_providers, M.available_provider_agents, M.cmd)
  M.chat_handler:prepare_commands()
  M.add_default_commands(M.cmd, M.hooks, M.options)
  M.chat_handler:buf_handler()

  M.loaded = true
end

M.Prompt = function(params, target, agent, prompt, template)
  M.chat_handler:prompt(params, target, agent, prompt, template)
end

M.ChatNew = function(params, chat_prompt)
  M.chat_handler:chat_new(params, chat_prompt)
end

M.get_chat_agent = function()
  return M.chat_handler:get_chat_agent()
end

M.get_command_agent = function()
  return M.chat_handler:get_command_agent()
end

M.register_hooks = function(hooks, options)
  -- register user commands
  for hook, _ in pairs(hooks) do
    vim.api.nvim_create_user_command(options.cmd_prefix .. hook, function(params)
      M.call_hook(hook, params)
    end, { nargs = "?", range = true, desc = "Parrot LLM plugin" })
  end
end

-- hook caller
M.call_hook = function(name, params)
  if M.hooks[name] ~= nil then
    return M.hooks[name](M, params)
  end
  M.logger.error("The hook '" .. name .. "' does not exist.")
end

M.add_default_commands = function(commands, hooks, options)
  local completions = {
    ChatNew = { "popup", "split", "vsplit", "tabnew" },
    ChatPaste = { "popup", "split", "vsplit", "tabnew" },
    ChatToggle = { "popup", "split", "vsplit", "tabnew" },
    Context = { "popup", "split", "vsplit", "tabnew" },
  }
  -- register default commands
  for cmd, cmd_func in pairs(commands) do
    if hooks[cmd] == nil then
      vim.api.nvim_create_user_command(options.cmd_prefix .. cmd, function(params)
        M.chat_handler[cmd_func](M.chat_handler, params)
      end, {
        nargs = "?",
        range = true,
        desc = "Parrot LLM plugin",
        complete = function()
          if completions[cmd] then
            return completions[cmd]
          end
          if cmd == "Agent" then
            local buf = vim.api.nvim_get_current_buf()
            local file_name = vim.api.nvim_buf_get_name(buf)
            return get_provider_agents(
              utils.is_chat(buf, file_name, options.chat_dir),
              M.chat_handler.state,
              M.chat_handler.providers,
              M.available_provider_agents
            )
          elseif cmd == "Provider" then
            return M.available_providers
          end
          return {}
        end,
      })
    end
  end
end

return M
