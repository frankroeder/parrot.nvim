-- Ensure a global inspect is defined for plenary (fallback if not available)
if not _G.inspect then
  local ok, inspect_mod = pcall(require, "inspect")
  _G.inspect = ok and inspect_mod or function(v)
    return tostring(v)
  end
end

local mock = require("luassert.mock")
local completion = require("parrot.completion")
local utils = mock(require("parrot.utils"), true)
local logger = mock(require("parrot.logger"), true)

describe("completion", function()
  -- describe("extract_cmd", function()
  -- it("returns nil for invalid input", function()
  --   assert.is_nil(completion.test_extract_cmd (nil))
  --   assert.is_nil(completion.test_extract_cmd ({}))
  --   assert.is_nil(completion.test_extract_cmd ({ context = {} }))
  -- end)

  --   it("extracts a command when it appears at the beginning of the line", function()
  --     local result = completion.test_extract_cmd({
  --       context = { cursor_before_line = "   @file:" },
  --       offset = 9  -- covers "   @file:" (including leading whitespace)
  --     })
  --     assert.equals("@file:", result)
  --   end)
  -- end)

  -- describe("is_available", function()
  --   local original_api = vim.api
  --   before_each(function()
  --     vim.api.nvim_get_current_buf = function() return 1 end
  --     vim.api.nvim_buf_get_name = function() return "/test/chat/dir/test.md" end
  --     vim.api.nvim_buf_get_option = function() return "normal" end
  --     vim.api.nvim_get_namespaces = function() return {} end
  --     vim.api.nvim_buf_get_extmarks = function() return {} end
  --     vim.fn.bufname = function() return "/test/chat/dir/test.md" end

  --     -- Make utils.is_chat return true for testing.
  --     utils.is_chat.returns(true)
  --   end)

  --   it("returns true when is_chat returns true", function()
  --     -- Use the module itself as the source instance.
  --     assert.is_true(completion.is_available())
  --     assert.stub(utils.is_chat).was_called_with(1, "/test/chat/dir/test.md", "/test/chat/dir")
  --   end)

  --   it("returns false when an API error occurs", function()
  --     vim.api.nvim_get_current_buf = function() error("test error") end
  --     assert.is_false(completion.is_available())
  --   end)

  --   after_each(function()
  --     vim.api = original_api
  --   end)
  -- end)

  -- describe("complete", function()
  --   it("returns initial suggestions for '@' trigger", function()
  --     -- Set up mocks for directory scanning.
  --     vim.loop.fs_scandir = function() return "mock_handle" end
  --     vim.loop.fs_scandir_next = function() return nil end

  --     local callback_called = false
  --     completion.complete(completion, {
  --       context = { cursor_before_line = "@" },
  --       offset = 1
  --     }, function(result)
  --       callback_called = true
  --       assert.is_table(result)
  --       -- Expect suggestions for "@file" and "@buffer"
  --       assert.equals(2, #result.items)
  --       assert.equals("file", result.items[1].label)
  --       assert.equals("buffer", result.items[2].label)
  --     end)

  --     assert.is_true(callback_called)
  --   end)

  --   it("handles errors gracefully in complete", function()
  --     local callback_called = false
  --     completion.complete(completion, {
  --       offset = "bad",               -- Invalid offset
  --       context = { cursor_before_line = 123 }  -- Invalid cursor text
  --     }, function(result)
  --       callback_called = true
  --       assert.is_table(result)
  --       assert.equals(0, #result.items)  -- Expect empty results
  --     end)

  --     assert.is_true(callback_called)
  --     assert.stub(logger.error).was_called()
  --   end)
  -- end)
end)
