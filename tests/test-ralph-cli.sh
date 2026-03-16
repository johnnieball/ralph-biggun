#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0

source "$SCRIPT_DIR/lib/assert.sh"

echo "Ralph CLI Tests"
echo "================"

# --- Test 1: Usage output ---
echo ""
echo "Test: No args shows usage"

set +e
output=$("$REPO_ROOT/ralph" 2>&1)
code=$?
set -e

assert_exit_code "exits with code 0" "0" "$code"
assert_output_contains "shows usage" "$output" "Usage: ralph"
assert_output_contains "lists init command" "$output" "init"
assert_output_contains "lists run command" "$output" "run"

# --- Test 2: Unknown command ---
echo ""
echo "Test: Unknown command shows usage"

set +e
output=$("$REPO_ROOT/ralph" nonsense 2>&1)
code=$?
set -e

assert_output_contains "shows usage for unknown command" "$output" "Usage: ralph"

# --- Test 3: Invalid stack preset ---
echo ""
echo "Test: Invalid --stack preset"

tmpdir=$(mktemp -d)
trap "rm -rf $tmpdir" EXIT

set +e
output=$("$REPO_ROOT/ralph" init --stack nonexistent-stack "$tmpdir" 2>&1)
code=$?
set -e

assert_true "exits with error" test "$code" -ne 0
assert_output_contains "mentions unknown stack" "$output" "Unknown stack preset"
assert_output_contains "lists available presets" "$output" "bun-typescript"

print_summary "Ralph CLI tests"
