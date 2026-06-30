local comp_utils = require("parrot.completion.utils")
local mock = require("luassert.mock")
local async = require("plenary.async")

describe("completion.utils", function()
  describe("resolve_path", function()
    it("should resolve relative paths correctly", function()
      local cwd = vim.fn.getcwd()
      local result = comp_utils.resolve_path("test/path", cwd)
      assert.are.equal(cwd .. "/test", result)
    end)

    it("should handle absolute paths correctly", function()
      local result = comp_utils.resolve_path("/absolute/path/file.txt", "")
      assert.are.equal("/absolute/path", result)
    end)

    it("should handle paths with trailing slashes", function()
      local result = comp_utils.resolve_path("test/path/", "")
      assert.are.equal("test/path/", result)
    end)

    it("should handle empty path with cwd", function()
      local cwd = vim.fn.getcwd()
      local result = comp_utils.resolve_path("", cwd)
      assert.are.equal(cwd, result)
    end)
  end)

  describe("get_command_documentation", function()
    it("should return documentation for known commands", function()
      local file_doc = comp_utils.get_command_documentation("file")
      assert.is_string(file_doc)
      assert.is_true(file_doc:find("@file:") > 0)

      local buffer_doc = comp_utils.get_command_documentation("buffer")
      assert.is_string(buffer_doc)
      assert.is_true(buffer_doc:find("@buffer:") > 0)

      local dir_doc = comp_utils.get_command_documentation("directory")
      assert.is_string(dir_doc)
      assert.is_true(dir_doc:find("@directory:") > 0)
    end)

    it("should return empty string for unknown commands", function()
      assert.are.equal("", comp_utils.get_command_documentation("unknown"))
    end)
  end)

  describe("is_completion_available", function()
    it("should return true in parrot chat files (path-based, including drafts)", function()
      local chat_dir = vim.fn.tempname() .. "_chat"
      vim.fn.mkdir(chat_dir, "p")
      local chat_file = chat_dir .. "/draft.md"

      local config = require("parrot.config")
      local orig_loaded = config.loaded
      local orig_chat_dir = config.options and config.options.chat_dir
      config.loaded = true
      config.options = vim.tbl_deep_extend("force", config.options or {}, { chat_dir = chat_dir })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, chat_file)
      vim.api.nvim_set_current_buf(buf)

      assert.is_true(comp_utils.is_completion_available(buf))

      config.loaded = orig_loaded
      if orig_chat_dir then
        config.options.chat_dir = orig_chat_dir
      end
      vim.api.nvim_buf_delete(buf, { force = true })
      vim.fn.delete(chat_dir, "rf")
    end)

    it("should return true in UI input buffers", function()
      local ns = vim.api.nvim_create_namespace("parrot_test_completion")
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
      vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
        virt_text = { { "Enter text here", "Comment" } },
      })

      assert.is_true(comp_utils.is_completion_available(buf))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should return false in regular files", function()
      local api_mock = mock(vim.api, true)
      api_mock.nvim_get_current_buf.returns(1)
      api_mock.nvim_buf_get_name.returns("somefile.txt")
      api_mock.nvim_get_option_value.returns("file")
      api_mock.nvim_get_namespaces.returns({})

      assert.is_false(comp_utils.is_completion_available())

      mock.revert(api_mock)
    end)
  end)

  -- describe("read_file_async", function()
  --   it("should read file content asynchronously", function()
  --     local uv_mock = mock(vim.uv, true)
  --     uv_mock.fs_open.returns(1)
  --     uv_mock.fs_read.returns("test content")
  --     uv_mock.fs_close.returns(true)

  --     local content
  --     async.run(function()
  --       comp_utils.read_file_async("test.txt", 1024, async).map(function(data)
  --         content = data
  --       end)
  --     end)

  --     vim.wait(100, function() return content ~= nil end)
  --     assert.are.equal("test content", content)

  --     mock.revert(uv_mock)
  --   end)
  -- end)
end)
