local Spinner = {}
Spinner.__index = Spinner

function Spinner:new(spinner_type)
  self.spinner_type = spinner_type
  self.pattern = {
    ["dots"] = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    ["dots2"] = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
    ["dots3"] = {
      "⠋",
      "⠙",
      "⠚",
      "⠒",
      "⠂",
      "⠂",
      "⠒",
      "⠲",
      "⠴",
      "⠦",
      "⠖",
      "⠒",
      "⠐",
      "⠐",
      "⠒",
      "⠓",
      "⠋",
    },
    ["line"] = { "-", "\\", "|", "/" },
    ["pipe"] = { "┤", "┘", "┴", "└", "├", "┌", "┬", "┐" },
    ["star"] = { "✶", "✸", "✹", "✺", "✹", "✷" },
    ["flip"] = { "_", "_", "_", "-", "`", "`", "'", "´", "-", "_", "_", "_" },
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
    ["triangle"] = { "▲", "▶", "▼", "◀" },
    ["box_corners"] = { "◰", "◳", "◲", "◱" },
    ["tetrahedron"] = { "△", "▷", "▽", "◁" },
    ["pac_man"] = { "ᗧ", "ᗤ", "ᗣ", "ᗥ" },
  }
  self.interval = 80
  self.current_frame = 1
  self.timer = nil
  self.message = ""
  return self
end

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

function Spinner:stop()
  if self.timer then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
    self:clear()
  end
end

function Spinner:draw()
  vim.api.nvim_echo(
    { { string.format("\r%s %s", self.pattern[self.spinner_type][self.current_frame], self.message), "None" } },
    false,
    {}
  )
  vim.cmd("redraw")
end

function Spinner:clear()
  vim.cmd('echon ""') -- Clear the current line
end

return Spinner
