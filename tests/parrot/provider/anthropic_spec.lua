local assert = require("luassert")
local mock = require("luassert.mock")

-- Mock the required modules
local logger_mock = mock(require("parrot.logger"), true)

-- Load the Anthropic class
local Anthropic = require("lua.parrot.provider.anthropic")

describe("Anthropic", function()
  local anthropic

  before_each(function()
    anthropic = Anthropic:new("https://api.anthropic.com", "test_api_key")
    assert.are.same(anthropic.name, "anthropic")
  end)

  -- TODO: preprocess_payload output is nil --
  -- describe("preprocess_payload", function()
  --   it("should handle payload with system message correctly", function()
  --     local input = {
  --       max_tokens = 4096,
  --       messages = {
  --         {
  --           content = "You are a versatile AI assistant with capabilities\nextending to general knowledge and coding support. When engaging\nwith users, please adhere to the following guidelines to ensure\nthe highest quality of interaction:\n\n- Admit when unsure by saying 'I don't know.'\n- Ask for clarification when needed.\n- Use first principles thinking to analyze queries.\n- Start with the big picture, then focus on details.\n- Apply the Socratic method to enhance understanding.\n- Include all necessary code in your responses.\n- Stay calm and confident with each task.\n",
  --           role = "system",
  --         },
  --         { content = "Who are you?", role = "user" },
  --       },
  --       model = "claude-3-haiku-20240307",
  --       stream = true,
  --     }
  --
  --     local expected = {
  --       max_tokens = 4096,
  --       messages = {
  --         { content = "Who are you?", role = "user" },
  --       },
  --       model = "claude-3-haiku-20240307",
  --       stream = true,
  --       system = "You are a versatile AI assistant with capabilities\nextending to general knowledge and coding support. When engaging\nwith users, please adhere to the following guidelines to ensure\nthe highest quality of interaction:\n\n- Admit when unsure by saying 'I don't know.'\n- Ask for clarification when needed.\n- Use first principles thinking to analyze queries.\n- Start with the big picture, then focus on details.\n- Apply the Socratic method to enhance understanding.\n- Include all necessary code in your responses.\n- Stay calm and confident with each task.",
  --     }
  --
  --     local result = anthropic:preprocess_payload(input)
  --
  --     assert.are.same(expected, result)
  --   end)
  -- end)

  describe("verify", function()
    it("should return true for a valid API key", function()
      assert.is_true(anthropic:verify())
    end)

    it("should return false and log an error for an invalid API key", function()
      anthropic.api_key = ""
      assert.is_false(anthropic:verify())
      assert.spy(logger_mock.error).was_called()
    end)
  end)

  describe("process_onexit", function()
    it("should log an error message when there's an API error", function()
      local input = vim.json.encode({
        type = "error",
        error = { type = "authentication_error", message = "invalid x-api-key" },
      })

      anthropic:process_onexit(input)

      assert.spy(logger_mock.error).was_called_with("Anthropic - message: invalid x-api-key type: authentication_error")
    end)
  end)

  describe("process_stdout", function()
    it("should extract text from content_block_delta with text_delta", function()
      local input = '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello, world!"}}'

      local result = anthropic:process_stdout(input)

      assert.equals("Hello, world!", result)
    end)

    it("should return nil for non-text_delta messages", function()
      local input =
        '{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":8}}'

      local result = anthropic:process_stdout(input)

      assert.is_nil(result)
    end)

    it("should handle invalid JSON gracefully", function()
      local input = "invalid json"

      local result = anthropic:process_stdout(input)

      assert.is_nil(result)
    end)

    it("should handle empty input gracefully", function()
      local input = ""

      local result = anthropic:process_stdout(input)

      assert.is_nil(result)
    end)

    it("should fail to decode", function()
      local input = "{ content_block_delta text_delta }"

      local result = anthropic:process_stdout(input)

      assert.is_nil(result)
    end)
  end)
end)

-- Thinking process
--  curl https://api.anthropic.com/v1/messages \                                                                                                              22:53:45
--      --header "x-api-key: $ANTHROPIC_API_KEY" \
--      --header "anthropic-version: 2023-06-01" \
--      --header "content-type: application/json" \
--      --data \
-- '{
--     "model": "claude-3-7-sonnet-20250219",
--     "max_tokens": 20000,
--     "stream": true,
--     "thinking": {
--         "type": "enabled",
--         "budget_tokens": 16000
--     },
--     "messages": [
--         {
--             "role": "user",
--             "content": "What is 27 * 453?"
--         }
--     ]
-- }'

-- event: message_start
-- data: {"type":"message_start","message":{"id":"msg_017bnwLbFy7uzWgDGkS4FpK5","type":"message","role":"assistant","model":"claude-3-7-sonnet-20250219","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":44,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}} }

-- event: content_block_start
-- data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}           }

-- event: ping
-- data: {"type": "ping"}

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"To calculate 27"}       }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" * 453, I'll multiply these"}      }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" numbers step by step."}  }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"\n\nFirst, let me break this down:\n27 "}            }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"* 453 = (20"}               }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" + 7) * "}           }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"453\n         = 20 * 453"}               }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" + 7 * 453\n         "}              }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"= 9060 + 7"}    }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" * 453\n\nNow I need to calculate"}    }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" 7 * 453."}}

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"\n7 * 453 = 7"}  }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" * 400 "}}

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"+ 7 *"}   }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" 50 + 7 "}          }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"* 3\n        "}            }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"= 2800 + 350 +"}}

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" 21\n        ="}               }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" 3171\n\nSo,"}         }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" 27 * 453 = 9"}     }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"060 + 3"}         }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"171 = 12231.\n\nLet me"}    }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" double-check using the standar"}               }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"d multiplication algorithm:\n\n    453"}             }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"\n  ×  27\n  "}  }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"-----\n   3171"}              }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"  (7 × 453)"}        }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"\n  9060   (20 "}    }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"× 453)\n  -----\n  "}   }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"12231\n\nSo 27 * 453"} }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" = 12231."}    }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"ErUBCkYIARgCIkBWljGprkAg3jqP0QHtn6lZ+uduvsVrxQsZhpM26RFq+lmLbwPbv6Ow9qvUmnU5T7HlLD47T0vL6RcgyYOh77qmEgz1esz0owfDCYDrga0aDGviVWnJRQv6cOR4MSIwYU+28tQAdNJ3m74ryq86qEdZt8d/tXfdV67t9DNc5FXaP0T4ZelOAB6XbVcj3IONKh1UFyd1cHJrPfpbv1wQcW3lPCYbjkPUJUZP/XQH5g=="} }

-- event: content_block_stop
-- data: {"type":"content_block_stop","index":0         }

-- event: content_block_start
-- data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}     }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"To multiply 27 × "}     }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"453, I'll work"}              }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" through this step by step"}}

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":":\n\n    453\n  × 27"}  }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"\n  -----\n   "}   }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"3171  (7 × 453)"}          }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"\n   9060  (20 × "}               }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"453)\n  -----\n  12231"}   }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"\n\nTherefore, 27 ×"}           }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" 453 = 12,"}  }

-- event: content_block_delta
-- data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"231"}          }

-- event: content_block_stop
-- data: {"type":"content_block_stop","index":1            }

-- event: message_delta
-- data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":324}  }

-- event: message_stop
-- data: {"type":"message_stop"      }
