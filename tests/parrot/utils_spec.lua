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
      local model = nil
      local params = { temperature = 3, top_p = 1.5 }
      local result = utils.prepare_payload(messages, model, params)
      assert.are.same({
        messages = messages,
        stream = true,
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

  describe("generate_endpoint_hash", function()
    it("should generate consistent hash for string endpoints", function()
      local provider = {
        name = "openai",
        model_endpoint = "https://api.openai.com/v1/models",
      }
      local hash1 = utils.generate_endpoint_hash(provider)
      local hash2 = utils.generate_endpoint_hash(provider)
      assert.are.equal(hash1, hash2)
      assert.is_true(#hash1 == 8) -- 8 character hex string
    end)

    it("should generate different hashes for different endpoints", function()
      local provider1 = {
        name = "openai",
        model_endpoint = "https://api.openai.com/v1/models",
      }
      local provider2 = {
        name = "openai",
        model_endpoint = "https://api.different.com/v1/models",
      }
      local hash1 = utils.generate_endpoint_hash(provider1)
      local hash2 = utils.generate_endpoint_hash(provider2)
      assert.is_not.equal(hash1, hash2)
    end)

    it("should generate hash for function endpoints", function()
      local provider = {
        name = "gemini",
        model_endpoint = function(self)
          return "https://api.gemini.com/models?key=" .. self.api_key
        end,
      }
      local hash = utils.generate_endpoint_hash(provider)
      assert.is_true(#hash == 8)
      assert.are.equal(hash, utils.generate_endpoint_hash(provider))
    end)

    it("should generate hash for table endpoints", function()
      local provider = {
        name = "custom",
        model_endpoint = { "curl", "-X", "GET", "https://api.custom.com/models" },
      }
      local hash = utils.generate_endpoint_hash(provider)
      assert.is_true(#hash == 8)
      assert.are.equal(hash, utils.generate_endpoint_hash(provider))
    end)

    it("should return empty string for missing or empty endpoints", function()
      local provider1 = { name = "test" }
      local provider2 = { name = "test", model_endpoint = "" }
      local provider3 = { name = "test", model_endpoint = nil }

      assert.are.equal("", utils.generate_endpoint_hash(provider1))
      assert.are.equal("", utils.generate_endpoint_hash(provider2))
      assert.are.equal("", utils.generate_endpoint_hash(provider3))
    end)

    it("should include provider name in function hash for uniqueness", function()
      local provider1 = {
        name = "provider1",
        model_endpoint = function()
          return "test"
        end,
      }
      local provider2 = {
        name = "provider2",
        model_endpoint = function()
          return "test"
        end,
      }
      local hash1 = utils.generate_endpoint_hash(provider1)
      local hash2 = utils.generate_endpoint_hash(provider2)
      assert.is_not.equal(hash1, hash2)
    end)
  end)
end)
