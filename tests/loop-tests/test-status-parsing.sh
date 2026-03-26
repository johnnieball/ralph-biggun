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

  mkdir -p specs

  mkdir -p "$tmpdir/bin"
  cp "$SCRIPT_DIR/mock-claude.sh" "$tmpdir/bin/claude"
  chmod +x "$tmpdir/bin/claude"
  export PATH="$tmpdir/bin:$PATH"
  export RALPH_SKIP_KICKOFF=1
  export RALPH_LOG_FILE="$tmpdir/logs/ralph-test.log"
  mkdir -p "$tmpdir/logs"
  OUTPUT_FILE="$tmpdir/output.txt"
}

# --- Subtest 1: All fields present — TESTS_STATUS extracted + lowercased ---
echo "Subtest: All fields present"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[{"id":"US-001","title":"Setup Project","passes":false,"acceptanceCriteria":["Project compiles"],"priority":"high","dependsOn":[]}]}
EOF

cat > .ralphrc << 'EOF'
RALPH_PLAN=test
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=1
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
EOF

export MOCK_SCENARIO=committed-with-story

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_output_contains "tests status lowercased in summary" "$output" "tests: passing"

# --- Subtest 2: CURRENT_STORY extracted — story ID + title + AC count ---
echo ""
echo "Subtest: CURRENT_STORY extracted"

# Reuse output from subtest 1
assert_output_contains "story ID in summary" "$output" "[US-001]"
assert_output_contains "story title in summary" "$output" "Setup Project"
assert_output_contains "AC count in summary" "$output" "1 ACs"

# --- Subtest 3: TESTS_STATUS case handling (FAILING → tests: failing) ---
echo ""
echo "Subtest: TESTS_STATUS FAILING lowercased"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[{"id":"US-001","title":"Setup","passes":false,"acceptanceCriteria":["test"],"priority":"high","dependsOn":[]}]}
EOF

cat > .ralphrc << 'EOF'
RALPH_PLAN=test
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=1
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
EOF

cat > bin/claude << 'MOCK_EOF'
#!/bin/bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) shift; shift ;;
    --output-format|--allowedTools) shift; shift ;;
    --dangerously-skip-permissions|--print|--verbose) shift ;;
    *) shift ;;
  esac
done

result_text="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
  '---RALPH_STATUS---' \
  'STATUS: IN_PROGRESS' \
  'CURRENT_STORY: US-001' \
  'TASKS_COMPLETED_THIS_LOOP: 0' \
  'FILES_MODIFIED: 1' \
  'TESTS_STATUS: FAILING' \
  'EXIT_SIGNAL: false' \
  'RECOMMENDATION: Fix test failures' \
  '---END_RALPH_STATUS---')"

jq -nc --arg t "Tests failing." '{"type":"assistant","message":{"content":[{"type":"text","text":$t}]}}'
jq -nc --arg r "$result_text" '{"type":"result","result":$r}'

touch .mock-failing-marker
git add .mock-failing-marker 2>/dev/null || true
git commit -m "RALPH: debug: fixing tests" --allow-empty 2>/dev/null || true
MOCK_EOF
chmod +x bin/claude

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
set -e
output=$(cat "$OUTPUT_FILE")

assert_output_contains "FAILING lowercased to failing" "$output" "tests: failing"

# --- Subtest 4: Missing status block entirely ---
echo ""
echo "Subtest: Missing status block entirely"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[]}
EOF

cat > .ralphrc << 'EOF'
RALPH_PLAN=test
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=1
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
EOF

export MOCK_SCENARIO=missing-status-block

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_output_contains "tests default to unknown" "$output" "tests: unknown"
assert_exit_code "does not crash (exits 1 for max iter)" "1" "$exit_code"

# --- Subtest 5: Extra whitespace around values ---
echo ""
echo "Subtest: Extra whitespace around values"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[{"id":"US-001","title":"Setup","passes":false,"acceptanceCriteria":["test"],"priority":"high","dependsOn":[]}]}
EOF

cat > .ralphrc << 'EOF'
RALPH_PLAN=test
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=1
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
EOF

cat > bin/claude << 'MOCK_EOF'
#!/bin/bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) shift; shift ;;
    --output-format|--allowedTools) shift; shift ;;
    --dangerously-skip-permissions|--print|--verbose) shift ;;
    *) shift ;;
  esac
done

result_text="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s' \
  '---RALPH_STATUS---' \
  'STATUS:    IN_PROGRESS  ' \
  'CURRENT_STORY:   US-001  ' \
  'TESTS_STATUS:   PASSING  ' \
  'EXIT_SIGNAL:   false  ' \
  'RECOMMENDATION:   Keep going  ' \
  '---END_RALPH_STATUS---')"

jq -nc --arg t "Working." '{"type":"assistant","message":{"content":[{"type":"text","text":$t}]}}'
jq -nc --arg r "$result_text" '{"type":"result","result":$r}'

touch .mock-ws-marker
git add .mock-ws-marker 2>/dev/null || true
git commit -m "RALPH: mock whitespace" --allow-empty 2>/dev/null || true
MOCK_EOF
chmod +x bin/claude

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
set -e
output=$(cat "$OUTPUT_FILE")

assert_output_contains "whitespace handled for story" "$output" "[US-001]"
assert_output_contains "whitespace handled for test status" "$output" "tests: passing"

# --- Subtest 6: EXIT_SIGNAL: false — loop does NOT exit early ---
echo ""
echo "Subtest: EXIT_SIGNAL false does not exit early"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[]}
EOF

cat > .ralphrc << 'EOF'
RALPH_PLAN=test
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=1
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
EOF

export MOCK_SCENARIO=normal

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits 1 (max iterations, not 0)" "1" "$exit_code"
assert_output_contains "reaches max iterations" "$output" "Ralph reached max iterations"

# --- Subtest 7: Same RECOMMENDATION triggers circuit breaker ---
echo ""
echo "Subtest: Same RECOMMENDATION triggers circuit breaker"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[]}
EOF

cat > .ralphrc << 'EOF'
RALPH_PLAN=test
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=10
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=2
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
EOF

export MOCK_SCENARIO=same-error

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits 1" "1" "$exit_code"
assert_output_contains "CB fires on same RECOMMENDATION" "$output" "CIRCUIT BREAKER: Same output repeated"

# --- Subtest 8: PHASE_COMPLETE with E2E disabled ---
echo ""
echo "Subtest: PHASE_COMPLETE with E2E disabled"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{
  "userStories": [{"id":"US-001","title":"Setup","passes":false,"acceptanceCriteria":["init"],"priority":"high","dependsOn":[]}],
  "phases": [{"id":"PH-1","stories":["US-001"],"journeys":[]}]
}
EOF

cat > .ralphrc << 'EOF'
RALPH_PLAN=test
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=1
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
E2E_ENABLED=false
EOF

cat > bin/claude << 'MOCK_EOF'
#!/bin/bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) shift; shift ;;
    --output-format|--allowedTools) shift; shift ;;
    --dangerously-skip-permissions|--print|--verbose) shift ;;
    *) shift ;;
  esac
done

result_text="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
  '---RALPH_STATUS---' \
  'STATUS: IN_PROGRESS' \
  'CURRENT_STORY: US-001' \
  'TESTS_STATUS: PASSING' \
  'EXIT_SIGNAL: false' \
  'PHASE_COMPLETE: PH-1' \
  'RECOMMENDATION: Phase done' \
  '---END_RALPH_STATUS---')"

jq -nc --arg t "Phase done." '{"type":"assistant","message":{"content":[{"type":"text","text":$t}]}}'
jq -nc --arg r "$result_text" '{"type":"result","result":$r}'

touch .mock-phase-marker
git add .mock-phase-marker 2>/dev/null || true
git commit -m "RALPH: mock phase complete" --allow-empty 2>/dev/null || true
MOCK_EOF
chmod +x bin/claude

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
set -e
output=$(cat "$OUTPUT_FILE")

assert_output_not_contains "no E2E gate with E2E disabled" "$output" "Running phase-end E2E gate"

print_summary "Status parsing tests"
