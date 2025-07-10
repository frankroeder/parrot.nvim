local ui = require("parrot.ui")
local utils = require("parrot.utils")

local Preview = {}
Preview.__index = Preview

-- Configuration for diff highlighting
local DIFF_ADD_HL = "DiffAdd"
local DIFF_DELETE_HL = "DiffDelete"
local DIFF_CHANGE_HL = "DiffChange"

--- Creates a new Preview instance
---@param options table Plugin options
---@return Preview
function Preview:new(options)
  local self = setmetatable({}, Preview)
  self.options = options
  self.preview_buf = nil
  self.preview_win = nil
  self.close_fn = nil
  self.apply_fn = nil
  self.reject_fn = nil
  self.auto_apply_timer = nil
  return self
end

--- Creates a unified diff between old and new content
---@param old_lines table Original lines
---@param new_lines table Modified lines
---@return table Diff lines with metadata
function Preview:create_diff(old_lines, new_lines)
  local diff_lines = {}
  local old_idx = 1
  local new_idx = 1

  -- Simple line-by-line diff implementation
  while old_idx <= #old_lines or new_idx <= #new_lines do
    local old_line = old_lines[old_idx]
    local new_line = new_lines[new_idx]

    if old_line == new_line then
      -- Lines match - show context
      table.insert(diff_lines, {
        type = "context",
        content = string.format(" %s", old_line or ""),
        old_num = old_idx,
        new_num = new_idx,
      })
      old_idx = old_idx + 1
      new_idx = new_idx + 1
    elseif old_idx > #old_lines then
      -- Only new lines remaining - additions
      table.insert(diff_lines, {
        type = "add",
        content = string.format("+%s", new_line or ""),
        old_num = nil,
        new_num = new_idx,
      })
      new_idx = new_idx + 1
    elseif new_idx > #new_lines then
      -- Only old lines remaining - deletions
      table.insert(diff_lines, {
        type = "delete",
        content = string.format("-%s", old_line or ""),
        old_num = old_idx,
        new_num = nil,
      })
      old_idx = old_idx + 1
    else
      -- Lines differ - show as deletion + addition
      table.insert(diff_lines, {
        type = "delete",
        content = string.format("-%s", old_line),
        old_num = old_idx,
        new_num = nil,
      })
      table.insert(diff_lines, {
        type = "add",
        content = string.format("+%s", new_line),
        old_num = nil,
        new_num = new_idx,
      })
      old_idx = old_idx + 1
      new_idx = new_idx + 1
    end
  end

  return diff_lines
end

--- Applies syntax highlighting to the diff buffer
---@param buf number Buffer number
---@param diff_lines table Diff lines with metadata
function Preview:apply_diff_highlighting(buf, diff_lines)
  local ns_id = vim.api.nvim_create_namespace("ParrotPreviewDiff")

  for line_idx, diff_line in ipairs(diff_lines) do
    local hl_group = nil
    if diff_line.type == "add" then
      hl_group = DIFF_ADD_HL
    elseif diff_line.type == "delete" then
      hl_group = DIFF_DELETE_HL
    elseif diff_line.type == "change" then
      hl_group = DIFF_CHANGE_HL
    end

    if hl_group then
      vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx - 1, 0, {
        end_col = -1,
        hl_group = hl_group,
      })
    end
  end
end

--- Shows the preview window with diff content
---@param old_content string Original content
---@param new_content string Modified content
---@param target_type string Type of operation (rewrite, append, prepend)
---@param apply_callback function Function to call when applying changes
---@param reject_callback function Function to call when rejecting changes
function Preview:show_diff_preview(old_content, new_content, target_type, apply_callback, reject_callback)
  if not self.options.enable_preview_mode then
    -- Preview disabled, apply changes directly
    apply_callback()
    return
  end

  local old_lines = vim.split(old_content, "\n")
  local new_lines = vim.split(new_content, "\n")
  local diff_lines = self:create_diff(old_lines, new_lines)

  -- Prepare diff content for display
  local diff_content = {}
  local header = {
    string.format("=== %s Preview ===", target_type:upper()),
    string.format("Lines: %d -> %d", #old_lines, #new_lines),
    "",
    "Actions: [a]pply, [r]eject, [q]uit",
    "───────────────────────────────────",
    "",
  }

  vim.list_extend(diff_content, header)
  for _, diff_line in ipairs(diff_lines) do
    table.insert(diff_content, diff_line.content)
  end

  -- Calculate window size
  local editor_width = vim.api.nvim_get_option_value("columns", {})
  local editor_height = vim.api.nvim_get_option_value("lines", {})
  local width = math.min(self.options.preview_max_width or 120, editor_width - 4)
  local height = math.min(self.options.preview_max_height or 30, math.max(#diff_content + 2, editor_height - 8))

  -- Create preview buffer and window
  self.preview_buf, self.preview_win, self.close_fn = ui.create_popup(
    nil,
    "Parrot Preview - " .. target_type,
    function(w, h)
      return width, height, math.floor((h - height) / 2), math.floor((w - width) / 2)
    end,
    { on_leave = false, escape = true, persist = false },
    { border = self.options.preview_border or "rounded" }
  )

  -- Set buffer content and options
  vim.api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, diff_content)
  vim.api.nvim_set_option_value("modifiable", false, { buf = self.preview_buf })
  vim.api.nvim_set_option_value("readonly", true, { buf = self.preview_buf })
  vim.api.nvim_set_option_value("filetype", "diff", { buf = self.preview_buf })

  -- Apply diff highlighting (skip header lines)
  local header_lines = #header
  local adj_diff_lines = {}
  for i, diff_line in ipairs(diff_lines) do
    adj_diff_lines[i + header_lines] = diff_line
  end
  self:apply_diff_highlighting(self.preview_buf, adj_diff_lines)

  -- Store callbacks
  self.apply_fn = apply_callback
  self.reject_fn = reject_callback

  -- Set up keymaps
  self:setup_preview_keymaps()

  -- Auto-apply timer if enabled
  if self.options.preview_auto_apply and self.options.preview_timeout > 0 then
    self.auto_apply_timer = vim.loop.new_timer()
    self.auto_apply_timer:start(
      self.options.preview_timeout,
      0,
      vim.schedule_wrap(function()
        self:apply_changes()
      end)
    )
  end

  -- Show countdown if auto-apply is enabled
  if self.options.preview_auto_apply then
    self:show_countdown()
  end
end

--- Shows countdown for auto-apply
function Preview:show_countdown()
  if not self.auto_apply_timer or not self.preview_buf then
    return
  end

  local remaining = self.options.preview_timeout
  local countdown_timer = vim.loop.new_timer()

  countdown_timer:start(
    0,
    1000,
    vim.schedule_wrap(function()
      remaining = remaining - 1000
      if remaining <= 0 or not vim.api.nvim_buf_is_valid(self.preview_buf) then
        countdown_timer:stop()
        countdown_timer:close()
        return
      end

      -- Update header with countdown
      local countdown_line =
        string.format("Auto-apply in %ds... [a]pply now, [r]eject, [q]uit", math.ceil(remaining / 1000))
      vim.api.nvim_set_option_value("modifiable", true, { buf = self.preview_buf })
      vim.api.nvim_buf_set_lines(self.preview_buf, 3, 4, false, { countdown_line })
      vim.api.nvim_set_option_value("modifiable", false, { buf = self.preview_buf })
    end)
  )
end

--- Sets up keyboard shortcuts for the preview window
function Preview:setup_preview_keymaps()
  local opts = { noremap = true, silent = true, buffer = self.preview_buf }

  -- Apply changes
  vim.keymap.set("n", "a", function()
    self:apply_changes()
  end, opts)
  vim.keymap.set("n", "<CR>", function()
    self:apply_changes()
  end, opts)

  -- Reject changes
  vim.keymap.set("n", "r", function()
    self:reject_changes()
  end, opts)
  vim.keymap.set("n", "<BS>", function()
    self:reject_changes()
  end, opts)

  -- Quit/close preview
  vim.keymap.set("n", "q", function()
    self:close_preview()
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    self:close_preview()
  end, opts)
  vim.keymap.set("n", "<C-c>", function()
    self:close_preview()
  end, opts)
end

--- Applies the changes and closes the preview
function Preview:apply_changes()
  if self.apply_fn then
    self.apply_fn()
  end
  self:cleanup()
end

--- Rejects the changes and closes the preview
function Preview:reject_changes()
  if self.reject_fn then
    self.reject_fn()
  end
  self:cleanup()
end

--- Closes the preview without applying changes
function Preview:close_preview()
  self:reject_changes()
end

--- Cleans up timers and closes preview window
function Preview:cleanup()
  -- Stop auto-apply timer
  if self.auto_apply_timer then
    self.auto_apply_timer:stop()
    self.auto_apply_timer:close()
    self.auto_apply_timer = nil
  end

  -- Close preview window
  if self.close_fn then
    self.close_fn()
  end

  -- Reset state
  self.preview_buf = nil
  self.preview_win = nil
  self.close_fn = nil
  self.apply_fn = nil
  self.reject_fn = nil
end

return Preview
