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
---@field spinner any
---@field chat_handler table
---@field params table
---@field model_obj table
---@field template string
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
---@param spinner any|nil Optional spinner for progress tracking
---@param chat_handler table|nil Reference to ChatHandler for edit functionality
---@param params table|nil Original command params for edit functionality
---@param model_obj table|nil Model object for edit functionality
---@param template string|nil Template for edit functionality
---@return PreviewResponseHandler
function PreviewResponseHandler:new(
  queries,
  buffer,
  window,
  target_type,
  start_line,
  end_line,
  prefix,
  options,
  spinner,
  chat_handler,
  params,
  model_obj,
  template
)
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
  self.spinner = spinner -- Optional spinner for progress tracking
  self.preview = Preview:new(options)
  self.chat_handler = chat_handler -- Reference to ChatHandler for edit functionality
  self.params = params -- Original command params for edit functionality
  self.model_obj = model_obj -- Model object for edit functionality
  self.template = template -- Template for edit functionality

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

    -- Update spinner progress if available
    if self.spinner then
      self.spinner:update_progress(#chunk)
    end
  end
end

--- Shows the preview and handles user decision
function PreviewResponseHandler:show_preview()
  local new_content = self:prepare_new_content()

  -- Get filename from buffer
  local filename = vim.api.nvim_buf_get_name(self.buffer)
  if filename and filename ~= "" then
    -- Get relative path if possible
    local cwd = vim.fn.getcwd()
    if filename:sub(1, #cwd) == cwd then
      filename = filename:sub(#cwd + 2) -- Remove cwd + separator
    end
  end

  self.preview:show_diff_preview(self.original_content, new_content, self.target_type, function()
    self:apply_changes()
  end, function()
    self:reject_changes()
  end, filename, self.start_line, self.end_line)
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
    response_length = #self.response,
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

--- Rejects the changes and prompts for edit
function PreviewResponseHandler:reject_changes()
  logger.debug("PreviewResponseHandler: Changes rejected")

  -- If we have chat_handler reference, implement edit functionality like PrtEdit
  if self.chat_handler and self.params and self.model_obj and self.template then
    -- Set up the parameters for re-prompting
    local edit_params = vim.deepcopy(self.params)
    edit_params.line1 = self.start_line
    edit_params.line2 = self.end_line
    edit_params.range = 2

    -- Get the target from the target_type
    local ui = require("parrot.ui")
    local target = ui.Target.rewrite
    if self.target_type == "append" then
      target = ui.Target.append
    elseif self.target_type == "prepend" then
      target = ui.Target.prepend
    end

    -- Get the last command from history
    local last_command = self.chat_handler.history.last_command or ""

    -- Use the same input method as PrtEdit
    local input_function = self.options.user_input_ui == "buffer" and require("parrot.ui").input
      or self.options.user_input_ui == "native" and vim.ui.input

    if input_function then
      input_function({ prompt = "🤖 Edit ~ ", default = last_command }, function(input)
        if not input or input == "" or input:match("^%s*$") then
          return
        end
        -- Update the history with the new command
        self.chat_handler.history.last_command = input
        -- Re-execute the prompt with the edited command
        self.chat_handler:prompt(edit_params, target, self.model_obj, nil, self.template, false)
      end)
    else
      logger.error("Invalid user input ui option: " .. self.options.user_input_ui)
    end
  else
    -- Fallback to simple rejection
    logger.warning("Edit functionality not available - missing chat_handler context")
  end

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
  return vim.schedule_wrap(function(_)
    -- Clean up the response (remove code fences, etc.)
    self.response = self
      .response
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
