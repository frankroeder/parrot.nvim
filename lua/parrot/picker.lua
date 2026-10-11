--- Single-choice picker with a fzf-lua -> telescope -> vim.ui.select fallback chain.
local M = {}

--- Prompts the user to pick one of `items`.
---@param items table # list of strings to choose from
---@param opts table # { prompt = string, fzf_opts = table|nil }
---@param on_select fun(choice: string|nil) # called with the choice, or nil when aborted
M.select = function(items, opts, on_select)
  local has_fzf, fzf_lua = pcall(require, "fzf-lua")
  if has_fzf then
    fzf_lua.fzf_exec(items, {
      prompt = opts.prompt .. " ❯",
      fzf_opts = opts.fzf_opts,
      actions = {
        ["default"] = function(selected)
          on_select(selected and selected[1])
        end,
      },
    })
    return
  end

  if pcall(require, "telescope") then
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local conf = require("telescope.config").values

    pickers
      .new({}, {
        prompt_title = opts.prompt .. " ❯",
        finder = finders.new_table({ results = items }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(_, map)
          local confirm = function(prompt_bufnr)
            local entry = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            on_select(entry and (entry.value or entry[1]))
          end
          map("i", "<CR>", confirm)
          map("n", "<CR>", confirm)
          return true
        end,
      })
      :find()
    return
  end

  vim.ui.select(items, { prompt = opts.prompt .. ":" }, on_select)
end

return M
