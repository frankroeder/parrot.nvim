local logger = require("parrot.logger")
local core = require("parrot.completion.core")
local comp_utils = require("parrot.completion.utils")

local source = {}

function source.new(opts)
  local self = setmetatable({}, { __index = source })
  self.opts = vim.tbl_deep_extend("keep", opts or {}, {
    show_hidden_files = false,
    max_items = 50,
  })
  return self
end

function source:get_trigger_characters()
  return { "@" }
end

function source:is_available(context)
  return comp_utils.is_completion_available(context.bufnr)
end

local function empty_response()
  return { is_incomplete_forward = false, is_incomplete_backward = false, items = {} }
end

-- The completion helpers are synchronous, so they run directly instead of on
-- blink.cmp's internal task library, which is not a stable API (blink.cmp v2
-- removed `blink.cmp.lib.async`). `callback` is schedule-wrapped either way.
local function respond(callback, method, label, fn)
  local ok, result = pcall(fn)
  if not ok then
    logger.error(label .. " completion error", {
      method = method,
      error = tostring(result),
    })
    callback(empty_response())
    return
  end
  callback({
    is_incomplete_forward = result.is_incomplete,
    is_incomplete_backward = false,
    items = result.items,
  })
end

function source:get_completions(context, callback)
  callback = vim.schedule_wrap(callback)
  local method = "completion.blink:get_completions"
  local input = context.line:sub(1, context.cursor[2])
  local cmd = core.extract_cmd(input)
  if not cmd then
    callback(empty_response())
  elseif cmd == "@" then
    respond(callback, method, "Base", core.get_base_completion_items)
  elseif cmd:match("^@file:") then
    local path = cmd:sub(7)
    respond(callback, method, "File", function()
      return core.get_file_completions_sync(path, false, self.opts.max_items)
    end)
  elseif cmd:match("^@buffer:") then
    local query = cmd:sub(9):lower()
    respond(callback, method, "Buffer", function()
      return core.get_buffer_completions_sync(query, self.opts.max_items)
    end)
  elseif cmd:match("^@directory:") then
    local path = cmd:sub(12)
    respond(callback, method, "Directory", function()
      return core.get_file_completions_sync(path, true, self.opts.max_items)
    end)
  else
    callback(empty_response())
  end
end

function source:resolve(item, callback)
  callback = vim.schedule_wrap(callback)
  if not item or not item.data or item.data.type ~= "file" or not item.data.full_path then
    callback(item)
    return
  end
  -- read_file calls back in a fast event; schedule before using vim.fn.
  comp_utils.read_file(item.data.full_path, 1024, vim.schedule_wrap(function(err, content)
    if err then
      logger.error("Resolve error", {
        method = "completion.blink:resolve",
        error = tostring(err),
      })
      callback(item)
      return
    end
    if content:find("\0") then
      item.documentation = { kind = "plaintext", value = "Binary file" }
    else
      local ext = vim.fn.fnamemodify(item.data.path, ":e")
      item.documentation = {
        kind = "markdown",
        value = "```" .. ext .. "\n" .. content .. "```",
      }
    end
    callback(item)
  end))
end

return source
