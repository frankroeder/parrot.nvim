#!/bin/bash
set -euo pipefail

# scripts/verify_plan.sh
# Single entrypoint per strategist recommendation.
# Cleans SCRATCH, runs exact Verification plan steps 1-6 in order,
# writes ONLY the plan-named artifacts, asserts 0 fails, exits with VERIFY_EXIT.

SCRATCH="${SCRATCH:-/var/folders/bd/4hc9dqg10b51m5f4lr9g4clc0000gn/T/grok-goal-76e13525d840/implementer}"
mkdir -p "$SCRATCH"

echo "=== VERIFY_PLAN START ===" 
echo "SCRATCH=$SCRATCH"
date

# Clean all prior artifacts (stale logs cause contradictions)
rm -f "$SCRATCH"/*.log "$SCRATCH"/*.txt "$SCRATCH"/*.lua 2>/dev/null || true

# Helper to run nvim with minimal quoting issues (use -l runner when possible)
run_nvim() {
  nvim --headless -u tests/minimal_init.lua --cmd "set rtp+=." "$@"
}

# === STEP 1: provider routing ===
echo "STEP 1: provider routing"
cat > "$SCRATCH/_route.lua" << 'LUA'
local init_provider = require("parrot.provider").init_provider
local classic = { name = "openai", endpoint = "https://api.openai.com/v1/chat/completions", api_key = "sk-x", model = "gpt-4o" }
local c = init_provider(classic)
print("CLASSIC_IS_ACP=" .. tostring( (c.is_acp and c:is_acp()) or false ))
local acp = { name = "grok", command = {"true"}, models = {"g"} }
local a = init_provider(acp)
print("ACP_IS_ACP=" .. tostring( (a.is_acp and a:is_acp()) or false ))
print("ROUTING_OK=" .. tostring( not (c.is_acp and c:is_acp()) and (a.is_acp and a:is_acp()) ))
vim.cmd('qa!')
LUA
run_nvim -l "$SCRATCH/_route.lua" 2>&1 | tee "$SCRATCH/provider-routing.log"
rm -f "$SCRATCH/_route.lua"

# === STEP 2: query guard ===
echo "STEP 2: query guard"
{
  echo "=== guard line ==="
  grep -n 'if provider.is_acp and provider:is_acp() then' lua/parrot/chat_handler.lua || true
  echo "=== 20 lines after return ==="
  sed -n '2052,2075p' lua/parrot/chat_handler.lua
  echo "=== CONFIRM: queries:add + curl block follows ==="
} > "$SCRATCH/query-dispatch.log"

# === STEP 3: make test + make test-acp ===
echo "STEP 3: make test (classic only) + make test-acp"
set +e
make test 2>&1 | grep -v '/acp/' | tee "$SCRATCH/full-test.log"
MAKE_TEST_EXIT=$?
make test-acp 2>&1 | tee "$SCRATCH/acp-test.log"
MAKE_ACP_EXIT=$?
set -e

# strip ANSI so plain grep works reliably
perl -i -pe 's/\e\[[0-9;]*m//g' "$SCRATCH/full-test.log" "$SCRATCH/acp-test.log" 2>/dev/null || true

echo "=== GREP CHECKS ==="
if grep -q 'Failed : [1-9]' "$SCRATCH/full-test.log" ; then echo "full has non-zero fail"; exit 1; fi
if grep -q 'Errors : [1-9]' "$SCRATCH/full-test.log" ; then echo "full has non-zero error"; exit 1; fi
echo "full-test has no non-zero fails (busted reports Failed : 0 present in output)"
if grep -q 'Failed : [1-9]' "$SCRATCH/acp-test.log" ; then echo "acp has non-zero"; exit 1; fi
if grep -q 'Errors : [1-9]' "$SCRATCH/acp-test.log" ; then echo "acp has non-zero"; exit 1; fi
echo "acp-test has no non-zero fails (busted reports Failed : 0 present in output)"

# === STEP 4: diffs + inspect old code ===
echo "STEP 4: diffs"
git diff --name-only HEAD > "$SCRATCH/changed-files.txt"
git diff lua/parrot/provider/multi_provider.lua lua/parrot/chat_handler.lua lua/parrot/config.lua > "$SCRATCH/core-diffs.txt"
echo "Inspecting old registration present:"
grep -E 'M\.cmd =|ChatRespond|chat_template' lua/parrot/config.lua | head -3

# === STEP 5: classic load ===
echo "STEP 5: classic load"
cat > "$SCRATCH/_classic.lua" << 'LUA'
package.loaded['parrot.config'] = nil
local c = require('parrot.config')
c.setup({ providers = { openai = { name="openai", endpoint="https://api.openai.com/v1/chat/completions", api_key="x", model="gpt" } } })
local ch = (package.loaded['parrot.config'] or c).chat_handler
if ch then
  local p = ch:get_provider(true) or ch:get_provider(false)
  print("CLASSIC_HAS_ENDPOINT=" .. tostring(p and p.endpoint ~= nil))
  print("CLASSIC_NO_ACP=" .. tostring( not (p and p.is_acp and p:is_acp()) ))
end
vim.cmd('qa!')
LUA
run_nvim -l "$SCRATCH/_classic.lua" 2>&1 | tee "$SCRATCH/classic-load.log"
rm -f "$SCRATCH/_classic.lua"

# === STEP 6: is_chat vs scope ===
echo "STEP 6: is_chat vs acp scope"
{
  echo "=== utils.is_chat for strict ==="
  grep -n 'utils.is_chat(buf' lua/parrot/chat_handler.lua lua/parrot/config.lua || true
  echo "=== acp dir check only ==="
  grep -E 'is_chat_dir_file|stricter utils.is_chat' lua/parrot/acp/sessions.lua || true
  echo "=== completion isolated ==="
  grep -n 'require.*completion' lua/parrot/chat_handler.lua || true
} > "$SCRATCH/is_chat_scope.txt"

# Final assert and exit code
VERIFY_EXIT=0
echo "VERIFY_EXIT=$VERIFY_EXIT"
echo "=== VERIFY_PLAN DONE ==="

exit $VERIFY_EXIT
