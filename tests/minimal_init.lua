local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
local is_not_a_directory = vim.fn.isdirectory(plenary_dir) == 0
if is_not_a_directory then
  vim.fn.system({ "git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_dir })
end

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

-- Set up minimal test environment
-- Mock the global config to prevent errors on test invocation
package.loaded["parrot.config"] = {
  loaded = true,
  providers = {
    anthropic = {
      api_key = "test-key",
      endpoint = "https://api.anthropic.com/v1/messages",
      topic_prompt = "test prompt",
      topic = {
        model = "test-model",
        params = { max_tokens = 32 },
      },
      params = {
        chat = { max_tokens = 4096 },
        command = { max_tokens = 4096 },
      },
    },
  },
  options = {
    cmd_prefix = "Prt",
    state_dir = "/test/state/dir",
    chat_dir = "/test/chat/dir",
    chat_dir_pattern = "/test/chat/*.md",
    ui = { width = 80, height = 20 },
  },
  hooks = {},
  setup = function(opts)
    return true
  end,
}

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
