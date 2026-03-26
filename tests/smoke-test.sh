#!/bin/bash
set -e

# Smoke test for ralph init --blueprint
# Verifies that blueprint init produces a valid Ralph project structure.
# Does NOT run the engine (no API calls needed).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0

source "$SCRIPT_DIR/lib/assert.sh"

cleanup() {
  if [ -n "$TMPDIR_PATH" ] && [ -d "$TMPDIR_PATH" ]; then
    rm -rf "$TMPDIR_PATH"
  fi
}
trap cleanup EXIT

echo "Smoke Test (Blueprint Init)"
echo "============================"

# 1. Create project via ralph init --blueprint
TMPDIR_PATH=$(mktemp -d)
rm -rf "$TMPDIR_PATH"  # init --blueprint expects target not to exist

echo "Running ralph init --blueprint bun-typescript-webapp..."
set +e
RALPH_BLUEPRINT_NO_RUN=1 bash "$REPO_ROOT/ralph" init --blueprint bun-typescript-webapp "$TMPDIR_PATH" > /dev/null 2>&1
setup_exit=$?
set -e

if [ "$setup_exit" -ne 0 ]; then
  echo "  FAIL: ralph init --blueprint exited with code $setup_exit"
  FAIL=$(( FAIL + 1 ))
  echo ""
  echo "Smoke tests: $PASS passed, $FAIL failed"
  exit 1
fi

cd "$TMPDIR_PATH"

# 2. Assert git repo initialised with initial commit
assert_true "git repo initialised" test -d .git
commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
if [ "$commit_count" -ge 1 ]; then
  echo "  PASS: initial commit exists"
  PASS=$(( PASS + 1 ))
else
  echo "  FAIL: no initial commit"
  FAIL=$(( FAIL + 1 ))
fi

# 3. Assert Ralph directive in CLAUDE.md
assert_file_contains "CLAUDE.md has Ralph directive" "CLAUDE.md" "<!-- Ralph -->"

# 4. Assert Ralph machinery present (.ralph/ layout)
assert_true ".ralph/engine/ralph.sh exists" test -f .ralph/engine/ralph.sh
assert_true ".ralph/engine/prompt.md exists" test -f .ralph/engine/prompt.md
assert_true ".ralph/engine/snapshot.sh exists" test -f .ralph/engine/snapshot.sh
assert_true ".ralph/specs/architecture.md exists" test -f .ralph/specs/architecture.md
assert_true ".ralph/skills/tdd/SKILL.md exists" test -f .ralph/skills/tdd/SKILL.md
assert_true ".ralph/hooks/block-dangerous-git.sh exists" test -f .ralph/hooks/block-dangerous-git.sh
assert_true ".ralph/progress.txt exists" test -f .ralph/progress.txt
assert_true ".ralph/config.sh exists" test -f .ralph/config.sh
assert_true ".ralph/CLAUDE-ralph.md exists" test -f .ralph/CLAUDE-ralph.md

# 5. Assert .claude/ integration
assert_true ".claude/settings.json exists" test -f .claude/settings.json

# 6. Assert blueprint task list was copied and configured
assert_true "blueprint task list exists" test -f .ralph/specs/tasks-bun-typescript-webapp.json
assert_file_contains "config has RALPH_PLAN set" ".ralph/config.sh" "RALPH_PLAN=bun-typescript-webapp"

# 7. Assert blueprint task list has project name substituted (not placeholder)
PROJECT_NAME="$(basename "$TMPDIR_PATH")"
assert_file_contains "blueprint task list has project name" ".ralph/specs/tasks-bun-typescript-webapp.json" "$PROJECT_NAME"

# 8. Assert blueprint task list does NOT contain the placeholder
if grep -q '__PROJECT_NAME__' .ralph/specs/tasks-bun-typescript-webapp.json 2>/dev/null; then
  echo "  FAIL: blueprint task list still contains __PROJECT_NAME__ placeholder"
  FAIL=$(( FAIL + 1 ))
else
  echo "  PASS: blueprint task list has no remaining placeholders"
  PASS=$(( PASS + 1 ))
fi

print_summary "Smoke tests"
