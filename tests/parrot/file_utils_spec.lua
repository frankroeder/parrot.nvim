local file_utils = require("parrot.file_utils")
local async = require("plenary.async")

describe("file_utils", function()
  local temp_dir = "/tmp/parrot_test_" .. os.time()
  local test_file = temp_dir .. "/test.json"
  local test_data = { key = "value", number = 42, array = { 1, 2, 3 } }

  before_each(function()
    -- Create temp directory for tests
    os.execute("mkdir -p " .. temp_dir)
  end)

  after_each(function()
    -- Clean up temp directory
    os.execute("rm -rf " .. temp_dir)
  end)

  describe("file_to_table", function()
    it("should read and decode JSON file correctly", function()
      -- Write test data to file
      local file = io.open(test_file, "w")
      file:write(vim.json.encode(test_data))
      file:close()

      local result = file_utils.file_to_table(test_file)
      assert.are.same(test_data, result)
    end)

    it("should return nil for non-existent file", function()
      local result = file_utils.file_to_table("/non/existent/file.json")
      assert.is_nil(result)
    end)

    it("should return nil for invalid JSON", function()
      -- Write invalid JSON to file
      local file = io.open(test_file, "w")
      file:write("{ invalid json }")
      file:close()

      local result = file_utils.file_to_table(test_file)
      assert.is_nil(result)
    end)

    it("should return nil for empty file", function()
      -- Create empty file
      local file = io.open(test_file, "w")
      file:close()

      local result = file_utils.file_to_table(test_file)
      assert.is_nil(result)
    end)
  end)

  describe("table_to_file", function()
    it("should write table to JSON file correctly", function()
      file_utils.table_to_file(test_data, test_file)

      -- Read back and verify
      local file = io.open(test_file, "r")
      local content = file:read("*a")
      file:close()

      local decoded = vim.json.decode(content)
      assert.are.same(test_data, decoded)
    end)

    it("should handle invalid file path gracefully", function()
      -- This should not throw an error
      file_utils.table_to_file(test_data, "/invalid/path/file.json")
    end)

    it("should handle tables with circular references", function()
      local circular_table = { key = "value" }
      circular_table.self = circular_table

      -- This should not crash
      file_utils.table_to_file(circular_table, test_file)
    end)
  end)

  describe("find_git_root", function()
    it("should find git root directory", function()
      -- Create a fake git directory
      local git_dir = temp_dir .. "/.git"
      os.execute("mkdir -p " .. git_dir)

      -- Change to test directory
      local original_cwd = vim.fn.getcwd()
      vim.cmd("cd " .. temp_dir)

      local result = file_utils.find_git_root()
      -- Use the real path since macOS /tmp may resolve to /private/tmp
      local expected = vim.fn.resolve(temp_dir)
      assert.equal(expected, result)

      -- Restore original directory
      vim.cmd("cd " .. original_cwd)
    end)

    it("should return empty string when no git root found", function()
      -- Change to tmp directory without git
      local original_cwd = vim.fn.getcwd()
      vim.cmd("cd /tmp")

      local result = file_utils.find_git_root()
      assert.equal("", result)

      -- Restore original directory
      vim.cmd("cd " .. original_cwd)
    end)
  end)

  describe("delete_file", function()
    it("should delete file from buffer and filesystem", function()
      -- Create test file
      local file = io.open(test_file, "w")
      file:write("test content")
      file:close()

      file_utils.delete_file(test_file, temp_dir)

      -- File should be gone
      assert.is_nil(io.open(test_file, "r"))
    end)

    it("should handle nil file parameter", function()
      -- Should not crash
      file_utils.delete_file(nil, temp_dir)
    end)

    it("should handle file not in target directory", function()
      -- Should not crash and should not delete the file
      file_utils.delete_file("/etc/passwd", temp_dir)
    end)

    it("should handle non-existent file", function()
      -- Should not crash
      file_utils.delete_file(temp_dir .. "/non_existent.txt", temp_dir)
    end)
  end)

  describe("read_file", function()
    it("should read file content correctly", function()
      local content = "Hello, World!"
      local file = io.open(test_file, "w")
      file:write(content)
      file:close()

      local result = file_utils.read_file(test_file)
      assert.equal(content, result)
    end)

    it("should return nil for nil path", function()
      local result = file_utils.read_file(nil)
      assert.is_nil(result)
    end)

    it("should return empty string for non-existent file", function()
      local result = file_utils.read_file("/non/existent/file.txt")
      assert.equal("", result)
    end)
  end)

  describe("write_file", function()
    it("should write content to file correctly", function()
      local content = "Hello, World!"
      local success = file_utils.write_file(test_file, content)
      assert.is_true(success)

      -- Verify content
      local file = io.open(test_file, "r")
      local read_content = file:read("*a")
      file:close()
      assert.equal(content, read_content)
    end)

    it("should return false for invalid path", function()
      local success = file_utils.write_file("/invalid/path/file.txt", "content")
      assert.is_false(success)
    end)
  end)

  describe("find_repo_instructions", function()
    it("should return instructions from .parrot.md file", function()
      -- Create a fake git directory
      local git_dir = temp_dir .. "/.git"
      os.execute("mkdir -p " .. git_dir)

      -- Create .parrot.md file
      local parrot_file = temp_dir .. "/.parrot.md"
      local instructions = "These are test instructions\nLine 2"
      local file = io.open(parrot_file, "w")
      file:write(instructions)
      file:close()

      -- Change to test directory
      local original_cwd = vim.fn.getcwd()
      vim.cmd("cd " .. temp_dir)

      local result = file_utils.find_repo_instructions()
      assert.equal(instructions, result)

      -- Restore original directory
      vim.cmd("cd " .. original_cwd)
    end)

    it("should return empty string when no git root", function()
      local original_cwd = vim.fn.getcwd()
      vim.cmd("cd /tmp")

      local result = file_utils.find_repo_instructions()
      assert.equal("", result)

      vim.cmd("cd " .. original_cwd)
    end)

    it("should return empty string when no .parrot.md file", function()
      -- Create a fake git directory but no .parrot.md
      local git_dir = temp_dir .. "/.git"
      os.execute("mkdir -p " .. git_dir)

      local original_cwd = vim.fn.getcwd()
      vim.cmd("cd " .. temp_dir)

      local result = file_utils.find_repo_instructions()
      assert.equal("", result)

      vim.cmd("cd " .. original_cwd)
    end)
  end)
end)
