#!/bin/bash
set -e

# Tests CLI argument parsing — the entry points real users hit.
# Every other loop test sets RALPH_PLAN in .ralphrc and passes zero args.
# These tests invoke ralph.sh the way users do: with CLI arguments.

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

  mkdir -p specs
  echo '{"userStories":[]}' > specs/tasks-test.json

  mkdir -p "$tmpdir/bin"
  cp "$SCRIPT_DIR/mock-claude.sh" "$tmpdir/bin/claude"
  chmod +x "$tmpdir/bin/claude"
  export PATH="$tmpdir/bin:$PATH"
  export RALPH_SKIP_KICKOFF=1
  export RALPH_LOG_FILE="$tmpdir/logs/ralph-test.log"
  mkdir -p "$tmpdir/logs"
  OUTPUT_FILE="$tmpdir/output.txt"
}

# --- Subtest 1: Plan name as sole argument ---
echo "Subtest: Plan name as sole argument"

setup_temp_repo

# Minimal config — NO RALPH_PLAN, NO MAX_ITERATIONS
cat > .ralphrc << 'EOF'
MAX_CALLS_PER_HOUR=100
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
EOF

export MOCK_SCENARIO=exit-signal

set +e
bash engine/ralph.sh test > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "plan name as first arg exits 0" "0" "$exit_code"
assert_output_contains "uses correct task file" "$output" "Using tasks: specs/tasks-test.json"

# --- Subtest 2: Numeric iterations + plan name ---
echo ""
echo "Subtest: Numeric iterations + plan name"

setup_temp_repo

cat > .ralphrc << 'EOF'
MAX_CALLS_PER_HOUR=100
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
EOF

export MOCK_SCENARIO=exit-signal

set +e
bash engine/ralph.sh 5 test > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "iterations + plan exits 0" "0" "$exit_code"
assert_output_contains "uses correct task file" "$output" "Using tasks: specs/tasks-test.json"
assert_output_contains "uses explicit iteration count" "$output" "Max iterations: 5"

# --- Subtest 3: No args, RALPH_PLAN from config ---
echo ""
echo "Subtest: No args with RALPH_PLAN in config"

setup_temp_repo

cat > .ralphrc << 'EOF'
RALPH_PLAN=test
MAX_CALLS_PER_HOUR=100
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
EOF

export MOCK_SCENARIO=exit-signal

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "config plan exits 0" "0" "$exit_code"
assert_output_contains "uses task file from config" "$output" "Using tasks: specs/tasks-test.json"

# --- Subtest 4: Zero iterations rejected ---
echo ""
echo "Subtest: Zero iterations rejected"

setup_temp_repo

cat > .ralphrc << 'EOF'
RALPH_PLAN=test
MAX_CALLS_PER_HOUR=100
ALLOWED_TOOLS=""
EOF

set +e
bash engine/ralph.sh 0 test > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "zero iterations exits 1" "1" "$exit_code"
assert_output_contains "rejects zero" "$output" "must be at least 1"

# --- Subtest 5: No plan and no config → helpful error ---
echo ""
echo "Subtest: No plan shows error with available plans"

setup_temp_repo

# Config with NO RALPH_PLAN
cat > .ralphrc << 'EOF'
MAX_CALLS_PER_HOUR=100
ALLOWED_TOOLS=""
EOF

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "no plan exits 1" "1" "$exit_code"
assert_output_contains "shows error" "$output" "No plan selected"
assert_output_contains "lists available plans" "$output" "test"

# --- Subtest 6: Non-existent plan → helpful error ---
echo ""
echo "Subtest: Non-existent plan shows error"

setup_temp_repo

cat > .ralphrc << 'EOF'
MAX_CALLS_PER_HOUR=100
ALLOWED_TOOLS=""
EOF

set +e
bash engine/ralph.sh nonexistent > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "bad plan exits 1" "1" "$exit_code"
assert_output_contains "says not found" "$output" "Task file not found"
assert_output_contains "lists available plans" "$output" "test"

# --- Subtest 7: Iteration budget auto-computed when plan name is sole arg ---
echo ""
echo "Subtest: Budget auto-computed with plan-name-only invocation"

setup_temp_repo

# 3 stories → budget should be 5 (minimum)
cat > specs/tasks-test.json << 'EOF'
{"userStories":[
  {"id":"US-001","title":"A","passes":false,"acceptanceCriteria":["t"],"priority":"high","dependsOn":[]},
  {"id":"US-002","title":"B","passes":false,"acceptanceCriteria":["t"],"priority":"medium","dependsOn":[]},
  {"id":"US-003","title":"C","passes":false,"acceptanceCriteria":["t"],"priority":"low","dependsOn":[]}
]}
EOF

cat > .ralphrc << 'EOF'
MAX_CALLS_PER_HOUR=100
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
EOF

export MOCK_SCENARIO=exit-signal

set +e
bash engine/ralph.sh test > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits 0" "0" "$exit_code"
assert_output_contains "budget computed" "$output" "Computed iteration budget: 5"

print_summary "CLI argument tests"
