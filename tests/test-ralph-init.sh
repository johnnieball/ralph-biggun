#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0
TMPDIR_PATHS=()

source "$SCRIPT_DIR/lib/assert.sh"
source "$REPO_ROOT/lib/utils.sh"

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
  git init -q
  echo "$tmpdir"
}

echo "Ralph Init Tests"
echo "================"

# --- Test 1: Bun/TS detection ---
echo ""
echo "Test: Detects bun-typescript from bun.lock"

tmpdir=$(setup_temp_project)
touch "$tmpdir/bun.lock"
echo '{"name":"test"}' > "$tmpdir/package.json"

set +e
output=$("$REPO_ROOT/ralph" init "$tmpdir" 2>&1)
code=$?
set -e

assert_true "init exits successfully" test "$code" -eq 0
assert_true ".ralph/ created" test -d "$tmpdir/.ralph"
assert_true ".ralph/engine/ralph.sh exists" test -f "$tmpdir/.ralph/engine/ralph.sh"
assert_true ".ralph/config.sh exists" test -f "$tmpdir/.ralph/config.sh"
assert_file_contains "config has bun-typescript" "$tmpdir/.ralph/config.sh" "bun-typescript"
assert_file_contains "config has bun run test" "$tmpdir/.ralph/config.sh" 'TEST_CMD="bun run test"'

# --- Test 2: Python detection ---
echo ""
echo "Test: Detects python from pyproject.toml"

tmpdir=$(setup_temp_project)
echo '[project]' > "$tmpdir/pyproject.toml"

set +e
output=$("$REPO_ROOT/ralph" init "$tmpdir" 2>&1)
code=$?
set -e

assert_true "init exits successfully" test "$code" -eq 0
assert_file_contains "config has python" "$tmpdir/.ralph/config.sh" "python"
assert_file_contains "config has pytest" "$tmpdir/.ralph/config.sh" 'TEST_CMD="pytest"'
assert_file_contains "CLAUDE-ralph has pytest" "$tmpdir/.ralph/CLAUDE-ralph.md" "pytest"

# --- Test 3: Generic fallback ---
echo ""
echo "Test: Falls back to generic"

tmpdir=$(setup_temp_project)

set +e
output=$("$REPO_ROOT/ralph" init "$tmpdir" 2>&1)
code=$?
set -e

assert_true "init exits successfully" test "$code" -eq 0
assert_file_contains "config has generic" "$tmpdir/.ralph/config.sh" "generic"

# --- Test 4: --stack override ---
echo ""
echo "Test: --stack override"

tmpdir=$(setup_temp_project)
touch "$tmpdir/bun.lock"

set +e
output=$("$REPO_ROOT/ralph" init --stack python "$tmpdir" 2>&1)
code=$?
set -e

assert_true "init exits successfully" test "$code" -eq 0
assert_file_contains "config has python despite bun.lock" "$tmpdir/.ralph/config.sh" "python"

# --- Test 5: CLAUDE.md directive appended ---
echo ""
echo "Test: CLAUDE.md directive appended to existing file"

tmpdir=$(setup_temp_project)
echo "# My Project" > "$tmpdir/CLAUDE.md"

set +e
output=$("$REPO_ROOT/ralph" init "$tmpdir" 2>&1)
code=$?
set -e

assert_file_contains "CLAUDE.md has original content" "$tmpdir/CLAUDE.md" "# My Project"
assert_file_contains "CLAUDE.md has Ralph directive" "$tmpdir/CLAUDE.md" "<!-- Ralph -->"

# --- Test 6: .claude/settings.json merge ---
echo ""
echo "Test: Merges into existing .claude/settings.json"

tmpdir=$(setup_temp_project)
mkdir -p "$tmpdir/.claude"
cat > "$tmpdir/.claude/settings.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write",
        "hooks": [{"type": "command", "command": "echo existing"}]
      }
    ]
  }
}
EOF

set +e
output=$("$REPO_ROOT/ralph" init "$tmpdir" 2>&1)
code=$?
set -e

assert_file_contains "settings.json has existing hook" "$tmpdir/.claude/settings.json" "existing"
assert_file_contains "settings.json has ralph hook" "$tmpdir/.claude/settings.json" ".ralph/hooks/block-dangerous-git.sh"

# --- Test 7: Refuse to init twice (suggests --upgrade) ---
echo ""
echo "Test: Refuses to init when .ralph/ exists, suggests --upgrade"

tmpdir=$(setup_temp_project)
"$REPO_ROOT/ralph" init "$tmpdir" > /dev/null 2>&1

set +e
output=$("$REPO_ROOT/ralph" init "$tmpdir" 2>&1)
code=$?
set -e

assert_true "exits with error" test "$code" -ne 0
assert_output_contains "suggests --upgrade" "$output" "--upgrade"

# --- Test 8: .gitignore entries ---
echo ""
echo "Test: Adds entries to .gitignore"

tmpdir=$(setup_temp_project)
echo "node_modules/" > "$tmpdir/.gitignore"

set +e
output=$("$REPO_ROOT/ralph" init "$tmpdir" 2>&1)
code=$?
set -e

assert_file_contains ".gitignore has .ralph/logs/" "$tmpdir/.gitignore" ".ralph/logs/"
assert_file_contains ".gitignore has .ralph-call-count" "$tmpdir/.gitignore" ".ralph-call-count"
assert_file_contains ".gitignore has codebase-snapshot.md" "$tmpdir/.gitignore" "codebase-snapshot.md"
assert_file_contains ".gitignore still has node_modules" "$tmpdir/.gitignore" "node_modules/"

# --- Test 9: Non-existent target directory ---
echo ""
echo "Test: Fails gracefully for non-existent target directory"

set +e
output=$("$REPO_ROOT/ralph" init "/tmp/ralph-nonexistent-$(date +%s)" 2>&1)
code=$?
set -e

assert_true "exits with error" test "$code" -ne 0
assert_output_contains "error message mentions target" "$output" "ERROR"

# --- Test 10: .gitignore from scratch ---
echo ""
echo "Test: Creates .gitignore when none exists"

tmpdir=$(setup_temp_project)
rm -f "$tmpdir/.gitignore"

set +e
output=$("$REPO_ROOT/ralph" init "$tmpdir" 2>&1)
code=$?
set -e

assert_true "init exits successfully" test "$code" -eq 0
assert_true ".gitignore created" test -f "$tmpdir/.gitignore"
assert_file_contains ".gitignore has .ralph/logs/" "$tmpdir/.gitignore" ".ralph/logs/"

# --- Test 11: CLAUDE.md idempotency ---
echo ""
echo "Test: CLAUDE.md directive not duplicated if already present"

tmpdir=$(setup_temp_project)
echo '<!-- Ralph --> Read .ralph/CLAUDE-ralph.md for autonomous development loop instructions.' > "$tmpdir/CLAUDE.md"

set +e
output=$("$REPO_ROOT/ralph" init "$tmpdir" 2>&1)
code=$?
set -e

# Count occurrences of the directive
directive_count=$(grep -cF '<!-- Ralph -->' "$tmpdir/CLAUDE.md")
if [ "$directive_count" -eq 1 ]; then
  echo "  PASS: CLAUDE.md directive appears exactly once"
  PASS=$(( PASS + 1 ))
else
  echo "  FAIL: CLAUDE.md directive appears $directive_count times (expected 1)"
  FAIL=$(( FAIL + 1 ))
fi

# =====================
# Upgrade Tests
# =====================

# --- Test 12: Basic upgrade updates engine files ---
echo ""
echo "Test: Upgrade updates engine files"

tmpdir=$(setup_temp_project)
"$REPO_ROOT/ralph" init "$tmpdir" > /dev/null 2>&1

# Corrupt an engine file to verify it gets replaced
echo "OLD CONTENT" > "$tmpdir/.ralph/engine/ralph.sh"

set +e
output=$("$REPO_ROOT/ralph" init --upgrade "$tmpdir" 2>&1)
code=$?
set -e

assert_true "upgrade exits successfully" test "$code" -eq 0
assert_false "engine/ralph.sh no longer has old content" grep -q "OLD CONTENT" "$tmpdir/.ralph/engine/ralph.sh"
assert_true "engine/ralph.sh has real content" test -s "$tmpdir/.ralph/engine/ralph.sh"
assert_output_contains "output mentions upgrade" "$output" "Upgrade complete"

# --- Test 13: Upgrade preserves progress.txt ---
echo ""
echo "Test: Upgrade preserves progress.txt"

tmpdir=$(setup_temp_project)
"$REPO_ROOT/ralph" init "$tmpdir" > /dev/null 2>&1
echo "MY CUSTOM PROGRESS" > "$tmpdir/.ralph/progress.txt"

set +e
output=$("$REPO_ROOT/ralph" init --upgrade "$tmpdir" 2>&1)
code=$?
set -e

assert_true "upgrade exits successfully" test "$code" -eq 0
assert_file_contains "progress.txt preserved" "$tmpdir/.ralph/progress.txt" "MY CUSTOM PROGRESS"

# --- Test 14: Upgrade preserves config.sh values ---
echo ""
echo "Test: Upgrade preserves config.sh custom values"

tmpdir=$(setup_temp_project)
"$REPO_ROOT/ralph" init "$tmpdir" > /dev/null 2>&1
echo 'MAX_ITERATIONS=99' >> "$tmpdir/.ralph/config.sh"

set +e
output=$("$REPO_ROOT/ralph" init --upgrade "$tmpdir" 2>&1)
code=$?
set -e

assert_true "upgrade exits successfully" test "$code" -eq 0
assert_file_contains "config.sh retains custom value" "$tmpdir/.ralph/config.sh" "MAX_ITERATIONS=99"

# --- Test 15: Upgrade renames prd-*.json → tasks-*.json ---
echo ""
echo "Test: Upgrade migrates prd-*.json to tasks-*.json"

tmpdir=$(setup_temp_project)
"$REPO_ROOT/ralph" init "$tmpdir" > /dev/null 2>&1
echo '{"stories":[]}' > "$tmpdir/.ralph/specs/prd-MY_PLAN.json"

set +e
output=$("$REPO_ROOT/ralph" init --upgrade "$tmpdir" 2>&1)
code=$?
set -e

assert_true "upgrade exits successfully" test "$code" -eq 0
assert_false "old prd file removed" test -f "$tmpdir/.ralph/specs/prd-MY_PLAN.json"
assert_true "new tasks file exists" test -f "$tmpdir/.ralph/specs/tasks-MY_PLAN.json"
assert_file_contains "tasks file has original content" "$tmpdir/.ralph/specs/tasks-MY_PLAN.json" '{"stories":[]}'
assert_output_contains "output mentions migration" "$output" "prd-MY_PLAN.json"

# --- Test 16: Upgrade removes legacy prd-build-prompt.md ---
echo ""
echo "Test: Upgrade removes legacy prd-build-prompt.md"

tmpdir=$(setup_temp_project)
"$REPO_ROOT/ralph" init "$tmpdir" > /dev/null 2>&1
echo "OLD PROMPT" > "$tmpdir/.ralph/engine/prd-build-prompt.md"

set +e
output=$("$REPO_ROOT/ralph" init --upgrade "$tmpdir" 2>&1)
code=$?
set -e

assert_true "upgrade exits successfully" test "$code" -eq 0
assert_false "prd-build-prompt.md removed" test -f "$tmpdir/.ralph/engine/prd-build-prompt.md"
assert_true "task-build-prompt.md exists" test -f "$tmpdir/.ralph/engine/task-build-prompt.md"

# --- Test 17: Upgrade patches config.sh prd comment ---
echo ""
echo "Test: Upgrade patches stale prd comment in config.sh"

tmpdir=$(setup_temp_project)
"$REPO_ROOT/ralph" init "$tmpdir" > /dev/null 2>&1
# Simulate old config comment
portable_sed 's|tasks-<name>\.json|prd-<name>.json|g' "$tmpdir/.ralph/config.sh"

set +e
output=$("$REPO_ROOT/ralph" init --upgrade "$tmpdir" 2>&1)
code=$?
set -e

assert_true "upgrade exits successfully" test "$code" -eq 0
assert_file_contains "config comment updated" "$tmpdir/.ralph/config.sh" "tasks-<name>.json"

# --- Test 18: Upgrade preserves user's architecture.md ---
echo ""
echo "Test: Upgrade preserves filled-in architecture.md"

tmpdir=$(setup_temp_project)
"$REPO_ROOT/ralph" init "$tmpdir" > /dev/null 2>&1
echo "# My Architecture" > "$tmpdir/.ralph/specs/architecture.md"

set +e
output=$("$REPO_ROOT/ralph" init --upgrade "$tmpdir" 2>&1)
code=$?
set -e

assert_true "upgrade exits successfully" test "$code" -eq 0
assert_file_contains "architecture.md preserved" "$tmpdir/.ralph/specs/architecture.md" "# My Architecture"

# --- Test 19: ralph upgrade shorthand works ---
echo ""
echo "Test: ralph upgrade shorthand"

tmpdir=$(setup_temp_project)
"$REPO_ROOT/ralph" init "$tmpdir" > /dev/null 2>&1

set +e
output=$("$REPO_ROOT/ralph" upgrade "$tmpdir" 2>&1)
code=$?
set -e

assert_true "upgrade shorthand exits successfully" test "$code" -eq 0
assert_output_contains "shorthand output mentions upgrade" "$output" "Upgrade complete"

# --- Test 20: Upgrade without existing .ralph/ fails ---
echo ""
echo "Test: Upgrade fails gracefully when no .ralph/ exists"

tmpdir=$(setup_temp_project)

set +e
output=$("$REPO_ROOT/ralph" init --upgrade "$tmpdir" 2>&1)
code=$?
set -e

assert_true "exits with error" test "$code" -ne 0

# --- Summary ---
print_summary "Init tests"
