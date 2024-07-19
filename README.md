<div align="center">

# parrot.nvim 🦜

This is [parrot.nvim](https://github.com/frankroeder/parrot.nvim), the ultimate [stochastic parrot](https://en.wikipedia.org/wiki/Stochastic_parrot) to support your text editing inside Neovim.

[Features](#features) • [Demo](#demo) • [Getting Started](#getting-started) • [Commands](#commands) • [Configuration](#configuration)

<img src="https://github.com/frankroeder/parrot.nvim/assets/19746932/b19c5260-1713-400a-bd55-3faa87f4b509" alt="parrot.nvim logo" width="50%">

</div>

> [!NOTE]⚠️
> This repository is still a work in progress, as large parts of the code are still being simplified and restructured.
> It is based on the brilliant work [gp.nvim](https://github.com/Robitx/gp.nvim) by https://github.com/Robitx.

I started this repository because a perplexity subscription provides $5 of API credits every month for free.
Instead of letting them go to waste, I modified my favorite GPT plugin, [gp.nvim](https://github.com/Robitx/gp.nvim), to meet my needs - a new Neovim plugin was born! 🔥

Unlike [gp.nvim](https://github.com/Robitx/gp.nvim), [parrot.nvim](https://github.com/frankroeder/parrot.nvim) prioritizes a seamless out-of-the-box experience by simplifying functionality and focusing solely on text generation, excluding the integration of DALLE and Whisper.

## Features

- Persistent conversations as markdown files stored within the Neovim standard path or a user-defined location
- Custom hooks for inline text editing with predefined prompts
- Support for multiple providers:
    + [Anthropic API](https://www.anthropic.com/api)
    + [perplexity.ai API](https://blog.perplexity.ai/blog/introducing-pplx-api)
    + [OpenAI API](https://platform.openai.com/)
    + [Mistral API](https://docs.mistral.ai/api/)
    + [Gemini API](https://ai.google.dev/gemini-api/docs)
    + Local and offline serving via [ollama](https://github.com/ollama/ollama)
- Custom agent definitions to determine specific prompt and API parameter combinations, similar to [GPTs](https://openai.com/index/introducing-gpts/)
- Flexible support for providing API credentials from various sources, such as environment variables, bash commands, and your favorite password manager CLI
- Provide repository-specific instructions with a `.parrot.md` file using the command `PrtContext`
- **No** autocompletion and **no** hidden requests in the background to analyze your files

## Demo

Seamlessly switch between providers and agents.
<div align="left">
    <img src="https://github.com/frankroeder/parrot.nvim/assets/19746932/da44ebb0-e705-4ea6-b7c0-1a93c6ba034f" width="100%">
</div>

---

Trigger code completions based on comments.
<div align="left">
    <img src="https://github.com/frankroeder/parrot.nvim/assets/19746932/dc5a0790-b9a2-45ff-90c8-e67eb02f26f3" width="100%">
</div>

---

Let the parrot fix your bugs.
<div align="left">
    <img src="https://github.com/frankroeder/parrot.nvim/assets/19746932/a77fa8b2-9714-42da-bafe-645b540931ab" width="100%">
</div>

## Getting Started

### Dependencies
- [`neovim`](https://github.com/neovim/neovim/releases)
- [`fzf`](https://github.com/junegunn/fzf)
- [`plenary`](https://github.com/nvim-lua/plenary.nvim)
- [`ripgrep`](https://github.com/BurntSushi/ripgrep)

### lazy.nvim
```lua
{
  "frankroeder/parrot.nvim",
  tag = "v0.3.6",
  dependencies = { 'ibhagwan/fzf-lua', 'nvim-lua/plenary.nvim' },
  -- optionally include "rcarriga/nvim-notify" for beautiful notifications
  config = function()
    require("parrot").setup {
      -- Providers must be explicitly added to make them available.
      providers = {
        pplx = {
          api_key = os.getenv "PERPLEXITY_API_KEY",
          -- OPTIONAL
          -- gpg command
          -- api_key = { "gpg", "--decrypt", vim.fn.expand("$HOME") .. "/pplx_api_key.txt.gpg"  },
          -- macOS security tool
          -- api_key = { "/usr/bin/security", "find-generic-password", "-s pplx-api-key", "-w" },
        },
        openai = {
          api_key = os.getenv "OPENAI_API_KEY",
        },
        anthropic = {
          api_key = os.getenv "ANTHROPIC_API_KEY",
        },
        mistral = {
          api_key = os.getenv "MISTRAL_API_KEY",
        },
        gemini = {
          api_key = os.getenv "GEMINI_API_KEY",
        },
        ollama = {} -- provide an empty list to make provider available
      },
    }
  end,
}
```

## Commands

Below are the available commands that can be configured as keybindings.
These commands are included in the default setup.
Additional useful commands are implemented through hooks (see my example configuration).

### General
| Command                   | Description                                  |
| ------------------        | -------------------------------------------- |
| `PrtNew`                  | open a new chat                              |
| `PrtProvider <provider>`  | switch the provider (empty arg triggers fzf) |
| `PrtAgent <agent>`        | switch the agent (empty arg triggers fzf)    |
| `PrtChatToggle <target>`  | toggle chat window                           |
| `PrtInfo`                 | print plugin config                          |
| `PrtContext`              | edits the local context file                 |
| `PrtAsk`                  | ask the selected agent a single question     |
| `PrtChatFinder`           | fuzzy search chat files using fzf            |
| `PrtChatPaste <target>`   | paste visual selection into the latest chat  |

### Interactive
The following commands can be triggered with visual selections.

| Command                  | Description                                                        |
| ------------------------ | ------------------------------------------------------------------ |
| `PrtChatNew <target>`    | paste visual selection into new chat (defaults to `toggle_target`) |
| `PrtChatToggle <target>` | paste visual selection into new chat (defaults to `toggle_target`) |
| `PrtImplement`           | implements selected comment/instruction                            |

### Chat
The following commands are available within the chat files.

| Command          | Description                                          |
| ---------------- | ---------------------------------------------------- |
| `PrtChatDelete`  | delete the present chat file (requires confirmation) |
| `PrtChatRespond` | trigger chat respond                                 |
| `PrtAsk`         | ask the selected agent a single question             |
| `PrtStop`        | interrupt ongoing respond                            |


## Configuration

### Options

```lua
{
    -- The provider definitions with endpoints, api keys and models used for chat summarization
    providers = ...

    -- the prefix used for all commands
    cmd_prefix = "Prt",

    -- optional parameters for curl
    curl_params = {},

    -- The directory to store persisted state information like the
    -- current provider and the selected agents
    state_dir = vim.fn.stdpath("data"):gsub("/$", "") .. "/parrot/persisted",

    -- Defintion of the agents (similar to GPTs) for the chats and the inline hooks
    agents = {
        chat = ...,
        command = ...,
    },

    -- The directory to store the chats (searched with PrtChatFinder)
    chat_dir = vim.fn.stdpath("data"):gsub("/$", "") .. "/parrot/chats",

    -- Chat user prompt prefix
    chat_user_prefix = "🗨:",

    -- Explicitly confirm deletion of a chat file
    chat_confirm_delete = true,

    -- Local chat buffer shortcuts
    chat_shortcut_respond = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g><C-g>" },
    chat_shortcut_delete = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>d" },
    chat_shortcut_stop = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>s" },
    chat_shortcut_new = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>c" },

    -- Option to move the chat to the end of the file after finished respond
    chat_free_cursor = false,

     -- use prompt buftype for chats (:h prompt-buffer)
    chat_prompt_buf_type = false,

    -- Default target for  PrtChatToggle, PrtChatNew, PrtContext and the chats opened from the ChatFinder
    -- values: popup / split / vsplit / tabnew
    toggle_target = "vsplit",

    -- The interactive user input appearing when can be "native" for
    -- vim.ui.input or "buffer" to query the input within a native nvim buffer
    -- (see video demonstrations below)
    user_input_ui = "native",

    -- Popup window layout
    -- border: "single", "double", "rounded", "solid", "shadow", "none"
    style_popup_border = "single",

    -- margins are number of characters or lines
    style_popup_margin_bottom = 8,
    style_popup_margin_left = 1,
    style_popup_margin_right = 2,
    style_popup_margin_top = 2,
    style_popup_max_width = 160

    -- Prompt used for interactive LLM calls like PrtRewrite where {{agent}} is
    -- a placeholder for the agent name
    command_prompt_prefix_template = "🤖 {{agent}} ~ ",

    -- auto select command response (easier chaining of commands)
    -- if false it also frees up the buffer cursor for further editing elsewhere
    command_auto_select_response = true,

    -- fzf_lua options for PrtAgent and PrtChatFinder when plugin is installed
    fzf_lua_opts = {
        ["--ansi"] = true,
        ["--sort"] = "",
        ["--info"] = "inline",
        ["--layout"] = "reverse",
        ["--preview-window"] = "nohidden:right:75%",
    },

    -- Enables the spinner animation during loading
    enable_spinner = true,
    -- Type of spinner animation to display while loading
    -- Available options: "dots", "line", "star", "bouncing_bar", "bouncing_ball"
    spinner_type = "star",
}
```

#### Demonstrations

<details>
<summary>With `user_input_ui = "native"`, use `vim.ui.input` as slim input interface.</summary>
<div align="left">
    <img src="https://github.com/user-attachments/assets/014ad6ad-6367-41d1-ac57-229563540061" width="100%">
</div>
</details>

<details>
<summary>With `user_input_ui = "buffer"`, your input is simply a buffer. All of the content is passed to the API when closed.</summary>
<div align="left">
    <img src="https://github.com/user-attachments/assets/3390a4c1-cb60-4f2a-8bd9-0f47f6ec6e55" width="100%">
</div>
</details>

<details>
<summary>The spinner is useful indicator for providers that take longer to respond.</summary>
<div align="left">
    <img src="https://github.com/user-attachments/assets/39828992-ad2c-4010-be66-e3a03038a980" width="100%">
</div>
</details>


### Refer to my personal lazy.nvim setup for custom hooks and key bindings.

https://github.com/frankroeder/dotfiles/blob/master/nvim/lua/plugins/parrot.lua

### Adding a new agents

We provide two types of agents that might need different system prompts and API parameters.
To make a new chat agent available, one simply adds a new entry to the list `chat` or to `command`, respectively.

```lua
require("parrot").setup {
    -- ...
    agents = {
        chat = {
          {
              name = "CodeLlama",
              model = { model = "codellama", temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
              system_prompt = "Help me!",
              provider = "ollama",
          }
        }
    },
    -- ...
}
```
### Adding a new command

```lua
require("parrot").setup {
    -- ...
    hooks = {
      -- PrtAsk simply ask a question that should be answered short and precisely.
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
            parrot.logger.info("Asking agent: " .. agent.name)
            parrot.Prompt(params, parrot.ui.Target.popup, "🤖 Ask ~ ", agent.model, template, "", agent.provider)
      end,
    }
    -- ...
}
```

### Utilizing Template Placeholders

Users can utilize the following placeholders in their templates to inject
specific content into the user messages:

| Placeholder             | Content                              |
|-------------------------|--------------------------------------|
| `{{selection}}`         | Current visual selection             |
| `{{filetype}}`          | Filetype of the current buffer       |
| `{{filepath}}`          | Full path of the current file        |
| `{{filecontent}}`       | Full content of the current buffer   |

Below is an example of how to use these placeholders in a completion hook, which
receives the full file context and the selected code snippet as input.


```lua
require("parrot").setup {
    -- ...
    hooks = {
    	CompleteFullContext = function(prt, params)
    	  local template = [[
          I have the following code from {{filename}}:

          ```{{filetype}}
          {{filecontent}}
          ```

          Please look at the following section specifically:
          ```{{filetype}}
          {{selection}}
          ```

          Please finish the code above carefully and logically.
          Respond just with the snippet of code that should be inserted.
          ]]
    	  local agent = prt.get_command_agent()
    	  prt.Prompt(params, prt.ui.Target.append, nil, agent.model, template, agent.system_prompt, agent.provider)
    	end,
    }
    -- ...
}
```

## Roadmap

- Add status line integration/ notifications for summary of tokens used or money spent
- Improve the documentation
- Create a tutorial video
- Reduce overall code complexity and improve robustness

## Contribution
Anyone is welcome to contribute to this project! If you have any ideas,
suggestions, or bug reports, please feel free to open an issue.

## FAQ

- I am getting errors realted to the state.
    > In case of a corrupted state, simply remove the file `~/.local/share/nvim/parrot/persisted/state.json`
- The completion is not working and I am getting errors.
    > Make sure you have enough API credits

## Related Projects

- [robitx/gp.nvim](https://github.com/Robitx/gp.nvim)
- [huynle/ogpt.nvim](https://github.com/huynle/ogpt.nvim)
