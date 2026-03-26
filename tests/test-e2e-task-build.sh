#!/bin/bash
set -e

# End-to-end tests for `ralph task-build` — invoked through the CLI dispatcher
# exactly as a user types it. Validates the full chain:
#   ralph → commands/task-build.sh

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
  OUTPUT_FILE="$tmpdir/output.txt"
}

echo "E2E Task Build Tests"
echo "===================="

# --- Subtest 1: ralph task-build spec.md plan-name ---
echo ""
echo "Test: ralph task-build spec.md plan-name"

setup_ralph_project

cat > my-spec.md << 'EOF'
# Test Spec
Build a simple hello world app.
EOF

export MOCK_SCENARIO=task-converge
export MOCK_TASKS_PATH="$(pwd)/.ralph/specs/tasks-myfeature.json"

set +e
"$REPO_ROOT/ralph" task-build my-spec.md myfeature > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits 0" "0" "$exit_code"
assert_output_contains "reports convergence" "$output" "TASK BUILD COMPLETE"
assert_true "task file created" test -f .ralph/specs/tasks-myfeature.json

# --- Subtest 2: ralph task-build spec.md (plan name from filename) ---
echo ""
echo "Test: ralph task-build derives plan name from spec"

setup_ralph_project

cat > feature-auth.md << 'EOF'
# Auth Feature
Add user authentication.
EOF

export MOCK_SCENARIO=task-converge
export MOCK_TASKS_PATH="$(pwd)/.ralph/specs/tasks-feature-auth.json"

set +e
"$REPO_ROOT/ralph" task-build feature-auth.md > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits 0" "0" "$exit_code"
assert_true "task file named from spec" test -f .ralph/specs/tasks-feature-auth.json

# --- Subtest 3: ralph task-build missing-spec.md → error ---
echo ""
echo "Test: ralph task-build with missing spec"

setup_ralph_project

set +e
"$REPO_ROOT/ralph" task-build does-not-exist.md > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits 1" "1" "$exit_code"
assert_output_contains "says file not found" "$output" "not found"

# --- Subtest 4: ralph task-build (no args) → usage ---
echo ""
echo "Test: ralph task-build no args"

setup_ralph_project

set +e
"$REPO_ROOT/ralph" task-build > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits 1" "1" "$exit_code"
assert_output_contains "shows usage" "$output" "Usage"

print_summary "E2E task-build tests"
