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
  local ralphrc_content="$1"
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

  # Provide RALPH_PLAN and a dummy PRD
  mkdir -p specs
  echo '{"userStories":[]}' > specs/prd-test.json
  {
    echo "RALPH_PLAN=test"
    echo "$ralphrc_content"
  } > .ralphrc

  mkdir -p "$tmpdir/bin"
  cp "$SCRIPT_DIR/mock-claude.sh" "$tmpdir/bin/claude"
  chmod +x "$tmpdir/bin/claude"
  export PATH="$tmpdir/bin:$PATH"
  export RALPH_SKIP_KICKOFF=1
}

# --- Subtest 1: No-progress circuit breaker ---
echo "Subtest: No-progress circuit breaker"

setup_temp_repo "$(cat <<'EOF'
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=10
CB_NO_PROGRESS_THRESHOLD=2
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
EOF
)"
export MOCK_SCENARIO=no-commit

set +e
output=$(bash engine/ralph.sh 2>&1)
exit_code=$?
set -e

assert_exit_code "exits with code 1" "1" "$exit_code"
assert_contains "mentions circuit breaker" "$output" "CIRCUIT BREAKER: No file changes"

# --- Subtest 2: Same-error circuit breaker ---
echo ""
echo "Subtest: Same-error circuit breaker"

setup_temp_repo "$(cat <<'EOF'
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=10
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=2
ALLOWED_TOOLS=""
EOF
)"
export MOCK_SCENARIO=same-error

set +e
output=$(bash engine/ralph.sh 2>&1)
exit_code=$?
set -e

assert_exit_code "exits with code 1" "1" "$exit_code"
assert_contains "mentions same output repeated" "$output" "CIRCUIT BREAKER: Same output repeated"

echo ""
echo "Circuit breaker tests: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
