local cmp = require("cmp")
local core = require("parrot.completion.core")
local comp_utils = require("parrot.completion.utils")
local logger = require("parrot.logger")

local source = {}

source.new = function()
  return setmetatable({}, { __index = source })
end

source.is_available = function()
  return comp_utils.is_completion_available()
end

source.get_trigger_characters = function()
  return { "@" }
end

source.complete = function(self, request, callback)
  local input = request.context.cursor_before_line:sub(1, request.offset)
  local cmd = core.extract_cmd(input)
  if not cmd then
    callback({ items = {}, isIncomplete = false })
    return
  end
  local ok, result = pcall(function()
    if cmd == "@" then
      local base = core.get_base_completion_items()
      return { items = base.items, isIncomplete = base.is_incomplete }
    elseif cmd:match("^@file:") then
      local path = cmd:sub(7)
      local file_completions = core.get_file_completions_sync(path, false, 50)
      return { items = file_completions.items, isIncomplete = file_completions.is_incomplete }
    elseif cmd:match("^@buffer:") then
      local query = cmd:sub(9):lower()
      local buffer_completions = core.get_buffer_completions_sync(query, 50)
      return { items = buffer_completions.items, isIncomplete = buffer_completions.is_incomplete }
    elseif cmd:match("^@directory:") then
      local path = cmd:sub(12)
      local dir_completions = core.get_file_completions_sync(path, true, 50)
      return { items = dir_completions.items, isIncomplete = dir_completions.is_incomplete }
    else
      return { items = {}, isIncomplete = false }
    end
  end)
  if not ok then
    logger.error("Completion error: " .. tostring(result))
    callback({
      items = { { label = "Error: " .. tostring(result), kind = cmp.lsp.CompletionItemKind.Text } },
      isIncomplete = false,
    })
    return
  end
  callback(result)
end

cmp.register_source("parrot", source.new())

return source
