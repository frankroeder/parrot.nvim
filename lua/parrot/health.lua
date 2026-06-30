local M = {}

function M.check()
  vim.health.start("parrot.nvim checks")

  if vim.F.npcall(require, "fzf-lua") then
    vim.health.ok("require('fzf-lua') succeeded")
  else
    vim.health.info("require('fzf-lua') failed")
  end

  if vim.F.npcall(require, "telescope") then
    vim.health.ok("require('telescope') succeeded")
  else
    vim.health.info("require('telescope') failed")
  end

  if vim.F.npcall(require, "plenary") then
    vim.health.ok("require('plenary') succeeded")
  else
    vim.health.info("require('plenary') failed")
  end

  local ok, parrot = pcall(require, "parrot")
  if not ok then
    vim.health.error("require('parrot') failed")
  else
    vim.health.ok("require('parrot') succeeded")

    if parrot.did_setup then
      vim.health.ok("require('parrot').setup() has been called")
    else
      vim.health.error("require('parrot').setup() has not been called")
    end
  end

  for _, name in ipairs({ "curl", "grep", "rg", "ln" }) do
    if vim.fn.executable(name) == 1 then
      vim.health.ok(("`%s` is installed"):format(name))
    else
      vim.health.warn(("`%s` is not installed"):format(name))
    end
  end

  if vim.fn.executable("grok") == 1 then
    vim.health.ok("`grok` CLI is installed (ACP agent available via `grok agent stdio`)")
    local done = false
    local output = ""
    vim.system({ "grok", "models" }, { text = true }, function(result)
      output = (result and result.stdout) or ""
      done = true
    end)
    vim.wait(5000, function()
      return done
    end)
    if output:match("Available models") then
      vim.health.ok("Grok models can be listed via `grok models`")
    elseif not done then
      vim.health.info("`grok models` timed out — check network or run manually")
    else
      vim.health.info("Could not list Grok models — check authentication (`grok login` or XAI_API_KEY)")
    end
  else
    vim.health.info("`grok` CLI not installed — install from https://x.ai/cli for ACP integration")
  end
end

return M
