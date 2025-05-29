local State = require("parrot.state")
local mock = require("luassert.mock")
local stub = require("luassert.stub")
local async = require("plenary.async")

describe("State", function()
  local function setup_mocks()
    stub(vim.fn, "filereadable")
    stub(require("parrot.file_utils"), "file_to_table")
    stub(require("parrot.file_utils"), "table_to_file")
  end

  local function teardown_mocks()
    vim.fn.filereadable:revert()
    require("parrot.file_utils").file_to_table:revert()
    require("parrot.file_utils").table_to_file:revert()
  end

  describe("new", function()
    before_each(setup_mocks)
    after_each(teardown_mocks)

    it("should create a new state instance with existing file", function()
      async.run(function()
        vim.fn.filereadable.returns(1)
        require("parrot.file_utils").file_to_table.returns({
          ollama = {
            command_model = "Gemma-7B",
            chat_model = "Gemma-7B",
          },
          mistral = {
            command_model = "Mistral-Medium",
            chat_model = "Open-Mixtral-8x7B",
          },
          pplx = {
            command_model = "Llama3-70B-Instruct",
            chat_model = "Llama3-Sonar-Large-32k-Chat",
          },
          anthropic = {
            command_model = "Claude-3.5-Sonnet",
            chat_model = "Claude-3-Haiku-Chat",
          },
          openai = {
            command_model = "CodeGPT4o",
            chat_model = "ChatGPT4",
          },
          provider = "anthropic",
        })

        local state = State:new("/tmp")

        assert.are.same("/tmp/state.json", state.state_file)
        assert.are.same({
          ollama = {
            command_model = "Gemma-7B",
            chat_model = "Gemma-7B",
          },
          mistral = {
            command_model = "Mistral-Medium",
            chat_model = "Open-Mixtral-8x7B",
          },
          pplx = {
            command_model = "Llama3-70B-Instruct",
            chat_model = "Llama3-Sonar-Large-32k-Chat",
          },
          anthropic = {
            command_model = "Claude-3.5-Sonnet",
            chat_model = "Claude-3-Haiku-Chat",
          },
          openai = {
            command_model = "CodeGPT4o",
            chat_model = "ChatGPT4",
          },
          provider = "anthropic",
        }, state.file_state)
        assert.are.same({}, state._state)
      end)
    end)

    it("should create a new state instance without existing file", function()
      async.run(function()
        vim.fn.filereadable.returns(0)

        local state = State:new("/tmp")

        assert.are.same("/tmp/state.json", state.state_file)
        assert.are.same({}, state.file_state)
        assert.are.same({}, state._state)
      end)
    end)
  end)

  describe("init_state", function()
    it("should initialize file state for each provider", function()
      async.run(function()
        local state = State:new("/tmp")
        local available_providers = { "ollama", "mistral" }
        state:init_file_state(available_providers)

        assert.are.same({
          ollama = {
            chat_model = nil,
            command_model = nil,
            cached_models = {},
          },
          mistral = {
            chat_model = nil,
            command_model = nil,
            cached_models = {},
          },
          current_provider = { chat = nil, command = nil },
        }, state.file_state)
      end)
    end)

    it("should initialize provider state", function()
      async.run(function()
        local state = State:new("/tmp")
        local available_providers = { "ollama" }
        local available_models = { ollama = { "model1", "model2" } }
        state:init_state(available_providers, available_models)

        assert.are.same({
          current_provider = { chat = nil, command = nil },
          ollama = {
            chat_model = "model1",
            command_model = "model1",
            cached_models = {},
          },
        }, state._state)
      end)
    end)
  end)

  describe("load_models", function()
    it("should load chat model from file state if valid", function()
      async.run(function()
        local state = State:new("/tmp")
        state.file_state = { ollama = { chat_model = "Gemma-7B" } }
        state._state = { ollama = { chat_model = nil } }
        local available_models = { ollama = { "Gemma-7B", "Llama2-7B" } }

        state:load_models("ollama", "chat_model", available_models)

        assert.are.same("Gemma-7B", state._state.ollama.chat_model)
      end)
    end)

    it("should load default chat model if file state is invalid", function()
      async.run(function()
        local state = State:new("/tmp")
        state.file_state = { ollama = { chat_model = "invalid-model" } }
        state._state = { ollama = { chat_model = nil } }
        local available_models = { ollama = { "Gemma-7B", "Llama2-7B" } }

        state:load_models("ollama", "chat_model", available_models)

        assert.are.same("Gemma-7B", state._state.ollama.chat_model)
      end)
    end)
  end)

  describe("refresh", function()
    before_each(setup_mocks)
    after_each(teardown_mocks)

    it("should refresh state with available providers and models", function()
      async.run(function()
        local state = State:new("/tmp")
        local available_providers = { "ollama", "openai", "anthropic", "mistral", "pplx" }
        local available_models = {
          ollama = { "Gemma-7B" },
          openai = { "ChatGPT4" },
          anthropic = { "Claude-3-Haiku-Chat" },
          mistral = { "Open-Mixtral-8x7B" },
          pplx = { "Llama3-Sonar-Large-32k-Chat" },
        }

        state:refresh(available_providers, available_models)

        assert.are.same({
          ollama = {
            chat_model = "Gemma-7B",
            command_model = "Gemma-7B",
            cached_models = {},
          },
          openai = {
            chat_model = "ChatGPT4",
            command_model = "ChatGPT4",
            cached_models = {},
          },
          anthropic = {
            chat_model = "Claude-3-Haiku-Chat",
            command_model = "Claude-3-Haiku-Chat",
            cached_models = {},
          },
          mistral = {
            chat_model = "Open-Mixtral-8x7B",
            command_model = "Open-Mixtral-8x7B",
            cached_models = {},
          },
          pplx = {
            chat_model = "Llama3-Sonar-Large-32k-Chat",
            command_model = "Llama3-Sonar-Large-32k-Chat",
            cached_models = {},
          },
          current_provider = {
            chat = "ollama",
            command = "ollama",
          },
        }, state._state)
      end)
    end)

    it("should switch to default provider if previous state provider gets unavailable", function()
      async.run(function()
        local state = State:new("/tmp")
        state.file_state = {
          current_provider = { chat = "unavailable_provider", command = "unavailable_provider" },
        }

        local available_providers = { "ollama", "openai" }
        local available_models = {
          ollama = { "Gemma-7B" },
          openai = { "ChatGPT4" },
        }

        state:refresh(available_providers, available_models)

        assert.are.same({
          ollama = {
            chat_model = "Gemma-7B",
            command_model = "Gemma-7B",
            cached_models = {},
          },
          openai = {
            chat_model = "ChatGPT4",
            command_model = "ChatGPT4",
            cached_models = {},
          },
          current_provider = {
            chat = "ollama",
            command = "ollama",
          },
        }, state._state)
      end)
    end)

    it("should initialize cached_models during refresh", function()
      async.run(function()
        local state = State:new("/tmp")
        local available_providers = { "openai", "anthropic" }
        local available_models = {
          openai = { "gpt-4" },
          anthropic = { "claude-3" },
        }

        state:refresh(available_providers, available_models)

        assert.is_not_nil(state.file_state.openai.cached_models)
        assert.is_not_nil(state.file_state.anthropic.cached_models)
      end)
    end)
  end)

  describe("set_provider", function()
    it("should set the current provider", function()
      async.run(function()
        local state = State:new("/tmp")
        state:init_state({ "openai" }, { openai = { "gpt-4o", "gpt-3.5" } })
        state:set_provider("openai", true)
        assert.are.same("openai", state._state.current_provider.chat)
        assert.are.same(nil, state._state.current_provider.command)

        state:set_provider("groq", false)
        assert.are.same("groq", state._state.current_provider.command)
      end)
    end)
  end)

  describe("set_model", function()
    it("should set the model for a specific provider and type", function()
      async.run(function()
        local state = State:new("/tmp")
        state:init_state({ "openai" }, { openai = { "gpt-4o", "gpt-3.5" } })
        state:set_model("openai", "ChatGPT4", "chat")
        assert.are.same("ChatGPT4", state._state.openai.chat_model)
      end)
    end)
  end)

  describe("get_provider", function()
    it("should get the current provider", function()
      async.run(function()
        local state = State:new("/tmp")
        state.file_state.current_provider = { chat = "ollama", command = "mistral" }
        assert.are.same("mistral", state:get_provider(false))
      end)
    end)
  end)

  describe("get_model", function()
    it("should get the model for a specific provider and type", function()
      async.run(function()
        local state = State:new("/tmp")
        state:init_state({ "anthropic" }, { anthropic = { "haiku", "opus" } })
        state._state.anthropic.chat_model = "Claude-3-Haiku-Chat"
        assert.are.same("Claude-3-Haiku-Chat", state:get_model("anthropic", "chat"))
      end)
    end)
  end)

  describe("set_last_chat", function()
    it("should set the last opened chat file path", function()
      async.run(function()
        local state = State:new("/tmp")
        state:set_last_chat("/path/to/chat.json")
        assert.are.same("/path/to/chat.json", state._state.last_chat)
      end)
    end)
  end)

  describe("get_last_chat", function()
    it("should get the last opened chat file path", function()
      async.run(function()
        local state = State:new("/tmp")
        state._state.last_chat = "/path/to/chat.json"
        assert.are.same("/path/to/chat.json", state:get_last_chat())
      end)
    end)
  end)

  describe("save", function()
    before_each(setup_mocks)
    after_each(teardown_mocks)

    it("should save the current state to a file", function()
      async.run(function()
        local state = State:new("/tmp")
        state._state = {
          ollama = { chat_model = "Gemma-7B", command_model = "Gemma-7B" },
          current_provider = { chat = "ollama", command = "ollama" },
        }

        state:save()

        assert.stub(require("parrot.file_utils").table_to_file).was_called_with(state._state, "/tmp/state.json")
      end)
    end)
  end)

  describe("cached models", function()
    before_each(setup_mocks)
    after_each(teardown_mocks)

    describe("set_cached_models", function()
      it("should cache models with timestamp and endpoint hash", function()
        async.run(function()
          local state = State:new("/tmp")
          local models = { "model1", "model2", "model3" }
          local endpoint_hash = "abc123"
          local before_time = os.time()

          state:set_cached_models("openai", models, endpoint_hash)

          local cached = state.file_state.openai.cached_models
          assert.are.same(models, cached.models)
          assert.are.same(endpoint_hash, cached.endpoint_hash)
          assert.is_true(cached.timestamp >= before_time)
          assert.is_true(cached.timestamp <= os.time())
        end)
      end)

      it("should initialize cached_models table if it doesn't exist", function()
        async.run(function()
          local state = State:new("/tmp")
          state.file_state.openai = nil

          state:set_cached_models("openai", { "model1" }, "hash123")

          assert.is_not_nil(state.file_state.openai)
          assert.is_not_nil(state.file_state.openai.cached_models)
        end)
      end)
    end)

    describe("get_cached_models", function()
      it("should return cached models if they are valid and not expired", function()
        async.run(function()
          local state = State:new("/tmp")
          local models = { "model1", "model2" }
          local endpoint_hash = "hash123"

          state.file_state.openai = {
            cached_models = {
              models = models,
              timestamp = os.time() - 3600, -- 1 hour ago
              endpoint_hash = endpoint_hash,
            },
          }

          local result = state:get_cached_models("openai", 48, endpoint_hash)
          assert.are.same(models, result)
        end)
      end)

      it("should return nil if cache is expired", function()
        async.run(function()
          local state = State:new("/tmp")
          state.file_state.openai = {
            cached_models = {
              models = { "model1" },
              timestamp = os.time() - (50 * 3600), -- 50 hours ago
              endpoint_hash = "hash123",
            },
          }

          local result = state:get_cached_models("openai", 48, "hash123")
          assert.is_nil(result)
        end)
      end)

      it("should return nil if endpoint hash doesn't match", function()
        async.run(function()
          local state = State:new("/tmp")
          state.file_state.openai = {
            cached_models = {
              models = { "model1" },
              timestamp = os.time() - 3600,
              endpoint_hash = "old_hash",
            },
          }

          local result = state:get_cached_models("openai", 48, "new_hash")
          assert.is_nil(result)
        end)
      end)

      it("should return cached models if endpoint hash is not provided", function()
        async.run(function()
          local state = State:new("/tmp")
          state.file_state.openai = {
            cached_models = {
              models = { "model1" },
              timestamp = os.time() - 3600,
              endpoint_hash = "hash123",
            },
          }

          local result = state:get_cached_models("openai", 48, nil)
          assert.are.same({ "model1" }, result)
        end)
      end)

      it("should return nil if provider is not cached", function()
        async.run(function()
          local state = State:new("/tmp")
          state.file_state = {}

          local result = state:get_cached_models("nonexistent", 48, "hash123")
          assert.is_nil(result)
        end)
      end)

      it("should return nil if cached_models table doesn't exist", function()
        async.run(function()
          local state = State:new("/tmp")
          state.file_state.openai = nil

          local result = state:get_cached_models("openai", 48, "hash123")
          assert.is_nil(result)
        end)
      end)
    end)

    describe("is_cache_valid", function()
      it("should return true if cache is valid", function()
        async.run(function()
          local state = State:new("/tmp")
          state.file_state.openai = {
            cached_models = {
              models = { "model1" },
              timestamp = os.time() - 3600,
              endpoint_hash = "hash123",
            },
          }

          local result = state:is_cache_valid("openai", 48, "hash123")
          assert.is_true(result)
        end)
      end)

      it("should return false if cache is invalid", function()
        async.run(function()
          local state = State:new("/tmp")
          state.file_state.openai = {
            cached_models = {
              models = { "model1" },
              timestamp = os.time() - (50 * 3600),
              endpoint_hash = "hash123",
            },
          }

          local result = state:is_cache_valid("openai", 48, "hash123")
          assert.is_false(result)
        end)
      end)
    end)

    describe("clear_cache", function()
      it("should clear cache for specific provider", function()
        async.run(function()
          local state = State:new("/tmp")
          state.file_state.openai = {
            cached_models = { models = { "model1" }, timestamp = os.time() },
          }
          state.file_state.anthropic = {
            cached_models = { models = { "model2" }, timestamp = os.time() },
          }

          state:clear_cache("openai")

          assert.are.same({}, state.file_state.openai.cached_models)
          assert.is_not_nil(state.file_state.anthropic.cached_models.models)
        end)
      end)

      it("should clear all caches when no provider specified", function()
        async.run(function()
          local state = State:new("/tmp")
          state.file_state.openai = {
            cached_models = { models = { "model1" }, timestamp = os.time() },
          }
          state.file_state.anthropic = {
            cached_models = { models = { "model2" }, timestamp = os.time() },
          }

          state:clear_cache()

          assert.are.same({}, state.file_state.openai.cached_models)
          assert.are.same({}, state.file_state.anthropic.cached_models)
        end)
      end)

      it("should handle case when cached_models doesn't exist", function()
        async.run(function()
          local state = State:new("/tmp")
          state.file_state.cached_models = nil

          -- Should not error
          state:clear_cache("openai")
          state:clear_cache()
        end)
      end)
    end)

    describe("cleanup_cache", function()
      it("should remove cache entries for providers that no longer exist", function()
        async.run(function()
          local state = State:new("/tmp")
          state.file_state.openai = {
            cached_models = { models = { "model1" }, timestamp = os.time() },
          }
          state.file_state.anthropic = {
            cached_models = { models = { "model2" }, timestamp = os.time() },
          }
          state.file_state.removed_provider = {
            cached_models = { models = { "model3" }, timestamp = os.time() },
          }

          local available_providers = { "openai", "anthropic" }
          state:cleanup_cache(available_providers)

          assert.is_not_nil(state.file_state.openai)
          assert.is_not_nil(state.file_state.anthropic)
          assert.is_nil(state.file_state.removed_provider)
        end)
      end)

      it("should handle case when cached_models doesn't exist", function()
        async.run(function()
          local state = State:new("/tmp")
          state.file_state = {}

          -- Should not error
          state:cleanup_cache({ "openai" })
        end)
      end)

      it("should handle empty provider list", function()
        async.run(function()
          local state = State:new("/tmp")
          state.file_state.openai = {
            cached_models = { models = { "model1" }, timestamp = os.time() },
          }

          state:cleanup_cache({})

          assert.is_nil(state.file_state.openai)
        end)
      end)
    end)

    describe("integration with refresh", function()
      it("should initialize cached_models during refresh", function()
        async.run(function()
          local state = State:new("/tmp")
          local available_providers = { "openai", "anthropic" }
          local available_models = {
            openai = { "gpt-4" },
            anthropic = { "claude-3" },
          }

          state:refresh(available_providers, available_models)

          assert.is_not_nil(state.file_state.openai.cached_models)
          assert.is_not_nil(state.file_state.anthropic.cached_models)
        end)
      end)
    end)
  end)
end)
