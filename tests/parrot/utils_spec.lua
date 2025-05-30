local utils = require("parrot.utils")

describe("utils", function()
  describe("trim", function()
    it("should trim leading whitespace and tabs", function()
      local input = "  \t  Hello, World!\n\t  Goodbye!"
      local expected = "Hello, World!\nGoodbye!"
      assert.are.equal(expected, utils.trim(input))
    end)
  end)

  describe("feedkeys", function()
    it("should call vim.api.nvim_feedkeys with correct arguments", function()
      local original_nvim_feedkeys = vim.api.nvim_feedkeys
      local called_with = {}
      vim.api.nvim_feedkeys = function(keys, mode, escape)
        called_with = { keys = keys, mode = mode, escape = escape }
      end

      utils.feedkeys("iHello<Esc>", "n")

      assert.are.same({
        keys = vim.api.nvim_replace_termcodes("iHello<Esc>", true, false, true),
        mode = "n",
        escape = true,
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
      local messages = { { role = "user", content = "Hello" } }
      local model = "gpt-3.5-turbo"
      local params = {}
      local result = utils.prepare_payload(messages, model, params)
      assert.are.same({
        messages = messages,
        stream = true,
        model = "gpt-3.5-turbo",
      }, result)
    end)

    it("should prepare payload with table model", function()
      local messages = { { role = "user", content = "Hello" } }
      local model = "gpt-4"
      local params = { temperature = 0.7, top_p = 0.9 }
      local result = utils.prepare_payload(messages, model, params)
      assert.are.same({
        messages = messages,
        stream = true,
        model = "gpt-4",
        temperature = 0.7,
        top_p = 0.9,
      }, result)
    end)

    it("should clamp temperature and top_p values", function()
      local messages = { { role = "user", content = "Hello" } }
      local model = "test-model"
      local params = { temperature = 3, top_p = 1.5 }
      local result = utils.prepare_payload(messages, model, params)
      assert.are.same({
        messages = messages,
        stream = true,
        model = "test-model",
        temperature = 2,
        top_p = 1,
      }, result)
    end)
  end)

  describe("has_valid_key", function()
    it("should return true if table has at least one valid key", function()
      local table = { a = 1, b = 2, c = 3 }
      assert.is_true(utils.has_valid_key(table, { "b", "d", "e" }))
      assert.is_false(utils.has_valid_key(table, { "d", "e", "f" }))
    end)
  end)

  describe("contains", function()
    it("should return true if table contains the value", function()
      local table = { 1, 2, 3, 4, 5 }
      assert.is_true(utils.contains(table, 3))
      assert.is_false(utils.contains(table, 6))
    end)
  end)

  describe("filter_payload_parameters", function()
    it("should filter payload parameters correctly", function()
      local valid_parameters = {
        ["contents"] = true,
        ["system_instruction"] = true,
        ["generationConfig"] = {
          ["stopSequences"] = true,
          ["temperature"] = true,
          ["maxOutputTokens"] = true,
          ["topP"] = true,
          ["topK"] = true,
        },
      }

      local old_payload = {
        contents = {
          {
            parts = {
              {
                text = "Hello World",
              },
            },
            role = "user",
          },
        },
        maxOutputTokens = 8192,
        messages = {
          {
            content = "Hello World",
            role = "user",
          },
        },
        model = "gemini-1.5-flash",
        stream = true,
        temperature = 0.8,
        topK = 10,
        topP = 1,
      }

      local expected_new_payload = {
        contents = {
          {
            parts = {
              {
                text = "Hello World",
              },
            },
            role = "user",
          },
        },
        generationConfig = {
          maxOutputTokens = 8192,
          temperature = 0.8,
          topK = 10,
          topP = 1,
        },
      }

      local new_payload = utils.filter_payload_parameters(valid_parameters, old_payload)
      assert.are.same(expected_new_payload, new_payload)
    end)
    it("should filter payload empty tables correctly", function()
      local valid_parameters = {
        ["contents"] = true,
        ["system_instruction"] = true,
        ["generationConfig"] = {
          ["stopSequences"] = true,
          ["temperature"] = true,
          ["maxOutputTokens"] = true,
          ["topP"] = true,
          ["topK"] = true,
        },
      }

      local old_payload = {
        contents = {
          {
            parts = {
              {
                text = "Hello World",
              },
            },
            role = "user",
          },
        },
        maxOutputTokens = 8192,
        messages = {
          {
            content = "Hello World",
            role = "user",
          },
        },
        model = "gemini-1.5-flash",
        stream = true,
        temperature = 0.8,
        topK = 10,
        topP = 1,
        generationConfig = {},
      }

      local expected_new_payload = {
        contents = {
          {
            parts = {
              {
                text = "Hello World",
              },
            },
            role = "user",
          },
        },
      }

      local new_payload = utils.filter_payload_parameters(valid_parameters, old_payload)
      assert.are.same(expected_new_payload, new_payload)
    end)
  end)

  describe("parse_raw_response", function()
    it("should handle HTML error response", function()
      local input = {
        "<html>",
        "<head><title>401 Authorization Required</title></head>",
        "<body>",
        "<center><h1>401 Authorization Required</h1></center>",
        "<hr><center>openresty/1.25.3.1</center>",
        "</body>",
        "</html>",
      }
      local expected =
        "<html> <head><title>401 Authorization Required</title></head> <body> <center><h1>401 Authorization Required</h1></center> <hr><center>openresty/1.25.3.1</center> </body> </html>"
      assert.are.equal(expected, utils.parse_raw_response(input))
    end)

    it("should handle authentication error JSON", function()
      local input = { '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}' }
      local expected = '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}'
      assert.are.equal(expected, utils.parse_raw_response(input))
    end)

    it("should handle API key error JSON", function()
      local input = {
        "{",
        '  "error": {',
        '    "code": 400,',
        '    "message": "API key not valid. Please pass a valid API key.",',
        '    "status": "INVALID_ARGUMENT",',
        '    "details": [',
        "      {",
        '        "@type": "type.googleapis.com/google.rpc.ErrorInfo",',
        '        "reason": "API_KEY_INVALID",',
        '        "domain": "googleapis.com",',
        '        "metadata": {',
        '          "service": "generativelanguage.googleapis.com"',
        "        }",
        "      }",
        "    ]",
        "  }",
        "}",
      }
      local expected =
        '{   "error": {     "code": 400,     "message": "API key not valid. Please pass a valid API key.",     "status": "INVALID_ARGUMENT",     "details": [       {         "@type": "type.googleapis.com/google.rpc.ErrorInfo",         "reason": "API_KEY_INVALID",         "domain": "googleapis.com",         "metadata": {           "service": "generativelanguage.googleapis.com"         }       }     ]   } }'
      assert.are.equal(expected, utils.parse_raw_response(input))
    end)

    it("should handle string input", function()
      local input = "Hello, World!"
      assert.are.equal(input, utils.parse_raw_response(input))
    end)

    it("should handle nil input", function()
      assert.is_nil(utils.parse_raw_response(nil))
    end)
  end)
end)

describe("utils improved error handling", function()
  local original_logger
  local log_calls = {}

  before_each(function()
    -- Mock logger to capture calls
    original_logger = require("parrot.logger")
    package.loaded["parrot.logger"] = {
      error = function(msg, context)
        table.insert(log_calls, { type = "error", msg = msg, context = context })
      end,
      warning = function(msg, context)
        table.insert(log_calls, { type = "warning", msg = msg, context = context })
      end,
      debug = function(msg, context)
        table.insert(log_calls, { type = "debug", msg = msg, context = context })
      end,
    }
    -- Clear log calls
    log_calls = {}
    -- Reload utils to get the mocked logger
    package.loaded["parrot.utils"] = nil
    utils = require("parrot.utils")
  end)

  after_each(function()
    -- Restore original logger
    package.loaded["parrot.logger"] = original_logger
    package.loaded["parrot.utils"] = nil
    utils = require("parrot.utils")
  end)

  describe("undojoin", function()
    it("should return false for invalid buffer number", function()
      local result = utils.undojoin("invalid")
      assert.is_false(result)
      assert.equal(1, #log_calls)
      assert.equal("warning", log_calls[1].type)
      assert.matches("invalid buffer number", log_calls[1].msg)
    end)

    it("should return false for nil buffer", function()
      local result = utils.undojoin(nil)
      assert.is_false(result)
      assert.equal(1, #log_calls)
      assert.equal("warning", log_calls[1].type)
    end)

    it("should handle valid buffer gracefully", function()
      local buf = vim.api.nvim_create_buf(false, true)
      local result = utils.undojoin(buf)
      assert.is_boolean(result)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("prepare_payload", function()
    it("should return nil for invalid messages", function()
      local result = utils.prepare_payload("invalid", "model", {})
      assert.is_nil(result)
      assert.equal(1, #log_calls)
      assert.equal("error", log_calls[1].type)
      assert.matches("messages must be a table", log_calls[1].msg)
    end)

    it("should return nil for invalid model name", function()
      local result = utils.prepare_payload({}, 123, {})
      assert.is_nil(result)
      assert.equal(1, #log_calls)
      assert.equal("error", log_calls[1].type)
      -- Debug: check what the actual message is
      local actual_msg = log_calls[1].msg
      assert.truthy(
        actual_msg and actual_msg:find("model_name"),
        "Expected message to contain 'model_name', got: " .. tostring(actual_msg)
      )
    end)

    it("should return nil for empty model name", function()
      local result = utils.prepare_payload({}, "", {})
      assert.is_nil(result)
      assert.equal(1, #log_calls)
      assert.equal("error", log_calls[1].type)
    end)

    it("should return nil for invalid params", function()
      local result = utils.prepare_payload({}, "model", "invalid")
      assert.is_nil(result)
      assert.equal(1, #log_calls)
      assert.equal("error", log_calls[1].type)
      assert.matches("params must be a table", log_calls[1].msg)
    end)

    it("should handle invalid temperature values", function()
      local result = utils.prepare_payload(
        { { role = "user", content = "test" } },
        "model",
        { temperature = "invalid" }
      )
      assert.is_table(result)
      assert.equal(1, result.temperature)
      assert.equal(1, #log_calls)
      assert.equal("warning", log_calls[1].type)
      assert.matches("invalid temperature value", log_calls[1].msg)
    end)

    it("should handle invalid top_p values", function()
      local result = utils.prepare_payload({ { role = "user", content = "test" } }, "model", { top_p = "invalid" })
      assert.is_table(result)
      assert.equal(1, result.top_p)
      assert.equal(1, #log_calls)
      assert.equal("warning", log_calls[1].type)
      assert.matches("invalid top_p value", log_calls[1].msg)
    end)
  end)

  describe("is_chat", function()
    it("should return false for invalid buffer", function()
      local result = utils.is_chat("invalid", "file.md", "/chat")
      assert.is_false(result)
      assert.equal(0, #log_calls) -- Should fail validation silently
    end)

    it("should return false for empty file name", function()
      local buf = vim.api.nvim_create_buf(false, true)
      local result = utils.is_chat(buf, "", "/chat")
      assert.is_false(result)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should return false for empty chat dir", function()
      local buf = vim.api.nvim_create_buf(false, true)
      local result = utils.is_chat(buf, "file.md", "")
      assert.is_false(result)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("append_selection", function()
    it("should return false for invalid params", function()
      local buf1 = vim.api.nvim_create_buf(false, true)
      local buf2 = vim.api.nvim_create_buf(false, true)

      local result = utils.append_selection("invalid", buf1, buf2, "")
      assert.is_false(result)
      assert.equal(1, #log_calls)
      assert.equal("error", log_calls[1].type)
      assert.matches("invalid params", log_calls[1].msg)

      vim.api.nvim_buf_delete(buf1, { force = true })
      vim.api.nvim_buf_delete(buf2, { force = true })
    end)

    it("should return false for invalid origin buffer", function()
      local buf = vim.api.nvim_create_buf(false, true)
      local params = { line1 = 1, line2 = 2 }

      local result = utils.append_selection(params, 999999, buf, "") -- Use invalid but numeric buffer ID
      assert.is_false(result)
      assert.equal(1, #log_calls)
      assert.equal("error", log_calls[1].type)
      assert.matches("invalid origin buffer", log_calls[1].msg)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should return false for invalid target buffer", function()
      local buf = vim.api.nvim_create_buf(false, true)
      local params = { line1 = 1, line2 = 2 }

      local result = utils.append_selection(params, buf, 999999, "") -- Use invalid but numeric buffer ID
      assert.is_false(result)
      assert.equal(1, #log_calls)
      assert.equal("error", log_calls[1].type)
      assert.matches("invalid target buffer", log_calls[1].msg)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("has_valid_key", function()
    it("should return false for non-table input", function()
      local result = utils.has_valid_key("invalid", { "key1", "key2" })
      assert.is_false(result)
    end)

    it("should return false for invalid valid_keys", function()
      local result = utils.has_valid_key({ key1 = "value" }, "invalid")
      assert.is_false(result)
    end)
  end)

  describe("contains", function()
    it("should return false for non-table input", function()
      local result = utils.contains("invalid", "value")
      assert.is_false(result)
    end)
  end)

  describe("filter_payload_parameters", function()
    it("should return empty table for invalid inputs", function()
      local result = utils.filter_payload_parameters("invalid", {})
      assert.same({}, result)
      assert.equal(1, #log_calls)
      assert.equal("error", log_calls[1].type)
      assert.matches("invalid input types", log_calls[1].msg)
    end)
  end)

  describe("parse_raw_response", function()
    it("should handle nil input", function()
      local result = utils.parse_raw_response(nil)
      assert.is_nil(result)
    end)

    it("should handle string input", function()
      local result = utils.parse_raw_response("test")
      assert.equal("test", result)
    end)

    it("should handle array table input", function()
      local result = utils.parse_raw_response({ "a", "b", "c" })
      assert.equal("a b c", result)
    end)

    it("should handle object table input", function()
      local result = utils.parse_raw_response({ key = "value" })
      assert.matches("key", result)
      assert.matches("value", result)
    end)

    it("should handle other types", function()
      local result = utils.parse_raw_response(123)
      assert.equal("123", result)
    end)
  end)

  describe("path_split", function()
    it("should return empty table for non-string input", function()
      local result = utils.path_split(123)
      assert.same({}, result)
      assert.equal(1, #log_calls)
      assert.equal("error", log_calls[1].type)
      assert.matches("path must be a string", log_calls[1].msg)
    end)

    it("should return empty table for empty string", function()
      local result = utils.path_split("")
      assert.same({}, result)
    end)
  end)

  describe("path_join", function()
    it("should return empty string for no arguments", function()
      local result = utils.path_join()
      assert.equal("", result)
      assert.equal(1, #log_calls)
      assert.equal("warning", log_calls[1].type)
      assert.matches("no arguments provided", log_calls[1].msg)
    end)

    it("should return empty string for non-string argument", function()
      local result = utils.path_join("valid", 123, "path")
      assert.equal("", result)
      assert.equal(1, #log_calls)
      assert.equal("error", log_calls[1].type)
      assert.matches("argument must be string", log_calls[1].msg)
    end)

    it("should warn for all empty arguments", function()
      local result = utils.path_join("", "/", "//")
      assert.equal("", result)
      assert.equal(1, #log_calls)
      assert.equal("warning", log_calls[1].type)
      assert.matches("all arguments were empty", log_calls[1].msg)
    end)
  end)
end)
