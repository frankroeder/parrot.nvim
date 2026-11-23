-- Regression tests for https://github.com/frankroeder/parrot.nvim/issues/206:
-- the blink.cmp source must not depend on blink.cmp internals such as
-- `blink.cmp.lib.async`, which blink.cmp v2 removed.

local function wait_for(get)
  local value
  vim.wait(1000, function()
    value = get()
    return value ~= nil
  end, 10)
  return value
end

describe("completion.blink", function()
  local tmp_dir

  before_each(function()
    -- Simulate blink.cmp v2, where `blink.cmp.lib.async` no longer exists.
    package.loaded["blink.cmp.lib.async"] = nil
    package.preload["blink.cmp.lib.async"] = function()
      error("module 'blink.cmp.lib.async' not found")
    end
    package.loaded["parrot.completion.blink"] = nil

    tmp_dir = vim.fn.tempname()
    vim.fn.mkdir(tmp_dir .. "/sub", "p")
    vim.fn.writefile({ "hello parrot" }, tmp_dir .. "/note.txt")
  end)

  after_each(function()
    package.preload["blink.cmp.lib.async"] = nil
    vim.fn.delete(tmp_dir, "rf")
  end)

  it("loads without blink.cmp.lib.async", function()
    local ok, blink = pcall(require, "parrot.completion.blink")
    assert.is_true(ok, tostring(blink))
    assert.is_function(blink.new)
  end)

  it("returns @file: completions", function()
    local blink = require("parrot.completion.blink")
    local source = blink.new()
    local line = "@file:" .. tmp_dir .. "/"
    local response
    source:get_completions({ line = line, cursor = { 1, #line } }, function(r)
      response = r
    end)
    response = wait_for(function()
      return response
    end)
    assert.is_not_nil(response)
    local labels = vim.tbl_map(function(item)
      return item.label
    end, response.items)
    assert.are.same({ "sub/", "note.txt" }, labels)
    assert.is_false(response.is_incomplete_forward)
  end)

  it("returns only directories for @directory:", function()
    local blink = require("parrot.completion.blink")
    local line = "@directory:" .. tmp_dir .. "/"
    local response
    blink.new():get_completions({ line = line, cursor = { 1, #line } }, function(r)
      response = r
    end)
    response = wait_for(function()
      return response
    end)
    local labels = vim.tbl_map(function(item)
      return item.label
    end, response.items)
    assert.are.same({ "sub/" }, labels)
  end)

  it("resolves a file item with a content preview", function()
    local blink = require("parrot.completion.blink")
    local item = {
      label = "note.txt",
      data = { type = "file", full_path = tmp_dir .. "/note.txt", path = "note.txt" },
    }
    local resolved
    blink.new():resolve(item, function(r)
      resolved = r
    end)
    resolved = wait_for(function()
      return resolved
    end)
    assert.are.equal("markdown", resolved.documentation.kind)
    assert.is_truthy(resolved.documentation.value:find("hello parrot", 1, true))
  end)

  it("returns the item unchanged when the file cannot be read", function()
    local blink = require("parrot.completion.blink")
    local item = {
      label = "missing.txt",
      data = { type = "file", full_path = tmp_dir .. "/missing.txt", path = "missing.txt" },
    }
    local resolved
    blink.new():resolve(item, function(r)
      resolved = r
    end)
    resolved = wait_for(function()
      return resolved
    end)
    assert.are.equal(item, resolved)
    assert.is_nil(resolved.documentation)
  end)
end)
