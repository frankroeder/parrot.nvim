local async = require("blink.cmp.lib.async")
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

function source:get_completions(context, callback)
  callback = vim.schedule_wrap(callback)
  local input = context.line:sub(1, context.cursor[2])
  local cmd = core.extract_cmd(input)
  if not cmd then
    callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    return
  end
  if cmd == "@" then
    local result = core.get_base_completion_items()
    callback({ is_incomplete_forward = result.is_incomplete, is_incomplete_backward = false, items = result.items })
  elseif cmd:match("^@file:") then
    local path = cmd:sub(7)
    async.task
      .new(function(resolve)
        local result = core.get_file_completions_sync(path, false, self.opts.max_items)
        resolve({
          is_incomplete_forward = result.is_incomplete,
          is_incomplete_backward = false,
          items = result.items,
        })
      end)
      :map(callback)
      :catch(function(err)
        logger.error(vim.inspect({
          msg = "File completion error",
          method = "completion.blink:get_completions",
          error = tostring(err)
        }))
        callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
      end)
  elseif cmd:match("^@buffer:") then
    local query = cmd:sub(9):lower()
    async.task
      .new(function(resolve)
        local result = core.get_buffer_completions_sync(query, self.opts.max_items)
        resolve({
          is_incomplete_forward = result.is_incomplete,
          is_incomplete_backward = false,
          items = result.items,
        })
      end)
      :map(callback)
      :catch(function(err)
        logger.error(vim.inspect({
          msg = "Buffer completion error",
          method = "completion.blink:get_completions",
          err = tostring(err),
        }))
        callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
      end)
  elseif cmd:match("^@directory:") then
    local path = cmd:sub(12)
    async.task
      .new(function(resolve)
        local result = core.get_file_completions_sync(path, true, self.opts.max_items)
        resolve({
          is_incomplete_forward = result.is_incomplete,
          is_incomplete_backward = false,
          items = result.items,
        })
      end)
      :map(callback)
      :catch(function(err)
        logger.error(vim.inspect({
          msg = "Directory completion error",
          method = "completion.blink:get_completions",
          err = tostring(err),
        }))
        callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
      end)
  else
    callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
  end
end

-- Keep the resolve function as is, since it’s specific to blink.cmp
function source:resolve(item, callback)
  callback = vim.schedule_wrap(callback)
  if not item or not item.data or item.data.type ~= "file" or not item.data.full_path then
    callback(item)
    return
  end
  comp_utils
    .read_file_async(item.data.full_path, 1024, async)
    :map(function(content)
      local is_binary = content:find("\0")
      if is_binary then
        item.documentation = {
          kind = "plaintext",
          value = "Binary file",
        }
      else
        local ext = vim.fn.fnamemodify(item.data.path, ":e")
        item.documentation = {
          kind = "markdown",
          value = "```" .. ext .. "\n" .. content .. "```",
        }
      end
      return item
    end)
    :map(function(resolved_item)
      callback(resolved_item)
    end)
    :catch(function(err)
      logger.error(vim.inspect({
        msg = "Resolve error",
          method = "completion.blink:get_completions",
        err = tostring(err),
      }))
      callback(item)
    end)
end

return source
