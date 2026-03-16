#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0
FAIL=0

cleanup() {
  if [ -n "$TMPDIR_PATH" ] && [ -d "$TMPDIR_PATH" ]; then
    rm -rf "$TMPDIR_PATH"
  fi
}
trap cleanup EXIT

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label (expected to find '$needle')"
    FAIL=$(( FAIL + 1 ))
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

setup_temp_repo() {
  TMPDIR_PATH=$(mktemp -d)
  cd "$TMPDIR_PATH"

  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > dummy.txt
  git add -A
  git commit -q -m "initial commit"

  mkdir -p engine
  cp "$REPO_ROOT/engine/ralph.sh" engine/
  cp "$REPO_ROOT/engine/prompt.md" engine/

  # Provide RALPH_PLAN and a dummy PRD
  mkdir -p specs
  echo '{"userStories":[]}' > specs/prd-test.json

  cat > .ralphrc << 'EOF'
RALPH_PLAN=test
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=10
CB_NO_PROGRESS_THRESHOLD=5
CB_SAME_ERROR_THRESHOLD=5
ALLOWED_TOOLS=""
EOF

  mkdir -p "$TMPDIR_PATH/bin"
  cp "$SCRIPT_DIR/mock-claude.sh" "$TMPDIR_PATH/bin/claude"
  chmod +x "$TMPDIR_PATH/bin/claude"
  export PATH="$TMPDIR_PATH/bin:$PATH"
  export RALPH_SKIP_KICKOFF=1
}

# --- Subtest 1: Promise COMPLETE ---
echo "Subtest: Promise COMPLETE"

setup_temp_repo
export MOCK_SCENARIO=exit-promise

set +e
output=$(bash engine/ralph.sh 2>&1)
exit_code=$?
set -e

assert_exit_code "exits with code 0" "0" "$exit_code"
assert_contains "detects Ralph complete" "$output" "Ralph complete"

# --- Subtest 2: EXIT_SIGNAL true ---
echo ""
echo "Subtest: EXIT_SIGNAL true"

cleanup
setup_temp_repo
export MOCK_SCENARIO=exit-signal

set +e
output=$(bash engine/ralph.sh 2>&1)
exit_code=$?
set -e

assert_exit_code "exits with code 0" "0" "$exit_code"
assert_contains "detects EXIT_SIGNAL" "$output" "Ralph received EXIT_SIGNAL"

# --- Subtest 3: Promise ABORT ---
echo ""
echo "Subtest: Promise ABORT"

cleanup
setup_temp_repo
export MOCK_SCENARIO=abort

set +e
output=$(bash engine/ralph.sh 2>&1)
exit_code=$?
set -e

assert_exit_code "exits with code 1" "1" "$exit_code"
assert_contains "detects abort" "$output" "Ralph aborted"

echo ""
echo "Exit detection tests: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
