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
  local tasks_json="$2"
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
  echo "$tasks_json" > specs/tasks-test.json
  {
    echo "RALPH_PLAN=test"
    echo "$ralphrc_content"
  } > .ralphrc

  mkdir -p "$tmpdir/bin"
  cp "$SCRIPT_DIR/mock-claude.sh" "$tmpdir/bin/claude"
  chmod +x "$tmpdir/bin/claude"
  export PATH="$tmpdir/bin:$PATH"
  export RALPH_SKIP_KICKOFF=1
  export RALPH_LOG_FILE="$tmpdir/logs/ralph-test.log"
  mkdir -p "$tmpdir/logs"
  OUTPUT_FILE="$tmpdir/output.txt"
}

RALPHRC_DEFAULTS="$(cat <<'EOF'
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=3
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
EOF
)"

# --- Subtest 1: No requiredEnv field — runs normally ---
echo "Subtest: No requiredEnv field"

TASKS_NO_ENV='{"userStories":[{"id":"US-001","title":"Setup","description":"Setup project","acceptanceCriteria":["Project initialises"],"priority":"high","passes":false,"dependsOn":[],"notes":""}]}'

setup_temp_repo "$RALPHRC_DEFAULTS" "$TASKS_NO_ENV"
export MOCK_SCENARIO=exit-signal

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits with code 0" "0" "$exit_code"
assert_output_not_contains "no preflight banner" "$output" "PRE-FLIGHT CHECK FAILED"

# --- Subtest 2: Empty requiredEnv array — runs normally ---
echo ""
echo "Subtest: Empty requiredEnv array"

TASKS_EMPTY_ENV='{"requiredEnv":[],"userStories":[{"id":"US-001","title":"Setup","description":"Setup project","acceptanceCriteria":["Project initialises"],"priority":"high","passes":false,"dependsOn":[],"notes":""}]}'

setup_temp_repo "$RALPHRC_DEFAULTS" "$TASKS_EMPTY_ENV"
export MOCK_SCENARIO=exit-signal

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits with code 0" "0" "$exit_code"
assert_output_not_contains "no preflight banner" "$output" "PRE-FLIGHT CHECK FAILED"

# --- Subtest 3: All vars present in environment — runs normally ---
echo ""
echo "Subtest: All vars present in environment"

TASKS_WITH_ENV='{"requiredEnv":[{"var":"PREFLIGHT_TEST_VAR_A","for":"Test A"},{"var":"PREFLIGHT_TEST_VAR_B","for":"Test B"}],"userStories":[{"id":"US-001","title":"Setup","description":"Setup project","acceptanceCriteria":["Project initialises"],"priority":"high","passes":false,"dependsOn":[],"notes":""}]}'

setup_temp_repo "$RALPHRC_DEFAULTS" "$TASKS_WITH_ENV"
export MOCK_SCENARIO=exit-signal
export PREFLIGHT_TEST_VAR_A="value-a"
export PREFLIGHT_TEST_VAR_B="value-b"

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits with code 0" "0" "$exit_code"
assert_output_not_contains "no preflight failure" "$output" "PRE-FLIGHT CHECK FAILED"

unset PREFLIGHT_TEST_VAR_A
unset PREFLIGHT_TEST_VAR_B

# --- Subtest 4: Var set to empty string — still passes ---
echo ""
echo "Subtest: Var set to empty string passes"

TASKS_EMPTY_VAL='{"requiredEnv":[{"var":"PREFLIGHT_EMPTY_VAR","for":"Should pass even if empty"}],"userStories":[{"id":"US-001","title":"Setup","description":"Setup project","acceptanceCriteria":["Project initialises"],"priority":"high","passes":false,"dependsOn":[],"notes":""}]}'

setup_temp_repo "$RALPHRC_DEFAULTS" "$TASKS_EMPTY_VAL"
export MOCK_SCENARIO=exit-signal
export PREFLIGHT_EMPTY_VAR=""

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits with code 0" "0" "$exit_code"
assert_output_not_contains "no preflight failure for empty var" "$output" "PRE-FLIGHT CHECK FAILED"

unset PREFLIGHT_EMPTY_VAR

# --- Subtest 5: Var missing entirely — exits 1 ---
echo ""
echo "Subtest: Var missing entirely"

TASKS_MISSING_VAR='{"requiredEnv":[{"var":"TOTALLY_MISSING_VAR_XYZ","for":"Integration tests (US-005)"}],"userStories":[{"id":"US-001","title":"Setup","description":"Setup project","acceptanceCriteria":["Project initialises"],"priority":"high","passes":false,"dependsOn":[],"notes":""}]}'

setup_temp_repo "$RALPHRC_DEFAULTS" "$TASKS_MISSING_VAR"
unset TOTALLY_MISSING_VAR_XYZ 2>/dev/null || true

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits with code 1" "1" "$exit_code"
assert_output_contains "shows preflight banner" "$output" "PRE-FLIGHT CHECK FAILED"
assert_output_contains "shows var name" "$output" "TOTALLY_MISSING_VAR_XYZ"
assert_output_contains "shows for description" "$output" "Integration tests (US-005)"
assert_output_contains "shows not-defined message" "$output" "not defined in environment or .env"

# --- Subtest 4: Var in .env but not in process — exits 1 with .env guidance ---
echo ""
echo "Subtest: Var in .env but not loaded"

TASKS_DOTENV_VAR='{"requiredEnv":[{"var":"DOTENV_ONLY_VAR","for":"Database connectivity"}],"userStories":[{"id":"US-001","title":"Setup","description":"Setup project","acceptanceCriteria":["Project initialises"],"priority":"high","passes":false,"dependsOn":[],"notes":""}]}'

setup_temp_repo "$RALPHRC_DEFAULTS" "$TASKS_DOTENV_VAR"
unset DOTENV_ONLY_VAR 2>/dev/null || true
echo "DOTENV_ONLY_VAR=some-secret-value" > .env

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits with code 1" "1" "$exit_code"
assert_output_contains "shows preflight banner" "$output" "PRE-FLIGHT CHECK FAILED"
assert_output_contains "shows .env guidance" "$output" "found in .env but NOT loaded"
assert_output_contains "shows fix hint" "$output" "source .env"

# --- Subtest 7: Var in .env with export prefix — still detected ---
echo ""
echo "Subtest: Var in .env with export prefix"

TASKS_EXPORT_ENV='{"requiredEnv":[{"var":"EXPORT_PREFIX_VAR","for":"Uses export syntax"}],"userStories":[{"id":"US-001","title":"Setup","description":"Setup project","acceptanceCriteria":["Project initialises"],"priority":"high","passes":false,"dependsOn":[],"notes":""}]}'

setup_temp_repo "$RALPHRC_DEFAULTS" "$TASKS_EXPORT_ENV"
unset EXPORT_PREFIX_VAR 2>/dev/null || true
echo "export EXPORT_PREFIX_VAR=some-value" > .env

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits with code 1" "1" "$exit_code"
assert_output_contains "detects export-prefixed var" "$output" "found in .env but NOT loaded"

# --- Subtest 8: RALPH_SKIP_PREFLIGHT=1 bypasses check ---
echo ""
echo "Subtest: RALPH_SKIP_PREFLIGHT=1 bypasses check"

TASKS_MISSING_BUT_SKIP='{"requiredEnv":[{"var":"TOTALLY_MISSING_VAR_XYZ","for":"Should be skipped"}],"userStories":[{"id":"US-001","title":"Setup","description":"Setup project","acceptanceCriteria":["Project initialises"],"priority":"high","passes":false,"dependsOn":[],"notes":""}]}'

setup_temp_repo "$RALPHRC_DEFAULTS" "$TASKS_MISSING_BUT_SKIP"
export MOCK_SCENARIO=exit-signal
export RALPH_SKIP_PREFLIGHT=1
unset TOTALLY_MISSING_VAR_XYZ 2>/dev/null || true

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits with code 0" "0" "$exit_code"
assert_output_not_contains "no preflight banner" "$output" "PRE-FLIGHT CHECK FAILED"

unset RALPH_SKIP_PREFLIGHT

# --- Subtest 6: Mixed — some vars present, some missing ---
echo ""
echo "Subtest: Mixed vars (one present, one missing)"

TASKS_MIXED='{"requiredEnv":[{"var":"PREFLIGHT_PRESENT_VAR","for":"This one is set"},{"var":"PREFLIGHT_ABSENT_VAR","for":"This one is missing"}],"userStories":[{"id":"US-001","title":"Setup","description":"Setup project","acceptanceCriteria":["Project initialises"],"priority":"high","passes":false,"dependsOn":[],"notes":""}]}'

setup_temp_repo "$RALPHRC_DEFAULTS" "$TASKS_MIXED"
export PREFLIGHT_PRESENT_VAR="I-exist"
unset PREFLIGHT_ABSENT_VAR 2>/dev/null || true

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits with code 1" "1" "$exit_code"
assert_output_contains "shows preflight banner" "$output" "PRE-FLIGHT CHECK FAILED"
assert_output_contains "reports missing var" "$output" "PREFLIGHT_ABSENT_VAR"
assert_output_contains "shows count of 1" "$output" "1 required environment variable(s)"
assert_output_not_contains "does not report present var as missing" "$output" "PREFLIGHT_PRESENT_VAR"

unset PREFLIGHT_PRESENT_VAR

print_summary "Pre-flight environment check tests"
