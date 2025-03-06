local mock = require("luassert.mock")

describe("context", function()
  local utils
  local futils
  local context
  local logger

  before_each(function()
    -- Mock dependencies
    utils = mock(require("parrot.utils"), true)
    futils = mock(require("parrot.file_utils"), true)
    logger = mock({
      error = function() end,
      warn = function() end,
      info = function() end,
    }, true)

    -- Reset the package.loaded to reload the module with mocks
    package.loaded["parrot.context"] = nil
    package.loaded["parrot.logger"] = logger

    -- Mock plenary.filetype
    _G.pft = {
      detect = function()
        return "lua"
      end,
    }

    -- Load the module with our mocks in place
    context = require("parrot.context")
  end)

  after_each(function()
    mock.revert(utils)
    mock.revert(futils)
    mock.revert(logger)
    package.loaded["parrot.context"] = nil
    package.loaded["parrot.logger"] = nil
    _G.pft = nil
    _G.vim = nil
  end)

  describe("cmd_split", function()
    it("should split commands correctly", function()
      local result = context.cmd_split("file:path/to/file.lua")
      assert.are.same({ "file", "path/to/file.lua" }, result)
    end)
  end)

  describe("insert_contexts", function()
    it("should handle nil message gracefully", function()
      -- Mock logger
      local result = context.insert_contexts(nil)
      assert.equal("", result)
      assert.stub(logger.error).was_called()
    end)

    it("should process file commands and replace them in the message", function()
      -- Setup mocks for file reading
      utils.path_join.returns("/full/path/to/file.lua")
      futils.read_file.returns("local M = {}\nreturn M")

      -- Mock Neovim API calls
      _G.vim = {
        fn = {
          getcwd = function()
            return "/current/dir"
          end,
          expand = function(path)
            return path
          end,
        },
      }

      local message = "Here is some code: @file:path/to/file.lua"
      local result = context.insert_contexts(message)

      -- Check that command was removed and content was added
      assert.is_true(not result:find("@file:path/to/file.lua"))
      assert.is_true(result:find("Here is some code:"))
      assert.is_true(result:find("```lua"))
      assert.is_true(result:find("local M = {}"))
      assert.is_true(result:find("return M"))
    end)

    it("should handle buffer commands", function()
      -- Setup buffer mocks
      _G.vim = {
        fn = {
          getcwd = function()
            return "/current/dir"
          end,
          bufnr = function()
            return 42
          end,
        },
        api = {
          nvim_buf_get_name = function()
            return "/path/to/buffer.lua"
          end,
          nvim_buf_get_lines = function()
            return { "local buf_content = true" }
          end,
          nvim_buf_is_loaded = function()
            return true
          end,
        },
      }

      local message = "Here is buffer content: @buffer:my_buffer"
      local result = context.insert_contexts(message)

      -- Check output
      assert.is_true(not result:find("@buffer:my_buffer"))
      assert.is_true(result:find("Here is buffer content:"))
      assert.is_true(result:find("```lua"))
      assert.is_true(result:find("local buf_content = true"))
    end)

    it("should handle file read errors gracefully", function()
      -- Setup mocks for file reading failure
      utils.path_join.returns("/bad/path.lua")
      futils.read_file.returns(nil)

      -- Mock Neovim API calls
      _G.vim = {
        fn = {
          getcwd = function()
            return "/current/dir"
          end,
          expand = function(path)
            return path
          end,
        },
      }

      local message = "Should handle errors: @file:bad/path.lua"
      local result = context.insert_contexts(message)

      -- Check that error is handled properly
      assert.is_true(not result:find("@file:bad/path.lua"))
      assert.is_true(result:find("Should handle errors:"))
      assert.is_true(result:find("Failed to read file: bad/path.lua"))
      assert.stub(logger.error).was_called()
    end)

    it("should handle non-existent buffers gracefully", function()
      -- Setup buffer mocks for failure case
      _G.vim = {
        fn = {
          getcwd = function()
            return "/current/dir"
          end,
          bufnr = function()
            return -1
          end, -- -1 indicates buffer not found
        },
      }

      local message = "Should handle missing buffer: @buffer:missing_buffer"
      local result = context.insert_contexts(message)

      -- Check output
      assert.is_true(not result:find("@buffer:missing_buffer"))
      assert.is_true(result:find("Should handle missing buffer:"))
      assert.is_true(result:find("Buffer not found: missing_buffer"))
      assert.stub(logger.warn).was_called()
    end)

    it("should handle multiple context commands in one message", function()
      -- Setup mocks for files and buffers
      utils.path_join.returns("/full/path/to/file.lua")
      futils.read_file.returns("local file_content = {}")

      -- Mock Neovim API calls
      _G.vim = {
        fn = {
          getcwd = function()
            return "/current/dir"
          end,
          expand = function(path)
            return path
          end,
          bufnr = function()
            return 42
          end,
        },
        api = {
          nvim_buf_get_name = function()
            return "/path/to/buffer.lua"
          end,
          nvim_buf_get_lines = function()
            return { "local buf_content = true" }
          end,
          nvim_buf_is_loaded = function()
            return true
          end,
        },
      }

      local message = "Multiple contexts: @file:path/to/file.lua and @buffer:my_buffer"
      local result = context.insert_contexts(message)

      -- Check output formatting
      assert.is_true(not result:find("@file:path/to/file.lua"))
      assert.is_true(not result:find("@buffer:my_buffer"))
      assert.is_true(result:find("Multiple contexts: and"))
      assert.is_true(result:find("local file_content = {}"))
      assert.is_true(result:find("local buf_content = true"))
      -- Check for multiple code blocks
      assert.is_true(result:find("```lua.*```.*```lua", true))
    end)
    
    it("should handle process_file_commands errors gracefully", function()
      -- Setup mocks to throw an error in process_file_commands
      utils.path_join.returns(function() error("Path join error") end)

      -- Mock Neovim API calls
      _G.vim = {
        fn = {
          getcwd = function()
            return "/current/dir"
          end,
          expand = function(path)
            return path
          end,
        },
      }

      local message = "Should handle process errors: @file:path/with/error.lua"
      local result = context.insert_contexts(message)

      -- Even with error, we should get a result
      assert.is_not_nil(result)
      assert.is_true(type(result) == "string")
      -- Error should be logged
      assert.stub(logger.error).was_called()
    end)
    
    it("should handle gsub errors gracefully", function()
      -- Create a special string that will cause pattern matching issues
      local problematic_pattern = "@file:%"  -- Invalid pattern due to unescaped %
      local message = "Should handle gsub errors: " .. problematic_pattern

      -- Mock file reading for any path
      utils.path_join.returns("/any/path")
      futils.read_file.returns("dummy content")

      -- Mock Neovim API calls
      _G.vim = {
        fn = {
          getcwd = function()
            return "/current/dir"
          end,
          expand = function(path)
            return path
          end,
        },
      }

      -- This should not throw
      local result = context.insert_contexts(message)
      
      -- We should still get a result
      assert.is_not_nil(result)
    end)
    
    it("should handle non-string content in code blocks", function()
      -- Setup mocks to return non-string content
      utils.path_join.returns("/path/to/file.lua")
      futils.read_file.returns(123)  -- Non-string content
      
      -- Mock Neovim API calls
      _G.vim = {
        fn = {
          getcwd = function()
            return "/current/dir"
          end,
          expand = function(path)
            return path
          end,
        },
      }

      local message = "Should handle non-string content: @file:path/to/file.lua"
      local result = context.insert_contexts(message)
      
      -- We should get a result with the content properly formatted
      assert.is_not_nil(result)
      assert.is_true(result:find("```")) -- Should still create code blocks
    end)
  end)
end)
