.PHONY: test lint format

TEST_INIT := tests/minimal_init.lua
TEST_DIR := tests/
PLUGIN_DIR := lua/

test:
	@nvim --clean --headless --noplugin \
		-u $(TEST_INIT) \
		-d "PlenaryBustedDirectory ${TEST_DIR} {minimal_init='$(TEST_INIT)'}"

lint:
	luacheck ${PLUGIN_DIR}

format:
	stylua -v -f .stylua.toml $$(find $(PWD) -type f -name '*.lua')
