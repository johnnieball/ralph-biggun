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

# --- Subtest 1: PHASE_COMPLETE in RALPH_STATUS triggers E2E gate message ---
echo "Subtest: Phase completion detected in RALPH_STATUS"

setup_temp_repo

# Create a task list with phases and journeys
cat > specs/tasks-test.json << 'EOF'
{
  "userStories": [
    {"id":"US-001","title":"Setup","passes":false,"acceptanceCriteria":["Project initialises"],"priority":"high","dependsOn":[]}
  ],
  "phases": [
    {"id":"PH-1","name":"Setup","stories":["US-001"],"journeys":[]}
  ],
  "journeys": []
}
EOF

# Create mock that emits PHASE_COMPLETE
cat > bin/claude << 'MOCK_EOF'
#!/bin/bash
# Consume all args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) shift; shift ;;
    --output-format|--allowedTools) shift; shift ;;
    --dangerously-skip-permissions|--print|--verbose) shift ;;
    *) shift ;;
  esac
done

result_text="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
  '---RALPH_STATUS---' \
  'STATUS: IN_PROGRESS' \
  'CURRENT_STORY: US-001' \
  'TASKS_COMPLETED_THIS_LOOP: 1' \
  'FILES_MODIFIED: 1' \
  'TESTS_STATUS: PASSING' \
  'WORK_TYPE: IMPLEMENTATION' \
  'EXIT_SIGNAL: true' \
  'PHASE_COMPLETE: PH-1' \
  'RECOMMENDATION: Phase 1 complete' \
  '---END_RALPH_STATUS---')"

jq -nc --arg t "Phase complete." '{"type":"assistant","message":{"content":[{"type":"text","text":$t}]}}'
jq -nc --arg r "$result_text" '{"type":"result","result":$r}'

touch .mock-iteration-marker
git add .mock-iteration-marker 2>/dev/null || true
git commit -m "RALPH: mock phase complete" --allow-empty 2>/dev/null || true
MOCK_EOF
chmod +x bin/claude

# E2E is disabled, so we just verify the phase detection logic doesn't break
cat > .ralphrc << 'EOF'
RALPH_PLAN=test
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=1
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
E2E_ENABLED=false
EOF

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits 0 with exit signal" "0" "$exit_code"
assert_output_contains "detects EXIT_SIGNAL" "$output" "Ralph received EXIT_SIGNAL"

# --- Subtest 2: Phase detection with E2E enabled but no gate script ---
echo ""
echo "Subtest: E2E enabled but no e2e-gate.sh — no crash"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{
  "userStories": [{"id":"US-001","title":"Setup","passes":false}],
  "phases": [{"id":"PH-1","stories":["US-001"],"journeys":[]}],
  "journeys": []
}
EOF

# Mock emits PHASE_COMPLETE
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

result_text="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
  '---RALPH_STATUS---' \
  'STATUS: COMPLETE' \
  'CURRENT_STORY: US-001' \
  'TASKS_COMPLETED_THIS_LOOP: 1' \
  'FILES_MODIFIED: 1' \
  'TESTS_STATUS: PASSING' \
  'WORK_TYPE: IMPLEMENTATION' \
  'EXIT_SIGNAL: true' \
  'PHASE_COMPLETE: PH-1' \
  'RECOMMENDATION: Done' \
  '---END_RALPH_STATUS---')"

jq -nc --arg t "Done." '{"type":"assistant","message":{"content":[{"type":"text","text":$t}]}}'
jq -nc --arg r "$result_text" '{"type":"result","result":$r}'

touch .mock-marker
git add .mock-marker 2>/dev/null || true
git commit -m "RALPH: mock done" --allow-empty 2>/dev/null || true
MOCK_EOF
chmod +x bin/claude

cat > .ralphrc << 'EOF'
RALPH_PLAN=test
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=1
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
E2E_ENABLED=true
EOF

# No e2e-gate.sh exists in engine/ — the -x check should prevent crash
set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e

assert_exit_code "exits 0 without e2e-gate.sh" "0" "$exit_code"

# --- Subtest 3: No PHASE_COMPLETE — no gate triggered ---
echo ""
echo "Subtest: No PHASE_COMPLETE field — no E2E gate"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[]}
EOF

export MOCK_SCENARIO=exit-signal
cat > .ralphrc << 'EOF'
RALPH_PLAN=test
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=1
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
E2E_ENABLED=true
EOF

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e
output=$(cat "$OUTPUT_FILE")

assert_exit_code "exits 0" "0" "$exit_code"
assert_output_not_contains "no phase E2E gate" "$output" "Running phase-end E2E gate"

print_summary "Phase detection tests"
