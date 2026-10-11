-- Every ```lua block of the README must parse; mark intentionally partial
-- snippets with `<!-- lua-skip -->` on the line right above the fence.
describe("README", function()
  local lines = vim.fn.readfile("README.md")

  local blocks, block, skip = {}, nil, false
  for i, line in ipairs(lines) do
    if block then
      -- a closing fence is indented by at most 3 spaces (CommonMark)
      if line:match("^ ? ? ?```%s*$") then
        table.insert(blocks, block)
        block = nil
      else
        table.insert(block.lines, line)
      end
    elseif line:match("^%s*```lua%s*$") then
      block = { start = i, lines = {}, skip = skip }
    end
    skip = line:match("^%s*<!%-%- lua%-skip %-%->%s*$") ~= nil
  end

  it("has lua examples", function()
    assert.is_true(#blocks > 10)
  end)

  for _, b in ipairs(blocks) do
    if not b.skip then
      it("lua block at line " .. b.start .. " parses", function()
        local code = table.concat(b.lines, "\n")
        -- a block may also be a single expression, e.g. a lazy.nvim spec table
        local _, err = loadstring(code)
        local _, expr_err = loadstring("return " .. code)
        assert.is_true(err == nil or expr_err == nil, err)
      end)
    end
  end
end)
