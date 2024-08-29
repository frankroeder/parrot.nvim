local ui = require("parrot.ui")
local utils = require("parrot.utils")

local M = {}

---@param params table | string # table with args or string args
---@return number # buf target
M.resolve_buf_target = function(params)
  local args = type(params) == "table" and (params.args or "") or params
  local target_map = {
    popup = ui.BufTarget.popup,
    split = ui.BufTarget.split,
    vsplit = ui.BufTarget.vsplit,
    tabnew = ui.BufTarget.tabnew,
  }
  return target_map[args] or ui.BufTarget.current
end
-- response handler
---@param queries table
---@param buf number | nil # buffer to insert response into
---@param win number | nil # window to insert response into
---@param line number | nil # line to insert response into
---@param first_undojoin boolean | nil # whether to skip first undojoin
---@param prefix string | nil # prefix to insert before each response line
---@param cursor boolean # whether to move cursor to the end of the response
M.create_handler = function(queries, buf, win, line, first_undojoin, prefix, cursor)
  buf = buf or vim.api.nvim_get_current_buf()
  win = win or vim.api.nvim_get_current_win()
  prefix = prefix or ""
  local first_line = line or (vim.api.nvim_win_get_cursor(win)[1] - 1)
  local finished_lines = 0
  local skip_first_undojoin = not first_undojoin

  local hl_handler_group = "PrtHandlerStandout"
  vim.api.nvim_set_hl(0, hl_handler_group, { link = "CursorLine" })

  local ns_id = vim.api.nvim_create_namespace("PrtHandler_" .. utils.uuid())
  local ex_id = vim.api.nvim_buf_set_extmark(buf, ns_id, first_line, 0, {
    strict = false,
    right_gravity = false,
  })

  local response = ""

  local function update_buffer(qid, chunk)
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    vim.api.nvim_buf_call(buf, function()
      if not skip_first_undojoin then
        vim.cmd("undojoin")
      end
      skip_first_undojoin = false

      first_line = vim.api.nvim_buf_get_extmark_by_id(buf, ns_id, ex_id, {})[1]

      -- Clean previous response and append new chunk
      local line_count = #vim.split(response, "\n")
      vim.api.nvim_buf_set_lines(buf, first_line + finished_lines, first_line + line_count, false, {})
      response = response .. chunk
      vim.cmd("undojoin")

      -- Prepend prefix to each line and update buffer
      local lines = vim.tbl_map(function(l)
        return prefix .. l
      end, vim.split(response, "\n", { plain = true }))
      local unfinished_lines = vim.list_slice(lines, finished_lines + 1)
      vim.api.nvim_buf_set_lines(buf, first_line + finished_lines, first_line + finished_lines, false, unfinished_lines)

      -- Update highlighting
      local new_finished_lines = math.max(0, #lines - 1)
      for i = finished_lines, new_finished_lines - 1 do
        vim.api.nvim_buf_add_highlight(buf, ns_id, hl_handler_group, first_line + i, 0, -1)
      end
      finished_lines = new_finished_lines

      -- Update query table
      local end_line = first_line + #lines
      if queries:get(qid) then
        queries:get(qid).first_line = first_line
        queries:get(qid).last_line = end_line - 1
        queries:get(qid).ns_id = ns_id
        queries:get(qid).ex_id = ex_id
      end

      -- Move cursor if needed
      if cursor then
        utils.cursor_to_line(end_line, buf, win)
      end
    end)
  end

  return vim.schedule_wrap(function(qid, chunk)
    if not queries:get(qid) then
      return
    end
    update_buffer(qid, chunk)
  end)
end

---@param buf number | nil
M.prep_md = function(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local buf_options = {
    swapfile = false,
    filetype = "markdown",
  }
  local win_options = {
    wrap = true,
    linebreak = true,
  }
  for option, value in pairs(buf_options) do
    vim.api.nvim_buf_set_option(buf, option, value)
  end
  for option, value in pairs(win_options) do
    vim.api.nvim_win_set_option(0, option, value)
  end

  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
    buffer = buf,
    command = "silent! write",
  })

  vim.api.nvim_command("stopinsert")
  utils.feedkeys("<esc>", "xn")
end

return M
