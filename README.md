# pplx.nvim 
> ⚠️ This repository is work in progress and will undergo major changes in the near future. <br>
> It is based on the brilliant work by https://github.com/Robitx

The ultimate LLM plugin to support your text editing through the perplexity.ai [API](https://blog.perplexity.ai/blog/introducing-pplx-api).
I started this repository because a perplexity subscription provides $5 of API credits every month for free.
Instead of letting those spoil, I changed my favorite GPT plugin [gp.nvim](https://github.com/Robitx/gp.nvim) for my needs - a new Neovim plugin is born 🔥.

## Getting Started
### Setup
#### lazy.nvim
```lua
{
    "frankroeder/pplx.nvim",
    cond = os.getenv "PERPLEXITY_API_KEY" ~= nil, -- OPTONAL
    config = function()
        require("pplx").setup {
            api_key = os.getenv "PERPLEXITY_API_KEY",
        }
    end
}
```

more to come ...
