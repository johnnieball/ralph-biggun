#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0
FAIL=0
TMPDIR_PATHS=()

cleanup() {
  for d in "${TMPDIR_PATHS[@]}"; do
    rm -rf "$d" 2>/dev/null || true
  done
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
  local tmpdir
  tmpdir=$(mktemp -d)
  TMPDIR_PATHS+=("$tmpdir")
  cd "$tmpdir"

  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > dummy.txt
  git add -A
  git commit -q -m "initial commit"

  mkdir -p engine
  cp "$REPO_ROOT/engine/ralph.sh" engine/
  cp "$REPO_ROOT/engine/prompt.md" engine/

  cat > .ralphrc << 'EOF'
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=1
CB_NO_PROGRESS_THRESHOLD=5
CB_SAME_ERROR_THRESHOLD=5
ALLOWED_TOOLS=""
EOF

  mkdir -p "$tmpdir/bin"
  cp "$SCRIPT_DIR/mock-claude.sh" "$tmpdir/bin/claude"
  chmod +x "$tmpdir/bin/claude"
  export PATH="$tmpdir/bin:$PATH"
}

# --- Subtest 1: ralph.sh fails without kickoff and without skip ---
echo "Subtest: Gate blocks without kickoff"

setup_temp_repo
unset RALPH_SKIP_KICKOFF
export MOCK_SCENARIO=normal

set +e
output=$(bash engine/ralph.sh 2>&1)
exit_code=$?
set -e

assert_exit_code "exits with code 1" "1" "$exit_code"
assert_contains "mentions kickoff not completed" "$output" "Kickoff not completed"

# --- Subtest 2: ralph.sh succeeds with .ralph-kickoff-complete ---
echo ""
echo "Subtest: Gate passes with kickoff complete"

setup_temp_repo
unset RALPH_SKIP_KICKOFF
echo "2026-01-01T00:00:00Z" > .ralph-kickoff-complete
export MOCK_SCENARIO=exit-promise

set +e
output=$(bash engine/ralph.sh 2>&1)
exit_code=$?
set -e

assert_exit_code "exits with code 0" "0" "$exit_code"
assert_contains "runs successfully" "$output" "Ralph complete"

# --- Subtest 3: ralph.sh succeeds with RALPH_SKIP_KICKOFF=1 ---
echo ""
echo "Subtest: Gate bypassed with RALPH_SKIP_KICKOFF=1"

setup_temp_repo
export RALPH_SKIP_KICKOFF=1
export MOCK_SCENARIO=exit-promise

set +e
output=$(bash engine/ralph.sh 2>&1)
exit_code=$?
set -e

assert_exit_code "exits with code 0" "0" "$exit_code"
assert_contains "runs successfully" "$output" "Ralph complete"

echo ""
echo "Kickoff gate tests: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
