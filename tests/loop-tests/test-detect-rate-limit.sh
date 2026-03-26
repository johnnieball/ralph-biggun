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

# Copy detect_rate_limit from ralph.sh (can't source ralph.sh without executing it).
# Drift guard below fails the suite if the copy diverges from the engine.
detect_rate_limit() {
  local file="$1"
  if jq -e 'select(.type == "rate_limit_event" and .rate_limit_info.status != "allowed")' "$file" >/dev/null 2>&1; then
    return 0
  fi
  if jq -r 'select(.type == "result" and .is_error == true) | .result // empty' "$file" 2>/dev/null \
     | grep -qiE '(hit your limit|rate.?limit|429|quota.?exceeded|too many requests|overloaded|resource_exhausted|try again later)'; then
    return 0
  fi
  return 1
}

# --- Drift guard: fail fast if our copy diverges from the engine ---
_engine_func=$(sed -n '/^detect_rate_limit()/,/^}/p' "$REPO_ROOT/engine/ralph.sh" | grep -v '^\s*#')
_test_func=$(sed -n '/^detect_rate_limit()/,/^}/p' "$0" | grep -v '^\s*#')
if [ "$_engine_func" != "$_test_func" ]; then
  echo "FAIL: detect_rate_limit() has drifted from engine/ralph.sh — update the copy in this test"
  exit 1
fi
unset _engine_func _test_func

TMPDIR=$(mktemp -d)
TMPDIR_PATHS+=("$TMPDIR")

# --- Subtest 1: rate_limit_event status "limited" ---
echo "Subtest: rate_limit_event status limited"
echo '{"type":"rate_limit_event","rate_limit_info":{"status":"limited"}}' > "$TMPDIR/test1.json"
assert_true "detects rate limit event" detect_rate_limit "$TMPDIR/test1.json"

# --- Subtest 2: rate_limit_event status "allowed" ---
echo ""
echo "Subtest: rate_limit_event status allowed"
echo '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}' > "$TMPDIR/test2.json"
assert_false "allowed is not rate limited" detect_rate_limit "$TMPDIR/test2.json"

# --- Subtest 3: Error result with "429" ---
echo ""
echo "Subtest: Error result with 429"
echo '{"type":"result","is_error":true,"result":"HTTP 429 Too Many Requests"}' > "$TMPDIR/test3.json"
assert_true "detects 429 in error" detect_rate_limit "$TMPDIR/test3.json"

# --- Subtest 4: Error result with "rate limit" ---
echo ""
echo "Subtest: Error result with rate limit text"
echo '{"type":"result","is_error":true,"result":"You have hit your rate limit"}' > "$TMPDIR/test4.json"
assert_true "detects rate limit in error" detect_rate_limit "$TMPDIR/test4.json"

# --- Subtest 5: Normal result (no rate limit) ---
echo ""
echo "Subtest: Normal result no rate limit"
echo '{"type":"result","result":"All good"}' > "$TMPDIR/test5.json"
assert_false "normal result is not rate limited" detect_rate_limit "$TMPDIR/test5.json"

# --- Subtest 6: is_error false with rate limit text ---
echo ""
echo "Subtest: is_error false with rate limit text"
echo '{"type":"result","is_error":false,"result":"rate limit reached"}' > "$TMPDIR/test6.json"
assert_false "is_error:false ignores rate limit text" detect_rate_limit "$TMPDIR/test6.json"

# --- Subtest 7: Multi-object stream with rate limit event ---
echo ""
echo "Subtest: Multi-object stream with rate limit event"
printf '%s\n%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}' \
  '{"type":"rate_limit_event","rate_limit_info":{"status":"limited"}}' \
  > "$TMPDIR/test7.json"
assert_true "detects rate limit in multi-object stream" detect_rate_limit "$TMPDIR/test7.json"

# --- Subtest 8: Multi-object stream without rate limit ---
echo ""
echo "Subtest: Multi-object stream no rate limit"
printf '%s\n%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}' \
  '{"type":"result","result":"All good"}' \
  > "$TMPDIR/test8.json"
assert_false "no rate limit in multi-object stream" detect_rate_limit "$TMPDIR/test8.json"

print_summary "Rate limit detection tests"
