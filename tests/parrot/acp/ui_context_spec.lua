local acp_ui = require("parrot.acp.ui")
local ChatHandler = require("parrot.chat_handler")
local init_provider = require("parrot.provider").init_provider

describe("parrot.acp.ui context", function()
  local chat_dir
  local handler
  local stub_provider
  local parrot

  local function make_parrot()
    local providers = {
      grok = {
        type = "acp",
        name = "grok",
        command = { "grok", "agent", "stdio" },
        models = { "grok-build" },
      },
    }
    handler = ChatHandler:new({
      state_dir = vim.fn.tempname() .. "_ui_state",
      chat_dir = chat_dir,
      cmd_prefix = "Prt",
      enable_spinner = false,
      chat_template = "# {{user}}\n\n",
      chat_user_prefix = "User",
      toggle_target = "popup",
      system_prompt = { chat = "", command = "" },
    }, providers, { "grok" }, { grok = { "grok-build" } }, {})

    stub_provider = init_provider({
      type = "acp",
      name = "grok",
      command = { "grok", "agent", "stdio" },
      models = { "grok-build" },
    })
    function stub_provider:verify()
      return true
    end
    handler.current_provider.chat = stub_provider
    handler.current_provider.command = stub_provider

    return {
      chat_handler = handler,
      options = {
        chat_dir = chat_dir,
        enable_spinner = false,
        model_cache_expiry_hours = 48,
        style_popup_border = "single",
      },
      ui = require("parrot.ui"),
    }
  end

  before_each(function()
    chat_dir = vim.fn.tempname() .. "_ui_chats"
    vim.fn.mkdir(chat_dir, "p")
    parrot = make_parrot()
  end)

  it("get_context uses path-based chat scope for marginal chat_dir buffers", function()
    local chat_file = chat_dir .. "/marginal.md"
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, chat_file)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "draft" })
    vim.api.nvim_set_current_buf(buf)

    local ctx = acp_ui.get_context(parrot)
    assert.is_not_nil(ctx)
    assert.is_true(ctx.is_chat)
    assert.equals("chat", ctx.scope.kind)
    assert.equals(buf, ctx.buf)
    assert.is_false(require("parrot.utils").is_chat(buf, chat_file, chat_dir))

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("run_slash_command keeps marginal chat on original buf with chat session kind", function()
    local chat_file = chat_dir .. "/slash.md"
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, chat_file)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x" })
    vim.api.nvim_set_current_buf(buf)

    local popup_created = false
    local orig_create_popup = parrot.ui.create_popup
    parrot.ui.create_popup = function(...)
      popup_created = true
      return orig_create_popup(...)
    end

    local captured = {}
    local orig_acp_query = handler.acp_query
    function handler:acp_query(target_buf, prov, payload, response_handler, on_exit)
      captured.buf = target_buf
      captured.model = payload.model
      local scope = require("parrot.acp.sessions").session_scope(target_buf, chat_dir, self.state)
      captured.session_kind = scope.kind
      if on_exit then
        on_exit()
      end
    end

    acp_ui.run_slash_command(parrot, "/compact")

    handler.acp_query = orig_acp_query
    parrot.ui.create_popup = orig_create_popup

    assert.is_false(popup_created)
    assert.equals(buf, captured.buf)
    assert.equals("chat", captured.session_kind)
    assert.equals("grok-build", captured.model)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)