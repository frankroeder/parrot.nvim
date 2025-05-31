local utils = require("parrot.utils")
local logger = require("parrot.logger")

---@class ResponseHandler
---@field buffer number
---@field window number
---@field ns_id number
---@field ex_id number
---@field first_line number
---@field finished_lines number
---@field response string
---@field prefix string
---@field cursor boolean
---@field hl_handler_group string
local ResponseHandler = {}
ResponseHandler.__index = ResponseHandler

---Creates a new ResponseHandler
---@param queries table
---@param buffer number|nil
---@param window number|nil
---@param line number|nil
---@param first_undojoin boolean|nil
---@param prefix string|nil
---@param cursor boolean
---@return ResponseHandler
function ResponseHandler:new(queries, buffer, window, line, first_undojoin, prefix, cursor)
  local self = setmetatable({}, ResponseHandler)
  self.buffer = buffer or vim.api.nvim_get_current_buf()
  self.window = window or vim.api.nvim_get_current_win()
  self.prefix = prefix or ""
  self.cursor = cursor or false
  self.first_line = line or (self.window and vim.api.nvim_win_get_cursor(self.window)[1] - 1 or 0)
  self.finished_lines = 0
  self.response = ""
  self.queries = queries
  self.skip_first_undojoin = not first_undojoin

  self.hl_handler_group = "PrtHandlerStandout"
  vim.api.nvim_set_hl(0, self.hl_handler_group, { link = "CursorLine" })

  self.ns_id = vim.api.nvim_create_namespace("PrtHandler_" .. utils.uuid())
  self.ex_id = vim.api.nvim_buf_set_extmark(self.buffer, self.ns_id, self.first_line, 0, {
    strict = false,
    right_gravity = false,
  })

  return self
end

---Handles a chunk of response
---@param qid any
---@param chunk string
function ResponseHandler:handle_chunk(qid, chunk)
  local qt = self.queries:get(qid)
  if not qt or not vim.api.nvim_buf_is_valid(self.buffer) then
    return
  end

  if not self.skip_first_undojoin then
    utils.undojoin(self.buffer)
  end
  self.skip_first_undojoin = false

  qt.ns_id = qt.ns_id or self.ns_id
  qt.ex_id = qt.ex_id or self.ex_id

  self.first_line = vim.api.nvim_buf_get_extmark_by_id(self.buffer, self.ns_id, self.ex_id, {})[1]

  local line_count = #vim.split(self.response, "\n")
  vim.api.nvim_buf_set_lines(
    self.buffer,
    self.first_line + self.finished_lines,
    self.first_line + line_count,
    false,
    {}
  )

  self:update_response(chunk)
  self:update_buffer()
  self:update_highlighting(qt)
  self:update_query_object(qt)
  self:move_cursor()
end

---Updates the response with a new chunk
---@param chunk string
function ResponseHandler:update_response(chunk)
  if chunk ~= nil then
    self.response = self.response .. chunk
    logger.debug("ResponseHandler:update_response", {
      response = self.response,
      chunk = chunk,
    })
    utils.undojoin(self.buffer)
  end
end

---Updates the buffer with the current response
function ResponseHandler:update_buffer()
  local lines = vim.split(self.response, "\n")
  local prefixed_lines = vim.tbl_map(function(l)
    return self.prefix .. l
  end, lines)
  logger.debug("ResponseHandler:update_buffer", {
    prefixed_lines = prefixed_lines,
    list_slice = vim.list_slice(prefixed_lines, self.finished_lines + 1),
  })
  vim.api.nvim_buf_set_lines(
    self.buffer,
    self.first_line + self.finished_lines,
    self.first_line + self.finished_lines,
    false,
    vim.list_slice(prefixed_lines, self.finished_lines + 1)
  )
end

---Updates the highlighting for new lines
---@param qt table
function ResponseHandler:update_highlighting(qt)
  local lines = vim.split(self.response, "\n")
  local new_finished_lines = math.max(0, #lines - 1)
  for i = self.finished_lines, new_finished_lines do
    vim.api.nvim_buf_add_highlight(self.buffer, qt.ns_id, self.hl_handler_group, self.first_line + i, 0, -1)
  end
  self.finished_lines = new_finished_lines
end

---Updates the query object with new line information
---@param qt table
function ResponseHandler:update_query_object(qt)
  local end_line = self.first_line + #vim.split(self.response, "\n")
  qt.first_line = self.first_line
  qt.last_line = end_line - 1
end

---Moves the cursor to the end of the response if needed
function ResponseHandler:move_cursor()
  if self.cursor then
    local end_line = self.first_line + #vim.split(self.response, "\n")
    utils.cursor_to_line(end_line, self.buffer, self.window)
  end
end

---Creates a handler function
---@return function
function ResponseHandler:create_handler()
  return vim.schedule_wrap(function(qid, chunk)
    self:handle_chunk(qid, chunk)
  end)
end

return ResponseHandler
