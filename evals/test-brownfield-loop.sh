#!/bin/bash
set -e

# test-brownfield-loop.sh — Verify the engine runs correctly with .ralph/ layout
# Uses mock-claude to test loop execution, circuit breakers, and exit detection.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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

setup_brownfield_repo() {
  local config_overrides="$1"
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

  # Initialise Ralph with .ralph/ layout
  "$REPO_ROOT/ralph" init "$tmpdir" > /dev/null 2>&1

  # Create a dummy PRD and set RALPH_PLAN
  echo '{"userStories":[]}' > "$tmpdir/.ralph/specs/prd-test.json"

  # Write config overrides into .ralph/config.sh
  {
    echo ""
    echo "RALPH_PLAN=test"
    echo "$config_overrides"
  } >> "$tmpdir/.ralph/config.sh"

  # Set up mock-claude
  mkdir -p "$tmpdir/bin"
  cp "$SCRIPT_DIR/loop-tests/mock-claude.sh" "$tmpdir/bin/claude"
  chmod +x "$tmpdir/bin/claude"
  export PATH="$tmpdir/bin:$PATH"
}

echo "Brownfield Loop Tests"
echo "====================="

# --- Test 1: Exit detection via .ralph/ layout ---
echo ""
echo "Test: Promise COMPLETE via .ralph/ layout"

setup_brownfield_repo "$(cat <<'EOF'
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=10
CB_NO_PROGRESS_THRESHOLD=5
CB_SAME_ERROR_THRESHOLD=5
ALLOWED_TOOLS=""
EOF
)"
export MOCK_SCENARIO=exit-promise

set +e
output=$("$REPO_ROOT/commands/run.sh" 2>&1)
exit_code=$?
set -e

assert_exit_code "exits with code 0" "0" "$exit_code"
assert_contains "detects Ralph complete" "$output" "Ralph complete"

# --- Test 2: Circuit breaker via .ralph/ layout ---
echo ""
echo "Test: No-progress circuit breaker via .ralph/ layout"

setup_brownfield_repo "$(cat <<'EOF'
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=10
CB_NO_PROGRESS_THRESHOLD=2
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
EOF
)"
export MOCK_SCENARIO=no-commit

set +e
output=$("$REPO_ROOT/commands/run.sh" 2>&1)
exit_code=$?
set -e

assert_exit_code "exits with code 1" "1" "$exit_code"
assert_contains "mentions circuit breaker" "$output" "CIRCUIT BREAKER"

# --- Test 3: Logs go to .ralph/logs/ ---
echo ""
echo "Test: Logs written to .ralph/logs/"

setup_brownfield_repo "$(cat <<'EOF'
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=1
CB_NO_PROGRESS_THRESHOLD=5
CB_SAME_ERROR_THRESHOLD=5
ALLOWED_TOOLS=""
EOF
)"
export MOCK_SCENARIO=exit-promise

set +e
"$REPO_ROOT/commands/run.sh" > /dev/null 2>&1
set -e

log_count=$(ls .ralph/logs/ralph-*.log 2>/dev/null | wc -l | tr -d ' ')
if [ "$log_count" -ge 1 ]; then
  echo "  PASS: log file created in .ralph/logs/"
  PASS=$(( PASS + 1 ))
else
  echo "  FAIL: no log file in .ralph/logs/"
  FAIL=$(( FAIL + 1 ))
fi

# --- Test 4: Direct ralph.sh invocation auto-detects .ralph/config.sh ---
echo ""
echo "Test: Direct ralph.sh invocation finds .ralph/config.sh"

setup_brownfield_repo "$(cat <<'EOF'
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=10
CB_NO_PROGRESS_THRESHOLD=5
CB_SAME_ERROR_THRESHOLD=5
ALLOWED_TOOLS=""
EOF
)"
export MOCK_SCENARIO=exit-promise

# Invoke ralph.sh directly (not via run.sh) — no RALPH_CONFIG env var
unset RALPH_CONFIG
set +e
output=$(.ralph/engine/ralph.sh 2>&1)
exit_code=$?
set -e

assert_exit_code "exits with code 0" "0" "$exit_code"
assert_contains "detects Ralph complete" "$output" "Ralph complete"

echo ""
echo "Brownfield loop tests: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
