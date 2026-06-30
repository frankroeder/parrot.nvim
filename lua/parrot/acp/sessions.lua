local futils = require("parrot.file_utils")
local utils = require("parrot.utils")

local M = {}

---True when the buffer path lives under chat_dir (parrot markdown chats).
---Uses path only — matches ACP session kind; stricter utils.is_chat is for UI keymaps.
---@param file_name string
---@param chat_dir string|nil
---@return boolean
function M.is_chat_dir_file(file_name, chat_dir)
  if not chat_dir or chat_dir == "" or file_name == "" then
    return false
  end
  return utils.starts_with(vim.fn.resolve(file_name), vim.fn.resolve(chat_dir))
end

---Capture git root (or Neovim cwd) for the current editor project context.
---@return string
function M.capture_project_cwd()
  local git_root = futils.find_git_root(vim.fn.getcwd())
  if git_root ~= "" then
    return vim.fn.resolve(git_root)
  end
  return vim.fn.resolve(vim.fn.getcwd())
end

---Persist project cwd when a chat buffer is created or first opened.
---@param state table|nil
---@param chat_file string
function M.bind_chat_project_cwd(state, chat_file)
  if not state or not chat_file or chat_file == "" then
    return
  end
  chat_file = vim.fn.resolve(chat_file)
  if state:get_chat_project_cwd(chat_file) then
    return
  end
  state:set_chat_project_cwd(chat_file, M.capture_project_cwd())
end

---Resolve project cwd for ACP sessions (agent tools + repo-scoped resume).
---Chat buffers use the project cwd bound at create/open (lazy-bind on first prompt if missing).
---Command buffers use buffer directory / git root at prompt time.
---@param buf number|nil
---@param chat_dir string|nil
---@param state table|nil
---@param is_chat_buf boolean|nil When nil, derived from is_chat_dir_file
---@return string
function M.project_cwd(buf, chat_dir, state, is_chat_buf)
  local file_name = buf and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) or ""
  if is_chat_buf == nil then
    is_chat_buf = M.is_chat_dir_file(file_name, chat_dir)
  end

  if is_chat_buf then
    if state then
      local chat_key = vim.fn.resolve(file_name)
      local stored = state:get_chat_project_cwd(chat_key)
      if stored and stored ~= "" then
        return vim.fn.resolve(stored)
      end
      local cwd = M.capture_project_cwd()
      state:set_chat_project_cwd(chat_key, cwd)
      return cwd
    end
    return M.capture_project_cwd()
  end

  local start_dir = file_name ~= "" and vim.fn.fnamemodify(file_name, ":h") or vim.fn.getcwd()
  local git_root = futils.find_git_root(start_dir)
  if git_root ~= "" then
    return vim.fn.resolve(git_root)
  end
  return vim.fn.resolve(vim.fn.getcwd())
end

---Path-based chat buffer check (ACP session kind; not parrot markdown template).
---@param buf number|nil
---@param chat_dir string|nil
---@return boolean
function M.is_acp_chat_buf(buf, chat_dir)
  local file_name = buf and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) or ""
  return M.is_chat_dir_file(file_name, chat_dir)
end

---Single source for ACP session kind + cwd (used by acp_query and slash/mode UI).
---@param buf number|nil
---@param chat_dir string|nil
---@param state table|nil
---@return { kind: string, cwd: string, is_chat_buf: boolean }
function M.session_scope(buf, chat_dir, state)
  local file_name = buf and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) or ""
  local is_chat_buf = M.is_chat_dir_file(file_name, chat_dir)
  return {
    kind = is_chat_buf and "chat" or "command",
    cwd = M.project_cwd(buf, chat_dir, state, is_chat_buf),
    is_chat_buf = is_chat_buf,
  }
end

---@param cwd string|nil
---@return string
function M.repo_key(cwd)
  cwd = cwd or vim.fn.getcwd()
  local git_root = futils.find_git_root(cwd)
  if git_root ~= "" then
    return vim.fn.resolve(git_root)
  end
  return vim.fn.resolve(cwd)
end

---@param state table|nil
---@param provider string
---@param kind string
---@param cwd string|nil
---@return string|nil
function M.get_id(state, provider, kind, cwd)
  if not state then
    return nil
  end
  local key = M.repo_key(cwd)
  return state:get_acp_session(provider, key, kind)
end

---@param state table|nil
---@param provider string
---@param kind string
---@param cwd string|nil
---@param session_id string
function M.save_id(state, provider, kind, cwd, session_id)
  if not state or not session_id then
    return
  end
  state:set_acp_session(provider, M.repo_key(cwd), kind, session_id)
end

return M