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

  describe("telescope", function()
    local mods = {
      "telescope",
      "telescope.pickers",
      "telescope.finders",
      "telescope.actions",
      "telescope.actions.state",
      "telescope.config",
    }
    local maps, closed

    before_each(function()
      maps, closed = {}, 0
      package.loaded["telescope"] = {}
      package.loaded["telescope.finders"] = { new_table = function() end }
      package.loaded["telescope.config"] = { values = { generic_sorter = function() end } }
      package.loaded["telescope.actions"] = {
        close = function()
          closed = closed + 1
        end,
      }
      package.loaded["telescope.actions.state"] = {
        get_selected_entry = function()
          return { value = "b" }
        end,
      }
      package.loaded["telescope.pickers"] = {
        new = function(_, spec)
          spec.attach_mappings(0, function(mode, key, fn)
            maps[mode .. key] = fn
          end)
          return { find = function() end }
        end,
      }
    end)

    after_each(function()
      for _, m in ipairs(mods) do
        package.loaded[m] = nil
      end
    end)

    it("confirms with <CR> in insert and normal mode", function()
      local choices = {}
      Picker.select({ "a", "b" }, { prompt = "Model selection" }, function(c)
        table.insert(choices, c)
      end)

      assert.is_function(maps["i<CR>"])
      assert.is_function(maps["n<CR>"])
      maps["i<CR>"](1)
      maps["n<CR>"](1)
      assert.are.same({ "b", "b" }, choices)
      assert.equal(2, closed)
    end)
  end)
end)
