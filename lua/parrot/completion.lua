local utils = require("parrot.utils")
local has_cmp, cmp = pcall(require, "cmp")

if not has_cmp then
  return { context = {
    insert_contexts = function(content)
      return content
    end,
  } }
end

local source = { context = require("parrot.context") }

source.new = function()
  return setmetatable({}, { __index = source })
end

source.is_available = function()
  return true
end

source.get_trigger_characters = function()
  return { "@" }
end

local function extract_cmd(request)
  local text = request.context.cursor_before_line:sub(1, request.offset)
  local start, _ = text:find("(@[^%s]*)$")
  if start then
    return text:sub(start)
  end
  return nil
end

local function completion_items_for_path(path)
  local path_parts = utils.path_split(path)
  if #path > 0 and path:sub(-1) ~= "/" then
    table.remove(path_parts)
  end
  local cwd = vim.fn.getcwd()
  local target_dir = utils.path_join(cwd, unpack(path_parts))
  local handle = vim.loop.fs_scandir(target_dir)
  local files = {}

  if not handle then
    return files
  end

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    local item_kind
    if type == "file" then
      item_kind = cmp.lsp.CompletionItemKind.File
    elseif type == "directory" then
      item_kind = cmp.lsp.CompletionItemKind.Folder
      name = name .. "/"
    end

    table.insert(files, {
      label = name,
      kind = item_kind,
    })
  end
  -- print("FILES", vim.inspect(files))
  return files
end

local function completion_items_for_buffers()
  local buffers = vim.api.nvim_list_bufs()
  local items = {}
  for _, buf in ipairs(buffers) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name and name ~= "" then
        table.insert(items, {
          label = vim.fn.fnamemodify(name, ":t"),
          kind = cmp.lsp.CompletionItemKind.Buffer,
          detail = name,
        })
      end
    end
  end
  -- print("BUFFER", vim.inspect(items))
  return items
end

source.complete = function(self, request, callback)
  local cmd = extract_cmd(request)
  if not cmd then
    callback({ items = {}, isIncomplete = false })
    return
  end

  if cmd == "@" then
    local items = {
      { label = "file", kind = cmp.lsp.CompletionItemKind.Keyword },
      { label = "buffer", kind = cmp.lsp.CompletionItemKind.Keyword },
    }
    callback({ items = items, isIncomplete = false })
  elseif cmd == "@file" then
    local item = {
      label = "@file:",
      kind = cmp.lsp.CompletionItemKind.Keyword,
    }
    callback({ items = { item }, isIncomplete = true })
  elseif cmd:match("^@file:") then
    local path = cmd:sub(7)
    local items = completion_items_for_path(path)
    callback({ items = items, isIncomplete = false })
  elseif cmd:match("^@buffer:") then
    local items = completion_items_for_buffers()
    callback({ items = items, isIncomplete = false })
  else
    callback({ items = {}, isIncomplete = false })
  end
end

cmp.register_source("parrot_completion", source.new())

return source
