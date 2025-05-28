<div align="center">

# parrot.nvim 🦜

This is [parrot.nvim](https://github.com/frankroeder/parrot.nvim), the ultimate [stochastic parrot](https://en.wikipedia.org/wiki/Stochastic_parrot) to support your text editing inside Neovim.

[Features](#features) • [Demo](#demo) • [Getting Started](#getting-started) • [Commands](#commands) • [Configuration](#configuration) • [Roadmap](#roadmap) • [FAQ](#faq)

<img src="https://github.com/frankroeder/parrot.nvim/assets/19746932/b19c5260-1713-400a-bd55-3faa87f4b509" alt="parrot.nvim logo" width="50%">
</div>

## Features

[parrot.nvim](https://github.com/frankroeder/parrot.nvim) offers a seamless out-of-the-box experience, providing tight integration of current LLM APIs into your Neovim workflows, with a focus solely on text generation.
The selected core features include on-demand text completion and editing, as well as chat-like sessions within native Neovim buffers.
While this project is still under development, a substantial part of the code is based on an early fork of the brilliant work by Tibor Schmidt's [gp.nvim](https://github.com/Robitx/gp.nvim).

- Persistent conversations stored as markdown files within Neovim's standard path or a user-defined location
- Custom hooks for inline text editing based on user instructions and chats with predefined system prompts
- Unified provider system supporting any OpenAI-compatible API:
    + [OpenAI API](https://platform.openai.com/)
    + [Anthropic API](https://www.anthropic.com/api)
    + [Google Gemini API](https://ai.google.dev/gemini-api/docs)
    + [xAI API](https://console.x.ai)
    + Local and offline serving via [ollama](https://github.com/ollama/ollama)
    + Any custom OpenAI-compatible endpoint with configurable functions; also supports [Perplexity.ai API](https://blog.perplexity.ai/blog/introducing-pplx-api), [Mistral API](https://docs.mistral.ai/api/), [Groq API](https://console.groq.com), [DeepSeek API](https://platform.deepseek.com), [GitHub Models](https://github.com/marketplace/models), and [NVIDIA API](https://docs.api.nvidia.com)
- Flexible API credential management from various sources:
    + Environment variables
    + Bash commands
    + Password manager CLIs (lazy evaluation)
- Repository-specific instructions via `.parrot.md` file using the `PrtContext` command
- **No** autocompletion and **no** hidden requests in the background to analyze your files


## Demo

Seamlessly switch between providers and models.
<div align="left">
    <p>https://github.com/user-attachments/assets/0df0348f-85c0-4a2d-ba1f-ede2738c6d02</p>
</div>

---

Trigger code completions based on comments.
<div align="left">
    <p>https://github.com/user-attachments/assets/197f99ac-9854-4fe9-bddb-394c1b64f6b6</p>
</div>

---

Let the parrot fix your bugs.
<div align="left">
    <p>https://github.com/user-attachments/assets/d3a0b261-a9dd-45e6-b508-dc5280594b06</p>
</div>

---

<details>
<summary>Rewrite a visual selection with `PrtRewrite`.</summary>
<div align="left">
    <p>https://github.com/user-attachments/assets/c3d38702-7558-4e9e-96a3-c43312a543d0</p>
</div>
</details>

---

<details>
<summary>Append code with the visual selection as context with `PrtAppend`.</summary>
<div align="left">
    <p>https://github.com/user-attachments/assets/80af02fa-cd88-4023-8a55-f2d3c0a2f28e</p>
</div>
</details>

---

<details>
<summary>Add comments to a function with `PrtPrepend`.</summary>
<div align="left">
    <p>https://github.com/user-attachments/assets/9a6bfe66-4bc7-4b63-8694-67bf9c23c064</p>
</div>
</details>

---

<details>
<summary>Retry your latest rewrite, append or prepend with `PrtRetry`.</summary>
<div align="left">
    <p>https://github.com/user-attachments/assets/03442f34-687b-482e-b7f1-7812f70739cc</p>
</div>
</details>

## Getting Started

### Dependencies

This plugin requires the latest version of Neovim and relies on a carefully selected set of established plugins.

- [`neovim 0.10+`](https://github.com/neovim/neovim/releases)
- [`plenary`](https://github.com/nvim-lua/plenary.nvim)
- [`ripgrep`](https://github.com/BurntSushi/ripgrep) (optional)
- [`fzf`](https://github.com/junegunn/fzf) (optional, requires ripgrep)
- [`telescope`](https://github.com/nvim-telescope/telescope.nvim) (optional)

### Installation

<details>
  <summary>lazy.nvim</summary>


```lua
{
  "frankroeder/parrot.nvim",
  dependencies = { "ibhagwan/fzf-lua", "nvim-lua/plenary.nvim" },
  opts = {}
}
```

</details>

<details>
  <summary>Packer</summary>

```lua
require("packer").startup(function()
  use({
    "frankroeder/parrot.nvim",
    requires = { 'ibhagwan/fzf-lua', 'nvim-lua/plenary.nvim'},
    config = function()
      require("parrot").setup()
    end,
  })
end)
```

</details>

<details>
  <summary>Neovim native package</summary>

```sh
git clone --depth=1 https://github.com/frankroeder/parrot.nvim.git \
  "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/pack/parrot/start/parrot.nvim
```

</details>

### Setup

The minimal requirement is to at least set up one provider, hence one from the [provider configuration examples](#provider-configuration-examples).

```lua
{
  "frankroeder/parrot.nvim",
  dependencies = { 'ibhagwan/fzf-lua', 'nvim-lua/plenary.nvim' },
  -- optionally include "folke/noice.nvim" or "rcarriga/nvim-notify" for beautiful notifications
  config = function()
    require("parrot").setup {
      -- Providers must be explicitly set up to make them available.
      providers = {
        openai = {
          name = "openai",
          api_key = os.getenv "OPENAI_API_KEY",
          endpoint = "https://api.openai.com/v1/chat/completions",
          -- default parameters
          params = {
            chat = { temperature = 1.1, top_p = 1 },
            command = { temperature = 1.1, top_p = 1 },
          },
          -- model and parameters to create chat headline
          topic = {
            model = "gpt-4.1-nano",
            params = { max_completion_tokens = 64 },
          },
          -- model selection for `PrtModel`
          models ={
            "gpt-4o",
            "o4-mini",
            "gpt-4.1-nano",
          }
        },
      },
    }
  end,
}
```

## Commands

Below are the available commands that can be configured as keybindings.
These commands are included in the default setup.
Additional useful commands are implemented through hooks (see below).

### General
| Command                   | Description                                   |
| ------------------------- | ----------------------------------------------|
| `PrtChatNew <target>`     | Open a new chat                               |
| `PrtChatToggle <target>`  | Toggle chat (open last chat or new one)       |
| `PrtChatPaste <target>`   | Paste visual selection into the latest chat   |
| `PrtInfo`                 | Print plugin config                           |
| `PrtContext <target>`     | Edits the local context file                  |
| `PrtChatFinder`           | Fuzzy search chat files using fzf             |
| `PrtChatDelete`           | Delete the current chat file                  |
| `PrtChatRespond`          | Trigger chat respond (in chat file)           |
| `PrtStop`                 | Interrupt ongoing respond                     |
| `PrtProvider <provider>`  | Switch the provider (empty arg triggers fzf)  |
| `PrtModel <model>`        | Switch the model (empty arg triggers fzf)     |
| `PrtStatus`               | Prints current provider and model selection   |
| `PrtThinking`             | Toggle or configure thinking mode for supported providers    |
| `PrtCmd <optional prompt>` | Directly generate executable Neovim commands (requires explicit Return to execute) |
|  __Interactive__          | |
| `PrtRewrite <optional prompt>` | Rewrites the visual selection based on a provided prompt (direct input, input dialog or from collection) |
| `PrtEdit`                 | Like `PrtRewrite` but you can change the last prompt |
| `PrtAppend <optional prompt>` | Append text to the visual selection based on a provided prompt (direct input, input dialog or from collection) |
| `PrtPrepend <optional prompt>` | Prepend text to the visual selection based on a provided prompt (direct input, input dialog or from collection) |
| `PrtNew`                  | Prompt the model to respond in a new window   |
| `PrtEnew`                 | Prompt the model to respond in a new buffer   |
| `PrtVnew`                 | Prompt the model to respond in a vsplit       |
| `PrtTabnew`               | Prompt the model to respond in a new tab      |
| `PrtRetry`                | Repeats the last rewrite/append/prepend       |
|  __Example Hooks__        | |
| `PrtImplement`            | Takes the visual selection as prompt to generate code |
| `PrtAsk`                  | Ask the model a question                      |

With `<target>`, we indicate the command to open the chat within one of the following target locations (defaults to `toggle_target`):

- `popup`: open a popup window which can be configured via the options provided below
- `split`: open the chat in a horizontal split
- `vsplit`: open the chat in a vertical split
- `tabnew`: open the chat in a new tab

All chat commands (`PrtChatNew, PrtChatToggle`) and custom hooks support the
visual selection to appear in the chat when triggered.
Interactive commands require the user to make use of the [template placeholders](#template-placeholders)
to consider a visual selection within an API request.

## Configuration

### Options

```lua
{
    -- The provider definitions include endpoints, API keys, default parameters,
    -- and topic model arguments for chat summarization. You can use any name
    -- for your providers and configure them with custom functions.
    providers = {
      openai = {
        api_key = os.getenv("OPENAI_API_KEY"),
        endpoint = "https://api.openai.com/v1/chat/completions",
        -- provide a small selection of models for `PrtProvider`
        model = {
          "gpt-4o",
          "o4-mini"
        },
        topic_prompt = "Summarize the topic of our conversation above in three or four words. Respond only with those words.",
        topic = {
          model = "gpt-4.1-nano",
          params = { max_completion_tokens = 64 },
        },
        params = {
          chat = { temperature = 1.1, top_p = 1 },
          command = { temperature = 1.1, top_p = 1 },
        },
      },
      -- Example with custom functions for non-OpenAI APIs
      my_custom_provider = {
        name = "my_custom_provider",
        api_key = os.getenv("MY_API_KEY"),
        -- OPTIONAL: Alternative methods to retrieve API key
        -- Using GPG for decryption:
        -- api_key = { "gpg", "--decrypt", vim.fn.expand("$HOME") .. "/my_api_key.txt.gpg" },
        -- Using macOS Keychain:
        -- api_key = { "/usr/bin/security", "find-generic-password", "-s my-api-key", "-w" },
        endpoint = "https://api.example.com/v1/chat/completions",
        model = { "model-1", "model-2" },
        -- Custom headers function
        headers = function(api_key)
          return {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. api_key,
            ["X-Custom-Header"] = "custom-value",
          }
        end,
        -- Custom payload preprocessing
        preprocess_payload = function(payload)
          -- Modify payload for your API format
          return payload
        end,
        -- Custom response processing
        process_stdout = function(response)
          -- Parse streaming response from your API
          local success, decoded = pcall(vim.json.decode, response)
          if success and decoded.content then
            return decoded.content
          end
        end,
      },
      ...
    }

    -- default system prompts used for the chat sessions and the command routines
    system_prompt = {
      chat = ...,
      command = ...
    },

    -- the prefix used for all commands
    cmd_prefix = "Prt",

    -- optional parameters for curl
    curl_params = {},

    -- The directory to store persisted state information like the
    -- current provider and the selected models
    state_dir = vim.fn.stdpath("data"):gsub("/$", "") .. "/parrot/persisted",

    -- The directory to store the chats (searched with PrtChatFinder)
    chat_dir = vim.fn.stdpath("data"):gsub("/$", "") .. "/parrot/chats",

    -- Chat user prompt prefix
    chat_user_prefix = "🗨:",

    -- llm prompt prefix
    llm_prefix = "🦜:",

    -- Explicitly confirm deletion of a chat file
    chat_confirm_delete = true,

    -- Local chat buffer shortcuts
    chat_shortcut_respond = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g><C-g>" },
    chat_shortcut_delete = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>d" },
    chat_shortcut_stop = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>s" },
    chat_shortcut_new = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>c" },

    -- Option to move the cursor to the end of the file after finished respond
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

    -- Prompt used for interactive LLM calls like PrtRewrite where {{llm}} is
    -- a placeholder for the llm name
    command_prompt_prefix_template = "🤖 {{llm}} ~ ",

    -- auto select command response (easier chaining of commands)
    -- if false it also frees up the buffer cursor for further editing elsewhere
    command_auto_select_response = true,

    -- fzf_lua options for PrtModel and PrtChatFinder when plugin is installed
    fzf_lua_opts = {
        ["--ansi"] = true,
        ["--sort"] = "",
        ["--info"] = "inline",
        ["--layout"] = "reverse",
        ["--preview-window"] = "nohidden:right:75%",
    },

    -- Enables the query spinner animation 
    enable_spinner = true,
    -- Type of spinner animation to display while loading
    -- Available options: "dots", "line", "star", "bouncing_bar", "bouncing_ball"
    spinner_type = "star",
    -- Show hints for context added through completion with @file, @buffer or @directory
    show_context_hints = true
    -- Controls visibility of the thinking window
    show_thinking_window = true,
}
```

#### Demonstrations

<details>
<summary>With <code>user_input_ui = "native"</code>, use <code>vim.ui.input</code> as slim input interface.</summary>
<div align="left">
    <p>https://github.com/user-attachments/assets/c2fe3bde-a35a-4f2a-957b-687e4f6f2e5c</p>
</div>
</details>

<details>
<summary>With <code>user_input_ui = "buffer"</code>, your input is simply a buffer. All of the content is passed to the API when closed.</summary>
<div align="left">
    <p>https://github.com/user-attachments/assets/63e6e1c4-a2ab-4c60-9b43-332e4b581360</p>
</div>
</details>

<details>
<summary>The spinner is a useful indicator for providers that take longer to respond.</summary>
<div align="left">
    <p>https://github.com/user-attachments/assets/ebcd27cb-da00-4150-a0f8-1d2e1afa0acb</p>
</div>
</details>


### Key Bindings

This plugin provides the following default key mappings:

| Keymap       | Description                                                 |
|--------------|-------------------------------------------------------------|
| `<C-g>c`     | Opens a new chat via `PrtChatNew`                           |
| `<C-g><C-g>` | Trigger the API to generate a response via `PrtChatRespond` |
| `<C-g>s`     | Stop the current text generation via `PrtStop`              |
| `<C-g>d`     | Delete the current chat file via `PrtChatDelete`            |

### Provider Configuration Examples

The unified provider system allows you to configure any OpenAI-compatible API provider. Below are examples for popular providers:

<details>
<summary>Anthropic Claude</summary>

```lua
providers = {
  anthropic = {
    name = "anthropic",
    endpoint = "https://api.anthropic.com/v1/messages",
    api_key = os.getenv "ANTHROPIC_API_KEY",
    params = {
      chat = { max_tokens = 4096 },
      command = { max_tokens = 4096 },
    },
    topic = {
      model = "claude-3-5-haiku-latest",
      params = { max_tokens = 32 },
    },
    models = {
      "claude-sonnet-4-20250514",
      "claude-opus-4-20250514",
      "claude-3-7-sonnet-20250219",
      "claude-3-5-sonnet-20241022",
      "claude-3-5-haiku-20241022",
      "claude-3-5-sonnet-20240620",
      "claude-3-haiku-20240307",
      "claude-3-opus-20240229",
      "claude-3-sonnet-20240229",
      "claude-2.1",
      "claude-2.0",
    },
    headers = function(api_key)
      return {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = api_key,
        ["anthropic-version"] = "2023-06-01",
      }
    end,
    preprocess_payload = function(payload)
      for _, message in ipairs(payload.messages) do
        message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
      end
      if payload.messages[1] and payload.messages[1].role == "system" then
        -- remove the first message that serves as the system prompt as Anthropic
        -- expects the system prompt to be part of the API call body and not the messages
        payload.system = payload.messages[1].content
        table.remove(payload.messages, 1)
      end
      return payload
    end,
    process_stdout  = function(response)
      local success, decoded_line = pcall(vim.json.decode, response)
      if not success then
        return nil
      end

      if decoded_line.delta then
        if decoded_line.delta.type == "text_delta" and decoded_line.delta.text then
          return decoded_line.delta.text
        end
      end

      return nil
    end
    get_available_models = function(self)
      local ids = self.models
      if self:verify() then
        local job = Job:new {
          command = "curl",
          args = {
            "https://api.anthropic.com/v1/models",
            "-H",
            "x-api-key: " .. self.api_key,
            "-H",
            "anthropic-version: 2023-06-01",
          },
          on_exit = function(job)
            local parsed_response = require("parrot.utils").parse_raw_response(job:result())
            self:process_onexit(parsed_response)
            ids = {}
            local success, decoded = pcall(vim.json.decode, parsed_response)
            if success and decoded.data then
              for _, item in ipairs(decoded.data) do
                table.insert(ids, item.id)
              end
            end
            return ids
          end,
        }
        job:start()
        job:wait()
      end
      return ids
    end,
  },
}
```
</details>

<details>
<summary>Google Gemini</summary>

```lua
providers = {
  gemini = {
    name = "gemini",
    endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:streamGenerateContent?alt=sse",
    api_key = os.getenv "GEMINI_API_KEY",
    params = {
      chat = { temperature = 1.1, topP = 1, topK = 10, maxOutputTokens = 8192 },
      command = { temperature = 0.8, topP = 1, topK = 10, maxOutputTokens = 8192 },
    },
    topic = {
      model = "gemini-1.5-flash",
      params = { maxOutputTokens = 64 },
    },
    headers = function(api_key)
      return {
        ["Content-Type"] = "application/json",
        ["x-goog-api-key"] = api_key,
      }
    end,
    models = {
      "gemini-2.5-flash-preview-05-20",
      "gemini-2.5-flash-preview-04-17",
      "gemini-2.5-pro-preview-05-06",
      "chat-bison-001",
      "text-bison-001",
      "gemini-1.5-pro-latest",
      "gemini-1.5-pro-001",
      "gemini-1.5-pro-002",
      "gemini-1.5-pro",
      "gemini-1.5-flash-latest",
      "gemini-1.5-flash-001",
      "gemini-1.5-flash-001-tuning",
      "gemini-1.5-flash",
      "gemini-1.5-flash-002",
      "gemini-1.5-flash-8b",
      "gemini-1.5-flash-8b-001",
      "gemini-1.5-flash-8b-latest",
      "gemini-1.5-flash-8b-exp-0827",
      "gemini-1.5-flash-8b-exp-0924",
      "gemini-2.5-pro-exp-03-25",
      "gemini-2.0-flash-exp",
      "gemini-2.0-flash",
      "gemini-2.0-flash-001",
      "gemini-2.0-flash-lite-001",
      "gemini-2.0-flash-lite",
      "gemini-2.0-flash-lite-preview-02-05",
      "gemini-2.0-flash-lite-preview",
      "gemini-2.0-pro-exp",
      "gemini-2.0-pro-exp-02-05",
      "gemini-exp-1206",
      "gemini-2.0-flash-thinking-exp-01-21",
      "gemini-2.0-flash-thinking-exp",
      "gemini-2.0-flash-thinking-exp-1219",
      "learnlm-1.5-pro-experimental",
      "learnlm-2.0-flash-experimental",
      "gemma-3-1b-it",
      "gemma-3-4b-it",
      "gemma-3-12b-it",
      "gemma-3-27b-it",
    },
    preprocess_payload = function(payload)
      local new_messages = {}
      for _, message in ipairs(payload.messages) do
        if message.role == "system" then
          payload.system_instruction = {
            parts = {
              text = (message.parts and message.parts.text or message.content):gsub(
                "^%s*(.-)%s*$",
                "%1"
              ),
            },
          }
        else
          local _role = message.role == "assistant" and "model" or message.role
          if message.content then
            table.insert(new_messages, {
              parts = { { text = message.content:gsub("^%s*(.-)%s*$", "%1") } },
              role = _role,
            })
          end
        end
      end
      payload.contents = vim.deepcopy(new_messages)
      return payload
    end,
    get_available_models = function(self)
      local ids = self.model
      if self:verify() then
        local job = Job:new {
          command = "curl",
          args = {
            "https://generativelanguage.googleapis.com/v1beta/models?key=" .. self.api_key,
          },
          on_exit = function(job)
            local parsed_response = require("parrot.utils").parse_raw_response(job:result())
            self:process_onexit(parsed_response)
            ids = {}
            local success, decoded = pcall(vim.json.decode, parsed_response)
            if success and decoded.models then
              for _, item in ipairs(decoded.models) do
                table.insert(ids, string.sub(item.name, 8))
              end
            end
          end,
        }
        job:start()
        job:wait()
      end
      return ids
    end,
  },
}
```
</details>

<details>
<summary>xAI</summary>

```lua
providers = {
  xai = {
    name = "xai",
    endpoint = "https://api.x.ai/v1/chat/completions",
    api_key = os.getenv "XAI_API_KEY",
    params = {
      chat = { temperature = 1.1, top_p = 1 },
      command = { temperature = 1.1, top_p = 1 },
    },
    topic = {
      model = "grok-3-mini-beta",
      params = { max_completion_tokens = 64 },
    },
    models = {
      "grok-3-beta",
      "grok-3-fast-beta",
      "grok-3-mini-beta",
      "grok-3-mini-fast-beta",
      "grok-2-1212",
      "grok-beta",
    },
    get_available_models = function(self)
      local ids = self.models
      if self:verify() then
        local job = Job:new {
          command = "curl",
          args = {
            "https://api.x.ai/v1/language-models",
            "-H",
            "Authorization: Bearer " .. self.api_key,
          },
          on_exit = function(job)
            local parsed_response = require("parrot.utils").parse_raw_response(job:result())
            self:process_onexit(parsed_response)
            ids = {}
            local success, decoded = pcall(vim.json.decode, parsed_response)
            if success and decoded.models then
              for _, item in ipairs(decoded.models) do
                table.insert(ids, item.id)
              end
            end
            return ids
          end,
        }
        job:start()
        job:wait()
      end
      return ids
    end,
  },
}
```
</details>

<details>
<summary>Ollama</summary>

```lua
providers = {
  ollama = {
    name = "ollama",
    endpoint = "http://localhost:11434/api/chat",
    api_key = "", -- not required for local Ollama
    params = {
      chat = { temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
      command = { temperature = 1.5, top_p = 1, num_ctx = 8192, min_p = 0.05 },
    },
    topic_prompt = [[
    Summarize the chat above and only provide a short headline of 2 to 3
    words without any opening phrase like "Sure, here is the summary",
    "Sure! Here's a shortheadline summarizing the chat" or anything similar.
    ]],
    topic = {
      model = "llama3.2",
      params = { max_tokens = 32 },
    },
    headers = {
      ["Content-Type"] = "application/json",
    },
    models = {
      "codestral",
      "llama3.2",
      "gemma3",
    },
    resolve_api_key = function()
      return true
    end,
    process_stdout = function(response)
      if response:match "message" and response:match "content" then
        local ok, data = pcall(vim.json.decode, response)
        if ok and data.message and data.message.content then
          return data.message.content
        end
      end
    end,
    get_available_models = function(self)
      local url = self.endpoint:gsub("chat", "")
      local logger = require "parrot.logger"
      local job = Job:new({
        command = "curl",
        args = { "-H", "Content-Type: application/json", url .. "tags" },
      }):sync()
      local parsed_response = require("parrot.utils").parse_raw_response(job)
      self:process_onexit(parsed_response)
      if parsed_response == "" then
        logger.debug("Ollama server not running on " .. endpoint_api)
        return {}
      end

      local success, parsed_data = pcall(vim.json.decode, parsed_response)
      if not success then
        logger.error("Ollama - Error parsing JSON: " .. vim.inspect(parsed_data))
        return {}
      end

      if not parsed_data.models then
        logger.error "Ollama - No models found. Please use 'ollama pull' to download one."
        return {}
      end

      local names = {}
      for _, model in ipairs(parsed_data.models) do
        table.insert(names, model.name)
      end

      return names
    end,
  },
}
```
</details>

### Adding a new command

#### Ask a single-turn question and receive the answer in a popup window

```lua
require("parrot").setup {
    -- ...
    hooks = {
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
    }
    -- ...
}
```

#### Start a chat with a predefined chat prompt to check your spelling.

```lua
require("parrot").setup {
    -- ...
    hooks = {
      SpellCheck = function(prt, params)
        local chat_prompt = [[
          Your task is to take the text provided and rewrite it into a clear,
          grammatically correct version while preserving the original meaning
          as closely as possible. Correct any spelling mistakes, punctuation
          errors, verb tense issues, word choice problems, and other
          grammatical mistakes.
        ]]
        prt.ChatNew(params, chat_prompt)
      end,
    }
    -- ...
}
```

Refer to my [personal lazy.nvim setup](https://github.com/frankroeder/dotfiles/blob/master/nvim/lua/plugins/parrot.lua) or
those of [other users](https://github.com/search?utf8=%E2%9C%93&q=frankroeder%2Fparrot.nvim+language%3ALua&type=code&l=Lua) for further hooks and key bindings.

### Prompt Collection

If you're repeatedly typing the same prompts into the input fields when using
`PrtRewrite`, `PrtAppend`, or `PrtPrepend`, a more lightweight alternative to
user commands (also known as hooks) is to define prompts as follows:
```lua
require("parrot").setup {
    -- ...
    prompts = {
        ["Spell"] = "I want you to proofread the provided text and fix the errors." -- e.g., :'<,'>PrtRewrite Spell
        ["Comment"] = "Provide a comment that explains what the snippet is doing." -- e.g., :'<,'>PrtPrepend Comment
        ["Complete"] = "Continue the implementation of the provided snippet in the file {{filename}}." -- e.g., :'<,'>PrtAppend Complete
    }
    -- ...
}
```
They will appear as arguments for the aforementioned interactive commands and
can also be used with the [template placeholders](#template-placeholders).

### Template Placeholders

Users can utilize the following placeholders in their hook and system templates to inject
additional context:

| Placeholder             | Content                              |
|-------------------------|--------------------------------------|
| `{{selection}}`         | Current visual selection             |
| `{{filetype}}`          | Filetype of the current buffer       |
| `{{filepath}}`          | Full path of the current file        |
| `{{filecontent}}`       | Full content of the current buffer   |
| `{{multifilecontent}}`  | Full content of all open buffers     |

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
        local model_obj = prt.get_model("command")
        prt.Prompt(params, prt.ui.Target.append, model_obj, nil, template)
      end,
    }
    -- ...
}
```

The placeholders `{{filetype}}` and  `{{filecontent}}` can also be used in the `chat_prompt` when
creating custom hooks calling `prt.ChatNew(params, chat_prompt)` to directly inject the whole file content.

```lua
require("parrot").setup {
    -- ...
      CodeConsultant = function(prt, params)
        local chat_prompt = [[
          Your task is to analyze the provided {{filetype}} code and suggest
          improvements to optimize its performance. Identify areas where the
          code can be made more efficient, faster, or less resource-intensive.
          Provide specific suggestions for optimization, along with explanations
          of how these changes can enhance the code's performance. The optimized
          code should maintain the same functionality as the original code while
          demonstrating improved efficiency.

          Here is the code
          ```{{filetype}}
          {{filecontent}}
          ```
        ]]
        prt.ChatNew(params, chat_prompt)
      end,
    }
    -- ...
}
```

## Completion

Instead of using the [template placeholders](#template-placeholders),
`parrot.nvim` supports inline completion via [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
and [blink.cmp](https://github.com/Saghen/blink.cmp/) for additional contexts:

- `@buffer:foo.txt` - Includes the content of the open buffer `foo.txt`
- `@file:test.lua` - Includes the content of the file `test.lua`
- `@directory:src/` - Includes all file contents from the directory `src/`

> Hint: The option `show_context_hints` allows you to transparently see notifications about the
actual file contents considered by the request. The completion keywords (e.g., `@file`) need to be placed
on a **new line**!

### Setup nvim-cmp

To enable `parrot.nvim` completions, add the source to your `nvim-cmp` configuration:

```lua
...
sources = cmp.config.sources({
  { name = "parrot" },
}),
...
```

### Setup blink.cmp

For `blink.cmp` you need to add `"parrot"` to the default sources and configure
the provider the following way:
```lua
...
parrot = {
    module = "parrot.completion.blink",
    name = "parrot",
    score_offset = 20,
    opts = {
        show_hidden_files = false,
        max_items = 50,
    }
},
...
```


## Thinking Mode

The `PrtThinking` command allows you to toggle or configure the "thinking" feature for providers that support it:

- `PrtThinking` - Toggle thinking on/off (default budget: 1024 tokens)
- `PrtThinking 2048` - Enable thinking with a specific budget of 2048 tokens
- `PrtThinking status` - Show current thinking settings

The thinking feature allows models to show their intermediate reasoning steps in a popup window
before providing a final response. Currently, this is fully implemented for the Anthropic provider,
but the framework supports adding this capability to other providers that can stream intermediate thinking steps.

## Statusline Support

Knowing the current chat or command model can be shown using your favorite statusline plugin.
Below, we provide an example for [lualine](https://github.com/nvim-lualine/lualine.nvim):

```lua
  -- define function and formatting of the information
  local function parrot_status()
    local status_info = require("parrot.config").get_status_info()
    local status = ""
    if status_info.is_chat then
      status = status_info.prov.chat.name
    else
      status = status_info.prov.command.name
    end
    return string.format("%s(%s)", status, status_info.model)
  end

  -- add to lueline section
  require('lualine').setup {
    sections = {
      lualine_a = { parrot_status }
  }

```

## Adding a custom provider
In case your provider is not available, there is an option to resuse a present
provider with a different endpoint and a custom selection of models.
For this, the `custom` provider needs to be added to the list of providers the following way:
```lua
  providers = {
    custom = {
      style = "openai",
      api_key = os.getenv "CUSTOM_API_KEY",
      endpoint = "https://api.openai.com/v1/chat/completions",
      models = {
        "gpt-4o-mini",
        "gpt-4o",
      },
      -- parameters to summarize chat
      topic = {
        model = "gpt-4o-mini",
        params = { max_completion_tokens = 64 },
      },
      -- default parameters
      params = {
        chat = { temperature = 1.1, top_p = 1 },
        command = { temperature = 1.1, top_p = 1 },
      },
    }
  }
```

## Bonus

Access parrot.nvim directly from your terminal:

```bash
command nvim -c "PrtChatNew"
```

Also works by piping content directly into the chat:

```bash
ls -l | command nvim - -c "normal ggVGy" -c ":PrtChatNew" -c "normal p"
```

## Roadmap

- Add status line integration/ notifications for summary of tokens used or money spent
- Improve the documentation
- Create a tutorial video
- Reduce overall code complexity and improve robustness

## FAQ

- I am encountering errors related to the state.
    > If the state is corrupted, simply delete the file `~/.local/share/nvim/parrot/persisted/state.json`.
- The completion feature is not functioning, and I am receiving errors.
    > Ensure that you have an adequate amount of API credits and examine the log file `~/.local/state/nvim/parrot.nvim.log` for any errors.
- I have discovered a bug, have a feature suggestion, or possess a general idea to enhance this project.
    > Everyone is invited to contribute to this project! If you have any suggestions, ideas, or bug reports, please feel free to submit an issue.

## Related Projects

- [parrot.nvim](https://github.com/frankroeder/parrot.nvim) is a fork of an earlier version of [robitx/gp.nvim](https://github.com/Robitx/gp.nvim), branching off the commit `607f94d361f36b8eabb148d95993604fdd74d901` in January 2024. Since then, a significant portion of the original code has been removed or rewritten, and this effort will continue until `parrot.nvim` evolves into its own independent version. The original `MIT` license has been retained and will be maintained.
- [huynle/ogpt.nvim](https://github.com/huynle/ogpt.nvim)
- The idea for `PrtCmd` was inspired by [exit.nvim](https://github.com/3v0k4/exit.nvim).

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=frankroeder/parrot.nvim&type=Date)](https://star-history.com/#frankroeder/parrot.nvim&Date)