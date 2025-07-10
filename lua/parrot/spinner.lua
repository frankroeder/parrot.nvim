local Spinner = {}
Spinner.__index = Spinner

-- Configuration for progress tracking
local PROGRESS_UPDATE_INTERVAL = 200 -- ms
local ETA_CALCULATION_THRESHOLD = 3000 -- Start ETA calculation after 3 seconds
local PROGRESS_BAR_WIDTH = 20

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
  instance.total_chunks = 0
  instance.processed_chunks = 0
  instance.bytes_received = 0
  instance.last_update_time = nil
  instance.show_progress = false
  instance.estimated_total = nil
  instance.progress_samples = {}
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
  self.last_update_time = self.start_time
  self.is_stopped = false

  -- Reset progress tracking
  self.total_chunks = 0
  self.processed_chunks = 0
  self.bytes_received = 0
  self.progress_samples = {}

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
--- @param chunk_size number # Size of the received chunk.
function Spinner:update_progress(chunk_size)
  if not self.show_progress or self.is_stopped then
    return
  end

  self.processed_chunks = self.processed_chunks + 1
  self.bytes_received = self.bytes_received + (chunk_size or 0)

  local current_time = vim.loop.hrtime()
  local elapsed = (current_time - self.start_time) / 1e9 -- Convert to seconds

  -- Store progress samples for ETA calculation
  table.insert(self.progress_samples, {
    time = elapsed,
    chunks = self.processed_chunks,
    bytes = self.bytes_received,
  })

  -- Keep only recent samples (last 10 seconds)
  local cutoff_time = elapsed - 10
  self.progress_samples = vim.tbl_filter(function(sample)
    return sample.time > cutoff_time
  end, self.progress_samples)
end

--- Calculates estimated time remaining based on progress samples.
--- @return string|nil # Formatted ETA string or nil if not enough data.
function Spinner:calculate_eta()
  if not self.show_progress or #self.progress_samples < 2 then
    return nil
  end

  local current_time = (vim.loop.hrtime() - self.start_time) / 1e9
  if current_time < ETA_CALCULATION_THRESHOLD / 1000 then
    return nil -- Wait for more data
  end

  -- Calculate average processing rate from recent samples
  local oldest_sample = self.progress_samples[1]
  local latest_sample = self.progress_samples[#self.progress_samples]

  local time_diff = latest_sample.time - oldest_sample.time
  local chunk_diff = latest_sample.chunks - oldest_sample.chunks

  if time_diff <= 0 or chunk_diff <= 0 then
    return nil
  end

  local chunks_per_second = chunk_diff / time_diff

  -- Estimate remaining chunks (this is heuristic since we don't know the total)
  -- We'll use a simple model based on typical response sizes
  local estimated_total_chunks = math.max(50, self.processed_chunks * 2)
  local remaining_chunks = estimated_total_chunks - self.processed_chunks

  if remaining_chunks <= 0 then
    return "completing..."
  end

  local eta_seconds = remaining_chunks / chunks_per_second

  if eta_seconds < 60 then
    return string.format("~%ds", math.ceil(eta_seconds))
  elseif eta_seconds < 3600 then
    return string.format("~%dm %ds", math.floor(eta_seconds / 60), math.ceil(eta_seconds % 60))
  else
    return ">1h"
  end
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

--- Creates a progress bar visualization.
--- @return string # The progress bar string.
function Spinner:create_progress_bar()
  if not self.show_progress or self.processed_chunks == 0 then
    return ""
  end

  -- Simple heuristic progress calculation
  -- Since we don't know the total response size, we estimate based on typical patterns
  local estimated_progress = math.min(0.95, self.processed_chunks / 100) -- Max 95% until complete
  local filled_width = math.floor(estimated_progress * PROGRESS_BAR_WIDTH)
  local empty_width = PROGRESS_BAR_WIDTH - filled_width

  local filled = string.rep("█", filled_width)
  local empty = string.rep("░", empty_width)
  local percentage = math.floor(estimated_progress * 100)

  return string.format("[%s%s] %d%%", filled, empty, percentage)
end

--- Draws the current frame of the spinner with enhanced progress information.
function Spinner:draw()
  if self.is_stopped then
    return
  end

  local spinner_char = self.pattern[self.spinner_type][self.current_frame]
  local message = self.message

  if self.show_progress then
    local elapsed = (vim.loop.hrtime() - self.start_time) / 1e9
    local progress_bar = self:create_progress_bar()
    local eta = self:calculate_eta()

    local parts = { spinner_char, message }

    if progress_bar ~= "" then
      table.insert(parts, progress_bar)
    end

    -- Add timing information
    if elapsed > 1 then
      table.insert(parts, string.format("%.1fs", elapsed))
    end

    if eta then
      table.insert(parts, string.format("ETA: %s", eta))
    end

    -- Add chunk/byte info for very long operations
    if elapsed > 10 and self.processed_chunks > 0 then
      table.insert(parts, string.format("%d chunks", self.processed_chunks))
      if self.bytes_received > 1024 then
        table.insert(parts, string.format("%.1fKB", self.bytes_received / 1024))
      end
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
