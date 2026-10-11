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
