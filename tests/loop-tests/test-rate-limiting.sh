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

  # Use .ralph/ layout
  "$REPO_ROOT/ralph" init "$tmpdir" > /dev/null 2>&1
  echo '{"userStories":[]}' > "$tmpdir/.ralph/specs/tasks-test.json"

  {
    echo ""
    echo "RALPH_PLAN=test"
    echo "$ralphrc_content"
  } >> "$tmpdir/.ralph/config.sh"

  mkdir -p "$tmpdir/bin"
  cp "$SCRIPT_DIR/mock-claude.sh" "$tmpdir/bin/claude"
  chmod +x "$tmpdir/bin/claude"
  export PATH="$tmpdir/bin:$PATH"
  export RALPH_SKIP_KICKOFF=1
}

echo "Subtest: Rate limit count file"

# Use exit-promise with MAX_ITERATIONS=1 so ralph exits after 1 iteration
# (deterministic — no background process or sleep needed)
setup_temp_repo "$(cat <<'EOF'
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=1
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
EOF
)"
export MOCK_SCENARIO=normal

set +e
.ralph/engine/ralph.sh > /dev/null 2>&1
set -e

# Check the rate count file
assert_true ".ralph-call-count file exists" test -f .ralph-call-count

if [ -f ".ralph-call-count" ]; then
  stored_hour=$(head -1 .ralph-call-count)
  stored_count=$(tail -1 .ralph-call-count)
  current_hour=$(date +"%Y%m%d%H")

  assert_exit_code "hour matches current hour" "$current_hour" "$stored_hour"

  if [ "$stored_count" -ge 1 ] 2>/dev/null; then
    echo "  PASS: count is at least 1 (got $stored_count)"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: count is not a positive number (got $stored_count)"
    FAIL=$(( FAIL + 1 ))
  fi
fi

# --- Subtest 2: Count increments across iterations ---
echo ""
echo "Subtest: Count file increments correctly"

setup_temp_repo "$(cat <<'EOF'
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=2
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
EOF
)"
export MOCK_SCENARIO=normal

set +e
.ralph/engine/ralph.sh > /dev/null 2>&1
set -e

if [ -f ".ralph-call-count" ]; then
  stored_count=$(tail -1 .ralph-call-count)
  if [ "$stored_count" -ge 2 ] 2>/dev/null; then
    echo "  PASS: count is at least 2 after 2 iterations (got $stored_count)"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: count should be at least 2, got $stored_count"
    FAIL=$(( FAIL + 1 ))
  fi
else
  echo "  FAIL: .ralph-call-count file does not exist after 2 iterations"
  FAIL=$(( FAIL + 1 ))
fi

print_summary "Rate limiting tests"
