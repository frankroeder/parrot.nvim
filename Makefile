.PHONY: test lint format

TEST_INIT := tests/minimal_init.lua
TEST_DIR := tests/
PLUGIN_DIR := lua/

test:
	nvim --clean --headless --noplugin \
		-u $(TEST_INIT) \
		-c "PlenaryBustedDirectory ${TEST_DIR} {minimal_init='$(TEST_INIT)'; timeout=500}"


lint:
	luacheck ${PLUGIN_DIR}

format:
	stylua -v -f .stylua.toml $$(find $(PWD) -type f -name '*.lua')
