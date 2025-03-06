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
  options = {
    model = "test-model",
    chat_dir = "/test/chat/dir",
    chat_dir_pattern = "/test/chat/*.md",
    api_key = "test-key",
    provider = "anthropic",
    ui = { width = 80, height = 20 },
    completion = {
      enabled = true,
    },
  },
  setup = function(opts)
    -- Mock setup function that doesn't crash in tests
    return true
  end,
}

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
