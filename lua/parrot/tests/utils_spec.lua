local utils = require("parrot.utils")

describe("utils", function()
  describe("trim", function()
    it("should trim leading whitespace and tabs", function()
      local input = "  \t  Hello, World!\n\t  Goodbye!"
      local expected = "Hello, World!\nGoodbye!"
      assert.are.equal(expected, utils.trim(input))
    end)
  end)

  describe("once", function()
    it("should only call the function once", function()
      local count = 0
      local increment = utils.once(function() count = count + 1 end)
      increment()
      increment()
      increment()
      assert.are.equal(1, count)
    end)
  end)

  describe("feedkeys", function()
    it("should call vim.api.nvim_feedkeys with correct arguments", function()
      local original_nvim_feedkeys = vim.api.nvim_feedkeys
      local called_with = {}
      vim.api.nvim_feedkeys = function(keys, mode, escape)
        called_with = {keys = keys, mode = mode, escape = escape}
      end

      utils.feedkeys("iHello<Esc>", "n")

      assert.are.same({
        keys = vim.api.nvim_replace_termcodes("iHello<Esc>", true, false, true),
        mode = "n",
        escape = true
      }, called_with)

      vim.api.nvim_feedkeys = original_nvim_feedkeys
    end)
  end)

  describe("uuid", function()
    it("should generate a valid UUID", function()
      local uuid = utils.uuid()
      assert.are.equal(36, #uuid)
      assert.truthy(uuid:match("^%x%x%x%x%x%x%x%x_%x%x%x%x_4%x%x%x_[89ab]%x%x%x_%x%x%x%x%x%x%x%x%x%x%x%x$"))
    end)
  end)

  describe("starts_with", function()
    it("should return true when string starts with given substring", function()
      assert.is_true(utils.starts_with("Hello, World!", "Hello"))
      assert.is_false(utils.starts_with("Hello, World!", "World"))
    end)
  end)

  describe("ends_with", function()
    it("should return true when string ends with given substring", function()
      assert.is_true(utils.ends_with("Hello, World!", "World!"))
      assert.is_false(utils.ends_with("Hello, World!", "Hello"))
    end)
  end)

  describe("prepare_payload", function()
    it("should prepare payload with string model", function()
      local messages = {{"role", "user", "content", "Hello"}}
      local model = "gpt-3.5-turbo"
      local result = utils.prepare_payload(messages, model)
      assert.are.same({
        messages = messages,
        stream = true,
        model = "gpt-3.5-turbo"
      }, result)
    end)

    it("should prepare payload with table model", function()
      local messages = {{"role", "user", "content", "Hello"}}
      local model = {model = "gpt-4", temperature = 0.7, top_p = 0.9}
      local result = utils.prepare_payload(messages, model)
      assert.are.same({
        messages = messages,
        stream = true,
        model = "gpt-4",
        temperature = 0.7,
        top_p = 0.9
      }, result)
    end)
  end)

  describe("has_valid_key", function()
    it("should return true if table has at least one valid key", function()
      local table = {a = 1, b = 2, c = 3}
      assert.is_true(utils.has_valid_key(table, {"b", "d", "e"}))
      assert.is_false(utils.has_valid_key(table, {"d", "e", "f"}))
    end)
  end)

  describe("contains", function()
    it("should return true if table contains the value", function()
      local table = {1, 2, 3, 4, 5}
      assert.is_true(utils.contains(table, 3))
      assert.is_false(utils.contains(table, 6))
    end)
  end)
end)
