#!/bin/bash
set -e

# Ensure bun is on PATH
export PATH="$HOME/.bun/bin:$PATH"

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

echo "Smoke Test"
echo "=========="

# 1. Create project via create-project.sh into a temp directory
TMPDIR_PATH=$(mktemp -d)
rm -rf "$TMPDIR_PATH"  # create-project.sh expects target not to exist

echo "Running create-project.sh..."
set +e
bash "$REPO_ROOT/create-project.sh" "$TMPDIR_PATH" > /dev/null 2>&1
setup_exit=$?
set -e

if [ "$setup_exit" -ne 0 ]; then
  echo "  FAIL: create-project.sh exited with code $setup_exit"
  FAIL=$(( FAIL + 1 ))
  echo ""
  echo "Smoke tests: $PASS passed, $FAIL failed"
  exit 1
fi

cd "$TMPDIR_PATH"

# 2. Assert bun install succeeded
assert_true "bun install succeeded (node_modules exists)" test -d node_modules

# 3. Assert bun run test exits cleanly
echo "Running bun run test..."
set +e
bun run test > /dev/null 2>&1
test_exit=$?
set -e
assert_exit_code "bun run test exits cleanly" "0" "$test_exit"

# 4. Assert bun run typecheck exits cleanly
echo "Running bun run typecheck..."
set +e
bun run typecheck > /dev/null 2>&1
typecheck_exit=$?
set -e
assert_exit_code "bun run typecheck exits cleanly" "0" "$typecheck_exit"

# 5. Assert git repo initialised with initial commit
assert_true "git repo initialised" test -d .git
commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
if [ "$commit_count" -ge 1 ]; then
  echo "  PASS: initial commit exists"
  PASS=$(( PASS + 1 ))
else
  echo "  FAIL: no initial commit"
  FAIL=$(( FAIL + 1 ))
fi

# 6. Assert placeholder replacement and Ralph directive
assert_file_contains "CLAUDE.md has project name" "CLAUDE.md" "$(basename "$TMPDIR_PATH")"
assert_file_contains "CLAUDE.md has Ralph directive" "CLAUDE.md" "<!-- Ralph -->"
assert_file_contains "package.json contains project name" "package.json" "$(basename "$TMPDIR_PATH")"

# 7. Assert Ralph machinery present (.ralph/ layout)
assert_true ".ralph/engine/ralph.sh exists" test -f .ralph/engine/ralph.sh
assert_true ".ralph/engine/prompt.md exists" test -f .ralph/engine/prompt.md
assert_true ".ralph/engine/snapshot.sh exists" test -f .ralph/engine/snapshot.sh
assert_true ".ralph/specs/architecture.md exists" test -f .ralph/specs/architecture.md
assert_true ".ralph/skills/tdd/SKILL.md exists" test -f .ralph/skills/tdd/SKILL.md
assert_true ".ralph/hooks/block-dangerous-git.sh exists" test -f .ralph/hooks/block-dangerous-git.sh
assert_true ".ralph/progress.txt exists" test -f .ralph/progress.txt
assert_true ".ralph/config.sh exists" test -f .ralph/config.sh
assert_true ".ralph/CLAUDE-ralph.md exists" test -f .ralph/CLAUDE-ralph.md
assert_true ".gitignore exists" test -f .gitignore

# 8. Assert .claude/ integration
assert_true ".claude/settings.json exists" test -f .claude/settings.json

print_summary "Smoke tests"
