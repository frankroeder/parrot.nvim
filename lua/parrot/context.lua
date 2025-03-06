local utils = require("parrot.utils")
local futils = require("parrot.file_utils")
local pft = require("plenary.filetype")
local M = {}

function M.cmd_split(cmd)
  return vim.split(cmd, ":", { plain = true })
end

local function get_commands(msg, cmds)
  -- More comprehensive pattern for file paths
  -- Allows alphanumeric characters, periods, hyphens, underscores, spaces, plus ':', '/', '\', '~', '&', '#', etc.
  for cmd in msg:gmatch("(@file:[^%s,;%?!\"'<>|]+)") do
    table.insert(cmds, cmd)
  end
  -- For buffer names - allowing a wider range of characters but still avoiding problematic ones
  for cmd in msg:gmatch("(@buffer:[^%s,;%?!\"'<>|]+)") do
    table.insert(cmds, cmd)
  end
end

local function process_file_commands(msg, texts)
  local cmds = {}
  get_commands(msg, cmds)
  local filetype = nil
  local logger = require("parrot.logger")

  for _, cmd in ipairs(cmds) do
    if cmd:match("^@file:") then
      local path = cmd:sub(7)
      -- Handle absolute paths or paths with ~ for home directory
      local fullpath
      if path:match("^[/~]") or path:match("^%a:[/\\]") then
        -- It's an absolute path or starts with ~
        fullpath = vim.fn.expand(path)
      else
        -- It's a relative path
        local cwd = vim.fn.getcwd()
        fullpath = utils.path_join(cwd, path)
      end

      -- Attempt to read the file with error handling
      local ok, content = pcall(futils.read_file, fullpath)
      if ok and content then
        filetype = pft.detect(fullpath, {})
        table.insert(texts, content)
      else
        -- Add a note about the failed file inclusion and log error
        local error_msg = "Failed to read file: " .. path
        logger.error(error_msg)
        table.insert(texts, "<!-- " .. error_msg .. " -->")
      end
    elseif cmd:match("^@buffer:") then
      local buffer_name = cmd:sub(9)
      local buf_nr = vim.fn.bufnr(buffer_name)

      if buf_nr ~= -1 and vim.api.nvim_buf_is_loaded(buf_nr) then
        local ok, result = pcall(function()
          filetype = pft.detect(vim.api.nvim_buf_get_name(buf_nr), {})
          local lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
          return table.concat(lines, "\n")
        end)

        if ok and result then
          table.insert(texts, result)
        else
          -- Add a note about the failed buffer inclusion and log error
          local error_msg = "Failed to read buffer: " .. buffer_name
          logger.error(error_msg)
          table.insert(texts, "<!-- " .. error_msg .. " -->")
        end
      else
        -- Add a note about the non-existent buffer and log warning
        local error_msg = "Buffer not found: " .. buffer_name
        logger.warn(error_msg)
        table.insert(texts, "<!-- " .. error_msg .. " -->")
      end
    end
  end

  return filetype
end

function M.insert_contexts(msg)
  -- Check input
  if not msg or type(msg) ~= "string" then
    local logger = require("parrot.logger")
    logger.error("Invalid message for context insertion: " .. tostring(msg))
    return msg or ""
  end

  local texts = {}
  local filetypes = {} -- Track multiple filetypes

  -- Process all file/buffer commands in the message
  local ok, filetype = pcall(process_file_commands, msg, texts)
  if ok and filetype then
    table.insert(filetypes, filetype)
  elseif not ok then
    local logger = require("parrot.logger")
    logger.error("Error processing file commands: " .. tostring(filetype))
  end

  -- Remove commands from the message
  local cmds = {}
  pcall(get_commands, msg, cmds)
  for _, cmd in ipairs(cmds) do
    -- Use pcall to handle any pattern matching errors
    local ok, new_msg = pcall(function() return msg:gsub(cmd, "", 1) end)
    if ok then
      msg = new_msg
    end
  end

  -- If no context was added, just return the original message
  if #texts == 0 then
    return msg
  end

  -- Determine the most common filetype for better code block formatting
  local ft_to_use = (#filetypes > 0) and filetypes[1] or ""

  -- Format the output with nicely formatted code blocks
  local result = msg
  -- Safely trim trailing whitespace
  local ok, trimmed = pcall(function() return msg:gsub("%s+$", "") end)
  if ok then
    result = trimmed
  end

  -- Add a separator if the message isn't empty
  if result ~= "" then
    result = result .. "\n\n"
  end

  -- Format each piece of content in its own code block
  for i, content in ipairs(texts) do
    -- Skip empty content
    if content and type(content) == "string" and content:match("%S") then
      -- Safely format the code block
      local block_ok, block = pcall(function() 
        return string.format("```%s\n%s\n```", ft_to_use, content) 
      end)
      
      if block_ok then
        result = result .. block
      else
        -- Fallback to simple formatting if string.format fails
        result = result .. "```\n" .. tostring(content) .. "\n```"
      end

      -- Add spacing between code blocks
      if i < #texts then
        result = result .. "\n\n"
      end
    end
  end

  return result
end

return M
