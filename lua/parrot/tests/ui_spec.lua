local ui = require("parrot.ui")

describe("ui", function()
  describe("template_replace", function()
    it("should replace key with value in template", function()
      local template = "Hello {{name}}!"
      local result = ui.template_replace(template, "{{name}}", "World")
      assert.are.equal("Hello World!", result)
    end)

    it("should remove key if value is nil", function()
      local template = "Hello {{name}}!"
      local result = ui.template_replace(template, "{{name}}", nil)
      assert.are.equal("Hello !", result)
    end)

    it("should handle table values", function()
      local template = "Items: {{items}}"
      local result = ui.template_replace(template, "{{items}}", { "apple", "banana", "cherry" })
      assert.are.equal("Items: apple\nbanana\ncherry", result)
    end)
  end)

  describe("template_render", function()
    it("should render multiple key-value pairs", function()
      local template = "{{greeting}} {{name}}! You are {{age}} years old."
      local key_value_pairs = {
        ["{{greeting}}"] = "Hello",
        ["{{name}}"] = "Alice",
        ["{{age}}"] = "30",
      }
      local result = ui.template_render(template, key_value_pairs)
      assert.are.equal("Hello Alice! You are 30 years old.", result)
    end)

    it("should return nil if template is nil", function()
      local result = ui.template_render(nil, {})
      assert.is_nil(result)
    end)
  end)

  describe("create_popup", function()
    it("should create a popup window", function()
      local buf, win, close, resize = ui.create_popup(nil, "Test Popup", function()
        return 50, 10, 5, 10
      end)
      assert.is_not_nil(buf)
      assert.is_not_nil(win)
      assert.is_function(close)
      assert.is_function(resize)
      close()
    end)
  end)
end)
