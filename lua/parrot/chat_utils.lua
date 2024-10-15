local ui = require("parrot.ui")
local utils = require("parrot.utils")

local M = {}

---@param params table | string # table with args or string args
---@return number # buf target
M.resolve_buf_target = function(params)
	local target = type(params) == "table" and (params.args or "") or params
  local target_map = {
    popup = ui.BufTarget.popup,
    split = ui.BufTarget.split,
    vsplit = ui.BufTarget.vsplit,
    tabnew = ui.BufTarget.tabnew,
  }
  return target_map[target] or ui.BufTarget.current
end

---@param buf number | nil
M.prep_md = function(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

  -- better text wrapping
  vim.api.nvim_command("setlocal wrap linebreak")
  -- auto save on TextChanged, InsertLeave
  vim.api.nvim_command("autocmd TextChanged,InsertLeave <buffer=" .. buf .. "> silent! write")

  -- register shortcuts local to this buffer
  buf = buf or vim.api.nvim_get_current_buf()

  -- ensure normal mode
  vim.api.nvim_command("stopinsert")
  utils.feedkeys("<esc>", "xn")
end

return M
