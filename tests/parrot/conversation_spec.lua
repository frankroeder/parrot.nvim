local Conversation = require("parrot.conversation")

local opts = { user_prefix = "🗨:", llm_prefix = "🦜:" }

describe("Conversation", function()
  describe("messages", function()
    it("should append messages in order", function()
      local conv = Conversation:new()
      conv:add_system_message("sys")
      conv:add_user_message("hi")
      conv:add_message("assistant", "yo")
      assert.equals(3, conv:count())
      assert.are.same({
        { role = "system", content = "sys" },
        { role = "user", content = "hi" },
        { role = "assistant", content = "yo" },
      }, conv:get_messages())
    end)

    it("should ignore empty or invalid roles", function()
      local conv = Conversation:new()
      assert.is_nil(conv:add_message(nil, nil))
      assert.is_nil(conv:add_message("", "x"))
      assert.is_nil(conv:add_message("tool", "x"))
      assert.equals(0, conv:count())
    end)

    it("should map over message content", function()
      local conv = Conversation:new()
      conv:add_user_message("a")
      conv:add_user_message("b")
      conv:map_content(function(c)
        return c:upper()
      end)
      assert.equals("A", conv:get_messages()[1].content)
      assert.equals("B", conv:get_messages()[2].content)
    end)
  end)

  describe("set_system_message", function()
    it("should prepend a system message when none exists", function()
      local conv = Conversation:new()
      conv:add_user_message("hi")
      conv:set_system_message("be nice")
      assert.are.same({
        { role = "system", content = "be nice" },
        { role = "user", content = "hi" },
      }, conv:get_messages())
    end)

    it("should replace an existing system message", function()
      local conv = Conversation:new()
      conv:add_system_message("old")
      conv:add_user_message("hi")
      conv:set_system_message("new")
      assert.are.same({
        { role = "system", content = "new" },
        { role = "user", content = "hi" },
      }, conv:get_messages())
    end)

    it("should unescape newlines", function()
      local conv = Conversation:new()
      conv:set_system_message("one\\ntwo")
      assert.equals("one\ntwo", conv:get_messages()[1].content)
    end)

    it("should no-op for blank content", function()
      local conv = Conversation:new()
      conv:add_user_message("hi")
      conv:set_system_message("   ")
      conv:set_system_message(nil)
      assert.are.same({ { role = "user", content = "hi" } }, conv:get_messages())
    end)
  end)

  describe("parse_headers", function()
    it("should parse header fields up to the --- line", function()
      local headers, header_end = Conversation.parse_headers({
        "# topic: ?",
        "- file: /tmp/x.md",
        "---",
        "🗨:",
        "hello",
      })
      assert.are.same({ topic = "?", file = "/tmp/x.md" }, headers)
      assert.equals(2, header_end)
    end)

    it("should return nil header_end when --- is missing", function()
      local headers, header_end = Conversation.parse_headers({ "# topic: ?", "🗨:" })
      assert.are.same({ topic = "?" }, headers)
      assert.is_nil(header_end)
    end)
  end)

  describe("from_chat_buffer", function()
    local lines = {
      "# topic: ?",
      "---",
      "🗨: first question",
      "more context",
      "🦜:",
      "the answer",
      "🗨: second question",
    }

    it("should build user/assistant messages without empty-role placeholders", function()
      local conv, headers = Conversation.from_chat_buffer(lines, opts)
      assert.are.same({ topic = "?" }, headers)
      assert.are.same({
        { role = "user", content = " first question\nmore context" },
        { role = "assistant", content = "\nthe answer" },
        { role = "user", content = " second question" },
      }, conv:get_messages())
    end)

    it("should use the header system prompt over the fallback", function()
      local with_system = vim.deepcopy(lines)
      table.insert(with_system, 2, "# system: from header")
      local conv = Conversation.from_chat_buffer(
        with_system,
        vim.tbl_extend("force", opts, {
          system_prompt = "fallback",
        })
      )
      assert.are.same({ role = "system", content = "from header" }, conv:get_messages()[1])
    end)

    it("should fall back to the model system prompt", function()
      local conv = Conversation.from_chat_buffer(
        lines,
        vim.tbl_extend("force", opts, {
          system_prompt = "fallback",
        })
      )
      assert.are.same({ role = "system", content = "fallback" }, conv:get_messages()[1])
    end)

    it("should honour a line range", function()
      local conv = Conversation.from_chat_buffer(lines, vim.tbl_extend("force", opts, { line1 = 7, line2 = 7 }))
      assert.are.same({
        { role = "user", content = " second question" },
      }, conv:get_messages())
    end)

    it("should error when the header separator is missing", function()
      local conv, err = Conversation.from_chat_buffer({ "# topic: ?", "🗨: hi" }, opts)
      assert.is_nil(conv)
      assert.is_true(err:match("^Error while parsing headers") ~= nil)
    end)
  end)

  describe("nth_last_user_line", function()
    local lines = { "---", "🗨: one", "🦜:", "a", "🗨: two", "🦜:", "b", "🗨: three" }

    it("should find the last user message", function()
      assert.equals(8, Conversation.nth_last_user_line(lines, 1, "🗨:"))
    end)

    it("should walk back n user messages", function()
      assert.equals(5, Conversation.nth_last_user_line(lines, 2, "🗨:"))
      assert.equals(2, Conversation.nth_last_user_line(lines, 3, "🗨:"))
    end)

    it("should clamp to the first line when n exceeds the message count", function()
      assert.equals(1, Conversation.nth_last_user_line(lines, 99, "🗨:"))
    end)
  end)
end)
