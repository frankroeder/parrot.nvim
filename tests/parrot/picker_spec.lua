local Picker = require("parrot.picker")

describe("Picker", function()
  local original_select

  before_each(function()
    original_select = vim.ui.select
  end)

  after_each(function()
    vim.ui.select = original_select
  end)

  -- fzf-lua and telescope are not available in the test environment, so
  -- Picker.select falls through to vim.ui.select.
  it("should fall back to vim.ui.select", function()
    local captured
    vim.ui.select = function(items, opts, on_choice)
      captured = { items = items, opts = opts }
      on_choice(items[2])
    end

    local choice
    Picker.select({ "a", "b" }, { prompt = "Provider selection" }, function(c)
      choice = c
    end)

    assert.are.same({ "a", "b" }, captured.items)
    assert.equal("Provider selection:", captured.opts.prompt)
    assert.equal("b", choice)
  end)

  it("should pass nil through when the user aborts", function()
    vim.ui.select = function(_, _, on_choice)
      on_choice(nil)
    end

    local called, choice = false, "unset"
    Picker.select({ "a" }, { prompt = "Model selection" }, function(c)
      called, choice = true, c
    end)

    assert.is_true(called)
    assert.is_nil(choice)
  end)
end)
