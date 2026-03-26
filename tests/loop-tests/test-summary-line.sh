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

# --- Subtest 1: Committed iteration format ---
echo "Subtest: Committed iteration format"

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
set -e
output=$(cat "$OUTPUT_FILE")

assert_output_matches "committed format" "$output" '\[1/1\] \[US-001\] - Setup Project \| 0/1 done \| committed \| tests: passing \| 1 ACs \| cb: 0/10'

# --- Subtest 2: No-commit iteration format ---
echo ""
echo "Subtest: No-commit iteration format"

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

export MOCK_SCENARIO=no-commit

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
set -e
output=$(cat "$OUTPUT_FILE")

assert_output_contains "no commit label" "$output" "no commit"
assert_output_contains "story progress" "$output" "0/0 done"

# --- Subtest 3: Story ID fallback from commit message ---
echo ""
echo "Subtest: Story ID fallback from commit message"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[{"id":"US-001","title":"Fallback Test","passes":false,"acceptanceCriteria":["works"],"priority":"high","dependsOn":[]}]}
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

# Inline mock: no CURRENT_STORY in RALPH_STATUS, commits with US-001
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

touch .mock-fallback-marker
git add .mock-fallback-marker 2>/dev/null || true
git commit -m "RALPH: feat: [US-001] - Fallback Test" --allow-empty 2>/dev/null || true
MOCK_EOF
chmod +x bin/claude

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
set -e
output=$(cat "$OUTPUT_FILE")

assert_output_contains "story ID from commit message" "$output" "[US-001]"
assert_output_contains "title from task JSON" "$output" "Fallback Test"

# --- Subtest 4: Run summary header on exit ---
echo ""
echo "Subtest: Run summary header"

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
set -e
output=$(cat "$OUTPUT_FILE")

assert_output_contains "run summary header" "$output" "RALPH RUN SUMMARY"

# --- Subtest 5: Exit reason label ---
echo ""
echo "Subtest: Exit reason label"

# Reuse output from subtest 4
assert_output_contains "exit reason present" "$output" "Exit reason:"
assert_output_contains "exit reason is exit_signal" "$output" "exit_signal"

# --- Subtest 6: Story timing section ---
echo ""
echo "Subtest: Story timing section"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[{"id":"US-001","title":"Timed Story","passes":false,"acceptanceCriteria":["works"],"priority":"high","dependsOn":[]}]}
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

assert_output_contains "story timing section" "$output" "Story Timing:"
assert_output_contains "story ID in timing" "$output" "US-001"

# --- Subtest 7: No stories → no timing section ---
echo ""
echo "Subtest: No stories no timing section"

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
set -e
output=$(cat "$OUTPUT_FILE")

assert_output_not_contains "no timing section" "$output" "Story Timing:"

# --- Subtest 8: Multi-iteration timing ---
echo ""
echo "Subtest: Multi-iteration timing"

setup_temp_repo

cat > specs/tasks-test.json << 'EOF'
{"userStories":[{"id":"US-001","title":"Multi Iter","passes":false,"acceptanceCriteria":["works"],"priority":"high","dependsOn":[]}]}
EOF

cat > .ralphrc << 'EOF'
RALPH_PLAN=test
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=2
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
ITER_TIMEOUT_SECS=0
EOF

# Inline mock: 2 iterations with story commits, different recommendations
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

COUNTER_FILE=".ralph-iter-counter"
count=0
if [ -f "$COUNTER_FILE" ]; then
  count=$(cat "$COUNTER_FILE")
fi
count=$(( count + 1 ))
echo "$count" > "$COUNTER_FILE"

result_text="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s' \
  '---RALPH_STATUS---' \
  'STATUS: IN_PROGRESS' \
  'CURRENT_STORY: US-001' \
  'TESTS_STATUS: PASSING' \
  'EXIT_SIGNAL: false' \
  "RECOMMENDATION: Iteration $count" \
  '---END_RALPH_STATUS---')"

jq -nc --arg t "Iteration $count." '{"type":"assistant","message":{"content":[{"type":"text","text":$t}]}}'
jq -nc --arg r "$result_text" '{"type":"result","result":$r}'

touch ".mock-multi-marker-$count"
git add ".mock-multi-marker-$count" 2>/dev/null || true
git commit -m "RALPH: feat: [US-001] - Multi iter $count" --allow-empty 2>/dev/null || true
MOCK_EOF
chmod +x bin/claude

set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
set -e
output=$(cat "$OUTPUT_FILE")

assert_output_contains "timing section exists" "$output" "Story Timing:"
assert_output_contains "average timing" "$output" "Average:"
assert_output_contains "slowest timing" "$output" "Slowest:"
assert_output_contains "fastest timing" "$output" "Fastest:"

print_summary "Summary line tests"
