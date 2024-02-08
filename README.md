# pplx.nvim 
> ⚠️ This repository is work in progress and will undergo major changes in the near future. <br>
> It is based on the brilliant work by https://github.com/Robitx.

The ultimate LLM plugin to support your text editing through the [perplexity.ai API](https://blog.perplexity.ai/blog/introducing-pplx-api) and [OpenAI API](https://platform.openai.com/).
I started this repository because a perplexity subscription provides $5 of API credits every month for free.
Instead of letting those spoil, I changed my favorite GPT plugin [gp.nvim](https://github.com/Robitx/gp.nvim) for my needs - a new Neovim plugin is born 🔥.

<div align="left">
    <img src="https://github.com/frankroeder/pplx.nvim/assets/19746932/617ff685-ee41-48fe-ac9c-4645cfe587be" width="100%">
</div>

## Getting Started

### lazy.nvim
```lua
{
    "frankroeder/pplx.nvim",
    -- OPTONAL
    -- cond = os.getenv "OPENAI_API_KEY" ~= nil or os.getenv "PERPLEXITY_API_KEY" ~= nil,
    config = function()
        require("pplx").setup {
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
            },
        }
    end
}
```

## Configuration

### For now, refer to my personal lazy.nvim setup.
https://github.com/frankroeder/dotfiles/blob/3c00dc390e2499e5fe229a243455160fae3e3637/nvim/lua/plugins/pplx_nvim.lua

more to come ...
