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
---@field chunk_buffer string
---@field update_timer any
---@field pending_chunks boolean
---@field last_update_time number
local ResponseHandler = {}
ResponseHandler.__index = ResponseHandler

-- Configuration for buffering and debouncing
local BUFFER_TIMEOUT_MS = 16 -- ~60fps
local MIN_CHUNK_SIZE = 10 -- minimum characters to trigger immediate update
local MAX_BUFFER_SIZE = 1000 -- maximum characters to buffer before forced update

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

  -- Buffering and debouncing fields
  self.chunk_buffer = ""
  self.update_timer = nil
  self.pending_chunks = false
  self.last_update_time = 0

  self.hl_handler_group = "PrtHandlerStandout"
  vim.api.nvim_set_hl(0, self.hl_handler_group, { link = "CursorLine" })

  self.ns_id = vim.api.nvim_create_namespace("PrtHandler_" .. utils.uuid())
  self.ex_id = vim.api.nvim_buf_set_extmark(self.buffer, self.ns_id, self.first_line, 0, {
    strict = false,
    right_gravity = false,
  })

  return self
end

---Handles a chunk of response with buffering and debouncing
---@param qid any
---@param chunk string
function ResponseHandler:handle_chunk(qid, chunk)
  local qt = self.queries:get(qid)
  if not qt or not vim.api.nvim_buf_is_valid(self.buffer) then
    return
  end

  -- Add chunk to buffer
  if chunk and chunk ~= "" then
    self.chunk_buffer = self.chunk_buffer .. chunk
    self.response = self.response .. chunk
    self.pending_chunks = true

    qt.ns_id = qt.ns_id or self.ns_id
    qt.ex_id = qt.ex_id or self.ex_id
    qt.response = self.response
  end

  -- Determine if we should update immediately or wait
  local should_update_immediately = false
  local current_time = vim.loop.hrtime() / 1000000 -- Convert to milliseconds

  -- Force update if chunk buffer is too large
  if #self.chunk_buffer >= MAX_BUFFER_SIZE then
    should_update_immediately = true
  end

  -- Force update if chunk contains newlines (likely end of sentence/paragraph)
  if chunk and chunk:find("\n") then
    should_update_immediately = true
  end

  -- Force update if chunk is large enough
  if chunk and #chunk >= MIN_CHUNK_SIZE then
    should_update_immediately = true
  end

  if should_update_immediately then
    self:flush_updates(qid)
  else
    -- Schedule a debounced update
    self:schedule_update(qid)
  end
end

---Schedule a debounced update
---@param qid any
function ResponseHandler:schedule_update(qid)
  -- Cancel existing timer if it exists
  if self.update_timer then
    self.update_timer:stop()
    self.update_timer:close()
  end

  -- Schedule new update
  self.update_timer = vim.loop.new_timer()
  self.update_timer:start(
    BUFFER_TIMEOUT_MS,
    0,
    vim.schedule_wrap(function()
      if self.pending_chunks then
        self:flush_updates(qid)
      end
      if self.update_timer then
        self.update_timer:close()
        self.update_timer = nil
      end
    end)
  )
end

---Flush all pending updates to the buffer
---@param qid any
function ResponseHandler:flush_updates(qid)
  if not self.pending_chunks or not vim.api.nvim_buf_is_valid(self.buffer) then
    return
  end

  local qt = self.queries:get(qid)
  if not qt then
    return
  end

  -- Cancel any pending timer
  if self.update_timer then
    self.update_timer:stop()
    self.update_timer:close()
    self.update_timer = nil
  end

  -- Perform batch update
  if not self.skip_first_undojoin then
    utils.undojoin(self.buffer)
  end
  self.skip_first_undojoin = false

  -- Safely get extmark position with fallback
  local extmark_pos = vim.api.nvim_buf_get_extmark_by_id(self.buffer, self.ns_id, self.ex_id, {})
  if extmark_pos and #extmark_pos > 0 then
    self.first_line = extmark_pos[1]
  elseif not self.first_line then
    -- Fallback to current cursor position if extmark is lost
    if self.window and vim.api.nvim_win_is_valid(self.window) then
      local cursor_pos = vim.api.nvim_win_get_cursor(self.window)
      self.first_line = math.max(0, cursor_pos[1] - 1)
    else
      -- Ultimate fallback - use end of buffer
      self.first_line = vim.api.nvim_buf_line_count(self.buffer)
    end
  end

  -- Clear previous response lines to avoid duplication
  local line_count = #vim.split(self.response, "\n")
  vim.api.nvim_buf_set_lines(
    self.buffer,
    self.first_line + self.finished_lines,
    self.first_line + line_count,
    false,
    {}
  )

  self:update_buffer()
  self:update_highlighting(qt)
  self:update_query_object(qt)
  self:move_cursor()

  -- Reset buffer state
  self.chunk_buffer = ""
  self.pending_chunks = false
  self.last_update_time = vim.loop.hrtime() / 1000000
end

---Updates the buffer with the current response
function ResponseHandler:update_buffer()
  -- Safety check for first_line
  if not self.first_line then
    return
  end

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

---Updates the highlighting for new lines (batch operation)
---@param qt table
function ResponseHandler:update_highlighting(qt)
  -- Safety check for first_line
  if not self.first_line then
    return
  end

  local lines = vim.split(self.response, "\n")
  local new_finished_lines = math.max(0, #lines - 1)

  -- Batch highlight updates to reduce flicker
  if new_finished_lines > self.finished_lines then
    -- Clear existing highlights in the range to avoid duplicates
    vim.api.nvim_buf_clear_namespace(
      self.buffer,
      qt.ns_id,
      self.first_line + self.finished_lines,
      self.first_line + new_finished_lines + 1
    )

    -- Add highlights for the new range
    for i = self.finished_lines, new_finished_lines do
      vim.api.nvim_buf_add_highlight(self.buffer, qt.ns_id, self.hl_handler_group, self.first_line + i, 0, -1)
    end
  end

  self.finished_lines = new_finished_lines
end

---Updates the query object with new line information
---@param qt table
function ResponseHandler:update_query_object(qt)
  -- Safety check for first_line
  if not self.first_line then
    return
  end

  local end_line = self.first_line + #vim.split(self.response, "\n")
  qt.first_line = self.first_line
  qt.last_line = end_line - 1
end

---Moves the cursor to the end of the response if needed
function ResponseHandler:move_cursor()
  if self.cursor and self.first_line then
    local end_line = self.first_line + #vim.split(self.response, "\n")
    utils.cursor_to_line(end_line, self.buffer, self.window)
  end
end

---Cleanup method to ensure timers are properly closed
function ResponseHandler:cleanup()
  if self.update_timer then
    self.update_timer:stop()
    self.update_timer:close()
    self.update_timer = nil
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
