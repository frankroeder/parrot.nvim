local ChatHandler = require("parrot.chat_handler")

describe("ChatHandler chat files", function()
  local handler, chat_dir

  before_each(function()
    chat_dir = vim.fn.tempname() .. "_chats"
    vim.fn.mkdir(chat_dir, "p")
    handler = ChatHandler:new({
      state_dir = vim.fn.tempname(),
      chat_dir = chat_dir,
      chat_confirm_delete = true,
      toggle_target = "popup",
    }, {}, { "fake" }, { fake = { "m" } }, {})
  end)

  describe("chat_finder with fzf-lua", function()
    after_each(function()
      package.loaded["fzf-lua"] = nil
    end)

    it("runs rg with double quotes only (works in every shell, incl. cmd.exe)", function()
      local cmd
      package.loaded["fzf-lua"] = {
        defaults = { actions = { files = {} } },
        fzf_exec = function(c)
          cmd = c
        end,
      }
      handler:chat_finder()
      assert.truthy(cmd:find('"# topic:"', 1, true))
      assert.is_nil(cmd:find("'", 1, true))
    end)
  end)

  describe("chat_delete", function()
    local original_input, prompted, file, buf

    before_each(function()
      original_input = vim.ui.input
      prompted = nil
      file = chat_dir .. "/2026-01-01.00-00-00.000.md"
      vim.fn.writefile({ "# topic: x" }, file)
      vim.cmd("edit " .. vim.fn.fnameescape(file))
      buf = vim.api.nvim_get_current_buf()
    end)

    after_each(function()
      vim.ui.input = original_input
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end)

    local answer = function(reply)
      vim.ui.input = function(opts, cb)
        prompted = opts.prompt
        cb(reply)
      end
    end

    it("asks first when chat_confirm_delete = true and keeps the file on no", function()
      answer("n")
      handler:chat_delete()
      assert.truthy(prompted:find("Delete", 1, true))
      assert.equal(1, vim.fn.filereadable(file))
    end)

    it("deletes after confirmation", function()
      answer("y")
      handler:chat_delete()
      assert.equal(0, vim.fn.filereadable(file))
    end)

    it("deletes without asking when chat_confirm_delete = false", function()
      answer("n")
      handler.options.chat_confirm_delete = false
      handler:chat_delete()
      assert.is_nil(prompted)
      assert.equal(0, vim.fn.filereadable(file))
    end)
  end)
end)
