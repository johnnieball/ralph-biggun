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

setup_temp_project() {
  local tmpdir
  tmpdir=$(mktemp -d)
  TMPDIR_PATHS+=("$tmpdir")
  cd "$tmpdir"

  mkdir -p engine
  cp "$REPO_ROOT/engine/e2e-gate.sh" engine/
  chmod +x engine/e2e-gate.sh

  mkdir -p specs
  echo "$tmpdir"
}

# --- Subtest 1: E2E disabled — exits 0 immediately ---
echo "Subtest: E2E disabled skips gate"

tmpdir=$(setup_temp_project)
cat > "$tmpdir/specs/tasks-test.json" << 'EOF'
{
  "userStories": [],
  "phases": [],
  "journeys": []
}
EOF

cat > "$tmpdir/.ralphrc" << 'EOF'
E2E_ENABLED=false
EOF
export RALPH_CONFIG="$tmpdir/.ralphrc"

set +e
output=$(bash "$tmpdir/engine/e2e-gate.sh" --all --tasks-path "$tmpdir/specs/tasks-test.json" 2>&1)
exit_code=$?
set -e

assert_exit_code "exits 0 when disabled" "0" "$exit_code"
assert_output_contains "shows disabled message" "$output" "E2E testing is disabled"

# --- Subtest 2: No journeys — exits 0 ---
echo ""
echo "Subtest: No journeys skips gate"

tmpdir=$(setup_temp_project)
cat > "$tmpdir/specs/tasks-test.json" << 'EOF'
{
  "userStories": [{"id":"US-001","title":"Setup","passes":false}],
  "phases": [{"id":"PH-1","stories":["US-001"],"journeys":[]}],
  "journeys": []
}
EOF

cat > "$tmpdir/.ralphrc" << 'EOF'
E2E_ENABLED=true
E2E_START_CMD=""
EOF
export RALPH_CONFIG="$tmpdir/.ralphrc"

set +e
output=$(bash "$tmpdir/engine/e2e-gate.sh" --all --tasks-path "$tmpdir/specs/tasks-test.json" 2>&1)
exit_code=$?
set -e

assert_exit_code "exits 0 with no journeys" "0" "$exit_code"
assert_output_contains "shows no journeys message" "$output" "No journeys to run"

# --- Subtest 3: Missing test files — exits 0 with warning ---
echo ""
echo "Subtest: Missing test files skips with warning"

tmpdir=$(setup_temp_project)
cat > "$tmpdir/specs/tasks-test.json" << 'EOF'
{
  "userStories": [
    {"id":"US-001","title":"Setup","passes":true,"e2eTestFile":null},
    {"id":"US-002","title":"Login","passes":true,"e2eTestFile":null}
  ],
  "phases": [{"id":"PH-1","stories":["US-001","US-002"],"journeys":["J-1"]}],
  "journeys": [{"id":"J-1","title":"Sign up flow","phase":"PH-1","steps":["Navigate to /signup"],"dependsOn":["US-001","US-002"]}]
}
EOF

cat > "$tmpdir/.ralphrc" << 'EOF'
E2E_ENABLED=true
E2E_START_CMD=""
EOF
export RALPH_CONFIG="$tmpdir/.ralphrc"

set +e
output=$(bash "$tmpdir/engine/e2e-gate.sh" --phase PH-1 --tasks-path "$tmpdir/specs/tasks-test.json" 2>&1)
exit_code=$?
set -e

assert_exit_code "exits 0 when no test files exist" "0" "$exit_code"
assert_output_contains "shows missing files message" "$output" "No E2E test files found"

# --- Subtest 4: Phase filter only returns phase journeys ---
echo ""
echo "Subtest: Phase filter selects correct journeys"

tmpdir=$(setup_temp_project)
cat > "$tmpdir/specs/tasks-test.json" << 'EOF'
{
  "userStories": [
    {"id":"US-001","title":"Setup","passes":true,"e2eTestFile":null},
    {"id":"US-002","title":"Login","passes":true,"e2eTestFile":null},
    {"id":"US-003","title":"Dashboard","passes":true,"e2eTestFile":null}
  ],
  "phases": [
    {"id":"PH-1","stories":["US-001","US-002"],"journeys":["J-1"]},
    {"id":"PH-2","stories":["US-003"],"journeys":["J-2"]}
  ],
  "journeys": [
    {"id":"J-1","title":"Sign up flow","phase":"PH-1","steps":["Navigate to /signup"],"dependsOn":["US-001","US-002"]},
    {"id":"J-2","title":"Dashboard flow","phase":"PH-2","steps":["Navigate to /dashboard"],"dependsOn":["US-003"]}
  ]
}
EOF

cat > "$tmpdir/.ralphrc" << 'EOF'
E2E_ENABLED=true
E2E_START_CMD=""
EOF
export RALPH_CONFIG="$tmpdir/.ralphrc"

set +e
output=$(bash "$tmpdir/engine/e2e-gate.sh" --phase PH-1 --tasks-path "$tmpdir/specs/tasks-test.json" 2>&1)
exit_code=$?
set -e

assert_output_contains "shows phase PH-1" "$output" "Running journeys for phase PH-1"
assert_output_not_contains "does not mention PH-2 journeys" "$output" "Dashboard flow"

# --- Subtest 5: Missing --tasks-path errors ---
echo ""
echo "Subtest: Missing --tasks-path errors"

tmpdir=$(setup_temp_project)

set +e
output=$(bash "$tmpdir/engine/e2e-gate.sh" --all 2>&1)
exit_code=$?
set -e

assert_exit_code "exits 1 without tasks-path" "1" "$exit_code"
assert_output_contains "shows error" "$output" "--tasks-path is required"

# --- Subtest 6: Missing --phase and --all errors ---
echo ""
echo "Subtest: Missing --phase and --all errors"

tmpdir=$(setup_temp_project)
cat > "$tmpdir/specs/tasks-test.json" << 'EOF'
{"userStories":[],"phases":[],"journeys":[]}
EOF

set +e
output=$(bash "$tmpdir/engine/e2e-gate.sh" --tasks-path "$tmpdir/specs/tasks-test.json" 2>&1)
exit_code=$?
set -e

assert_exit_code "exits 1 without phase or all" "1" "$exit_code"
assert_output_contains "shows error" "$output" "Specify --phase PH-X or --all"

print_summary "E2E gate tests"
