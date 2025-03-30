local has_cmp, _ = pcall(require, "cmp")
local has_blink, _ = pcall(require, "blink.cmp")

if has_blink then
  return true
elseif has_cmp then
  require("parrot.completion.cmp")
  return true
end

return false
