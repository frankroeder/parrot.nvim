local M = {}
local utils = require("parrot.utils")
local comp_utils = require("parrot.completion.utils")

function M.extract_cmd(input)
  return input:match("^%s*(@%S*)")
end

function M.get_base_completion_items()
  return {
    items = {
      {
        label = "file",
        kind = 14, -- LSP CompletionItemKind.Keyword
        documentation = {
          kind = "markdown",
          value = comp_utils.get_command_documentation("file"),
        },
      },
      {
        label = "buffer",
        kind = 14, -- LSP CompletionItemKind.Keyword
        documentation = {
          kind = "markdown",
          value = comp_utils.get_command_documentation("buffer"),
        },
      },
      {
        label = "directory",
        kind = 14, -- LSP CompletionItemKind.Keyword
        documentation = {
          kind = "markdown",
          value = comp_utils.get_command_documentation("directory"),
        },
      },
    },
    is_incomplete = false,
  }
end

function M.get_file_completions_sync(path, only_directories, max_items)
  only_directories = only_directories or false
  max_items = max_items or 50
  local cwd = vim.fn.getcwd()
  local target_dir = comp_utils.resolve_path(path, cwd)
  if not target_dir then
    return { items = {}, is_incomplete = false }
  end
  local handle, err = vim.uv.fs_scandir(target_dir)
  if err or not handle then
    return { items = {}, is_incomplete = false }
  end
  local items = {}
  local count = 0
  while count < max_items do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if not name:match("^%.") then -- Skip hidden files
      local item_kind
      local is_valid = true
      if type == "directory" then
        item_kind = 19 -- LSP CompletionItemKind.Folder
        name = name .. "/"
      elseif type == "file" then
        if only_directories then
          is_valid = false
        else
          item_kind = 17 -- LSP CompletionItemKind.File
        end
      else
        is_valid = false
      end
      if is_valid then
        local full_path = utils.path_join(target_dir, name)
        local documentation_value
        if type == "file" then
          local stat = vim.uv.fs_stat(full_path)
          if stat then
            local size = stat.size
            local mtime = os.date("%Y-%m-%d %H:%M", stat.mtime.sec)
            documentation_value =
              string.format("**File:** %s\n**Size:** %d bytes\n**Modified:** %s", full_path, size, mtime)
          else
            documentation_value = string.format("**File:** %s", full_path)
          end
        else
          documentation_value = string.format("**Directory:** %s", full_path)
        end
        table.insert(items, {
          label = name,
          kind = item_kind,
          filterText = name:lower(),
          documentation = {
            kind = "markdown",
            value = documentation_value,
          },
        })
        count = count + 1
      end
    end
  end
  table.sort(items, function(a, b)
    local a_is_dir = a.label:sub(-1) == "/"
    local b_is_dir = b.label:sub(-1) == "/"
    if a_is_dir and not b_is_dir then
      return true
    elseif not a_is_dir and b_is_dir then
      return false
    else
      return a.label:lower() < b.label:lower()
    end
  end)
  return { items = items, is_incomplete = (count >= max_items) }
end

function M.get_buffer_completions_sync(query, max_items)
  max_items = max_items or 50
  local buffers = vim.api.nvim_list_bufs()
  local items = {}
  local current_buf = vim.api.nvim_get_current_buf()
  for _, buf in ipairs(buffers) do
    if #items >= max_items then
      break
    end
    if vim.api.nvim_buf_is_loaded(buf) then
      local bufhidden = vim.api.nvim_get_option_value("bufhidden", { buf = buf })
      local name = vim.api.nvim_buf_get_name(buf)
      local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
      local modified = vim.api.nvim_get_option_value("modified", { buf = buf })
      if name and name ~= "" and not (bufhidden and bufhidden:match("^wipe")) then
        local filename = vim.fn.fnamemodify(name, ":t")
        local rel_path = vim.fn.fnamemodify(name, ":~:.")
        if
          not query
          or query == ""
          or filename:lower():find(query, 1, true)
          or rel_path:lower():find(query, 1, true)
        then
          local item = {
            label = filename,
            kind = 26, -- Assuming Buffer kind is 26 (extended from LSP)
            detail = string.format("Buffer No.: [%d]\nRelative path: %s\n", buf, rel_path),
            filterText = filename:lower(),
            documentation = {
              kind = "markdown",
              value = string.format(
                "Absolute path: %s\nType: %s\n%s",
                name,
                filetype ~= "" and filetype or "unknown",
                modified and "*(modified)*" or ""
              ),
            },
          }
          if buf == current_buf then
            table.insert(items, 1, item)
          else
            table.insert(items, item)
          end
        end
      end
    end
  end
  return { items = items, is_incomplete = false }
end

return M
