# Gp.nvim (GPT prompt) Neovim AI plugin
> This is a personal fork that supports the www.perplexity.ai API. <br>
> See https://github.com/Robitx/gp.nvim for the original repository.

## Getting Started
### Setup
#### lazy.nvim
```lua
{
    "frankroeder/gp.nvim",
    cond = os.getenv "PERPLEXITY_API_KEY" ~= nil, -- OPTONAL
    config = function()
        require("gp").setup {
            api_key = os.getenv "PERPLEXITY_API_KEY",
        }
    end
}
```
