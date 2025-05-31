local pft = require("plenary.filetype")
local logger = require("parrot.logger")
local Placeholders = require("parrot.placeholders")

local M = {}

-- Trim leading whitespace and tabs from a string.
---@param str string The input string to be trimmed.
---@return string The trimmed string.
function M.trim(str)
  return str:gsub("^%s+", ""):gsub("\n%s+", "\n")
end

-- Feed keys to Neovim.
---@param keys string String of keystrokes
---@param mode string String of vim mode ('n', 'i', 'c', etc.), default is 'n'
function M.feedkeys(keys, mode)
  mode = mode or "n"
  keys = vim.api.nvim_replace_termcodes(keys, true, true, true)
  vim.api.nvim_feedkeys(keys, mode, true)
end

-- Set keymap for multiple buffers.
---@param buffers table Table of buffers
---@param mode table|string Mode(s) to set keymap for
---@param key string Shortcut key
---@param callback function|string Callback or string to set keymap
---@param desc string|nil Optional description for keymap
function M.set_keymap(buffers, mode, key, callback, desc)
  for _, buf in ipairs(buffers) do
    local opts = {
      noremap = true,
      silent = true,
      nowait = true,
      buffer = buf,
      desc = desc,
    }
    vim.keymap.set(mode, key, callback, opts)
  end
end

-- Create an autocommand for specified events and buffers.
---@param events string|table Events to listen to
---@param buffers table|nil Buffers to listen to (nil for all buffers)
---@param callback function Callback to call
---@param gid number Augroup id
function M.autocmd(events, buffers, callback, gid)
  if buffers then
    for _, buf in ipairs(buffers) do
      local opts = {
        group = gid,
        buffer = buf,
        callback = vim.schedule_wrap(callback),
      }
      vim.api.nvim_create_autocmd(events, opts)
    end
  else
    local opts = {
      group = gid,
      callback = vim.schedule_wrap(callback),
    }
    vim.api.nvim_create_autocmd(events, opts)
  end
end

-- Delete all buffers with a given file name.
---@param file_name string # name of the file for which to delete buffers
M.delete_buffer = function(file_name)
  -- iterate over buffer list and close all buffers with the same name
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == file_name then
      vim.api.nvim_buf_delete(b, { force = true })
    end
  end
end

-- Generate a unique UUID.
---@return string # returns unique uuid
M.uuid = function()
  local template = "xxxxxxxx_xxxx_4xxx_yxxx_xxxxxxxxxxxx"
  return string.gsub(template, "[xy]", function(c)
    local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format("%x", v)
  end)
end

-- Create a new augroup with a unique name.
---@param name string # name of the augroup
---@param opts table | nil # options for the augroup
---@return number # returns augroup id
M.create_augroup = function(name, opts)
  return vim.api.nvim_create_augroup(name .. "_" .. M.uuid(), opts or { clear = true })
end

-- Find the last line with content in a buffer.
---@param buf number # buffer number
---@return number # returns the first line with content of specified buffer
M.last_content_line = function(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  -- go from end and return number of last nonwhitespace line
  local line = vim.api.nvim_buf_line_count(buf)
  while line > 0 do
    local content = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
    if content:match("%S") then
      return line
    end
    line = line - 1
  end
  return 0
end

-- Move the cursor to a specific line in a buffer and window.
---@param line number # line number
---@param buf number # buffer number
---@param win number | nil # window number
M.cursor_to_line = function(line, buf, win)
  -- don't manipulate cursor if user is elsewhere
  if buf ~= vim.api.nvim_get_current_buf() then
    return
  end

  -- check if win is valid
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  -- move cursor to the line
  vim.api.nvim_win_set_cursor(win, { line, 0 })
end

-- Check if a string starts with a given substring.
---@param str string # string to check
---@param start string # string to check for
---@return boolean
M.starts_with = function(str, start)
  return str:sub(1, #start) == start
end

-- Check if a string ends with a given substring.
---@param str string # string to check
---@param ending string # string to check for
---@return boolean
M.ends_with = function(str, ending)
  return ending == "" or str:sub(-#ending) == ending
end

-- Get the buffer number for a file with a given name.
---@param file_name string # name of the file for which to get buffer
---@return number | nil
M.get_buffer = function(file_name)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) then
      if M.ends_with(vim.api.nvim_buf_get_name(b), file_name) then
        return b
      end
    end
  end
  return nil
end

-- Join the current change with the previous one in the undo history.
---@param buf number # buffer number
---@return boolean # true if successful, false otherwise
M.undojoin = function(buf)
  if not buf or type(buf) ~= "number" then
    logger.warning("undojoin: invalid buffer number", { buf = buf })
    return false
  end

  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    logger.debug("undojoin: buffer not valid or loaded", { buf = buf })
    return false
  end

  local status, result = pcall(vim.cmd.undojoin)
  if not status then
    -- E790: undojoin is not allowed after undo - this is expected behavior, not an error
    if result and result:match("E790") then
      logger.debug("undojoin: E790 - undojoin not allowed after undo")
      return false
    end
    logger.error("Error running undojoin", { buf = buf, error = result })
    return false
  end
  return true
end

-- Prepare the payload for a model request.
---@param messages table # The messages to include in the request
---@param model_name string # The name of the model
---@param params table # Additional parameters for the request
---@return table|nil # the prepared payload, or nil if invalid input
M.prepare_payload = function(messages, model_name, params)
  -- Input validation
  if type(messages) ~= "table" then
    logger.error("prepare_payload: messages must be a table", { messages = messages })
    return nil
  end

  if type(model_name) ~= "string" or model_name == "" then
    logger.error("prepare_payload: model_name must be a non-empty string", { model_name = model_name })
    return nil
  end

  if type(params) ~= "table" then
    logger.error("prepare_payload: params must be a table", { params = params })
    return nil
  end

  local model_req = {
    messages = messages,
    stream = true,
    model = model_name,
  }

  -- TODO: Provider specific --
  -- insert the model parameters with validation
  for k, v in pairs(params) do
    if k == "temperature" then
      -- Validate temperature range
      if type(v) == "number" then
        model_req[k] = math.max(0, math.min(2, v))
      else
        logger.warning("prepare_payload: invalid temperature value, using default", { value = v })
        model_req[k] = 1
      end
    elseif k == "top_p" then
      -- Validate top_p range
      if type(v) == "number" then
        model_req[k] = math.max(0, math.min(1, v))
      else
        logger.warning("prepare_payload: invalid top_p value, using default", { value = v })
        model_req[k] = 1
      end
    else
      if type(v) == "table" then
        model_req[k] = {}
        for pk, pv in pairs(v) do
          model_req[k][pk] = pv
        end
      else
        model_req[k] = v
      end
    end
  end

  return model_req
end

-- Check if a buffer is a chat file.
---@param buf number # buffer number
---@param file_name string # name of the file
---@param chat_dir string # directory path for chat files
---@return boolean
M.is_chat = function(buf, file_name, chat_dir)
  -- Input validation
  if not buf or type(buf) ~= "number" or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  if type(file_name) ~= "string" or file_name == "" then
    return false
  end

  if type(chat_dir) ~= "string" or chat_dir == "" then
    return false
  end

  if not M.starts_with(file_name, chat_dir) then
    return false
  end

  local success, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, -1, false)
  if not success then
    logger.warning("is_chat: failed to get buffer lines", { buf = buf, file_name = file_name })
    return false
  end

  if #lines < 4 then
    return false
  end

  if not lines[1]:match("^# ") then
    return false
  end

  return true
end

-- Get the content of all loaded buffers.
---@return string
M.get_all_buffer_content = function()
  local buffers = vim.api.nvim_list_bufs()
  local content = {}

  for _, buf in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
      local success, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, -1, false)
      if success and lines then
        table.insert(content, "Buffer: " .. vim.api.nvim_buf_get_name(buf)) -- Add buffer name as headline
        table.insert(content, table.concat(lines, "\n"))
      else
        logger.debug("get_all_buffer_content: failed to get lines for buffer", { buf = buf })
      end
    end
  end

  return table.concat(content, "\n\n")
end

-- Append selected text to a target buffer.
---@param params table # table with command args
---@param origin_buf number # selection origin buffer
---@param target_buf number # selection target buffer
---@param template_selection string # template for formatting the selection
---@return boolean # true if successful, false otherwise
M.append_selection = function(params, origin_buf, target_buf, template_selection)
  -- Input validation
  if type(params) ~= "table" or not params.line1 or not params.line2 then
    logger.error("append_selection: invalid params", { params = params })
    return false
  end

  if not origin_buf or not vim.api.nvim_buf_is_valid(origin_buf) then
    logger.error("append_selection: invalid origin buffer", { origin_buf = origin_buf })
    return false
  end

  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    logger.error("append_selection: invalid target buffer", { target_buf = target_buf })
    return false
  end

  -- prepare selection with error handling
  local success, lines = pcall(vim.api.nvim_buf_get_lines, origin_buf, params.line1 - 1, params.line2, false)
  if not success then
    logger.error("append_selection: failed to get lines from origin buffer", {
      origin_buf = origin_buf,
      line1 = params.line1,
      line2 = params.line2,
    })
    return false
  end

  local selection = table.concat(lines, "\n")
  if selection ~= "" then
    local filetype = pft.detect(vim.api.nvim_buf_get_name(origin_buf), {})
    local fname = vim.api.nvim_buf_get_name(origin_buf)
    local filecontent_success, filecontent_lines = pcall(vim.api.nvim_buf_get_lines, origin_buf, 0, -1, false)
    local filecontent = filecontent_success and table.concat(filecontent_lines, "\n") or ""
    local multifilecontent = M.get_all_buffer_content()

    if template_selection and template_selection ~= "" then
      local _placeholders =
        Placeholders:new(template_selection, "", selection, filetype, fname, filecontent, multifilecontent)
      local rendered = _placeholders:return_render()
      if rendered then
        selection = rendered
      end
    end
  end

  -- delete whitespace lines at the end of the file
  local last_content_line = M.last_content_line(target_buf)
  local set_success = pcall(vim.api.nvim_buf_set_lines, target_buf, last_content_line, -1, false, {})
  if not set_success then
    logger.error("append_selection: failed to clear end lines", { target_buf = target_buf })
    return false
  end

  -- insert selection lines
  lines = vim.split("\n" .. selection, "\n")
  set_success = pcall(vim.api.nvim_buf_set_lines, target_buf, last_content_line, -1, false, lines)
  if not set_success then
    logger.error("append_selection: failed to insert selection", { target_buf = target_buf })
    return false
  end

  return true
end

-- Check if a table has at least one of the specified valid keys.
---@param tbl table<string, any> # the table to check
---@param valid_keys string[] # valid key names to look for
---@return boolean
M.has_valid_key = function(tbl, valid_keys)
  if type(tbl) ~= "table" then
    return false
  end

  if type(valid_keys) ~= "table" then
    return false
  end

  for _, key in ipairs(valid_keys) do
    if tbl[key] ~= nil then
      return true
    end
  end
  return false
end

-- Check if a table contains a specific value.
---@param tbl table # The table to search
---@param val any # The value to search for
---@return boolean
M.contains = function(tbl, val)
  if type(tbl) ~= "table" then
    return false
  end

  for i = 1, #tbl do
    if tbl[i] == val then
      return true
    end
  end
  return false
end

-- Filter payload parameters based on valid parameters.
---@param valid_parameters table
---@param payload table
---@return table
M.filter_payload_parameters = function(valid_parameters, payload)
  if type(valid_parameters) ~= "table" or type(payload) ~= "table" then
    logger.error("filter_payload_parameters: invalid input types", {
      valid_parameters_type = type(valid_parameters),
      payload_type = type(payload),
    })
    return {}
  end

  local new_payload = {}
  for key, value in pairs(valid_parameters) do
    if type(value) == "table" then
      -- Initialize table only if needed
      if new_payload[key] == nil then
        new_payload[key] = {}
      end

      local found_values = false
      if payload[key] then
        for tkey, _ in pairs(value) do
          if payload[key][tkey] then
            new_payload[key][tkey] = payload[key][tkey]
            found_values = true
          end
        end
      else
        -- Look for the nested keys at top level
        for tkey, _ in pairs(value) do
          if payload[tkey] then
            new_payload[key][tkey] = payload[tkey]
            found_values = true
          end
        end
      end

      -- Remove empty tables
      if not found_values then
        new_payload[key] = nil
      end
    else
      new_payload[key] = payload[key]
    end
  end
  return new_payload
end

-- Parse a raw response, converting it to a string if necessary.
---@param response string|table|nil # The raw response to parse
---@return string|nil
M.parse_raw_response = function(response)
  if response == nil then
    return nil
  end

  if type(response) == "string" then
    return response
  end

  if type(response) == "table" then
    -- Handle array-like tables
    if #response > 0 then
      return table.concat(response, " ")
    else
      -- Handle object-like tables by converting to string
      return vim.inspect(response)
    end
  end

  -- For other types, convert to string
  return tostring(response)
end

-- Improved path_split with validation
---@param path string # path to split
---@return table # array of path components
function M.path_split(path)
  if type(path) ~= "string" then
    logger.error("path_split: path must be a string", { path = path })
    return {}
  end

  if path == "" then
    return {}
  end

  return vim.split(path, "/")
end

---@param ... string # path components to join
---@return string # joined path
function M.path_join(...)
  local args = { ... }

  if #args == 0 then
    logger.warning("path_join: no arguments provided")
    return ""
  end

  local parts = {}

  for i, part in ipairs(args) do
    if type(part) ~= "string" then
      logger.error("utils.path_join: argument must be string", {
        part = part,
        argument = i,
        part_type = type(part),
      })
      return ""
    end

    -- Remove leading/trailing separators (both / and \)
    part = part:gsub("^[/\\]+", ""):gsub("[/\\]+$", "")

    if #part > 0 then
      table.insert(parts, part)
    end
  end

  if #parts == 0 then
    logger.warning("path_join: all arguments were empty or separators")
    return ""
  end

  local result = table.concat(parts, "/")

  -- Preserve leading slash if the first argument had one
  if args[1] and args[1]:match("^[/\\]") then
    result = "/" .. result
  end

  return result
end

-- Generate a hash for provider endpoint configuration to detect changes
---@param provider table # Provider configuration
---@return string # Hash of endpoint configuration
function M.generate_endpoint_hash(provider)
  if not provider.model_endpoint or provider.model_endpoint == "" then
    return ""
  end

  local endpoint_str = ""
  if type(provider.model_endpoint) == "string" then
    endpoint_str = provider.model_endpoint
  elseif type(provider.model_endpoint) == "function" then
    -- For functions, we can't reliably hash the function content,
    -- so we include the provider name as part of the hash
    endpoint_str = "function:" .. provider.name
  elseif type(provider.model_endpoint) == "table" then
    endpoint_str = vim.inspect(provider.model_endpoint)
  end

  -- Simple hash using a basic algorithm compatible with Lua 5.1
  local hash = 0
  for i = 1, #endpoint_str do
    hash = ((hash * 33) + string.byte(endpoint_str, i)) % 0x100000000
  end

  return string.format("%08x", hash)
end

return M
