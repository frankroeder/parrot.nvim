local acp_client = require("parrot.acp.client")
local State = require("parrot.state")

-- Fake agent connection: answers every request immediately and records it.
local function fake_connection(requests)
  local conn = {
    sessions = {},
    active_prompts = {},
    _streams = {},
    slash_commands = {},
    config_options = {},
    load_session = true,
  }
  conn.rpc = {
    request = function(method, params, cb)
      table.insert(requests, { method = method, params = params })
      if method == "session/new" then
        cb(nil, { sessionId = "sess-" .. #requests })
      elseif method == "session/prompt" then
        conn._streams[params.sessionId]("answer")
        cb(nil, { stopReason = "end_turn" })
      else
        cb(nil, {})
      end
    end,
  }
  return conn
end

local function methods(requests)
  return vim.tbl_map(function(r)
    return r.method
  end, requests)
end

describe("parrot.acp.client sessions", function()
  local orig_get_connection
  local state, state_dir
  local config = { name = "grok", command = { "grok", "agent", "stdio" }, model = "grok-build" }

  before_each(function()
    orig_get_connection = acp_client.get_connection
    state_dir = vim.fn.tempname() .. "_parrot_state"
    vim.fn.mkdir(state_dir, "p")
    state = State:new(state_dir)
    state:init_file_state({ "grok" })
    state:init_state({ "grok" }, { grok = { "grok-build" } })
  end)

  after_each(function()
    acp_client.get_connection = orig_get_connection
    vim.fn.delete(state_dir, "rf")
  end)

  local function prompt(conn, opts)
    acp_client.get_connection = function(_, _, cb)
      cb(nil, conn)
    end
    local out = {}
    acp_client.prompt(
      config,
      vim.tbl_extend("force", {
        state = state,
        on_chunk = function(text)
          table.insert(out, text)
        end,
      }, opts)
    )
    return out
  end

  it("continued_entry accepts only histories that extend the stored one", function()
    local msgs = { { role = "user", content = "a" }, { role = "assistant", content = "b" } }
    local entry = { id = "s", n = 2, hash = acp_client.history_hash(msgs, 2) }
    local longer = vim.list_extend(vim.deepcopy(msgs), { { role = "user", content = "c" } })
    assert.equals(entry, acp_client.continued_entry(entry, longer))
    assert.is_nil(acp_client.continued_entry(entry, msgs))
    longer[1].content = "edited"
    assert.is_nil(acp_client.continued_entry(entry, longer))
  end)

  it("reuses a chat session and only sends new messages", function()
    local requests = {}
    local conn = fake_connection(requests)
    local messages = { { role = "system", content = "be brief" }, { role = "user", content = "hi" } }
    prompt(conn, { session_kind = "chat", session_key = "/chats/a.md", messages = messages })

    assert.same({ "session/new", "session/prompt" }, methods(requests))
    assert.equals("be brief", requests[1].params._meta.rules)
    assert.same({ { type = "text", text = "hi" } }, requests[2].params.prompt)

    for i = #requests, 1, -1 do
      requests[i] = nil
    end
    local next_messages = vim.list_extend(vim.deepcopy(messages), {
      { role = "assistant", content = "\nanswer\n" },
      { role = "user", content = "more" },
    })
    prompt(conn, { session_kind = "chat", session_key = "/chats/a.md", messages = next_messages })

    assert.same({ "session/prompt" }, methods(requests))
    assert.same({ { type = "text", text = "more" } }, requests[1].params.prompt)
    assert.equals(5, state:get_acp_session("grok", "/chats/a.md").n)
  end)

  it("starts a new session with the full transcript when the chat history diverged", function()
    local requests = {}
    local conn = fake_connection(requests)
    state:set_acp_session("grok", "/chats/b.md", { id = "old", n = 2, hash = "stale" })
    prompt(conn, {
      session_kind = "chat",
      session_key = "/chats/b.md",
      messages = {
        { role = "user", content = "q1" },
        { role = "assistant", content = "a1" },
        { role = "user", content = "q2" },
      },
    })

    -- the replaced session is deleted
    assert.same({ "session/new", "_x.ai/session/delete", "session/prompt" }, methods(requests))
    assert.equals("old", requests[2].params.sessionId)
    assert.equals(3, #requests[3].params.prompt)
    assert.equals("user:\nq1", requests[3].params.prompt[1].text)
    assert.not_equals("old", state:get_acp_session("grok", "/chats/b.md").id)
  end)

  it("loads a persisted chat session that is not live in the agent process", function()
    local requests = {}
    local conn = fake_connection(requests)
    local history = { { role = "user", content = "q1" }, { role = "assistant", content = "a1" } }
    state:set_acp_session(
      "grok",
      "/chats/c.md",
      { id = "persisted", n = 2, hash = acp_client.history_hash(history, 2) }
    )
    prompt(conn, {
      session_kind = "chat",
      session_key = "/chats/c.md",
      messages = vim.list_extend(vim.deepcopy(history), { { role = "user", content = "q2" } }),
    })

    assert.same({ "session/load", "session/prompt" }, methods(requests))
    assert.equals("persisted", requests[2].params.sessionId)
    assert.same({ { type = "text", text = "q2" } }, requests[2].params.prompt)
  end)

  it("gives every command prompt a fresh tool-free session that is deleted afterwards", function()
    local requests = {}
    local conn = fake_connection(requests)
    config.command_reasoning_effort = "low"
    for _ = 1, 2 do
      prompt(conn, { session_kind = "command", messages = { { role = "user", content = "rewrite" } } })
    end
    config.command_reasoning_effort = nil

    assert.same({
      "session/new",
      "session/set_config_option",
      "session/prompt",
      "_x.ai/session/delete",
      "session/new",
      "session/set_config_option",
      "session/prompt",
      "_x.ai/session/delete",
    }, methods(requests))
    assert.same(acp_client.COMMAND_PROFILE, requests[1].params._meta.agentProfile)
    assert.matches("You have no tools", requests[1].params._meta.rules)
    assert.equals(requests[3].params.sessionId, requests[4].params.sessionId)
    assert.equals("low", requests[2].params.value)
  end)

  it("does not send a prompt that was cancelled while its session was opening", function()
    local requests = {}
    local conn = fake_connection(requests)
    local done_result
    acp_client.cancel("q-early")
    prompt(conn, {
      qid = "q-early",
      session_kind = "command",
      messages = { { role = "user", content = "rewrite" } },
      on_done = function(result)
        done_result = result
      end,
    })

    assert.same({ "session/new", "_x.ai/session/delete" }, methods(requests))
    assert.equals("cancelled", done_result.stopReason)
  end)

  it("refuses a second prompt into a session that is still streaming", function()
    local requests = {}
    local conn = fake_connection(requests)
    local history = { { role = "user", content = "q1" }, { role = "assistant", content = "a1" } }
    state:set_acp_session("grok", "/chats/d.md", { id = "busy", n = 2, hash = acp_client.history_hash(history, 2) })
    conn.sessions.busy = true
    conn._streams.busy = function() end
    local err
    prompt(conn, {
      session_kind = "chat",
      session_key = "/chats/d.md",
      raw = true,
      messages = { { role = "user", content = "/context" } },
      on_error = function(e)
        err = e
      end,
    })

    assert.matches("busy", err)
    assert.is_nil(vim.tbl_contains(methods(requests), "session/prompt") or nil)
  end)

  it("continues a chat in a new session while a stopped turn is still finishing", function()
    local requests = {}
    local conn = fake_connection(requests)
    local history = { { role = "user", content = "q1" }, { role = "assistant", content = "a1" } }
    state:set_acp_session("grok", "/chats/e.md", { id = "busy", n = 2, hash = acp_client.history_hash(history, 2) })
    conn.sessions.busy = true
    conn._streams.busy = function() end
    local err
    prompt(conn, {
      session_kind = "chat",
      session_key = "/chats/e.md",
      messages = vim.list_extend(vim.deepcopy(history), { { role = "user", content = "q2" } }),
      on_error = function(e)
        err = e
      end,
    })

    assert.is_nil(err)
    assert.same({ "session/new", "_x.ai/session/delete", "session/prompt" }, methods(requests))
    assert.equals(3, #requests[3].params.prompt) -- full transcript replayed
    assert.not_equals("busy", state:get_acp_session("grok", "/chats/e.md").id)
  end)

  it("keeps the replacing session when a stopped turn finishes late", function()
    local requests = {}
    local conn = fake_connection(requests)
    local request, held = conn.rpc.request, nil
    conn.rpc.request = function(method, params, cb)
      if method == "session/prompt" and not held then
        held = cb -- the first turn is still running
        return
      end
      request(method, params, cb)
    end
    local messages = { { role = "user", content = "q1" } }
    prompt(conn, { session_kind = "chat", session_key = "/chats/h.md", messages = messages })
    prompt(conn, { session_kind = "chat", session_key = "/chats/h.md", messages = messages })
    local replacement = state:get_acp_session("grok", "/chats/h.md").id

    held(nil, { stopReason = "cancelled" })
    assert.equals(replacement, state:get_acp_session("grok", "/chats/h.md").id)
  end)

  it("drops a chat's new session when its prompt is cancelled before it is sent", function()
    local requests = {}
    local conn = fake_connection(requests)
    state:set_acp_session("grok", "/chats/f.md", { id = "old", n = 2, hash = "stale" })
    acp_client.cancel("q-chat-early")
    prompt(conn, {
      qid = "q-chat-early",
      session_kind = "chat",
      session_key = "/chats/f.md",
      messages = { { role = "user", content = "q1" } },
    })

    -- old (replaced) and new (never prompted) sessions are both deleted, nothing stale is stored
    assert.same({ "session/new", "_x.ai/session/delete", "_x.ai/session/delete" }, methods(requests))
    assert.is_nil(state:get_acp_session("grok", "/chats/f.md"))
  end)

  it("runs slash commands outside chats with the full agent in a deleted one-shot session", function()
    local requests = {}
    local conn = fake_connection(requests)
    prompt(
      conn,
      { session_kind = "command", raw = true, messages = { { role = "user", content = "/deep-research x" } } }
    )

    assert.same({ "session/new", "session/prompt", "_x.ai/session/delete" }, methods(requests))
    assert.is_nil(requests[1].params._meta)
  end)
end)
