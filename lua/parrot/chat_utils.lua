local ui = require("parrot.ui")
local utils = require("parrot.utils")

local M = {}

-- Buffer target resolution
---@param params table | string # table with args or string args
---@return number # buf target
function M.resolve_buffer_target(params)
  local args = type(params) == "table" and (params.args or "") or params
  local target_map = {
    popup = ui.BufTarget.popup,
    split = ui.BufTarget.split,
    vsplit = ui.BufTarget.vsplit,
    tabnew = ui.BufTarget.tabnew,
  }
  return target_map[args] or ui.BufTarget.current
end

-- Response handler creation
---@param queries table # queries object
---@param buf number | nil # buffer to insert response into
---@param win number | nil # window to insert response into
---@param line number | nil # line to insert response into
---@param first_undojoin boolean | nil # whether to skip first undojoin
---@param prefix string | nil # prefix to insert before each response line
---@param cursor boolean # whether to move cursor to the end of the response
function M.create_handler(queries, buf, win, line, first_undojoin, prefix, cursor)
  buf = buf or vim.api.nvim_get_current_buf()
  prefix = prefix or ""
  local first_line = line or vim.api.nvim_win_get_cursor(win)[1] - 1
  local finished_lines = 0
  local skip_first_undojoin = not first_undojoin

  -- Set up highlighting
  local hl_handler_group = "PrtHandlerStandout"
  vim.cmd("highlight default link " .. hl_handler_group .. " CursorLine")

  -- Create namespace and extmark
  local ns_id = vim.api.nvim_create_namespace("PrtHandler_" .. utils.uuid())
  local ex_id = vim.api.nvim_buf_set_extmark(buf, ns_id, first_line, 0, {
    strict = false,
    right_gravity = false,
  })

  local response = ""

  return vim.schedule_wrap(function(qid, chunk)
    local qt = queries:get(qid)
    if not qt or not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    -- Handle undojoin
    if not skip_first_undojoin then
      utils.undojoin(buf)
    end
    skip_first_undojoin = false

    -- Set namespace and extmark IDs if not set
    qt.ns_id = qt.ns_id or ns_id
    qt.ex_id = qt.ex_id or ex_id

    first_line = vim.api.nvim_buf_get_extmark_by_id(buf, ns_id, ex_id, {})[1]

    -- Update response
    response = response .. chunk
    local lines = vim.split(response, "\n")
    local prefixed_lines = vim.tbl_map(function(l)
      return prefix .. l
    end, lines)

    -- Update buffer content
    vim.api.nvim_buf_set_lines(buf, first_line + finished_lines, first_line + #vim.split(response, "\n"), false, {})
    vim.api.nvim_buf_set_lines(
      buf,
      first_line + finished_lines,
      first_line + finished_lines,
      false,
      vim.list_slice(prefixed_lines, finished_lines + 1)
    )

    -- Update highlighting
    local new_finished_lines = math.max(0, #lines - 1)
    for i = finished_lines, new_finished_lines do
      vim.api.nvim_buf_add_highlight(buf, qt.ns_id, hl_handler_group, first_line + i, 0, -1)
    end
    finished_lines = new_finished_lines

    -- Update query object
    local end_line = first_line + #lines
    qt.first_line = first_line
    qt.last_line = end_line - 1

    -- Move cursor if needed
    if cursor then
      utils.cursor_to_line(end_line, buf, win)
    end
  end)
end

-- Markdown buffer preparation
---@param buf number | nil
function M.prepare_markdown_buffer(buf)
  buf = buf or vim.api.nvim_get_current_buf()

  -- Set buffer options
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

  -- Set text wrapping
  vim.api.nvim_command("setlocal wrap linebreak")

  -- Set up auto-save
  vim.api.nvim_command("autocmd TextChanged,InsertLeave <buffer=" .. buf .. "> silent! write")

  -- Ensure normal mode
  vim.api.nvim_command("stopinsert")
  utils.feedkeys("<esc>", "xn")
end

return M
