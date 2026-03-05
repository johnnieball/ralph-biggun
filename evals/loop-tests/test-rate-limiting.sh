#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0
FAIL=0

cleanup() {
  if [ -n "$TMPDIR_PATH" ] && [ -d "$TMPDIR_PATH" ]; then
    rm -rf "$TMPDIR_PATH"
  fi
}
trap cleanup EXIT

echo "Subtest: Rate limit count file"

TMPDIR_PATH=$(mktemp -d)
cd "$TMPDIR_PATH"

git init -q
git config user.email "test@test.com"
git config user.name "Test"
echo "init" > dummy.txt
git add -A
git commit -q -m "initial commit"

mkdir -p engine
cp "$REPO_ROOT/engine/ralph.sh" engine/
cp "$REPO_ROOT/engine/prompt.md" engine/

# Use normal scenario (creates commits) with low MAX_CALLS_PER_HOUR
# but high enough MAX_ITERATIONS to get a few iterations in
cat > .ralphrc << 'EOF'
MAX_CALLS_PER_HOUR=2
MAX_ITERATIONS=3
CB_NO_PROGRESS_THRESHOLD=10
CB_SAME_ERROR_THRESHOLD=10
ALLOWED_TOOLS=""
EOF

mkdir -p "$TMPDIR_PATH/bin"
cp "$SCRIPT_DIR/mock-claude.sh" "$TMPDIR_PATH/bin/claude"
chmod +x "$TMPDIR_PATH/bin/claude"
export PATH="$TMPDIR_PATH/bin:$PATH"
export RALPH_SKIP_KICKOFF=1
export MOCK_SCENARIO=normal

# Run ralph.sh in background, kill after a few seconds
# (It will sleep when hitting the rate limit, so we just need 2 iterations)
set +e
bash engine/ralph.sh > /dev/null 2>&1 &
RALPH_PID=$!

# Wait for a couple of iterations (normal scenario is fast)
sleep 8

# Kill ralph if still running (it might be sleeping due to rate limit)
kill $RALPH_PID 2>/dev/null || true
wait $RALPH_PID 2>/dev/null || true
set -e

# Check the rate count file
if [ -f ".ralph-call-count" ]; then
  echo "  PASS: .ralph-call-count file exists"
  PASS=$(( PASS + 1 ))

  stored_hour=$(head -1 .ralph-call-count)
  stored_count=$(tail -1 .ralph-call-count)

  current_hour=$(date +"%Y%m%d%H")
  if [ "$stored_hour" = "$current_hour" ]; then
    echo "  PASS: hour matches current hour"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: hour mismatch (expected $current_hour, got $stored_hour)"
    FAIL=$(( FAIL + 1 ))
  fi

  if [ "$stored_count" -ge 1 ] 2>/dev/null; then
    echo "  PASS: count is at least 1 (got $stored_count)"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: count is not a positive number (got $stored_count)"
    FAIL=$(( FAIL + 1 ))
  fi
else
  echo "  FAIL: .ralph-call-count file does not exist"
  FAIL=$(( FAIL + 1 ))
  # Try to debug what happened
  echo "  DEBUG: files in dir:" >&2
  ls -la >&2
fi

echo ""
echo "Rate limiting tests: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
