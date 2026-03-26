#!/bin/bash

# tests/lib/assert.sh — Shared test helpers for Ralph test scripts
# Source this file after declaring PASS=0 and FAIL=0 in your test script.

assert_true() {
  local label="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_false() {
  local label="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "  FAIL: $label (expected false but got true)"
    FAIL=$(( FAIL + 1 ))
  else
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  fi
}

assert_exit_code() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label (expected exit $expected, got $actual)"
    FAIL=$(( FAIL + 1 ))
  fi
}

# Check that a file contains a literal string (grep -qF)
assert_file_contains() {
  local label="$1" file="$2" needle="$3"
  if grep -qF "$needle" "$file" 2>/dev/null; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label (expected '$needle' in $file)"
    FAIL=$(( FAIL + 1 ))
  fi
}

# Check that a string variable contains a literal substring (grep -qF)
assert_output_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label (expected to find '$needle')"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_output_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "  FAIL: $label (expected NOT to find '$needle')"
    FAIL=$(( FAIL + 1 ))
  else
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  fi
}

# Check that a string variable matches an extended regex (grep -qE)
assert_output_matches() {
  local label="$1" haystack="$2" pattern="$3"
  if echo "$haystack" | grep -qE -- "$pattern"; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label (expected to match pattern '$pattern')"
    FAIL=$(( FAIL + 1 ))
  fi
}

print_summary() {
  local suite_name="$1"
  echo ""
  echo "$suite_name: $PASS passed, $FAIL failed"

  if [ "$FAIL" -gt 0 ]; then
    exit 1
  fi
  exit 0
}
