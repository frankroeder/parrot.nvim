local comp_utils = require("parrot.completion.utils")
local mock = require("luassert.mock")

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
    it("should return true in parrot chat files", function()
      local config_mock = mock(require("parrot.config"), true)
      config_mock.loaded = true
      config_mock.options = { chat_dir = "/mock/chat/dir" }

      local utils_mock = mock(require("parrot.utils"), true)
      utils_mock.is_chat.returns(true)

      local api_mock = mock(vim.api, true)
      api_mock.nvim_get_current_buf.returns(1)
      api_mock.nvim_buf_get_name.returns("/mock/chat/dir/test.txt")

      assert.is_true(comp_utils.is_completion_available())

      mock.revert(config_mock)
      mock.revert(utils_mock)
      mock.revert(api_mock)
    end)

    it("should return true in UI input buffers", function()
      local api_mock = mock(vim.api, true)
      api_mock.nvim_get_current_buf.returns(1)
      api_mock.nvim_buf_get_name.returns("")
      api_mock.nvim_get_option_value.returns("nofile")
      api_mock.nvim_get_namespaces.returns({ 1 })
      api_mock.nvim_buf_get_extmarks.returns({
        { 1, 0, 0, { virt_text = { { "Enter text here", "Comment" } } } },
      })

      assert.is_true(comp_utils.is_completion_available())

      mock.revert(api_mock)
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

  describe("read_file", function()
    it("reads up to byte_limit bytes", function()
      local path = vim.fn.tempname()
      vim.fn.writefile({ "0123456789" }, path)
      local result
      comp_utils.read_file(path, 4, function(err, data)
        result = { err = err, data = data }
      end)
      vim.wait(1000, function()
        return result ~= nil
      end, 10)
      vim.fn.delete(path)
      assert.is_nil(result.err)
      assert.are.equal("0123", result.data)
    end)

    it("reports an error for a missing file", function()
      local result
      comp_utils.read_file(vim.fn.tempname(), 4, function(err, data)
        result = { err = err, data = data }
      end)
      vim.wait(1000, function()
        return result ~= nil
      end, 10)
      assert.is_not_nil(result.err)
      assert.is_nil(result.data)
    end)
  end)
end)
