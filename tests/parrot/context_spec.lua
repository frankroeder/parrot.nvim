local context = require("parrot.context")

describe("context", function()
  describe("cmd_split", function()
    it("should split a string by colons", function()
      local cmd = "part1:part2:part3"
      local parts = context.cmd_split(cmd)
      assert.are.same({ "part1", "part2", "part3" }, parts)
    end)

    it("should handle empty strings", function()
      local cmd = ""
      local parts = context.cmd_split(cmd)
      assert.are.same({ "" }, parts)
    end)

    it("should handle strings with no colons", function()
      local cmd = "nocolonshere"
      local parts = context.cmd_split(cmd)
      assert.are.same({ "nocolonshere" }, parts)
    end)
  end)

  describe("insert_contexts", function()
    local logger = require("parrot.logger")
    local original_error = logger.error
    local error_messages = {}

    before_each(function()
      -- Create test directory if it doesn't exist.
      vim.fn.mkdir("test", "p")

      -- Mock logger.error to capture error messages.
      error_messages = {}
      logger.error = function(msg)
        table.insert(error_messages, msg)
        original_error(msg)
      end
    end)

    after_each(function()
      -- Clean up test files.
      vim.fn.delete("test/test_file.txt")
      vim.fn.delete("test/file1.txt")
      vim.fn.delete("test/file2.java")
      vim.fn.delete("test/buffer.lua")
      vim.fn.delete("test/file with spaces.txt")
      logger.error = original_error
    end)

    it("should return the original message if no @file or @buffer commands are present", function()
      local msg = "This is a test message."
      local result = context.insert_contexts(msg)
      assert.are.equal(msg, result)
    end)

    it("should handle invalid input gracefully", function()
      local invalid_inputs = { nil, 123, {}, function() end }
      for _, input in ipairs(invalid_inputs) do
        error_messages = {}
        local result = context.insert_contexts(input)
        assert.are.equal("", result)
        assert.is_true(#error_messages > 0, "Expected error message for invalid input")
        assert.is_true(
          string.match(error_messages[1], "Invalid message") ~= nil,
          "Error message should mention invalid message"
        )
      end
    end)

    it("should insert content from a file when using @file command", function()
      local expected_content = "This is the content of the test file."
      vim.fn.writefile({ expected_content }, "test/test_file.txt")
      local absolute_path = vim.fn.fnamemodify("test/test_file.txt", ":p")
      local msg = "Test message with\n@file:test/test_file.txt"
      local result = context.insert_contexts(msg)
      local expected = "Test message with\n\n" .. absolute_path .. "\n```\n" .. expected_content .. "\n```"
      assert.are.equal(expected, result)
    end)

    it("should correctly handle buffers", function()
      vim.fn.writefile(
        { "local test_buffer_content = 'this is a buffer'", "print(test_buffer_content)" },
        "test/buffer.lua"
      )
      vim.cmd("edit test/buffer.lua")
      local buf_id = vim.api.nvim_get_current_buf()
      local buf_name = vim.api.nvim_buf_get_name(buf_id)
      local result_current_buffer = context.insert_contexts("@buffer:" .. buf_name)
      local buf_content = table.concat(vim.api.nvim_buf_get_lines(buf_id, 0, -1, false), "\n")

      local expected = "\n\n" .. buf_name .. "\n```lua\n" .. buf_content .. "\n```"
      assert.are.equal(expected, result_current_buffer)

      local non_existent_buffer = "@buffer:non_existent_buffer.lua"
      local result_buffer_not_found = context.insert_contexts(non_existent_buffer)
      assert.are.equal("", result_buffer_not_found)
    end)

    it("should handle multiple commands", function()
      local file1_content = "Content of file 1."
      local file2_content = "Content of file 2."
      vim.fn.writefile({ file1_content }, "test/file1.txt")
      vim.fn.writefile({ file2_content }, "test/file2.java")
      local absolute_path1 = vim.fn.fnamemodify("test/file1.txt", ":p")
      local absolute_path2 = vim.fn.fnamemodify("test/file2.java", ":p")
      local msg = "Message with multiple commands:\n@file:test/file1.txt\n@file:test/file2.java"
      local result = context.insert_contexts(msg)
      local expected_result = "Message with multiple commands:\n\n"
        .. absolute_path1
        .. "\n```\n"
        .. file1_content
        .. "\n```\n\n"
        .. absolute_path2
        .. "\n```java\n"
        .. file2_content
        .. "\n```"
      assert.are.equal(expected_result, result)
    end)

    it("should handle non-existent files gracefully", function()
      local msg = "This is a test with\n@file:non-existent-file.txt"
      local result = context.insert_contexts(msg)
      -- The command is removed and no context appended if file not found.
      assert.are.equal("This is a test with", result)
    end)

    it("should handle special characters in file paths", function()
      local file_name_with_spaces = "test/file with spaces.txt"
      local file_content = "This is file with spaces!"
      vim.fn.writefile({ file_content }, file_name_with_spaces)
      local absolute_path = vim.fn.fnamemodify(file_name_with_spaces, ":p")
      local msg = "test message.\n@file:test/file with spaces.txt"
      local result = context.insert_contexts(msg)
      local expected = "test message.\n\n" .. absolute_path .. "\n```\n" .. file_content .. "\n```"
      assert.are.equal(expected, result)
    end)

    it("should strip all whitespace at end including newline", function()
      local msg = "Some message\n\n"
      local processed_message = context.insert_contexts(msg)
      assert.are.equal("Some message", processed_message)
    end)
  end)
end)
