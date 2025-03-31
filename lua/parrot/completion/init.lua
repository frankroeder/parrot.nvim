local has_cmp, _ = pcall(require, "cmp")
local has_blink, _ = pcall(require, "blink.cmp")
local logger = require("parrot.logger")

if has_blink then
  logger.debug("Using blink.cmp.")
  return true
elseif has_cmp then
  require("parrot.completion.cmp")
  logger.debug("Using nvim-cmp.")
  return true
end

logger.debug("No compatible completion engine found.")
return false
