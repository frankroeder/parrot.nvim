local logger = require("parrot.logger")
local utils = require("parrot.utils")
local M = {}

---@param file_path string # the file path from where to read the json into a table
---@return table | nil # the table read from the file, or nil if an error occurred
M.file_to_table = function(file_path)
  local status, file, err = pcall(io.open, file_path, "r")
  if not status or not file then
    logger.error("Failed to open file: " .. file_path .. "\nError: " .. (err or "Unknown error"))
    return nil
  end

  local content, content_err = file:read("*a")
  file:close()

  if not content or content == "" then
    logger.error(
      "Failed to read content from file: " .. file_path .. (content_err and ("\nError: " .. content_err) or "")
    )
    return nil
  end

  local decode_status, result = pcall(vim.json.decode, content)
  if not decode_status then
    logger.error("JSON decoding failed for file: " .. file_path .. "\nError: " .. result)
    return nil
  end

  return result
end

---@param tbl table # the table to be stored
---@param file_path string # the file path where the table will be stored as json
M.table_to_file = function(tbl, file_path)
  local file, err = io.open(file_path, "w")
  if not file then
    logger.error(string.format("Failed to open file for writing: %s", file_path))
    return
  end

  local ok, json_str = pcall(vim.json.encode, tbl)
  if not ok then
    logger.error("Failed to encode table to JSON.")
    file:close()
    return
  end

  ok, err = pcall(file.write, file, json_str)
  if not ok then
    logger.error(string.format("Failed to write data to file: %s", err))
  end

  file:close()
end

-- helper function to find the root directory of the current git repository
---@return string # returns the path of the git root dir or an empty string if not found
M.find_git_root = function()
  local cwd = vim.fn.expand("%:p:h")
  local git_dir = cwd .. "/.git"
  while cwd ~= "/" do
    if vim.fn.isdirectory(git_dir) == 1 then
      return cwd
    end
    cwd = vim.fn.fnamemodify(cwd, ":h")
    git_dir = cwd .. "/.git"
  end
  return ""
end

-- tries to find an .parrot.md file in the root of current git repo
---@return string # returns instructions from the .parrot.md file
M.find_repo_instructions = function()
  local git_root = M.find_git_root()
  if git_root == "" then
    return ""
  end
  local instruct_file = git_root .. "/.parrot.md"
  if vim.fn.filereadable(instruct_file) == 1 then
    local lines = vim.fn.readfile(instruct_file)
    return table.concat(lines, "\n")
  end
  return ""
end

---@param file string | nil # name of the file to delete
---@param target_dir string # target directory for the file
M.delete_file = function(file, target_dir)
  if not file then
    logger.error("No file specified for deletion.")
    return
  end

  -- Checks if the file is actually located in the specified directory
  if file:match(target_dir) == nil then
    logger.error("File '" .. file .. "' not in target directory.")
    return
  end

  -- Proceed to delete the file from buffer and the filesystem
  utils.delete_buffer(file)
  if not os.remove(file) then
    logger.error("Error: Failed to delete file '" .. file .. "'.")
  end
end

--- Reads the content of a file at the specified path.
--- @param path string The path to the file to be read
--- @return string The content of the file, or an empty string if the file cannot be opened
M.read_file = function(path)
  local file = io.open(path, "r")
  if not file then
    return ""
  end
  local content = file:read("*a")
  file:close()
  return content
end

--- Writes content to a file at the specified path.
--- @param path string
--- @param content string
--- @return boolean
M.write_file = function(path, content)
  local file = io.open(path, "w")
  if not file then
    return false
  end
  file:write(content)
  file:close()
  return true
end

return M
