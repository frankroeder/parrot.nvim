local mock = require("luassert.mock")

describe("completion", function()
  local utils
  local completion
  local config
  local logger
  local loop_mock

  before_each(function()
    -- Mock modules
    utils = mock(require("parrot.utils"), true)
    logger = mock({
      error = function() end,
      warn = function() end,
      info = function() end,
    }, true)

    -- Mock vim.loop for fs operations
    loop_mock = {
      fs_scandir = function() return "mock_handle" end,
      fs_scandir_next = function() return nil end, -- Return nil to stop loop
    }

    config = {
      loaded = true,
      options = {
        chat_dir = "/test/chat/dir",
      },
    }

    -- Reset the package.loaded to reload our module with the mocks
    package.loaded["parrot.completion"] = nil
    package.loaded["parrot.config"] = config
    package.loaded["parrot.logger"] = logger

    -- Create a mock for cmp
    _G.cmp = {
      register_source = function() end,
      lsp = {
        CompletionItemKind = {
          File = "File",
          Folder = "Folder",
          Buffer = "Buffer",
          Keyword = "Keyword",
        },
      },
    }

    -- Setup Neovim API mocks with stable base functionality
    _G.vim = {
      api = {
        nvim_get_current_buf = function() return 1 end,
        nvim_buf_get_name = function() return "/test/file.lua" end,
        nvim_buf_get_option = function() return "normal" end,
        nvim_get_namespaces = function() return {} end,
        nvim_buf_get_extmarks = function() return {} end,
        nvim_list_bufs = function() return {1, 2, 3} end,
        nvim_buf_is_loaded = function() return true end,
      },
      fn = {
        bufname = function() return "/test/file.lua" end,
        getcwd = function() return "/test" end,
        fnamemodify = function(path, modifier) 
          if modifier == ":t" then return "file.lua"
          elseif modifier == ":~:." then return "file.lua"
          else return path end
        end,
      },
      loop = loop_mock,
    }

    -- Now load the module with our mocks in place
    completion = require("parrot.completion")
  end)

  after_each(function()
    mock.revert(utils)
    mock.revert(logger)
    package.loaded["parrot.completion"] = nil
    package.loaded["parrot.config"] = nil
    package.loaded["parrot.logger"] = nil
    _G.cmp = nil
    _G.vim = nil
    _G.extract_cmd_test = nil
  end)

  describe("is_available", function()
    it("should return true for chat files", function()
      -- Setup mocks
      local buf = 1
      local file_name = "/test/chat/dir/test.md"

      -- Mock Neovim API calls
      _G.vim.api.nvim_get_current_buf = function() return buf end
      _G.vim.api.nvim_buf_get_name = function() return file_name end
      _G.vim.fn.bufname = function() return file_name end

      -- Mock is_chat function to return true
      utils.is_chat.returns(true)

      -- Create source instance
      local source_instance = completion.new()

      -- Test
      assert.is_true(source_instance.is_available())

      -- Verify our mocks were called as expected
      assert.stub(utils.is_chat).was_called_with(buf, file_name, "/test/chat/dir")
    end)

    it("should return true for UI input buffers", function()
      -- Setup mocks
      local buf = 2
      local file_name = ""

      -- Mock an extmark with "Enter text here" prompt
      local extmark =
        { 0, 0, 1, {
          virt_text = { { "Enter text here... confirm with: CTRL-W_q", "Comment" } },
        } }

      -- Mock Neovim API calls
      _G.vim.api.nvim_get_current_buf = function() return buf end
      _G.vim.api.nvim_buf_get_name = function() return file_name end
      _G.vim.api.nvim_buf_get_option = function() return "nofile" end
      _G.vim.api.nvim_get_namespaces = function() return { input_prompt = 1 } end
      _G.vim.api.nvim_buf_get_extmarks = function() return { extmark } end
      _G.vim.fn.bufname = function() return "" end

      -- Mock is_chat function to return false
      utils.is_chat.returns(false)

      -- Create source instance
      local source_instance = completion.new()

      -- Test
      assert.is_true(source_instance.is_available())
    end)

    it("should return false for regular files", function()
      -- Setup mocks
      local buf = 3
      local file_name = "/regular/file.lua"

      -- Mock Neovim API calls
      _G.vim.api.nvim_get_current_buf = function() return buf end
      _G.vim.api.nvim_buf_get_name = function() return file_name end
      _G.vim.api.nvim_buf_get_option = function() return "normal" end
      _G.vim.api.nvim_get_namespaces = function() return {} end
      _G.vim.api.nvim_buf_get_extmarks = function() return {} end
      _G.vim.fn.bufname = function() return file_name end

      -- Mock is_chat function to return false
      utils.is_chat.returns(false)

      -- Create source instance
      local source_instance = completion.new()

      -- Test
      assert.is_false(source_instance.is_available())
    end)

    it("should handle API errors gracefully", function()
      -- Setup mocks to throw an error
      _G.vim.api.nvim_get_current_buf = function() error("Test error") end

      -- Create source instance
      local source_instance = completion.new()

      -- Test - should not throw but return false and log error
      assert.is_false(source_instance.is_available())
      assert.stub(logger.error).was_called(1)
    end)
  end)

  describe("extract_cmd", function()
    it("should handle invalid request gracefully", function()
      -- Get the extract_cmd function via _G
      _G.extract_cmd_test = function(request)
        return completion.test_extract_cmd(request)
      end

      -- Test with nil request
      local result1 = _G.extract_cmd_test(nil)
      assert.is_nil(result1)

      -- Test with empty request
      local result2 = _G.extract_cmd_test({})
      assert.is_nil(result2)

      -- Test with partial request
      local result3 = _G.extract_cmd_test({ context = {} })
      assert.is_nil(result3)
    end)

    it("should extract command correctly", function()
      _G.extract_cmd_test = function(request)
        return completion.test_extract_cmd(request)
      end

      -- Test with valid request for @file: command
      local result = _G.extract_cmd_test({
        context = { cursor_before_line = "Check this @file:" },
        offset = 18
      })
      assert.equals("@file:", result)
    end)
  end)

  describe("complete", function()
    it("should handle errors gracefully", function()
      -- Setup a source instance
      local source_instance = completion.new()

      -- Create a callback spy
      local callback_spy = spy.new(function() end)

      -- Create a request that will trigger an error
      local bad_request = {
        -- Missing or invalid properties that would cause an error
        offset = "not_a_number", -- This should be a number
        context = {
          cursor_before_line = 123, -- This should be a string
        },
      }

      -- Call complete and expect no error to bubble up
      source_instance.complete(source_instance, bad_request, callback_spy)

      -- Verify the callback was called with empty results
      assert.spy(callback_spy).was_called_with({ items = {}, isIncomplete = false })

      -- Verify that the error was logged
      assert.stub(logger.error).was_called()
    end)

    it("should return initial suggestions for @ trigger", function()
      -- Setup successful directory access mocks
      _G.vim.loop.fs_scandir = function() return "mock_handle" end
      _G.vim.loop.fs_scandir_next = function() return nil end
      
      -- Setup a source instance
      local source_instance = completion.new()

      -- Create a callback spy
      local callback_spy = spy.new(function() end)

      -- Create a request for initial @ trigger
      local request = {
        context = { cursor_before_line = "@" },
        offset = 1
      }

      -- Call complete
      source_instance.complete(source_instance, request, callback_spy)

      -- Verify callback was called with initial suggestions
      local call_args = callback_spy.calls[1].refs[1]
      assert.equals(2, #call_args.items) -- Should suggest @file and @buffer
      assert.equals("file", call_args.items[1].label)
      assert.equals("buffer", call_args.items[2].label)
    end)

    it("should suggest file completions for @file: trigger", function()
      -- Setup directory content mocks
      local file_count = 0
      local test_files = {
        {"test.lua", "file"},
        {"src", "directory"}
      }
      
      _G.vim.loop.fs_scandir = function() return "mock_handle" end
      _G.vim.loop.fs_scandir_next = function()
        file_count = file_count + 1
        if file_count <= #test_files then
          return test_files[file_count][1], test_files[file_count][2]
        else
          return nil
        end
      end
      
      -- Setup a source instance
      local source_instance = completion.new()

      -- Create a callback spy
      local callback_spy = spy.new(function() end)

      -- Create a request for @file: path
      local request = {
        context = { cursor_before_line = "@file:" },
        offset = 6
      }

      -- Call complete
      source_instance.complete(source_instance, request, callback_spy)

      -- Verify callback was called with file list
      local call_args = callback_spy.calls[1].refs[1]
      assert.equals(2, #call_args.items)
      assert.equals("test.lua", call_args.items[1].label)
      assert.equals("src/", call_args.items[2].label)
    end)
  end)
end)
