#!/bin/bash
set -e

# End-to-end tests for `ralph run` — invoked through the CLI dispatcher
# exactly as a user types it. Validates the full chain:
#   ralph → commands/run.sh → engine/ralph.sh

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

setup_ralph_project() {
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

  # Use `ralph init` to create a real .ralph/ layout
  "$REPO_ROOT/ralph" init "$tmpdir" > /dev/null 2>&1

  # Mock claude in PATH
  mkdir -p "$tmpdir/bin"
  cp "$SCRIPT_DIR/loop-tests/mock-claude.sh" "$tmpdir/bin/claude"
  chmod +x "$tmpdir/bin/claude"
  export PATH="$tmpdir/bin:$PATH"
  export RALPH_SKIP_KICKOFF=1
  export RALPH_LOG_FILE="$tmpdir/.ralph/logs/ralph-test.log"
  OUTPUT_FILE="$tmpdir/output.txt"
}

echo "E2E Run Tests"
echo "============="

# --- Subtest 1: ralph run plan-name (plan as sole argument) ---
echo ""
echo "Test: ralph run plan-name"

setup_ralph_project

cat > .ralph/specs/tasks-myplan.json << 'EOF'
{"userStories":[{"id":"US-001","title":"Test","passes":false,"acceptanceCriteria":["works"],"priority":"high","dependsOn":[]}]}
EOF

# No RALPH_PLAN, no MAX_ITERATIONS — both must come from CLI/auto-compute
cat >> .ralph/config.sh << 'EOF'
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
EOF

export MOCK_SCENARIO=exit-signal

set +e
"$REPO_ROOT/ralph" run myplan > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits 0" "0" "$exit_code"
assert_output_contains "finds task file" "$output" "tasks-myplan.json"
assert_output_contains "auto-computes budget" "$output" "Computed iteration budget:"

# --- Subtest 2: ralph run 3 plan-name (explicit iterations + plan) ---
echo ""
echo "Test: ralph run 3 plan-name"

setup_ralph_project

echo '{"userStories":[]}' > .ralph/specs/tasks-demo.json

cat >> .ralph/config.sh << 'EOF'
MAX_CALLS_PER_HOUR=100
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
EOF

export MOCK_SCENARIO=exit-signal

set +e
"$REPO_ROOT/ralph" run 3 demo > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits 0" "0" "$exit_code"
assert_output_contains "uses explicit iterations" "$output" "Max iterations: 3"
assert_output_contains "finds task file" "$output" "tasks-demo.json"

# --- Subtest 3: ralph run (no args, plan from config) ---
echo ""
echo "Test: ralph run with plan from config"

setup_ralph_project

echo '{"userStories":[]}' > .ralph/specs/tasks-configured.json

cat >> .ralph/config.sh << 'EOF'
RALPH_PLAN=configured
MAX_CALLS_PER_HOUR=100
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
EOF

export MOCK_SCENARIO=exit-signal

set +e
"$REPO_ROOT/ralph" run > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits 0" "0" "$exit_code"
assert_output_contains "uses config plan" "$output" "tasks-configured.json"

# --- Subtest 4: ralph run nonexistent → helpful error ---
echo ""
echo "Test: ralph run nonexistent plan"

setup_ralph_project

cat >> .ralph/config.sh << 'EOF'
MAX_CALLS_PER_HOUR=100
ALLOWED_TOOLS=""
EOF

set +e
"$REPO_ROOT/ralph" run nonexistent > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits 1" "1" "$exit_code"
assert_output_contains "shows error" "$output" "Task file not found"

# --- Subtest 5: ralph run 0 plan → rejected ---
echo ""
echo "Test: ralph run 0 rejected"

setup_ralph_project

echo '{"userStories":[]}' > .ralph/specs/tasks-test.json

cat >> .ralph/config.sh << 'EOF'
MAX_CALLS_PER_HOUR=100
ALLOWED_TOOLS=""
EOF

set +e
"$REPO_ROOT/ralph" run 0 test > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits 1" "1" "$exit_code"
assert_output_contains "rejects zero" "$output" "must be at least 1"

# --- Subtest 6: Full iteration with summary output ---
echo ""
echo "Test: ralph run completes iteration with summary"

setup_ralph_project

cat > .ralph/specs/tasks-full.json << 'EOF'
{"userStories":[{"id":"US-001","title":"Setup","passes":false,"acceptanceCriteria":["compiles"],"priority":"high","dependsOn":[]}]}
EOF

cat >> .ralph/config.sh << 'EOF'
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=1
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
EOF

export MOCK_SCENARIO=committed-with-story

set +e
"$REPO_ROOT/ralph" run 1 full > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits 1 (max iterations)" "1" "$exit_code"
assert_output_contains "summary line has story" "$output" "[US-001]"
assert_output_contains "run summary printed" "$output" "RALPH RUN SUMMARY"

print_summary "E2E run tests"
