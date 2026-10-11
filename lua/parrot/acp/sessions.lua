local futils = require("parrot.file_utils")
local utils = require("parrot.utils")

local M = {}

---True when the file lives under chat_dir. Path only (unlike utils.is_chat): cheap enough for
---statuslines, and it decides whether a buffer uses its chat's ACP session.
---@param file_name string
---@param chat_dir string|nil
---@return boolean
function M.is_chat_dir_file(file_name, chat_dir)
  if not chat_dir or chat_dir == "" or file_name == "" then
    return false
  end
  -- trailing separator: `chats_old/a.md` is not under `chats`
  local dir = utils.resolve_path(chat_dir):gsub("/$", "") .. "/"
  return utils.starts_with(utils.resolve_path(file_name), dir)
end

---Git root of dir, or Neovim's cwd: the working directory of ACP sessions.
---@param dir string
---@return string
local function project_root(dir)
  local git_root = futils.find_git_root(dir)
  return vim.fn.resolve(git_root ~= "" and git_root or vim.fn.getcwd())
end

---Bind a chat file to the current project when it is first opened, so its agent keeps working
---there after a `:cd`.
---@param state table
---@param chat_file string
function M.bind_chat_project_cwd(state, chat_file)
  if not state:get_chat_project_cwd(chat_file) then
    state:set_chat_project_cwd(chat_file, project_root(vim.fn.getcwd()))
  end
end

---Working directory of the command sessions of a buffer: its file's project.
---@param buf number|nil nil for command prompts without a buffer
---@return string
function M.buffer_cwd(buf)
  local file_name = buf and vim.api.nvim_buf_get_name(buf) or ""
  return project_root(file_name ~= "" and vim.fn.fnamemodify(file_name, ":h") or vim.fn.getcwd())
end

---ACP session kind and cwd of a buffer. A chat file maps 1:1 to a session, keyed by its resolved
---path, in its bound project; other buffers get one-shot command sessions.
---@param buf number|nil
---@param chat_dir string
---@param state table
---@return { kind: "chat"|"command", cwd: string, key: string|nil }
function M.session_scope(buf, chat_dir, state)
  local file_name = buf and vim.api.nvim_buf_get_name(buf) or ""
  if not M.is_chat_dir_file(file_name, chat_dir) then
    return { kind = "command", cwd = M.buffer_cwd(buf) }
  end
  M.bind_chat_project_cwd(state, file_name)
  return { kind = "chat", cwd = state:get_chat_project_cwd(file_name), key = vim.fn.resolve(file_name) }
end

return M
