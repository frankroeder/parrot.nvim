.PHONY: test test-acp test-acp-smoke lint format

TEST_INIT := tests/minimal_init.lua
TEST_DIR := tests/
PLUGIN_DIR := lua/

# Full suite. For classic-only evidence we filter acp lines in the verify script.
test:
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua', sequential = true}"

# Fast offline ACP unit tests only (no grok agent stdio, ~few seconds).
# Two nvim runs: a FileType/treesitter error in the directory runner can skip later -c.
test-acp:
	nvim --headless -u tests/minimal_init.lua \
	  -c "PlenaryBustedDirectory tests/parrot/acp {minimal_init = 'tests/minimal_init.lua'}" \
	  -c "qa!"
	nvim --headless -u tests/minimal_init.lua \
	  -c "lua require('plenary.busted').run('tests/parrot/provider/acp_provider_spec.lua')" \
	  -c "qa!"

test-acp-smoke:
	nvim --headless -u tests/minimal_init.lua --cmd "set rtp+=." -l tests/acp_smoke.lua

lint:
	luacheck ${PLUGIN_DIR}

format:
	stylua -v -f .stylua.toml $$(find $(PWD) -type f -name '*.lua')
