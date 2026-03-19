#!/bin/bash
set -e

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

# Sets up a temp project dir with engine, specs, logs, mock-claude on PATH.
# Sets TMPDIR to the path and cd's into it (call directly, not via $()).
setup_temp_project() {
  TMPDIR=$(mktemp -d)
  TMPDIR_PATHS+=("$TMPDIR")
  cd "$TMPDIR"

  # Minimal project structure
  mkdir -p engine specs logs

  # Copy prompt template
  cp "$REPO_ROOT/engine/prd-build-prompt.md" engine/

  # Create a dummy spec file
  cat > spec.md << 'EOF'
# Test Spec
Build a calculator that adds two numbers.
EOF

  # Put mock-claude on PATH
  mkdir -p "$TMPDIR/bin"
  cp "$SCRIPT_DIR/loop-tests/mock-claude.sh" "$TMPDIR/bin/claude"
  chmod +x "$TMPDIR/bin/claude"
  export PATH="$TMPDIR/bin:$PATH"
}

echo "PRD Build Tests"
echo "==============="

# --- Test 1: No args shows usage ---
echo ""
echo "Test: No args shows usage"

set +e
output=$("$REPO_ROOT/commands/prd-build.sh" 2>&1)
code=$?
set -e

assert_exit_code "exits with code 1" "1" "$code"
assert_output_contains "shows usage" "$output" "Usage: ralph prd-build"

# --- Test 2: Missing spec file ---
echo ""
echo "Test: Missing spec file"

set +e
output=$("$REPO_ROOT/commands/prd-build.sh" /tmp/nonexistent-spec-file-$$.md 2>&1)
code=$?
set -e

assert_exit_code "exits with code 1" "1" "$code"
assert_output_contains "mentions spec file not found" "$output" "Spec file not found"

# --- Test 3: Convergence detection ---
echo ""
echo "Test: PRD converges after 2 iterations"

setup_temp_project
export MOCK_SCENARIO=prd-converge
export MOCK_PRD_PATH="$TMPDIR/specs/prd-spec.json"

set +e
output=$("$REPO_ROOT/commands/prd-build.sh" "$TMPDIR/spec.md" 2>&1)
code=$?
set -e

assert_exit_code "exits with code 0" "0" "$code"
assert_output_contains "reports convergence" "$output" "PRD BUILD COMPLETE"
assert_true "PRD file was created" test -f "$TMPDIR/specs/prd-spec.json"
# Verify it's valid JSON
assert_true "PRD is valid JSON" jq empty "$TMPDIR/specs/prd-spec.json"

# --- Test 4: Max iterations cap ---
echo ""
echo "Test: Reaches max iterations"

setup_temp_project
export MOCK_SCENARIO=prd-always-change
export MOCK_PRD_PATH="$TMPDIR/specs/prd-spec.json"

set +e
output=$("$REPO_ROOT/commands/prd-build.sh" "$TMPDIR/spec.md" spec 2 2>&1)
code=$?
set -e

assert_exit_code "exits with code 0" "0" "$code"
assert_output_contains "reports max iterations" "$output" "MAX ITERATIONS"
assert_true "PRD file exists" test -f "$TMPDIR/specs/prd-spec.json"

# --- Test 5: PRD not created guard ---
echo ""
echo "Test: Warns when PRD not created"

setup_temp_project
export MOCK_SCENARIO=prd-no-write
export MOCK_PRD_PATH="$TMPDIR/specs/prd-spec.json"

set +e
output=$("$REPO_ROOT/commands/prd-build.sh" "$TMPDIR/spec.md" spec 2 2>&1)
code=$?
set -e

assert_exit_code "exits with code 1" "1" "$code"
assert_output_contains "warns about missing PRD" "$output" "PRD file not created"
assert_output_contains "reports error" "$output" "PRD was never created"

# --- Test 6: Plan name derived from spec filename ---
echo ""
echo "Test: Plan name from spec filename"

setup_temp_project
cat > "$TMPDIR/my-cool-project.md" << 'EOF'
# Cool Project
Build something cool.
EOF
export MOCK_SCENARIO=prd-converge
export MOCK_PRD_PATH="$TMPDIR/specs/prd-my-cool-project.json"

set +e
output=$("$REPO_ROOT/commands/prd-build.sh" "$TMPDIR/my-cool-project.md" 2>&1)
code=$?
set -e

assert_exit_code "exits with code 0" "0" "$code"
assert_true "PRD named from spec stem" test -f "$TMPDIR/specs/prd-my-cool-project.json"

# --- Test 7: Log file created ---
echo ""
echo "Test: Log file created"

setup_temp_project
export MOCK_SCENARIO=prd-converge
export MOCK_PRD_PATH="$TMPDIR/specs/prd-spec.json"

set +e
output=$("$REPO_ROOT/commands/prd-build.sh" "$TMPDIR/spec.md" 2>&1)
code=$?
set -e

log_count=$(ls "$TMPDIR/logs"/prd-build-*.log 2>/dev/null | wc -l | tr -d ' ')
assert_true "log file created in logs/" test "$log_count" -ge 1

# --- Test 8: Summary line format ---
echo ""
echo "Test: Summary line includes key info"

setup_temp_project
export MOCK_SCENARIO=prd-always-change
export MOCK_PRD_PATH="$TMPDIR/specs/prd-spec.json"

set +e
output=$("$REPO_ROOT/commands/prd-build.sh" "$TMPDIR/spec.md" spec 1 2>&1)
code=$?
set -e

assert_output_contains "summary has iteration counter" "$output" "[1/1]"
assert_output_contains "summary has fixes count" "$output" "fixes"
assert_output_contains "summary has human items" "$output" "human items"
assert_output_contains "summary has verdict" "$output" "verdict:"

# --- Test 9: NEEDS_HUMAN shows decisions and course of action ---
echo ""
echo "Test: NEEDS_HUMAN shows decisions and next steps"

setup_temp_project
export MOCK_SCENARIO=prd-needs-human
export MOCK_PRD_PATH="$TMPDIR/specs/prd-spec.json"

set +e
output=$("$REPO_ROOT/commands/prd-build.sh" "$TMPDIR/spec.md" 2>&1)
code=$?
set -e

assert_exit_code "exits with code 0" "0" "$code"
assert_output_contains "banner says NEEDS HUMAN INPUT" "$output" "NEEDS HUMAN INPUT"
assert_output_contains "shows Decisions needed header" "$output" "Decisions needed"
assert_output_contains "shows first human item" "$output" "auth: should sessions use JWT"
assert_output_contains "shows second human item" "$output" "search: full-text search"
assert_output_contains "tells user to update spec" "$output" "add your decisions to the spec file"
assert_output_contains "shows re-run command" "$output" "ralph prd-build"
# Should NOT show the /prd-review next step
if echo "$output" | grep -q '/prd-review'; then
  echo "  FAIL: should not show /prd-review when NEEDS_HUMAN"
  FAIL=$(( FAIL + 1 ))
else
  echo "  PASS: does not show /prd-review when NEEDS_HUMAN"
  PASS=$(( PASS + 1 ))
fi

# --- Test 10: NEEDS_HUMAN via max-iterations exit path ---
echo ""
echo "Test: NEEDS_HUMAN at max iterations shows decisions"

setup_temp_project
export MOCK_SCENARIO=prd-needs-human-no-converge
export MOCK_PRD_PATH="$TMPDIR/specs/prd-spec.json"

set +e
output=$("$REPO_ROOT/commands/prd-build.sh" "$TMPDIR/spec.md" spec 2 2>&1)
code=$?
set -e

assert_exit_code "exits with code 0" "0" "$code"
assert_output_contains "banner says MAX ITERATIONS + NEEDS HUMAN" "$output" "NEEDS HUMAN INPUT"
assert_output_contains "shows Decisions needed header" "$output" "Decisions needed"
assert_output_contains "shows human item" "$output" "caching: Redis or in-memory LRU"
assert_output_contains "tells user to update spec" "$output" "add your decisions to the spec file"
# Should NOT show the generic "may need further review" message
if echo "$output" | grep -q 'may need further review'; then
  echo "  FAIL: should not show generic review message when human items exist"
  FAIL=$(( FAIL + 1 ))
else
  echo "  PASS: generic review message suppressed when human items exist"
  PASS=$(( PASS + 1 ))
fi

print_summary "PRD Build tests"
