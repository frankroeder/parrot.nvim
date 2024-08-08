local M = {}

M.did_setup = false

---@param opts? table
function M.setup(opts)
  M.did_setup = true
  require("parrot.config").setup(opts)
end

return M
