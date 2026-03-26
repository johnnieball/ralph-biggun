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

# --- Subtest 1: Empty userStories [] ---
echo "Subtest: Empty userStories []"

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

export MOCK_SCENARIO=exit-signal

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e

assert_exit_code "no crash with empty stories" "0" "$exit_code"

# --- Subtest 2: Missing userStories key {} ---
echo ""
echo "Subtest: Missing userStories key"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{}
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

export MOCK_SCENARIO=exit-signal

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
exit_code=$?
set -e

assert_exit_code "no crash with missing key" "0" "$exit_code"

# --- Subtest 3: Custom storyPrefix "FEAT" ---
echo ""
echo "Subtest: Custom storyPrefix FEAT"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"storyPrefix":"FEAT","userStories":[{"id":"FEAT-001","title":"Custom Feature","passes":false,"acceptanceCriteria":["works"],"priority":"high","dependsOn":[]}]}
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

# Inline mock: no CURRENT_STORY, commits with FEAT-001 in message
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

result_text="$(printf '%s\n%s\n%s\n%s\n%s\n%s' \
  '---RALPH_STATUS---' \
  'STATUS: IN_PROGRESS' \
  'TESTS_STATUS: PASSING' \
  'EXIT_SIGNAL: false' \
  'RECOMMENDATION: Continue' \
  '---END_RALPH_STATUS---')"

jq -nc --arg t "Working." '{"type":"assistant","message":{"content":[{"type":"text","text":$t}]}}'
jq -nc --arg r "$result_text" '{"type":"result","result":$r}'

touch .mock-feat-marker
git add .mock-feat-marker 2>/dev/null || true
git commit -m "RALPH: feat: [FEAT-001] - Custom Feature" --allow-empty 2>/dev/null || true
MOCK_EOF
chmod +x bin/claude

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
set -e
output=$(cat "$OUTPUT_FILE")

assert_output_contains "custom prefix extracted from commit" "$output" "[FEAT-001]"

# --- Subtest 4: Missing storyPrefix defaults to US ---
echo ""
echo "Subtest: Missing storyPrefix defaults to US"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[{"id":"US-001","title":"Default Prefix","passes":false,"acceptanceCriteria":["works"],"priority":"high","dependsOn":[]}]}
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

# Inline mock: no CURRENT_STORY, commits with US-001 in message
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

result_text="$(printf '%s\n%s\n%s\n%s\n%s\n%s' \
  '---RALPH_STATUS---' \
  'STATUS: IN_PROGRESS' \
  'TESTS_STATUS: PASSING' \
  'EXIT_SIGNAL: false' \
  'RECOMMENDATION: Continue' \
  '---END_RALPH_STATUS---')"

jq -nc --arg t "Working." '{"type":"assistant","message":{"content":[{"type":"text","text":$t}]}}'
jq -nc --arg r "$result_text" '{"type":"result","result":$r}'

touch .mock-us-marker
git add .mock-us-marker 2>/dev/null || true
git commit -m "RALPH: feat: [US-001] - Default Prefix" --allow-empty 2>/dev/null || true
MOCK_EOF
chmod +x bin/claude

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
set -e
output=$(cat "$OUTPUT_FILE")

assert_output_contains "default US prefix extracted" "$output" "[US-001]"

# --- Subtest 5: Story missing acceptanceCriteria field ---
echo ""
echo "Subtest: Story missing acceptanceCriteria"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[{"id":"US-001","title":"No ACs","passes":false,"priority":"high","dependsOn":[]}]}
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

# jq: null | length = 0, so missing AC field → 0 ACs
assert_output_contains "missing AC field handled" "$output" "0 ACs"
assert_exit_code "no crash" "1" "$exit_code"

# --- Subtest 6: Empty acceptanceCriteria [] ---
echo ""
echo "Subtest: Empty acceptanceCriteria []"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[{"id":"US-001","title":"Empty ACs","passes":false,"acceptanceCriteria":[],"priority":"high","dependsOn":[]}]}
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
set -e
output=$(cat "$OUTPUT_FILE")

assert_output_contains "empty AC shows 0" "$output" "0 ACs"

# --- Subtest 7: passes: "true" (string vs boolean true) ---
echo ""
echo "Subtest: passes string true vs boolean true"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[{"id":"US-001","title":"String passes","passes":"true","acceptanceCriteria":["test"],"priority":"high","dependsOn":[]}]}
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
set -e
output=$(cat "$OUTPUT_FILE")

# jq select(.passes == true) won't match string "true"
assert_output_contains "string true not counted as done" "$output" "0/1 done"

# --- Subtest 8: Iteration budget with 3 remaining ---
echo ""
echo "Subtest: Iteration budget 3 remaining"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[
  {"id":"US-001","title":"A","passes":false,"acceptanceCriteria":["t"],"priority":"high","dependsOn":[]},
  {"id":"US-002","title":"B","passes":false,"acceptanceCriteria":["t"],"priority":"medium","dependsOn":[]},
  {"id":"US-003","title":"C","passes":false,"acceptanceCriteria":["t"],"priority":"low","dependsOn":[]}
]}
EOF

# No MAX_ITERATIONS — let it be computed
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
set -e
output=$(cat "$OUTPUT_FILE")

# remaining=3, computed=(3*13+9)/10=4, max(4,5)=5
assert_output_contains "budget is 5 (minimum)" "$output" "Computed iteration budget: 5"

# --- Subtest 9: Iteration budget with 10 remaining ---
echo ""
echo "Subtest: Iteration budget 10 remaining"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[
  {"id":"US-001","title":"A","passes":false,"acceptanceCriteria":["t"],"priority":"high","dependsOn":[]},
  {"id":"US-002","title":"B","passes":false,"acceptanceCriteria":["t"],"priority":"high","dependsOn":[]},
  {"id":"US-003","title":"C","passes":false,"acceptanceCriteria":["t"],"priority":"high","dependsOn":[]},
  {"id":"US-004","title":"D","passes":false,"acceptanceCriteria":["t"],"priority":"high","dependsOn":[]},
  {"id":"US-005","title":"E","passes":false,"acceptanceCriteria":["t"],"priority":"high","dependsOn":[]},
  {"id":"US-006","title":"F","passes":false,"acceptanceCriteria":["t"],"priority":"medium","dependsOn":[]},
  {"id":"US-007","title":"G","passes":false,"acceptanceCriteria":["t"],"priority":"medium","dependsOn":[]},
  {"id":"US-008","title":"H","passes":false,"acceptanceCriteria":["t"],"priority":"medium","dependsOn":[]},
  {"id":"US-009","title":"I","passes":false,"acceptanceCriteria":["t"],"priority":"low","dependsOn":[]},
  {"id":"US-010","title":"J","passes":false,"acceptanceCriteria":["t"],"priority":"low","dependsOn":[]}
]}
EOF

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
set -e
output=$(cat "$OUTPUT_FILE")

# remaining=10, computed=(10*13+9)/10=13, max(13,5)=13
assert_output_contains "budget is 13" "$output" "Computed iteration budget: 13"

# --- Subtest 10: Story with no title field ---
echo ""
echo "Subtest: Story with no title field"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[{"id":"US-001","passes":false,"acceptanceCriteria":["test"],"priority":"high","dependsOn":[]}]}
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
set -e
output=$(cat "$OUTPUT_FILE")

assert_output_contains "story ID without title" "$output" "[US-001]"
assert_output_not_contains "no dash-title separator" "$output" "[US-001] -"

print_summary "Task JSON contract tests"
