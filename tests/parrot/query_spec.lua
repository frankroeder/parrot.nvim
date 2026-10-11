local ChatHandler = require("parrot.chat_handler")
local MultiProvider = require("parrot.provider.multi_provider")

describe("ChatHandler:query curl transport", function()
  local handler, provider, original_system, call

  before_each(function()
    handler = ChatHandler:new({
      state_dir = vim.fn.tempname(),
      chat_dir = vim.fn.tempname(),
      curl_params = {},
    }, {}, { "fake" }, { fake = { "m" } }, {})
    provider = MultiProvider:new({
      name = "fake",
      endpoint = "http://127.0.0.1:1/v1/chat/completions",
      api_key = "x",
      models = { "m" },
    })
    original_system = vim.system
    call = nil
    vim.system = function(cmd, opts, on_exit)
      call = { cmd = cmd, opts = opts, on_exit = on_exit }
      return { pid = 4242 }
    end
  end)

  after_each(function()
    vim.system = original_system
  end)

  local payload = function()
    return { model = "m", stream = true, messages = { { role = "user", content = "very-secret-prompt" } } }
  end

  it("sends the payload via stdin, never via argv", function()
    handler:query(nil, provider, payload(), function() end)

    assert.equals("curl", call.cmd[1])
    local d = vim.fn.index(call.cmd, "-d")
    assert.is_true(d >= 0)
    assert.equals("@-", call.cmd[d + 2])
    assert.equals("very-secret-prompt", vim.json.decode(call.opts.stdin).messages[1].content)
    for _, arg in ipairs(call.cmd) do
      assert.is_nil(tostring(arg):find("very-secret-prompt", 1, true))
    end
  end)

  it("tracks the process in the pool while it runs", function()
    handler:query(nil, provider, payload(), function() end)
    assert.is_false(handler.pool:is_empty())
  end)

  it("reassembles lines split across chunks, strips \\r and flushes the last line at EOF", function()
    local got, exits = {}, 0
    handler:query(nil, provider, payload(), function(_, content)
      table.insert(got, content)
    end, function()
      exits = exits + 1
    end)

    local stdout = call.opts.stdout
    stdout(nil, 'data: {"choices":[{"delta":{"content":"Hel"}}]}\r\ndata: {"choi')
    stdout(nil, 'ces":[{"delta":{"content":"lo"}}]}\r\n')
    stdout(nil, 'data: {"choices":[{"delta":{"content":"!"}}]}') -- no trailing newline
    stdout(nil, nil) -- EOF
    call.on_exit({ code = 0 })

    assert.are.same({ "Hel", "lo", "!" }, got)
    assert.equals(1, exits)
    assert.is_true(handler.pool:is_empty())
  end)
end)
