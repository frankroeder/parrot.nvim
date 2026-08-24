--- Message list of a chat, plus parsing of parrot chat buffers.
--- Modeled after prt.nvim's Conversation.
local Conversation = {}
Conversation.__index = Conversation

local VALID_ROLES = { system = true, user = true, assistant = true }

--- Creates an empty conversation.
---@return table
function Conversation:new()
  return setmetatable({ messages = {} }, self)
end

--- Appends a message. Empty roles are ignored (never sent to APIs).
---@param role string # "system", "user" or "assistant"
---@param content string
---@return table|nil # the inserted message, or nil when skipped
function Conversation:add_message(role, content)
  role = role or ""
  if not VALID_ROLES[role] then
    return nil
  end
  local msg = { role = role, content = content or "" }
  table.insert(self.messages, msg)
  return msg
end

---@param content string
---@return table|nil
function Conversation:add_system_message(content)
  return self:add_message("system", content)
end

---@param content string
---@return table|nil
function Conversation:add_user_message(content)
  return self:add_message("user", content)
end

--- Sets or replaces the leading system message.
--- No-op when content is blank.
---@param content string|nil
function Conversation:set_system_message(content)
  if not content or not content:match("%S") then
    return
  end
  local msg = { role = "system", content = content:gsub("\\n", "\n") }
  if self.messages[1] and self.messages[1].role == "system" then
    self.messages[1] = msg
  else
    table.insert(self.messages, 1, msg)
  end
end

---@return table # list of messages safe to send to an API
function Conversation:get_messages()
  return self.messages
end

---@return number
function Conversation:count()
  return #self.messages
end

--- Applies fn to the content of every message.
---@param fn fun(content: string): string
function Conversation:map_content(fn)
  for _, message in ipairs(self.messages) do
    message.content = fn(message.content)
  end
end

--- Parses the `# key: value` header block preceding the first `---` line.
---@param lines table # all lines of the chat buffer
---@return table headers, number|nil header_end # header_end is the 0-based index of the `---` line
function Conversation.parse_headers(lines)
  local headers = {}
  local line_idx = 0
  for _, line in ipairs(lines) do
    if line:sub(1, 3) == "---" then
      return headers, line_idx
    end
    local key, value = line:match("^[-#] (%w+): (.*)")
    if key ~= nil then
      headers[key] = value
    end
    line_idx = line_idx + 1
  end
  return headers, nil
end

--- Builds a conversation from the lines of a parrot chat buffer.
---@param lines table # all lines of the chat buffer
---@param opts table # { user_prefix, llm_prefix, system_prompt?, line1?, line2? }
---@return table|nil conversation, table|string # headers on success, error message on failure
function Conversation.from_chat_buffer(lines, opts)
  local headers, header_end = Conversation.parse_headers(lines)
  if header_end == nil then
    return nil, "Error while parsing headers: --- not found. Check your chat template."
  end

  local start_index = header_end + 1
  local end_index = #lines
  if opts.line1 and opts.line2 then
    start_index = math.max(start_index, opts.line1)
    end_index = math.min(end_index, opts.line2)
  end

  local conv = Conversation:new()
  local role, content = "", ""
  for index = start_index, end_index do
    local line = lines[index]
    if line:sub(1, #opts.user_prefix) == opts.user_prefix then
      if role ~= "" then
        conv:add_message(role, content)
      end
      role = "user"
      content = line:sub(#opts.user_prefix + 1)
    elseif line:sub(1, #opts.llm_prefix) == opts.llm_prefix then
      if role ~= "" then
        conv:add_message(role, content)
      end
      role = "assistant"
      content = ""
    elseif role ~= "" then
      content = content .. "\n" .. line
    end
  end
  if role ~= "" then
    conv:add_message(role, content)
  end

  local system = headers.system
  if not (system and system:match("%S")) then
    system = opts.system_prompt
  end
  conv:set_system_message(system)

  return conv, headers
end

--- Finds the line starting the nth-to-last user message.
---@param lines table # all lines of the chat buffer
---@param n_requests number # how many user messages to walk back
---@param user_prefix string
---@return number # 1-based line number
function Conversation.nth_last_user_line(lines, n_requests, user_prefix)
  local cur_index = #lines
  while cur_index > 0 and n_requests > 0 do
    if lines[cur_index]:sub(1, #user_prefix) == user_prefix then
      n_requests = n_requests - 1
    end
    cur_index = cur_index - 1
  end
  return cur_index + 1
end

return Conversation
