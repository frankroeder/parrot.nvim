local utils = require("parrot.utils")
local logger = require("parrot.logger")
local Preview = require("parrot.preview")

---@class PreviewResponseHandler
---@field buffer number
---@field window number
---@field target_type string
---@field start_line number
---@field end_line number
---@field original_content string
---@field prefix string
---@field response string
---@field queries table
---@field preview Preview
---@field options table
local PreviewResponseHandler = {}
PreviewResponseHandler.__index = PreviewResponseHandler

--- Creates a new PreviewResponseHandler
---@param queries table
---@param buffer number
---@param window number
---@param target_type string Type of operation (rewrite, append, prepend)
---@param start_line number
---@param end_line number
---@param prefix string
---@param options table Plugin options
---@return PreviewResponseHandler
function PreviewResponseHandler:new(queries, buffer, window, target_type, start_line, end_line, prefix, options)
  local self = setmetatable({}, PreviewResponseHandler)
  self.buffer = buffer
  self.window = window
  self.target_type = target_type
  self.start_line = start_line
  self.end_line = end_line
  self.prefix = prefix or ""
  self.response = ""
  self.queries = queries
  self.options = options
  self.preview = Preview:new(options)
  
  -- Capture original content for diff
  self:capture_original_content()
  
  return self
end

--- Captures the original content that will be modified
function PreviewResponseHandler:capture_original_content()
  if self.target_type == "rewrite" then
    -- For rewrite, capture the selected lines
    local lines = vim.api.nvim_buf_get_lines(self.buffer, self.start_line - 1, self.end_line, false)
    self.original_content = table.concat(lines, "\n")
  elseif self.target_type == "append" then
    -- For append, original content is empty (we're adding after)
    self.original_content = ""
  elseif self.target_type == "prepend" then
    -- For prepend, original content is empty (we're adding before)
    self.original_content = ""
  end
end

--- Handles a chunk of response
---@param qid any
---@param chunk string
function PreviewResponseHandler:handle_chunk(qid, chunk)
  local qt = self.queries:get(qid)
  if not qt or not vim.api.nvim_buf_is_valid(self.buffer) then
    return
  end

  if chunk and chunk ~= "" then
    self.response = self.response .. chunk
    qt.response = self.response
  end
end

--- Shows the preview and handles user decision
function PreviewResponseHandler:show_preview()
  local new_content = self:prepare_new_content()
  
  self.preview:show_diff_preview(
    self.original_content,
    new_content,
    self.target_type,
    function() self:apply_changes() end,
    function() self:reject_changes() end
  )
end

--- Prepares the new content based on target type
---@return string
function PreviewResponseHandler:prepare_new_content()
  local response_lines = vim.split(self.response, "\n")
  local prefixed_lines = vim.tbl_map(function(line)
    return self.prefix .. line
  end, response_lines)
  
  if self.target_type == "rewrite" then
    return table.concat(prefixed_lines, "\n")
  elseif self.target_type == "append" then
    -- For append, show what will be added
    return table.concat(prefixed_lines, "\n")
  elseif self.target_type == "prepend" then
    -- For prepend, show what will be added
    return table.concat(prefixed_lines, "\n")
  end
  
  return self.response
end

--- Applies the changes to the buffer
function PreviewResponseHandler:apply_changes()
  logger.debug("PreviewResponseHandler: Applying changes", {
    target_type = self.target_type,
    start_line = self.start_line,
    end_line = self.end_line,
    response_length = #self.response
  })
  
  local response_lines = vim.split(self.response, "\n")
  local prefixed_lines = vim.tbl_map(function(line)
    return self.prefix .. line
  end, response_lines)
  
  -- Apply changes based on target type
  if self.target_type == "rewrite" then
    -- Replace the selected lines
    vim.api.nvim_buf_set_lines(self.buffer, self.start_line - 1, self.end_line, false, prefixed_lines)
  elseif self.target_type == "append" then
    -- Insert lines after the selection
    vim.api.nvim_buf_set_lines(self.buffer, self.end_line, self.end_line, false, prefixed_lines)
  elseif self.target_type == "prepend" then
    -- Insert lines before the selection
    vim.api.nvim_buf_set_lines(self.buffer, self.start_line - 1, self.start_line - 1, false, prefixed_lines)
  end
  
  -- Position cursor appropriately
  if self.target_type == "rewrite" then
    utils.cursor_to_line(self.start_line + #prefixed_lines - 1, self.buffer, self.window)
  elseif self.target_type == "append" then
    utils.cursor_to_line(self.end_line + #prefixed_lines, self.buffer, self.window)
  elseif self.target_type == "prepend" then
    utils.cursor_to_line(self.start_line + #prefixed_lines - 1, self.buffer, self.window)
  end
  
  -- Fire completion event
  vim.cmd("doautocmd User PrtPreviewApplied")
end

--- Rejects the changes (no-op for now)
function PreviewResponseHandler:reject_changes()
  logger.debug("PreviewResponseHandler: Changes rejected")
  vim.cmd("doautocmd User PrtPreviewRejected")
end

--- Creates a handler function for the response processing
---@return function
function PreviewResponseHandler:create_handler()
  return vim.schedule_wrap(function(qid, chunk)
    self:handle_chunk(qid, chunk)
  end)
end

--- Creates a completion handler that shows the preview
---@return function
function PreviewResponseHandler:create_completion_handler()
  return vim.schedule_wrap(function(qid)
    -- Clean up the response (remove code fences, etc.)
    self.response = self.response
      :gsub("^```[%w]*\n", "") -- Remove opening code fence
      :gsub("\n```$", "") -- Remove closing code fence
      :gsub("^%s+", "") -- Remove leading whitespace
      :gsub("%s+$", "") -- Remove trailing whitespace
    
    if self.response == "" then
      logger.warning("No content generated for preview")
      self:reject_changes()
      return
    end
    
    self:show_preview()
  end)
end

return PreviewResponseHandler