# parrot.nvim 🦜
> ⚠️ This repository is work in progress and will undergo major changes in the near future. <br>
> It is based on the brilliant work by https://github.com/Robitx.

The ultimate [stochastic parrot](https://en.wikipedia.org/wiki/Stochastic_parrot) to support your text editing inside neovim.
+ [perplexity.ai API](https://blog.perplexity.ai/blog/introducing-pplx-api)🦜
+ [OpenAI API](https://platform.openai.com/).
+ Local and offline serving via [ollama](https://github.com/ollama/ollama)

I started this repository because a perplexity subscription provides $5 of API credits every month for free.
Instead of letting those spoil, I changed my favorite GPT plugin [gp.nvim](https://github.com/Robitx/gp.nvim) for my needs - a new neovim plugin is born 🔥.

<div align="left">
    <img src="https://github.com/frankroeder/parrot.nvim/assets/19746932/617ff685-ee41-48fe-ac9c-4645cfe587be" width="100%">
</div>

## Getting Started

### lazy.nvim
```lua
{
    "frankroeder/parrot.nvim",
    -- OPTONAL
    -- cond = os.getenv "OPENAI_API_KEY" ~= nil or os.getenv "PERPLEXITY_API_KEY" ~= nil,
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
            },
        }
    end
}
```

## Configuration

### For now, refer to my personal lazy.nvim setup.
https://github.com/frankroeder/dotfiles/blob/master/nvim/lua/plugins/parrot.lua#L10-L182

more to come ...
