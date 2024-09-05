local ui = require("parrot.ui")
local utils = require("parrot.utils")

local M = {}

---@param params table | string # table with args or string args
---@return number # buf target
M.resolve_buf_target = function(params)
  local args = ""
  if type(params) == "table" then
    args = params.args or ""
  else
    args = params
  end

  if args == "popup" then
    return ui.BufTarget.popup
  elseif args == "split" then
    return ui.BufTarget.split
  elseif args == "vsplit" then
    return ui.BufTarget.vsplit
  elseif args == "tabnew" then
    return ui.BufTarget.tabnew
  else
    return ui.BufTarget.current
  end
end

---@param buf number | nil
M.prep_md = function(buf)
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
