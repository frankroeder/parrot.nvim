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
---@field queries table
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
  local len = #line
  while pos <= len do
    -- Code block: ```...```
    if line:sub(pos, pos + 2) == "```" then
      local endp = line:find("```", pos + 3, true)
      if endp then
        -- drop preceding whitespace-only token, if any
        local prev = tokens[#tokens]
        if prev and prev.type == "text" and prev.text:match("^%s+$") then
          table.remove(tokens, #tokens)
        end
        local txt = line:sub(pos, endp + 2)
        table.insert(tokens, { text = txt, type = "code_block" })
        pos = endp + 3
      else
        -- unmatched, rest as text
        table.insert(tokens, { text = line:sub(pos), type = "text" })
        break
      end
    -- Inline code: `...`
    elseif line:sub(pos, pos) == "`" then
      local endp = line:find("`", pos + 1, true)
      if endp then
        local txt = line:sub(pos, endp)
        table.insert(tokens, { text = txt, type = "code" })
        pos = endp + 1
      else
        table.insert(tokens, { text = "`", type = "text" })
        pos = pos + 1
      end
    -- Strong emphasis: **...** or __...__
    elseif line:sub(pos, pos + 1) == "**" or line:sub(pos, pos + 1) == "__" then
      local delim = line:sub(pos, pos + 1)
      local close = line:find(delim, pos + 2, true)
      if close then
        local txt = line:sub(pos, close + 1)
        table.insert(tokens, { text = txt, type = "strong" })
        pos = close + 2
      else
        table.insert(tokens, { text = delim, type = "text" })
        pos = pos + 2
      end
    -- Emphasis: *...* or _..._
    elseif line:sub(pos, pos) == "*" or line:sub(pos, pos) == "_" then
      local delim = line:sub(pos, pos)
      local close = line:find(delim, pos + 1, true)
      if close then
        local txt = line:sub(pos, close)
        table.insert(tokens, { text = txt, type = "emphasis" })
        pos = close + 1
      else
        table.insert(tokens, { text = delim, type = "text" })
        pos = pos + 1
      end
    -- Heading: #
    elseif line:sub(pos, pos) == "#" then
      table.insert(tokens, { text = "#", type = "heading" })
      pos = pos + 1
    -- Regular text up to next markdown char
    else
      local nextp = line:find("[%`%*_%#]", pos + 1)
      if nextp then
        local txt = line:sub(pos, nextp - 1)
        if #txt > 0 then
          table.insert(tokens, { text = txt, type = "text" })
        end
        pos = nextp
      else
        table.insert(tokens, { text = line:sub(pos), type = "text" })
        break
      end
    end
  end
  return tokens
end

---Handles a chunk of response
---@param qid any
---@param chunk string
function ResponseHandler:handle_chunk(qid, chunk)
  local qt = self.queries:get(qid)
  if not qt or not api.nvim_buf_is_valid(self.buffer) then
    return
  end
  if not self.skip_first_undojoin then
    utils.undojoin(self.buffer)
  end
  self.skip_first_undojoin = false

  qt.ns_id = qt.ns_id or self.ns_id
  qt.ex_id = qt.ex_id or self.ex_id
  local first_line = api.nvim_buf_get_extmark_by_id(self.buffer, self.ns_id, self.ex_id, {})[1]

  -- Accumulate and split on real newlines
  self.response = (self.response or "") .. (chunk or "")
  local lines = vim.split(self.response, "\n")

  -- Clear old content
  api.nvim_buf_set_lines(self.buffer, first_line, first_line + math.max(self.finished_lines, #lines), false, {})

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
