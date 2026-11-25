local client_handlers = require("parrot.acp.client_handlers")
local rpc = require("parrot.acp.rpc")

local function call(handler, method, params)
  local res, err
  handler(method, params, function(r, e)
    res, err = r, e
  end)
  return res, err
end

describe("parrot.acp.client_handlers", function()
  local dir, handler, access

  before_each(function()
    dir = vim.fn.tempname() .. "_acp_fs"
    vim.fn.mkdir(dir, "p")
    -- existing cases run as an approved agent jailed to this directory
    handler, _, _, access = client_handlers.create({ always_approve = true })
    access.note_session(nil, dir)
  end)

  after_each(function()
    vim.fn.delete(dir, "rf")
  end)

  it("reads a loaded buffer and writes back without an extra line", function()
    local path = dir .. "/a.txt"
    vim.fn.writefile({ "alpha", "gamma" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()

    -- unsaved user edits in the buffer are what the agent reads
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "alpha2" })
    local res = call(handler, "fs/read_text_file", { path = path })
    assert.equals("alpha2\ngamma\n", res.content)

    -- the write lands in the buffer and is saved to disk
    call(handler, "fs/write_text_file", { path = path, content = "beta\ngamma\n" })
    assert.same({ "beta", "gamma" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    assert.same({ "beta", "gamma" }, vim.fn.readfile(path))
    assert.is_false(vim.bo[buf].modified)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("reads a line range, with line and limit each optional", function()
    local path = dir .. "/lines.txt"
    vim.fn.writefile({ "1", "2", "3", "4" }, path)
    assert.equals("2\n3", call(handler, "fs/read_text_file", { path = path, line = 2, limit = 2 }).content)
    assert.equals("3\n4\n", call(handler, "fs/read_text_file", { path = path, line = 3 }).content)
    assert.equals("1\n2", call(handler, "fs/read_text_file", { path = path, limit = 2 }).content)
  end)

  it("sees disk changes made by the agent's shell in an unmodified buffer", function()
    local path = dir .. "/shell.txt"
    vim.fn.writefile({ "one" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    vim.wait(1100) -- distinct mtime
    vim.fn.writefile({ "two" }, path) -- e.g. `sed -i` in an agent terminal

    assert.equals("two\n", call(handler, "fs/read_text_file", { path = path }).content)
    local _, err = call(handler, "fs/write_text_file", { path = path, content = "three\n" })
    assert.is_nil(err)
    assert.same({ "three" }, vim.fn.readfile(path))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("writes the agent's bytes exactly, final newline included or not", function()
    local path = dir .. "/eol.txt"
    vim.fn.writefile({ "a" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    local function disk()
      return table.concat(vim.fn.readfile(path, "b"), "\n")
    end
    for _, content in ipairs({ "b", "b\n", "", "x\ny\n" }) do
      call(handler, "fs/write_text_file", { path = path, content = content })
      assert.equals(content, disk())
    end
    assert.is_true(vim.bo[buf].fixeol) -- the user's option is restored
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("matches a buffer opened through a symlink", function()
    local real = dir .. "/real.txt"
    vim.fn.writefile({ "old" }, real)
    vim.uv.fs_symlink(real, dir .. "/link.txt")
    vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/link.txt"))
    local buf = vim.api.nvim_get_current_buf()
    call(handler, "fs/write_text_file", { path = real, content = "new\n" })
    assert.same({ "new" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("restores the buffer when saving the agent's write fails", function()
    if vim.uv.getuid() == 0 then
      pending("root can write read-only files")
      return
    end
    local path = dir .. "/ro.txt"
    vim.fn.writefile({ "keep" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    vim.fn.setfperm(path, "r--r--r--")

    local _, err = call(handler, "fs/write_text_file", { path = path, content = "agent\n" })
    assert.is_not_nil(err)
    assert.same({ "keep" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    assert.is_false(vim.bo[buf].modified)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("does not write into a buffer whose name only starts with the path", function()
    local path = dir .. "/b.txt"
    vim.fn.writefile({ "orig" }, path .. ".orig")
    vim.cmd("edit " .. vim.fn.fnameescape(path .. ".orig"))
    local buf = vim.api.nvim_get_current_buf()

    call(handler, "fs/write_text_file", { path = path, content = "new\n" })
    assert.same({ "orig" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    assert.same({ "new" }, vim.fn.readfile(path))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("always_approve picks the allow_once option", function()
    local h = client_handlers.create({ always_approve = true })
    local res = call(h, "session/request_permission", {
      options = {
        { optionId = "always", kind = "allow_always" },
        { optionId = "no", kind = "reject_once" },
        { optionId = "yes", kind = "allow_once" },
      },
    })
    assert.equals("yes", res.outcome.optionId)
    res = call(h, "session/request_permission", { options = { { optionId = "always", kind = "allow_always" } } })
    assert.equals("always", res.outcome.optionId)
  end)

  it(":PrtAcpMode overrides the always_approve of the provider's config", function()
    local h = client_handlers.create({ name = "appr", always_approve = false })
    local options = { options = { { optionId = "yes", kind = "allow_once" } } }
    client_handlers.always_approve.appr = true
    local res = call(h, "session/request_permission", options)
    client_handlers.always_approve.appr = nil
    assert.equals("yes", res.outcome.optionId)
  end)

  it("answers an open permission prompt with cancelled when the turn is cancelled", function()
    local h, _, cancel_permission = client_handlers.create({})
    local orig_select = vim.ui.select
    local user_choice
    vim.ui.select = function(_, _, cb)
      user_choice = cb
    end
    local answers = {}
    h("session/request_permission", {
      sessionId = "s1",
      options = { { optionId = "ok", kind = "allow_once", name = "Allow" } },
    }, function(r)
      table.insert(answers, r)
    end)
    vim.ui.select = orig_select

    -- a second prompt of the same session is open at the same time
    vim.ui.select = function() end
    h("session/request_permission", {
      sessionId = "s1",
      options = { { optionId = "ok", kind = "allow_once", name = "Allow" } },
    }, function(r)
      table.insert(answers, r)
    end)
    vim.ui.select = orig_select

    cancel_permission("s1")
    user_choice("Allow", 1) -- a late pick is ignored
    assert.equals(2, #answers)
    assert.equals("cancelled", answers[1].outcome.outcome)
    assert.equals("cancelled", answers[2].outcome.outcome)
  end)

  it("runs a command line without args through a shell", function()
    -- grok sends e.g. `/usr/bin/bash -lc '...'` as the command
    local res = call(handler, "terminal/create", { command = 'echo "hi $((6*7))"', cwd = dir })
    local status = vim.wait(3000, function()
      return call(handler, "terminal/output", { terminalId = res.terminalId }).exitStatus ~= nil
    end)
    assert.is_true(status)
    local out = call(handler, "terminal/output", { terminalId = res.terminalId })
    assert.equals("hi 42\n", out.output)
    assert.equals(0, out.exitStatus.exitCode)
    assert.equals(vim.NIL, out.exitStatus.signal)
  end)

  it("keeps a killed terminal readable until release", function()
    local res = call(handler, "terminal/create", { command = "sleep", args = { "5" } })
    local id = res.terminalId
    call(handler, "terminal/kill", { terminalId = id })
    local _, err = call(handler, "terminal/output", { terminalId = id })
    assert.is_nil(err)
    call(handler, "terminal/release", { terminalId = id })
    _, err = call(handler, "terminal/output", { terminalId = id })
    assert.is_not_nil(err)
  end)

  it("kills the children of a terminal's shell, so wait_for_exit answers", function()
    -- the shell forks `sleep`, which would otherwise keep the output pipes open
    local res = call(handler, "terminal/create", { command = "sleep 5; echo done" })
    local exit_status
    handler("terminal/wait_for_exit", { terminalId = res.terminalId }, function(r)
      exit_status = r
    end)
    call(handler, "terminal/kill", { terminalId = res.terminalId })
    assert.is_true(vim.wait(2000, function()
      return exit_status ~= nil
    end))
    assert.equals("", call(handler, "terminal/output", { terminalId = res.terminalId }).output)
  end)

  it("passes the agent's env to the command (grok sends e.g. GROK_SESSION_ID)", function()
    local res = call(handler, "terminal/create", {
      command = "echo $PARROT_ENV_TEST",
      env = { { name = "PARROT_ENV_TEST", value = "from-agent" } },
    })
    vim.wait(3000, function()
      return call(handler, "terminal/output", { terminalId = res.terminalId }).exitStatus ~= nil
    end)
    assert.equals("from-agent\n", call(handler, "terminal/output", { terminalId = res.terminalId }).output)
  end)

  it("kill_terminals stops and forgets all terminals when the agent goes away", function()
    local h, kill_terminals, _, kill_access = client_handlers.create({ always_approve = true })
    kill_access.note_session(nil, dir)
    local res = call(h, "terminal/create", { command = "sleep 5; echo done" })
    local exit_status
    h("terminal/wait_for_exit", { terminalId = res.terminalId }, function(r)
      exit_status = r
    end)
    kill_terminals()
    assert.is_true(vim.wait(2000, function()
      return exit_status ~= nil
    end))
    local _, err = call(h, "terminal/output", { terminalId = res.terminalId })
    assert.is_not_nil(err)
  end)
end)

describe("parrot.acp.client_handlers permissions and path jail", function()
  local dir, outside

  before_each(function()
    dir = vim.fn.tempname() .. "_acp_root"
    outside = vim.fn.tempname() .. "_acp_outside"
    vim.fn.mkdir(dir, "p")
    vim.fn.mkdir(outside, "p")
  end)

  after_each(function()
    vim.fn.delete(dir, "rf")
    vim.fn.delete(outside, "rf")
    vim.fn.delete(dir .. "_old", "rf")
  end)

  it("does not read, write, or spawn when approval is off", function()
    local secret = dir .. "/secret.txt"
    vim.fn.writefile({ "pw" }, secret)
    local marker = dir .. "/spawned"
    local h, _, _, access = client_handlers.create({ always_approve = false })
    access.note_session("s1", dir)

    local res, err = call(h, "fs/read_text_file", { sessionId = "s1", path = secret })
    assert.is_nil(res)
    assert.matches("Permission denied", err.message)

    _, err = call(h, "fs/write_text_file", { sessionId = "s1", path = dir .. "/written.txt", content = "nope\n" })
    assert.matches("Permission denied", err.message)
    assert.equals(0, vim.fn.filereadable(dir .. "/written.txt"))

    res, err = call(h, "terminal/create", {
      sessionId = "s1",
      command = "touch",
      args = { marker },
      cwd = dir,
    })
    assert.is_nil(res)
    assert.matches("Permission denied", err.message)
    vim.wait(300)
    assert.equals(0, vim.fn.filereadable(marker))
  end)

  it("allows fs and terminal inside the root only after an allow permission", function()
    local h, _, _, access = client_handlers.create({})
    access.note_session("s1", dir)
    local orig_select = vim.ui.select
    vim.ui.select = function(_, _, cb)
      cb("Allow", 1)
    end
    local outcome = call(h, "session/request_permission", {
      sessionId = "s1",
      options = {
        { optionId = "ok", kind = "allow_once", name = "Allow" },
        { optionId = "no", kind = "reject_once", name = "Reject" },
      },
    })
    vim.ui.select = orig_select
    assert.equals("ok", outcome.outcome.optionId)

    local path = dir .. "/note.txt"
    local _, err = call(h, "fs/write_text_file", { sessionId = "s1", path = path, content = "kept\n" })
    assert.is_nil(err)
    assert.equals("kept\n", call(h, "fs/read_text_file", { sessionId = "s1", path = path }).content)

    local outside_file = outside .. "/nope.txt"
    _, err = call(h, "fs/write_text_file", { sessionId = "s1", path = outside_file, content = "x\n" })
    assert.matches("outside", err.message)
    assert.equals(0, vim.fn.filereadable(outside_file))
  end)

  it("does not grant fs access when the user rejects", function()
    local h, _, _, access = client_handlers.create({})
    access.note_session("s1", dir)
    local orig_select = vim.ui.select
    vim.ui.select = function(_, _, cb)
      cb("Reject", 1)
    end
    call(h, "session/request_permission", {
      sessionId = "s1",
      options = { { optionId = "no", kind = "reject_once", name = "Reject" } },
    })
    vim.ui.select = orig_select
    local _, err = call(h, "fs/read_text_file", { sessionId = "s1", path = dir .. "/a.txt" })
    assert.matches("Permission denied", err.message)
  end)

  it("drops fs access when always_approve is turned off, without a prior user grant", function()
    local h = client_handlers.create({ name = "mode-off", always_approve = true, roots = { dir } })
    client_handlers.always_approve["mode-off"] = false
    local _, err = call(h, "fs/read_text_file", { sessionId = "s1", path = dir .. "/a.txt" })
    client_handlers.always_approve["mode-off"] = nil
    assert.matches("Permission denied", err.message)
  end)

  it("refuses paths outside the root, sibling prefixes, symlink escapes, and null bytes", function()
    local h = client_handlers.create({ always_approve = true, roots = { dir } })
    local secret = outside .. "/secret.txt"
    vim.fn.writefile({ "hidden" }, secret)

    local res, err = call(h, "fs/read_text_file", { path = secret })
    assert.is_nil(res)
    assert.matches("outside", err.message)

    local sibling = dir .. "_old"
    vim.fn.mkdir(sibling, "p")
    vim.fn.writefile({ "sib" }, sibling .. "/a.txt")
    res, err = call(h, "fs/read_text_file", { path = sibling .. "/a.txt" })
    assert.is_nil(res)
    assert.matches("outside", err.message)

    vim.uv.fs_symlink(secret, dir .. "/leak")
    res, err = call(h, "fs/read_text_file", { path = dir .. "/leak" })
    assert.is_nil(res)
    assert.is_nil(res and res.content)

    vim.uv.fs_symlink(outside, dir .. "/escape")
    local pwned = outside .. "/pwned.txt"
    _, err = call(h, "fs/write_text_file", { path = dir .. "/escape/pwned.txt", content = "nope\n" })
    assert.is_not_nil(err)
    assert.equals(0, vim.fn.filereadable(pwned))

    local nul = dir .. "/a\0.txt"
    _, err = call(h, "fs/write_text_file", { path = nul, content = "nope\n" })
    assert.is_not_nil(err)
    assert.equals(0, vim.fn.filereadable(dir .. "/a"))

    -- `..` that normalizes back inside the root is still allowed
    vim.fn.writefile({ "inside" }, dir .. "/inside.txt")
    res = call(h, "fs/read_text_file", { path = dir .. "/sub/../inside.txt" })
    assert.equals("inside\n", res.content)
  end)

  it("does not spawn a terminal whose cwd is outside the root", function()
    local h = client_handlers.create({ always_approve = true, roots = { dir } })
    local marker = outside .. "/spawned"
    local res, err = call(h, "terminal/create", { command = "touch", args = { marker }, cwd = outside })
    assert.is_nil(res)
    assert.matches("outside", err.message)
    vim.wait(300)
    assert.equals(0, vim.fn.filereadable(marker))
  end)

  it("limits a session to its own cwd when several projects share a connection", function()
    local other = vim.fn.tempname() .. "_acp_other"
    vim.fn.mkdir(other, "p")
    vim.fn.writefile({ "other" }, other .. "/a.txt")
    vim.fn.writefile({ "mine" }, dir .. "/a.txt")
    local h, _, _, access = client_handlers.create({ always_approve = true })
    access.note_session("sA", dir)
    access.note_session("sB", other)

    local res, err = call(h, "fs/read_text_file", { sessionId = "sA", path = other .. "/a.txt" })
    assert.is_nil(res)
    assert.matches("outside", err.message)
    assert.equals("mine\n", call(h, "fs/read_text_file", { sessionId = "sA", path = dir .. "/a.txt" }).content)
    assert.equals("other\n", call(h, "fs/read_text_file", { sessionId = "sB", path = other .. "/a.txt" }).content)
    vim.fn.delete(other, "rf")
  end)
end)

describe("parrot.acp.client connections", function()
  local acp_client = require("parrot.acp.client")
  local function agents_running()
    return tonumber(vim.fn.system("ps -eo args | grep -c '^sleep 7.4242'"))
  end

  it("terminate_all stops every agent process (VimLeavePre)", function()
    acp_client.get_connection(
      { name = "t", command = { "sh", "-c", "sleep 7.4242" }, models = { "m" } },
      "m",
      function() end
    )
    vim.wait(300)
    assert.equals(1, agents_running())
    acp_client.terminate_all()
    assert.is_true(vim.wait(2000, function()
      return agents_running() == 0
    end))
  end)

  it("retries from a start-failure callback without crashing", function()
    local name = "reenter-" .. vim.fn.tempname():gsub(".*/", "")
    local config = { name = name, command = { "parrot-audit-missing-bin" }, models = { "m" } }
    local errs = {}
    local ok, err = pcall(function()
      acp_client.get_connection(config, "m", function(start_err)
        table.insert(errs, start_err or "ok")
        if #errs == 1 then
          acp_client.get_connection(config, "m", function(retry_err)
            table.insert(errs, retry_err or "ok")
          end)
        end
      end)
    end)
    assert.is_true(ok, tostring(err))
    assert.equals(2, #errs)
    assert.matches("Could not start", errs[1])
    assert.matches("Could not start", errs[2])
  end)
end)

describe("parrot.acp.rpc", function()
  it("terminate fails pending requests once, even if a callback terminates again", function()
    local client
    local calls = 0
    client = rpc.start({ "sh", "-c", "sleep 5" }, {})
    client.request("initialize", {}, function(err)
      calls = calls + 1
      assert.is_not_nil(err)
      client.terminate()
    end)
    client.terminate()
    assert.equals(1, calls)
    -- requests after close fail right away instead of staying pending
    local late_err
    client.request("session/new", {}, function(err)
      late_err = err
    end)
    assert.is_not_nil(late_err)
  end)

  it("gives up on an agent that never initializes", function()
    local acp_client = require("parrot.acp.client")
    local orig = acp_client.INIT_TIMEOUT_MS
    acp_client.INIT_TIMEOUT_MS = 200
    local result
    acp_client.get_connection(
      { name = "hang", command = { "sh", "-c", "sleep 5" }, models = { "m" } },
      "m",
      function(err)
        result = err or "ok"
      end
    )
    vim.wait(2000, function()
      return result ~= nil
    end)
    acp_client.INIT_TIMEOUT_MS = orig
    assert.matches("did not initialize", result)
  end)

  it("answers a server request whose handler throws and keeps reading", function()
    -- fake agent: sends a request and a notification in one chunk, then saves our response line
    local out = vim.fn.tempname()
    local script = [[printf '%s\n%s\n' '{"jsonrpc":"2.0","id":7,"method":"boom","params":{}}' ]]
      .. [['{"jsonrpc":"2.0","method":"note","params":{}}'; read line; printf '%s' "$line" > "$0"; sleep 1]]
    local noted = false
    local client = rpc.start({ "sh", "-c", script, out }, {
      server_request = function()
        error("handler failed")
      end,
      notification = function()
        noted = true
      end,
    })
    vim.wait(3000, function()
      return noted and vim.fn.filereadable(out) == 1 and vim.fn.getfsize(out) > 0
    end)
    assert.is_true(noted)
    local response = vim.json.decode(vim.fn.readfile(out)[1])
    assert.equals(7, response.id)
    assert.equals(rpc.code.internal_error, response.error.code)
    client.terminate()
    vim.fn.delete(out)
  end)
end)
