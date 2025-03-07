local utils = require("parrot.utils")
local futils = require("parrot.file_utils")
local pft = require("plenary.filetype")
local logger = require("parrot.logger")
local M = {}

-- Splits a command string by literal colons.
function M.cmd_split(cmd)
  return vim.split(cmd, ":", { plain = true })
end

-- Given a message string, only lines that start (after optional whitespace)
-- with "@file:" or "@buffer:" are treated as commands.
function M.insert_contexts(msg)
  if not msg or type(msg) ~= "string" then
    logger.error("Invalid message for context insertion: " .. tostring(msg))
    return ""
  end

  -- Split message into lines.
  local lines = vim.split(msg, "\n", { plain = true })
  local normal_lines = {}
  local contexts = {}

  for _, line in ipairs(lines) do
    -- Check for file command at beginning of the line.
    local file_cmd = line:match("^%s*@file:(.+)$")
    local buffer_cmd = line:match("^%s*@buffer:(%S+)$")
    if file_cmd then
      local path = file_cmd
      if path:sub(1, 1) == '"' and path:sub(-1) == '"' then
        path = path:sub(2, -2)
      end

      local fullpath
      if path:match("^[/~]") or path:match("^%a:[/\\]") then
        fullpath = vim.fn.expand(path)
      else
        local cwd = vim.fn.getcwd()
        fullpath = utils.path_join(cwd, path)
      end

      -- Only attempt to read the file if it exists.
      if vim.fn.filereadable(fullpath) == 1 then
        local ok, content = pcall(futils.read_file, fullpath)
        if ok and content and content:match("%S") then
          local ft = pft.detect(fullpath, {})
          if fullpath:match("%.txt$") then
            ft = ""
          end
          content = content:gsub("\n+$", "")
          table.insert(contexts, { content = content, filetype = ft })
        end
      end
    elseif buffer_cmd then
      local buffer_name = buffer_cmd
      local buf_nr = vim.fn.bufnr(buffer_name)
      if buf_nr ~= -1 and vim.api.nvim_buf_is_loaded(buf_nr) then
        local ok, result = pcall(function()
          local ft = pft.detect(vim.api.nvim_buf_get_name(buf_nr), {})
          local buf_lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
          return { content = table.concat(buf_lines, "\n"), filetype = ft }
        end)
        if ok and result then
          table.insert(contexts, result)
        else
          logger.error("Failed to read buffer: " .. buffer_name)
        end
      end
    else
      -- Regular line, include in the message.
      table.insert(normal_lines, line)
    end
  end

  -- Reassemble the base message.
  local base = table.concat(normal_lines, "\n")
  base = base:gsub("[\n\r]+$", "") -- trim trailing newlines

  if #contexts == 0 then
    return base
  end

  -- Append each context as its own code block.
  local result = base .. "\n\n"
  for i, ctx in ipairs(contexts) do
    if ctx.content and ctx.content:match("%S") then
      local code_block
      if ctx.filetype and ctx.filetype ~= "" then
        code_block = "```" .. ctx.filetype .. "\n" .. ctx.content .. "\n```"
      else
        code_block = "```\n" .. ctx.content .. "\n```"
      end
      result = result .. code_block
      if i < #contexts then
        result = result .. "\n\n"
      end
    end
  end

  return result
end

return M
