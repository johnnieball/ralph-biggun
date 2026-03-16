#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0
FAIL=0
TMPDIR_PATHS=()

source "$SCRIPT_DIR/../lib/assert.sh"

cleanup() {
  for d in "${TMPDIR_PATHS[@]}"; do
    rm -rf "$d" 2>/dev/null || true
  done
}
trap cleanup EXIT

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

  mkdir -p "$tmpdir/bin"
  cp "$SCRIPT_DIR/mock-claude.sh" "$tmpdir/bin/claude"
  chmod +x "$tmpdir/bin/claude"
  export PATH="$tmpdir/bin:$PATH"
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
assert_output_contains "detects Ralph complete" "$output" "Ralph complete"

# --- Subtest 2: EXIT_SIGNAL true ---
echo ""
echo "Subtest: EXIT_SIGNAL true"

setup_temp_repo
export MOCK_SCENARIO=exit-signal

set +e
output=$(bash engine/ralph.sh 2>&1)
exit_code=$?
set -e

assert_exit_code "exits with code 0" "0" "$exit_code"
assert_output_contains "detects EXIT_SIGNAL" "$output" "Ralph received EXIT_SIGNAL"

# --- Subtest 3: Promise ABORT ---
echo ""
echo "Subtest: Promise ABORT"

setup_temp_repo
export MOCK_SCENARIO=abort

set +e
output=$(bash engine/ralph.sh 2>&1)
exit_code=$?
set -e

assert_exit_code "exits with code 1" "1" "$exit_code"
assert_output_contains "detects abort" "$output" "Ralph aborted"

print_summary "Exit detection tests"
