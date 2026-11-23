local ChatHandler = require("parrot.chat_handler")

-- Chat buffer shortcuts: each can be disabled with `false` (issue #205).
describe("ChatHandler:prep_chat shortcuts", function()
  local chat_dir, buf

  local shortcut = function(lhs)
    return { modes = { "n", "i", "v", "x" }, shortcut = lhs }
  end

  local open_chat = function(opts)
    local handler = ChatHandler:new(
      vim.tbl_extend("force", {
        cmd_prefix = "Prt",
        state_dir = vim.fn.tempname(),
        chat_dir = chat_dir,
      }, opts),
      {},
      { "fake" },
      { fake = { "m" } },
      {}
    )
    local file = chat_dir .. "/2026-01-01.00-00-00.000.md"
    vim.fn.writefile({ "# topic: x", "", "- file: " .. file, "", "🗨:" }, file)
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    buf = vim.api.nvim_get_current_buf()
    handler.bind_acp_chat = function() end -- no provider/ACP in tests
    handler:prep_chat(buf, file)
  end

  -- parrot's buffer-local maps only (the markdown ftplugin adds its own)
  local buf_lhs = function(mode)
    local found = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
      if (map.desc or ""):match("^Parrot") then
        found[vim.fn.keytrans(map.lhsraw or map.lhs)] = map.desc
      end
    end
    return found
  end

  before_each(function()
    chat_dir = vim.fn.tempname() .. "_chats"
    vim.fn.mkdir(chat_dir, "p")
  end)

  after_each(function()
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  it("maps all four shortcuts by default", function()
    open_chat({
      chat_shortcut_respond = shortcut("<C-g><C-g>"),
      chat_shortcut_delete = shortcut("<C-g>d"),
      chat_shortcut_stop = shortcut("<C-g>s"),
      chat_shortcut_new = shortcut("<C-g>c"),
    })
    local n = buf_lhs("n")
    assert.truthy(n["<C-G><C-G>"])
    assert.truthy(n["<C-G>d"])
    assert.truthy(n["<C-G>s"])
    assert.truthy(n["<C-G>c"])
  end)

  it("maps nothing when every shortcut is false", function()
    open_chat({
      chat_shortcut_respond = false,
      chat_shortcut_delete = false,
      chat_shortcut_stop = false,
      chat_shortcut_new = false,
    })
    for _, mode in ipairs({ "n", "i", "v", "x" }) do
      assert.same({}, buf_lhs(mode))
    end
  end)

  it("disables a single shortcut and keeps the others", function()
    open_chat({
      chat_shortcut_respond = shortcut("<C-g><C-g>"),
      chat_shortcut_delete = false,
      chat_shortcut_stop = shortcut("<C-g>s"),
      chat_shortcut_new = shortcut("<C-g>c"),
    })
    local n = buf_lhs("n")
    assert.is_nil(n["<C-G>d"])
    assert.truthy(n["<C-G><C-G>"])
    assert.truthy(n["<C-G>s"])
  end)
end)
