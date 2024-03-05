# parrot.nvim 🦜

This is [parrot.nvim](https://github.com/frankroeder/parrot.nvim), the ultimate [stochastic parrot](https://en.wikipedia.org/wiki/Stochastic_parrot) to support your text editing inside Neovim.

<div align="center">
    <img src="https://github.com/frankroeder/parrot.nvim/assets/19746932/b19c5260-1713-400a-bd55-3faa87f4b509" alt="parrot.nvim logo" width="50%">
</div>

> ⚠️ This repository is work in progress and will undergo major changes in the near future. <br>
> It is based on the brilliant work by https://github.com/Robitx.

Currently, we support the following providers:
+ [Anthropic API](https://www.anthropic.com/api) for Claude-3 ❗
+ [perplexity.ai API](https://blog.perplexity.ai/blog/introducing-pplx-api)
+ [OpenAI API](https://platform.openai.com/)
+ Local and offline serving via [ollama](https://github.com/ollama/ollama)

I started this repository because a perplexity subscription provides $5 of API credits every month for free.
Instead of letting them go to waste, I modified my favorite GPT plugin, [gp.nvim](https://github.com/Robitx/gp.nvim), to meet my needs - a new Neovim plugin was born! 🔥

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

### lazy.nvim
```lua
{
    "frankroeder/parrot.nvim",
    -- OPTIONAL dependency
    -- dependencies = { "fzf-lua" }
    config = function()
        require("parrot").setup {
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
                }
                anthropic = {
                    api_key = os.getenv "ANTHROPIC_API_KEY",
                }
            },
        }
    end
}
```

## Configuration

### For now, refer to my personal lazy.nvim setup for custom hooks and key bindings.
https://github.com/frankroeder/dotfiles/blob/master/nvim/lua/plugins/parrot.lua

## Known Issues

- In case of a corrupted state, simply remove the file `~/.local/share/nvim/parrot/persisted/state.json`

more to come ...
