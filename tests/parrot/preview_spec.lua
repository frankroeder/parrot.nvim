local Preview = require("parrot.preview")

describe("preview diff highlighting", function()
  it("highlights diff rows below the header instead of stopping at the ipairs hole", function()
    local preview = Preview:new({
      enable_preview_mode = true,
      preview_auto_apply = false,
      preview_timeout = 0,
      preview_border = "rounded",
    })
    preview:show_diff_preview("old line", "new line", "rewrite", function() end, function() end, "file.lua", 1, 1)

    local ns = vim.api.nvim_create_namespace("ParrotPreviewDiff")
    local marks = vim.api.nvim_buf_get_extmarks(preview.preview_buf, ns, 0, -1, {})
    -- header is 6 rows; a one-line change is a delete plus an add under it
    assert.is_true(#marks >= 2)
    for _, mark in ipairs(marks) do
      assert.is_true(mark[2] >= 6)
    end

    if preview.close_fn then
      preview.close_fn()
    end
  end)
end)
