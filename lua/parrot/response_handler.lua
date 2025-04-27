local utils = require("parrot.utils")
local logger = require("parrot.logger")
local api = vim.api

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
---@field typing_speed number
---@field word_delay number
---@field markdown_ns number
---@field hl_groups table
local ResponseHandler = {}
ResponseHandler.__index = ResponseHandler

-- Default highlight groups
local default_hl_groups = {
  text = "Normal",
  code = "Comment",
  code_block = "@text.literal",
  heading = "Title",
  emphasis = "@text.emphasis",
  strong = "@text.strong",
  typing = "PrtTyping",
}

---Creates a new ResponseHandler
---@param queries table
---@param buffer number|nil
---@param window number|nil
---@param line number|nil
---@param first_undojoin boolean|nil
---@param prefix string|nil
---@param cursor boolean
---@return ResponseHandler
---Creates a new ResponseHandler
---@param queries table
---@param buffer number|nil
---@param window number|nil
---@param line number|nil
---@param first_undojoin boolean|nil
---@param prefix string|nil
---@param cursor boolean
---@return ResponseHandler
function ResponseHandler:new(queries, buffer, window, line, first_undojoin, prefix, cursor, is_rewrite)
  local self = setmetatable({}, ResponseHandler)
  self.buffer = buffer or api.nvim_get_current_buf()
  self.window = window or api.nvim_get_current_win()
  self.prefix = prefix or ""
  self.cursor = cursor or false
  self.first_line = line or (self.window and api.nvim_win_get_cursor(self.window)[1] - 1 or 0)
  self.finished_lines = 0
  self.response = ""
  self.current_line = ""
  self.queries = queries
  self.skip_first_undojoin = not first_undojoin
  self.typing_speed = 10 -- ms between characters
  self.word_delay = 30 -- ms between words
  self.first_chunk = true -- Track first chunk for interactive commands
  self.is_rewrite = is_rewrite -- Track if this is a rewrite command

  -- Initialize highlight groups
  self.hl_groups = default_hl_groups
  for name, link in pairs(self.hl_groups) do
    api.nvim_set_hl(0, "Prt" .. name:gsub("^%l", string.upper), { link = link })
  end

  -- Create namespaces for different highlighting purposes
  self.ns_id = api.nvim_create_namespace("PrtHandler_" .. utils.uuid())
  self.markdown_ns = api.nvim_create_namespace("PrtMarkdown_" .. utils.uuid())

  self.ex_id = api.nvim_buf_set_extmark(self.buffer, self.ns_id, self.first_line, 0, {
    strict = false,
    right_gravity = false,
  })

  return self
end

---Handles a chunk of response
---@param qid any
---@param chunk string
---Process markdown tokens in a line
---@param line string
---@return table
function ResponseHandler:process_markdown(line)
  local tokens = {}
  local pos = 1

  while pos <= #line do
    -- Check for code blocks
    local code_start = line:find("```", pos)
    if code_start == pos then
      local code_end = line:find("```", pos + 3)
      if code_end then
        table.insert(tokens, { text = line:sub(pos, code_end + 2), type = "code_block" })
        pos = code_end + 3
        goto continue
      end
    end

    -- Check for inline code
    local inline_start = line:find("`[^`]", pos)
    if inline_start == pos then
      local inline_end = line:find("`", pos + 1)
      if inline_end then
        table.insert(tokens, { text = line:sub(pos, inline_end), type = "code" })
        pos = inline_end + 1
        goto continue
      end
    end

    -- Check for other markdown elements
    local char = line:sub(pos, pos)
    if char == "#" then
      table.insert(tokens, { text = char, type = "heading" })
    elseif char == "*" or char == "_" then
      local next_char = line:sub(pos + 1, pos + 1)
      if next_char == char then
        table.insert(tokens, { text = char .. char, type = "strong" })
        pos = pos + 1
      else
        table.insert(tokens, { text = char, type = "emphasis" })
      end
    else
      -- Regular text
      local next_special = line:find("[`#*_]", pos + 1) or #line + 1
      table.insert(tokens, { text = line:sub(pos, next_special - 1), type = "text" })
      pos = next_special - 1
    end

    pos = pos + 1
    ::continue::
  end

  return tokens
end

---Handles a chunk of response
---@param qid any
---@param chunk string
function ResponseHandler:handle_chunk(qid, chunk)
  local qt = self.queries:get(qid)
  if not qt or not api.nvim_buf_is_valid(self.buffer) then return end
  if not self.skip_first_undojoin then utils.undojoin(self.buffer) end
  self.skip_first_undojoin = false

  qt.ns_id = qt.ns_id or self.ns_id
  qt.ex_id = qt.ex_id or self.ex_id
  local first_line = api.nvim_buf_get_extmark_by_id(self.buffer, self.ns_id, self.ex_id, {})[1]

  -- Accumulate and split on real newlines
  self.response = (self.response or "") .. (chunk or "")
  local lines = vim.split(self.response, "\n")

  -- Clear old content
  api.nvim_buf_set_lines(
    self.buffer,
    first_line,
    first_line + math.max(self.finished_lines, #lines),
    false,
    {}
  )

  -- Render and highlight each line
  for i, l in ipairs(lines) do
    local disp = self.prefix .. l
    api.nvim_buf_set_lines(self.buffer, first_line + i - 1, first_line + i - 1, false, { disp })
    local tokens, col = self:process_markdown(l), 0
    for _, tk in ipairs(tokens) do
      api.nvim_buf_add_highlight(
        self.buffer,
        self.markdown_ns,
        "Prt" .. tk.type:gsub("^%l", string.upper),
        first_line + i - 1,
        #self.prefix + col,
        #self.prefix + col + #tk.text
      )
      col = col + #tk.text
    end
  end

  -- Finalize
  self.finished_lines = #lines
  self:update_query_object(qt)
  self:move_cursor()
end

---Updates the query object with new line information
---@param qt table
function ResponseHandler:update_query_object(qt)
  local total_lines = self.first_line + self.finished_lines + (self.current_line ~= "" and 1 or 0)
  qt.first_line = self.first_line
  qt.last_line = total_lines - 1
end

---Moves the cursor to the end of the response if needed
function ResponseHandler:move_cursor()
  if self.cursor then
    local end_line = self.first_line + self.finished_lines + (self.current_line ~= "" and 1 or 0)
    utils.cursor_to_line(end_line, self.buffer, self.window)
  end
end

---Set typing animation speed
---@param speed number milliseconds between characters
---@param word_delay number milliseconds between words
function ResponseHandler:set_typing_speed(speed, word_delay)
  self.typing_speed = speed or 10
  self.word_delay = word_delay or 30
end

---Creates a handler function
---@return function
function ResponseHandler:create_handler()
  return vim.schedule_wrap(function(qid, chunk)
    self:handle_chunk(qid, chunk)
  end)
end

return ResponseHandler
