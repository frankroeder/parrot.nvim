local utils = require("parrot.utils")
local M = {}

---@param file_path string # the file path from where to read the json into a table
---@return table | nil # the table read from the file, or nil if an error occurred
M.file_to_table = function(file_path)
  local file, err = io.open(file_path, "r")
  if not file then
    M.logger.warning("Failed to open file for reading: " .. file_path .. "\nError: " .. err)
    return nil
  end
  local content = file:read("*a")
  file:close()

  if content == nil or content == "" then
    M.logger.warning("Failed to read any content from file: " .. file_path)
    return nil
  end

  return vim.json.decode(content)
end

---@param tbl table # the table to be stored
---@param file_path string # the file path where the table will be stored as json
M.table_to_file = function(tbl, file_path)
  local file = io.open(file_path, "w")
  if not file then
    M.warning("Failed to open file for writing: " .. file_path)
    return
  end
  file:write(vim.json.encode(tbl))
  file:close()
end

-- helper function to find the root directory of the current git repository
---@return string # returns the path of the git root dir or an empty string if not found
M.find_git_root = function()
  local cwd = vim.fn.expand("%:p:h")
  while cwd ~= "/" do
    local files = vim.fn.readdir(cwd)
    if vim.tbl_contains(files, ".git") then
      return cwd
    end
    cwd = vim.fn.fnamemodify(cwd, ":h")
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

  if vim.fn.filereadable(instruct_file) == 0 then
    return ""
  end

  local lines = vim.fn.readfile(instruct_file)
  return table.concat(lines, "\n")
end

---@param file string | nil # name of the file to delete
M.delete_file = function(file, state_dir)
  if file:match(state_dir) ~= nil then
    print("File not in state directory: " .. file)
    return nil
  end
  if file == nil then
    return
  end
  utils.delete_buffer(file)
  os.remove(file)
end

return M
