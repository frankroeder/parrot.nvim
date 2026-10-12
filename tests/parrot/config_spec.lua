-- tests/minimal_init.lua stubs parrot.config; this spec needs the real module
package.loaded["parrot.config"] = nil
local config = require("parrot.config")

describe("config.setup", function()
  local original_system, calls

  before_each(function()
    original_system = vim.system
    calls = {}
    vim.system = function(cmd, opts, on_exit)
      table.insert(calls, cmd)
      local res = { code = 0, stdout = '{"data":[{"id":"fresh"}]}' }
      if on_exit then
        on_exit(res)
      end
      return {
        wait = function()
          return res
        end,
      }
    end
    config.setup({
      state_dir = vim.fn.tempname(),
      chat_dir = vim.fn.tempname(),
      providers = {
        fake = {
          name = "fake",
          endpoint = "http://127.0.0.1:1/v1/chat/completions",
          model_endpoint = "http://127.0.0.1:1/v1/models",
          api_key = "x",
          models = { "m" },
        },
      },
    })
  end)

  after_each(function()
    vim.system = original_system
  end)

  it("does no network I/O itself and refreshes a stale model cache once afterwards", function()
    assert.equal(0, #calls)
    assert.are.same({ "m" }, config.available_models.fake)

    vim.wait(1000, function()
      return config.available_models.fake[1] == "fresh"
    end)
    assert.equal(1, #calls)
    assert.are.same({ "fresh" }, config.available_models.fake)
  end)

  it("maps every default command to a ChatHandler method", function()
    for name, method in pairs(config.cmd) do
      assert.is_function(config.chat_handler[method], name .. " -> " .. method)
      assert.equal(2, vim.fn.exists(":Prt" .. name), "missing :Prt" .. name)
    end
  end)

  it("registers :PrtChatRespond, used by the chat keymaps", function()
    assert.is_not_nil(vim.api.nvim_get_commands({}).PrtChatRespond)
  end)
end)

describe("PrtInfo masking", function()
  it("masks keys of 6 characters or fewer and does not reveal a longer key", function()
    local original = vim.api.nvim_get_current_buf()
    config.hooks.Info({
      providers = {
        short = { api_key = "secret" },
        tiny = { api_key = "zz9" },
        long = { api_key = "sk-1234567890abcdef" },
        cmd = { api_key = { "printf", "%s", "not-a-string-key" } },
      },
    }, {})
    local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    assert.is_nil(text:find("secret", 1, true))
    assert.is_nil(text:find("zz9", 1, true))
    assert.is_nil(text:find("sk-1234567890abcdef", 1, true))
    assert.truthy(text:find("sk%-", 1, false))
    assert.truthy(text:find("******", 1, true))
    assert.truthy(text:find("printf", 1, true))
    vim.api.nvim_win_set_buf(0, original)
  end)
end)
