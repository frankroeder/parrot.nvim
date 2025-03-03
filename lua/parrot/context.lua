local utils = require("parrot.utils")
local futils = require("parrot.file_utils")
local M = {}

function M.cmd_split(cmd)
  return vim.split(cmd, ":", { plain = true })
end

local function get_commands(msg, cmds)
  for cmd in msg:gmatch("(@file:[%w%.%-/_ ]+)") do
    table.insert(cmds, cmd)
  end
  for cmd in msg:gmatch("(@buffer:[%w%.%-/_ ]+)") do
    table.insert(cmds, cmd)
  end
end

local function process_file_commands(msg, texts)
  local cmds = {}
  get_commands(msg, cmds)

  for _, cmd in ipairs(cmds) do
    if cmd:match("^@file:") then
      local path = cmd:sub(7)
      local cwd = vim.fn.getcwd()
      local fullpath = utils.path_join(cwd, path)
      local content = futils.read_file(fullpath)
      if content then
        table.insert(texts, content)
      end
    elseif cmd:match("^@buffer:") then
      local buffer_name = cmd:sub(9)
      local buf_nr = vim.fn.bufnr(buffer_name)
      if buf_nr ~= -1 then
        local lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
        local content = table.concat(lines, "\n")
        if content then
          table.insert(texts, content)
        end
      end
    end
  end
end

function M.insert_contexts(msg)
  local texts = {}
  process_file_commands(msg, texts)

  local cmds = {}
  get_commands(msg, cmds)
  for _, cmd in ipairs(cmds) do
    msg = msg:gsub(cmd, "", 1)
  end

  if #texts == 0 then
    return msg
  else
    return string.format("%s\n\n%s", table.concat(texts, "\n\n"), msg)
  end
end

return M
