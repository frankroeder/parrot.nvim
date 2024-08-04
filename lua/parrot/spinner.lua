local Spinner = {}
Spinner.__index = Spinner

--- Creates a new Spinner instance.
--- @param spinner_type string # The type of spinner to use.
--- @return table # A new Spinner instance.
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
  return instance
end

--- Starts the spinner with an optional message.
--- @param message string|nil # The message to display alongside the spinner, optional.
function Spinner:start(message)
  if self.timer then
    return
  end
  self.message = message or ""
  self.timer = vim.loop.new_timer()
  self.timer:start(
    0,
    self.interval,
    vim.schedule_wrap(function()
      self.current_frame = (self.current_frame % #self.pattern[self.spinner_type]) + 1
      self:draw()
    end)
  )
end

--- Stops the spinner and clears the display.
function Spinner:stop()
  if self.timer then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
    self:clear()
  end
end

--- Draws the current frame of the spinner.
function Spinner:draw()
  vim.api.nvim_echo(
    { { string.format("\r%s %s", self.pattern[self.spinner_type][self.current_frame], self.message), "None" } },
    false,
    {}
  )
  vim.cmd("redraw")
end

--- Clears the spinner display.
function Spinner:clear()
  vim.cmd('echon ""') -- Clear the current line
end

return Spinner
