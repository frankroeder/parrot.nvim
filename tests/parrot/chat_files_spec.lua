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

    it("does not mutate fzf-lua's shared file actions", function()
      local shared = { ["ctrl-p"] = "original-ctrl-p", ["ctrl-d"] = "original-ctrl-d" }
      local passed
      package.loaded["fzf-lua"] = {
        defaults = { actions = { files = shared } },
        fzf_exec = function(_, opts)
          passed = opts.actions
        end,
      }
      handler:chat_finder()
      assert.equals("original-ctrl-p", shared["ctrl-p"])
      assert.equals("original-ctrl-d", shared["ctrl-d"])
      assert.equal("function", type(passed["ctrl-p"]))
      assert.equal("table", type(passed["ctrl-d"]))
    end)
  end)

  describe("open_buf path escaping", function()
    local ui = require("parrot.ui")

    after_each(function()
      pcall(vim.api.nvim_del_user_command, "ParrotAuditInject")
      vim.g.parrot_audit_injected = nil
    end)

    local function inject_command()
      vim.api.nvim_create_user_command("ParrotAuditInject", function()
        vim.g.parrot_audit_injected = 1
      end, {})
    end

    it("does not run an Ex command hidden after a pipe in the path", function()
      inject_command()
      local path = chat_dir .. "/notes|ParrotAuditInject"
      vim.fn.writefile({ "hello" }, path)
      local buf = handler:open_buf(path, ui.BufTarget.current, 1, false)
      assert.is_nil(vim.g.parrot_audit_injected)
      assert.truthy(vim.api.nvim_buf_get_name(buf):find("|ParrotAuditInject", 1, true))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("opens a path that contains a space", function()
      local path = chat_dir .. "/my chat.md"
      vim.fn.writefile({ "# topic: spaced" }, path)
      local buf = handler:open_buf(path, ui.BufTarget.current, 1, false)
      assert.truthy(vim.api.nvim_buf_get_name(buf):find("my chat.md", 1, true))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("reads and writes a popup whose path contains a pipe", function()
      inject_command()
      local path = chat_dir .. "/pop|ParrotAuditInject.md"
      vim.fn.writefile({ "line-one" }, path)
      local buf = handler:open_buf(path, ui.BufTarget.popup, 1, false)
      assert.is_nil(vim.g.parrot_audit_injected)
      assert.truthy(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("line-one", 1, true))
      assert.equal(1, vim.fn.filereadable(path))
      assert.truthy(table.concat(vim.fn.readfile(path), "\n"):find("line-one", 1, true))
      vim.api.nvim_buf_delete(buf, { force = true })
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

    it("does not delete a sibling directory that shares the chat dir prefix", function()
      local sibling = chat_dir .. "_old"
      vim.fn.mkdir(sibling, "p")
      local sibling_file = sibling .. "/notes.md"
      vim.fn.writefile({ "# topic: x" }, sibling_file)
      vim.cmd("edit " .. vim.fn.fnameescape(sibling_file))
      local sibling_buf = vim.api.nvim_get_current_buf()
      local utils = require("parrot.utils")
      handler._chat_usage[utils.resolve_path(sibling_file)] = { requests = 1 }
      handler.options.chat_confirm_delete = false

      handler:chat_delete()

      assert.equal(1, vim.fn.filereadable(sibling_file))
      assert.equal(1, handler._chat_usage[utils.resolve_path(sibling_file)].requests)
      vim.api.nvim_buf_delete(sibling_buf, { force = true })
      vim.fn.delete(sibling, "rf")
    end)
  end)
end)
