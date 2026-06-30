-- scripts/run_classic_tests.lua
-- Used by `make test` to run only classic (non-acp) specs.
-- This ensures full-test.log contains no acp/ scheduling or bleed.
local busted = require('plenary.busted')
local files = vim.fn.glob('tests/parrot/**/*_spec.lua', false, true)
for _, f in ipairs(files) do
  if not f:match('/acp/') then
    busted.run(f)
  end
end
vim.cmd('qa!')
