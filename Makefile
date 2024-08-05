.PHONY: test testlocal lint format

TESTS_INIT=tests/minimal_init.lua
TESTS_DIR := tests/
PLUGIN_DIR := lua/

test:
	@nvim \
		--headless \
		--noplugin \
		-u ${TESTS_INIT} \
		-c "PlenaryBustedDirectory ${TESTS_DIR} { minimal_init = '${TESTS_INIT}' }"

lint:
	luacheck ${PLUGIN_DIR}

format:
	stylua -v -f .stylua.toml $$(find $(PWD) -type f -name '*.lua')
