#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0
TMPDIR_PATHS=()

source "$SCRIPT_DIR/lib/assert.sh"

cleanup() {
  for d in "${TMPDIR_PATHS[@]}"; do
    rm -rf "$d" 2>/dev/null || true
  done
}
trap cleanup EXIT

echo "Run.sh Tests"
echo "============"

# --- Test 1: No config found ---
echo ""
echo "Test: Fails when no Ralph config exists"

tmpdir=$(mktemp -d)
TMPDIR_PATHS+=("$tmpdir")
cd "$tmpdir"

set +e
output=$("$REPO_ROOT/commands/run.sh" 2>&1)
code=$?
set -e

assert_true "exits with error" test "$code" -ne 0
assert_output_contains "mentions no config found" "$output" "No Ralph configuration found"
assert_output_contains "suggests ralph init" "$output" "ralph init"

print_summary "Run.sh tests"
