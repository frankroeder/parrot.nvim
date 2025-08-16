local ChatHandler = require("parrot.chat_handler")
local init_provider = require("parrot.provider").init_provider
local utils = require("parrot.utils")
local Spinner = require("parrot.spinner")
local State = require("parrot.state")

local M = {
  ui = require("parrot.ui"),
  logger = require("parrot.logger"),
}
local system_chat_prompt = [[
You are a versatile AI assistant with capabilities
extending to general knowledge and coding support. When engaging
with users, please adhere to the following guidelines to ensure
the highest quality of interaction:

- Admit when unsure by saying 'I don't know.'
- Ask for clarification when needed.
- Use first principles thinking to analyze queries.
- Start with the big picture, then focus on details.
- Apply the Socratic method to enhance understanding.
- Include all necessary code in your responses.
- Stay calm and confident with each task.
]]

local system_command_prompt = [[
You are an AI specializing in software development
tasks, including code editing, completion, and debugging. Your
responses should strictly pertain to the code provided. Please ensure
that your reply is solely focused on the code snippet in question.
]]

local defaults = {
  providers = {},
  cmd_prefix = "Prt",
  curl_params = {},
  system_prompt = {
    chat = system_chat_prompt,
    command = system_command_prompt,
  },
  state_dir = vim.fn.stdpath("data") .. "/parrot/persisted",
  chat_dir = vim.fn.stdpath("data") .. "/parrot/chats",
  chat_user_prefix = "🗨:",
  llm_prefix = "🦜:",
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
  command_prompt_prefix_template = "🤖 {{llm}} ~ ",
  command_auto_select_response = true,
  model_cache_expiry_hours = 48,
  fzf_lua_opts = {
    ["--ansi"] = true,
    ["--sort"] = "",
    ["--info"] = "inline",
    ["--layout"] = "reverse",
    ["--preview-window"] = "nohidden:right:75%",
  },
  enable_spinner = true,
  spinner_type = "dots",
  show_context_hints = false,
  enable_preview_mode = true,
  preview_auto_apply = false, -- If true, applies changes automatically after preview timeout
  preview_timeout = 10000, -- Time in ms before auto-apply (if enabled)
  preview_border = "rounded",
  preview_max_width = 120,
  preview_max_height = 30,
  chat_template = [[
  # topic: ?
  {{optional}}
  ---

  {{user}}]],

  topic_prompt = [[
  Summarize the topic of our conversation above
  in three or four words. Respond only with those words.
  ]],
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
  template_nvim_cmd = [[
  You are a Neovim command generator.
  Given a plain‐English request, reply with ONLY the exact command, nothing else.
  Do NOT include any backticks, colons, or other formatting.
  Do NOT include any explanations, just the plain Vim command.

  The command should be valid and executable in Vim.
  For example, if the request is "exit vim", respond with just "q".
  Other examples:
  - Request: Save file and quit editor. Command: wq
  - Request: Yank the next 5 lines. Command: 5yy
  - Request: Replace every occurrence of foo with bar. Command: %s/foo/bar/g
  - Request: Open the file init.lua. Command: :e init.lua
  - Request: Delete current line and next 3 lines. Command: normal d3j
  - Request: Sort lines 1 through 20. Command: 1,20sort
  - Request: Delete all lines containing DEBUG. Command: g/DEBUG/d
  - Request: Search for lines starting with "This". Command: /^This
  - Request: Split current window vertically. Command: vsplit
  - Request: Search for function test. Command: /function test

  Here is the request:
  {{command}}
  ]],

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
    Status = function(parrot, _)
      local status_info = parrot.get_status_info()
      local provider = status_info.is_chat and status_info.prov.chat or status_info.prov.command
      local status = string.format("%s (%s)", provider.name, status_info.model)
      parrot.logger.info(string.format("Current provider: %s", status))
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
      local model_obj = parrot.get_model("command")
      parrot.logger.info("Implementing selection with model: " .. model_obj.name)
      parrot.Prompt(params, parrot.ui.Target.rewrite, model_obj, nil, template)
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
      local model_obj = parrot.get_model("command")
      parrot.logger.info("Asking model: " .. model_obj.name)
      parrot.Prompt(params, parrot.ui.Target.popup, model_obj, "🤖 Ask ~ ", template)
    end,
  },
  prompts = {
    ["ProofReader"] = "You are a professional proofreader looking for spell and grammar errors",
    ["CodeFixer"] = [[
    You are a proficient programmer in the provided language. I want you to
    look for erros and bugs within the provided snippet. Simply assume that you
    have access to the used libraries and packages, hence skip importing them.
    ]],
    ["CodeFixerContext"] = [[
    You are a proficient programmer in the provided language. I want you to
    look for erros and bugs within the provided snippet given the full file content

    ```{{filetype}}
    {{filecontent}}
    ```
    ]],
  },
}

M.get_prompt_keys = function(options)
  local keys = {}
  for k, v in pairs(options.prompts) do
    if v and v ~= "" then
      table.insert(keys, k)
    end
  end
  return keys
end

M.merge_providers = function(default_providers, user_providers)
  local result = {}
  for provider, config in pairs(user_providers) do
    result[provider] = vim.tbl_deep_extend("force", default_providers[provider] or {}, config)
  end
  return result
end

M.loaded = false
M.options = nil
M.providers = nil
M.hooks = nil

function M.setup(opts)
  if vim.fn.has("nvim-0.10") == 0 then
    return M.logger.notify("parrot.nvim requires Neovim >= 0.10", vim.log.levels.ERROR)
  end

  math.randomseed(os.time())

  M.options = vim.tbl_deep_extend("force", {}, defaults, opts or {})
  M.providers = opts.providers -- M.merge_providers(defaults.providers, opts.providers)
  -- Ensure each provider has params for chat and command, defaulting to OpenAI-style params or empty
  -- local default_params = (defaults.providers.openai and defaults.providers.openai.params) or { chat = {}, command = {} }
  -- for _, prov in pairs(M.providers) do
  --   prov.params = vim.tbl_deep_extend("force", {}, default_params, prov.params or {})
  -- end
  M.options.providers = nil
  M.hooks = M.options.hooks
  M.options.hooks = nil

  -- resolve symlinks
  local chat_dir_stat = vim.uv.fs_lstat(M.options.chat_dir)
  if chat_dir_stat and chat_dir_stat.type == "link" then
    M.options.chat_dir = vim.fn.resolve(M.options.chat_dir)
  end
  local state_dir_stat = vim.uv.fs_lstat(M.options.state_dir)
  if state_dir_stat and state_dir_stat.type == "link" then
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

  -- Initialize state early to enable caching
  local temp_state = State:new(M.options.state_dir)

  -- Clean up cache for removed providers
  temp_state:cleanup_cache(M.available_providers)

  local available_models = {}

  -- Check each provider individually and fetch models
  for _, prov_name in ipairs(M.available_providers) do
    -- Create the new provider config format
    local provider_config = vim.tbl_deep_extend("force", {
      name = prov_name,
    }, M.providers[prov_name])
    local _prov = init_provider(provider_config)

    -- Use cached model fetching if provider has model_endpoint
    if _prov:online_model_fetching() and M.options.model_cache_expiry_hours > 0 then
      -- Check cache validity for this specific provider
      local endpoint_hash = utils.generate_endpoint_hash(_prov)
      local needs_update = not temp_state:is_cache_valid(prov_name, M.options.model_cache_expiry_hours, endpoint_hash)

      -- Show spinner only for this provider if needed
      local spinner = nil
      if needs_update and M.options.enable_spinner then
        spinner = Spinner:new(M.options.spinner_type)
        M.logger.info("Updating model cache for " .. prov_name)
      end

      available_models[prov_name] =
        _prov:get_available_models_cached(temp_state, M.options.model_cache_expiry_hours, spinner)
    else
      -- Fall back to static models for providers without model_endpoint
      available_models[prov_name] = _prov.models
    end
  end

  -- Now refresh the state with all available models
  temp_state:refresh(M.available_providers, available_models)

  M.available_models = available_models

  table.sort(M.available_providers)
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
    Model = "model",
    Provider = "provider",
    Retry = "retry",
    Edit = "edit",
    Rewrite = "Rewrite",
    Append = "Append",
    Prepend = "Prepend",
    Cmd = "Cmd",
  }

  M.chat_handler = ChatHandler:new(M.options, M.providers, M.available_providers, M.available_models, M.cmd)
  M.chat_handler:prepare_commands()
  M.add_default_commands(M.cmd, M.hooks, M.options)
  M.chat_handler:buf_handler()

  M.loaded = true
end

M.Prompt = function(params, target, model_obj, prompt, template)
  M.chat_handler:prompt(params, target, model_obj, prompt, template)
end

M.ChatNew = function(params, chat_prompt)
  M.chat_handler:chat_new(params, chat_prompt)
end

M.get_model = function(model_type)
  return M.chat_handler:get_model(model_type)
end

M.get_status_info = function()
  return M.chat_handler:get_status_info()
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
    Rewrite = M.get_prompt_keys(options),
    Append = M.get_prompt_keys(options),
    Prepend = M.get_prompt_keys(options),
  }
  -- register default commands
  for cmd, cmd_func in pairs(commands) do
    if hooks[cmd] == nil then
      vim.api.nvim_create_user_command(options.cmd_prefix .. cmd, function(params)
        M.chat_handler[cmd_func](M.chat_handler, params)
      end, {
        nargs = "?",
        range = true,
        desc = "Parrot LLM plugin: " .. cmd,
        complete = function()
          if completions[cmd] then
            return completions[cmd]
          end
          if cmd == "Model" then
            -- TODO: Should detect the respective mode --
            local current_provider = M.chat_handler.state:get_provider(true) -- Use chat provider by default
            if current_provider and M.available_models[current_provider] then
              return M.available_models[current_provider]
            end
            return {}
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
