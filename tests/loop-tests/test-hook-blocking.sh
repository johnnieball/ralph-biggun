#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_SCRIPT="$REPO_ROOT/.claude/hooks/block-dangerous-git.sh"
PASS=0
FAIL=0

source "$SCRIPT_DIR/../lib/assert.sh"

# The hook reads JSON from stdin with .tool_input.command
run_hook() {
  local command="$1"
  local json="{\"tool_input\":{\"command\":\"$command\"}}"
  echo "$json" | bash "$HOOK_SCRIPT"
}

assert_blocked() {
  local label="$1" command="$2"
  set +e
  run_hook "$command" > /dev/null 2>&1
  local code=$?
  set -e
  if [ "$code" -ne 0 ]; then
    echo "  PASS: $label (blocked with exit $code)"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label (expected non-zero exit, got 0)"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_allowed() {
  local label="$1" command="$2"
  set +e
  run_hook "$command" > /dev/null 2>&1
  local code=$?
  set -e
  if [ "$code" -eq 0 ]; then
    echo "  PASS: $label (allowed with exit 0)"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label (expected exit 0, got $code)"
    FAIL=$(( FAIL + 1 ))
  fi
}

echo "Subtest: Hook blocking dangerous git commands"

assert_blocked "git push origin main" "git push origin main"
assert_blocked "git reset --hard HEAD" "git reset --hard HEAD"
assert_blocked "git clean -fd" "git clean -fd"
assert_blocked "git branch -D main" "git branch -D main"
assert_blocked "git push --force-with-lease" "git push --force-with-lease"
assert_blocked "git clean -f" "git clean -f"

echo ""
echo "Subtest: Hook allowing safe git commands"

assert_allowed "git add ." "git add ."
assert_allowed "git commit -m test" "git commit -m \"test\""

print_summary "Hook blocking tests"
