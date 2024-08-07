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
        local providers = { "ollama", "mistral" }

        state:init_state(providers, { ollama = { "model1", "model2" }, mistral = { "model3", "model4" } })

        assert.are.same({
          current_provider = {
            chat = "",
            command = "",
          },
          mistral = {
            chat_model = "model3",
            command_model = "model3",
          },
          ollama = {
            chat_model = "model1",
            command_model = "model1",
          },
        }, state._state)
      end)
    end)
  end)

  describe("init_state", function()
    it("should initialize provider state", function()
      async.run(function()
        local state = State:new("/tmp")
        state:init_state({ "ollama" }, { ollama = { "model1", "model2" } })
        assert.are.same({
          current_provider = { chat = "", command = "" },
          ollama = { chat_model = "model1", command_model = "model1" },
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
        local available_providers = { "ollama", "mistral", "pplx", "anthropic", "openai" }
        local available_models = {
          ollama = { "Gemma-7B" },
          mistral = { "Open-Mixtral-8x7B", "Mistral-Medium" },
          pplx = { "Llama3-Sonar-Large-32k-Chat", "Llama3-70B-Instruct" },
          anthropic = { "Claude-3-Haiku-Chat", "Claude-3.5-Sonnet" },
          openai = { "ChatGPT4", "CodeGPT4o" },
        }

        state:refresh(available_providers, available_models)

        assert.are.same({
          ollama = { chat_model = "Gemma-7B", command_model = "Gemma-7B" },
          mistral = { chat_model = "Open-Mixtral-8x7B", command_model = "Open-Mixtral-8x7B" },
          pplx = { chat_model = "Llama3-Sonar-Large-32k-Chat", command_model = "Llama3-Sonar-Large-32k-Chat" },
          anthropic = { chat_model = "Claude-3-Haiku-Chat", command_model = "Claude-3-Haiku-Chat" },
          openai = { chat_model = "ChatGPT4", command_model = "ChatGPT4" },
          current_provider = { chat = "ollama", command = "ollama" },
        }, state._state)
      end)
    end)

    it("should switch to default provider if previous state provider gets unavailable", function()
      async.run(function()
        local state = State:new("/tmp")
        state.file_state = {
          current_provider = { chat = "ollama", command = "ollama" },
          anthropic = { command_model = "Claude-3-Haiku", chat_model = "Claude-3-Haiku-Chat" },
          openai = { command_model = "CodeGPT3.5", chat_model = "ChatGPT3.5" },
          ollama = { command_model = "Llama2-13B", chat_model = "Llama2-13B" },
        }

        local available_providers = { "ollama", "openai" }
        local available_models = {
          ollama = { "Gemma-7B" },
          openai = { "ChatGPT4", "CodeGPT4o" },
        }

        state:refresh(available_providers, available_models)

        assert.are.same({
          ollama = { chat_model = "Gemma-7B", command_model = "Gemma-7B" },
          openai = { chat_model = "ChatGPT4", command_model = "ChatGPT4" },
          current_provider = { chat = "ollama", command = "ollama" },
        }, state._state)
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
        assert.are.same("", state._state.current_provider.command)

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
end)
