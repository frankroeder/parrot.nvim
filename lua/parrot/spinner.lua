local Spinner = {}
Spinner.__index = Spinner

-- Configuration for progress tracking
local PROGRESS_UPDATE_INTERVAL = 200 -- ms
local CHARS_PER_TOKEN = 4 -- Approximate characters per token for token estimation
local TOKEN_DISPLAY_DELAY = 3 -- Show token count only after this many seconds

--- Creates a new Spinner instance.
--- @param spinner_type string # The type of spinner to use.
--- @return table
function Spinner:new(spinner_type)
  local instance = setmetatable({}, self)
  instance.spinner_type = spinner_type
  instance.pattern = {
    ["dots"] = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    ["line"] = { "-", "\\", "|", "/" },
    ["star"] = { "✶", "✸", "✹", "✺", "✹", "✷" },
    ["bouncing_bar"] = {
      "[    ]",
      "[=   ]",
      "[==  ]",
      "[=== ]",
      "[ ===]",
      "[  ==]",
      "[   =]",
      "[    ]",
      "[   =]",
      "[  ==]",
      "[ ===]",
      "[====]",
      "[=== ]",
      "[==  ]",
      "[=   ]",
    },
    ["bouncing_ball"] = {
      "( ●    )",
      "(  ●   )",
      "(   ●  )",
      "(    ● )",
      "(     ●)",
      "(    ● )",
      "(   ●  )",
      "(  ●   )",
      "( ●    )",
      "(●     )",
    },
  }
  instance.interval = 80
  instance.current_frame = 1
  instance.timer = nil
  instance.message = ""

  -- Progress tracking fields
  instance.start_time = nil
  instance.processed_chunks = 0
  instance.bytes_received = 0
  instance.total_chars = 0
  instance.show_progress = false
  instance.is_stopped = false

  return instance
end

--- Starts the spinner with an optional message.
--- @param message string|nil # The message to display alongside the spinner, optional.
--- @param enable_progress boolean|nil # Whether to enable progress tracking.
function Spinner:start(message, enable_progress)
  if self.timer then
    return
  end

  self.message = message or ""
  self.show_progress = enable_progress or false
  self.start_time = vim.loop.hrtime()
  self.is_stopped = false

  -- Reset progress tracking
  self.processed_chunks = 0
  self.bytes_received = 0
  self.total_chars = 0

  self.timer = vim.uv.new_timer()
  local update_interval = self.show_progress and PROGRESS_UPDATE_INTERVAL or self.interval

  self.timer:start(
    0,
    update_interval,
    vim.schedule_wrap(function()
      if self.is_stopped then
        return
      end
      self.current_frame = (self.current_frame % #self.pattern[self.spinner_type]) + 1
      self:draw()
    end)
  )
end

--- Updates progress tracking with new chunk information.
--- @param chunk_size number # Size of the received chunk (character count).
function Spinner:update_progress(chunk_size)
  if not self.show_progress or self.is_stopped then
    return
  end

  self.processed_chunks = self.processed_chunks + 1
  self.bytes_received = self.bytes_received + (chunk_size or 0)
  self.total_chars = self.total_chars + (chunk_size or 0)
end

--- Stops the spinner and clears the display.
--- @param error_occurred boolean|nil # Whether the spinner is being stopped due to an error.
function Spinner:stop(error_occurred)
  self.is_stopped = true

  if self.timer then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
  end

  -- Show completion or error message briefly before clearing
  if error_occurred then
    self:show_final_message("❌ Request failed", "ErrorMsg")
  elseif self.show_progress then
    local elapsed = (vim.loop.hrtime() - self.start_time) / 1e9
    self:show_final_message(string.format("✓ Completed in %.1fs", elapsed), "DiagnosticOk")
  else
    self:clear()
  end
end

--- Shows a final message briefly before clearing.
--- @param message string # The message to show.
--- @param highlight string # The highlight group to use.
function Spinner:show_final_message(message, highlight)
  vim.api.nvim_echo({ { message, highlight } }, false, {})
  vim.cmd("redraw")

  -- Clear after a short delay
  vim.defer_fn(function()
    self:clear()
  end, 1500)
end

--- Draws the current frame of the spinner with progress information.
function Spinner:draw()
  if self.is_stopped then
    return
  end

  local spinner_char = self.pattern[self.spinner_type][self.current_frame]
  local message = self.message

  if self.show_progress then
    local elapsed = (vim.loop.hrtime() - self.start_time) / 1e9
    local parts = { spinner_char, message }

    -- Add elapsed time (always show after 1 second)
    if elapsed > 1 then
      table.insert(parts, string.format("%.1fs", elapsed))
    end

    -- Add token approximation only after the configured delay
    if elapsed > TOKEN_DISPLAY_DELAY and self.total_chars > 0 then
      local estimated_tokens = math.floor(self.total_chars / CHARS_PER_TOKEN)
      table.insert(parts, string.format("~%d tokens", estimated_tokens))
    end

    message = table.concat(parts, " ")
  else
    message = string.format("%s %s", spinner_char, message)
  end

  vim.api.nvim_echo({ { string.format("\r%s", message), "None" } }, false, {})
  vim.cmd("redraw")
end

--- Clears the spinner display.
function Spinner:clear()
  vim.cmd('echon ""') -- Clear the current line
  vim.cmd("redraw")
end

return Spinner
