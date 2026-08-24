--- Single-choice picker with a fzf-lua -> telescope -> vim.ui.select fallback chain.
local M = {}

--- Prompts the user to pick one of `items`.
---@param items table # list of strings to choose from
---@param opts table # { prompt = string, fzf_opts = table|nil }
---@param on_select fun(choice: string|nil) # called with the choice, or nil when aborted
M.select = function(items, opts, on_select)
  local has_fzf, fzf_lua = pcall(require, "fzf-lua")
  if has_fzf then
    -- Empty scratch buffers (popups, new chats) make fzf-lua's close() hit E749.
    local curbuf = vim.api.nvim_get_current_buf()
    if vim.api.nvim_buf_line_count(curbuf) == 0 then
      vim.api.nvim_buf_set_lines(curbuf, 0, -1, false, { "" })
    end
    fzf_lua.fzf_exec(items, {
      prompt = opts.prompt .. " ❯",
      no_hide = true,
      previewer = false,
      winopts = {
        split = false,
        preview = { hidden = true },
      },
      file_icons = false,
      git_icons = false,
      color_icons = false,
      fzf_opts = vim.tbl_extend("force", {}, opts.fzf_opts or {}, {
        ["--preview-window"] = "hidden",
      }),
      actions = {
        ["default"] = function(selected)
          vim.schedule(function()
            on_select(selected and selected[1])
          end)
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
