.PHONY: test lint format

TEST_INIT := tests/minimal_init.lua
TEST_DIR := tests/
PLUGIN_DIR := lua/

test:
	@nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init ='tests/minimal_init.lua'}"

lint:
	luacheck ${PLUGIN_DIR}

format:
	stylua -v -f .stylua.toml $$(find $(PWD) -type f -name '*.lua')
