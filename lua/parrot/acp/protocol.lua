--- Agent Client Protocol method names.
local M = {
  PROTOCOL_VERSION = 1,

  agent = {
    initialize = "initialize",
    authenticate = "authenticate",
    session_new = "session/new",
    session_load = "session/load",
    session_prompt = "session/prompt",
    session_cancel = "session/cancel",
    session_set_mode = "session/set_mode",
    session_set_config_option = "session/set_config_option",
  },

  client = {
    session_update = "session/update",
    session_request_permission = "session/request_permission",
    fs_read_text_file = "fs/read_text_file",
    fs_write_text_file = "fs/write_text_file",
    terminal_create = "terminal/create",
    terminal_output = "terminal/output",
    terminal_wait_for_exit = "terminal/wait_for_exit",
    terminal_release = "terminal/release",
    terminal_kill = "terminal/kill",
  },
}

return M