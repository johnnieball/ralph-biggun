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
assert_output_contains "reports convergence" "$output" "PRD converged"
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
assert_output_contains "reports max iterations" "$output" "reached max iterations (2)"
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

print_summary "PRD Build tests"
