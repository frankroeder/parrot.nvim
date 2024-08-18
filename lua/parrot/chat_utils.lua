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

-- response handler
---@param buf number | nil # buffer to insert response into
---@param win number | nil # window to insert response into
---@param line number | nil # line to insert response into
---@param first_undojoin boolean | nil # whether to skip first undojoin
---@param prefix string | nil # prefix to insert before each response line
---@param cursor boolean # whether to move cursor to the end of the response
M.create_handler = function(queries, buf, win, line, first_undojoin, prefix, cursor)
  buf = buf or vim.api.nvim_get_current_buf()
  prefix = prefix or ""
  local first_line = line or vim.api.nvim_win_get_cursor(win)[1] - 1
  local finished_lines = 0
  local skip_first_undojoin = not first_undojoin

  local hl_handler_group = "PrtHandlerStandout"
  vim.cmd("highlight default link " .. hl_handler_group .. " CursorLine")

  local ns_id = vim.api.nvim_create_namespace("PrtHandler_" .. utils.uuid())

  local ex_id = vim.api.nvim_buf_set_extmark(buf, ns_id, first_line, 0, {
    strict = false,
    right_gravity = false,
  })

  local response = ""
  return vim.schedule_wrap(function(qid, chunk)
    local qt = queries:get(qid)
    if not qt then
      return
    end
    -- if buf is not valid, stop
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    -- undojoin takes previous change into account, so skip it for the first chunk
    if skip_first_undojoin then
      skip_first_undojoin = false
    else
      utils.undojoin(buf)
    end

    if not qt.ns_id then
      qt.ns_id = ns_id
    end

    if not qt.ex_id then
      qt.ex_id = ex_id
    end

    first_line = vim.api.nvim_buf_get_extmark_by_id(buf, ns_id, ex_id, {})[1]

    -- clean previous response
    local line_count = #vim.split(response, "\n")
    vim.api.nvim_buf_set_lines(buf, first_line + finished_lines, first_line + line_count, false, {})

    -- append new response
    response = response .. chunk
    utils.undojoin(buf)

    -- prepend prefix to each line
    local lines = vim.split(response, "\n")
    for i, l in ipairs(lines) do
      lines[i] = prefix .. l
    end

    local unfinished_lines = {}
    for i = finished_lines + 1, #lines do
      table.insert(unfinished_lines, lines[i])
    end

    vim.api.nvim_buf_set_lines(buf, first_line + finished_lines, first_line + finished_lines, false, unfinished_lines)

    local new_finished_lines = math.max(0, #lines - 1)
    for i = finished_lines, new_finished_lines do
      vim.api.nvim_buf_add_highlight(buf, qt.ns_id, hl_handler_group, first_line + i, 0, -1)
    end
    finished_lines = new_finished_lines

    local end_line = first_line + #vim.split(response, "\n")
    qt.first_line = first_line
    qt.last_line = end_line - 1

    -- move cursor to the end of the response
    if cursor then
      utils.cursor_to_line(end_line, buf, win)
    end
  end)
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
