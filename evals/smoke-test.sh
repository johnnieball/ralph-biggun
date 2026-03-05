#!/bin/bash
set -e

# Ensure bun is on PATH
export PATH="$HOME/.bun/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0

cleanup() {
  if [ -n "$TMPDIR_PATH" ] && [ -d "$TMPDIR_PATH" ]; then
    rm -rf "$TMPDIR_PATH"
  fi
}
trap cleanup EXIT

assert_true() {
  local label="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_false() {
  local label="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "  FAIL: $label (expected false but got true)"
    FAIL=$(( FAIL + 1 ))
  else
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  fi
}

assert_contains() {
  local label="$1" file="$2" needle="$3"
  if grep -q "$needle" "$file" 2>/dev/null; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label (expected '$needle' in $file)"
    FAIL=$(( FAIL + 1 ))
  fi
}

echo "Smoke Test"
echo "=========="

# 1. Copy repo to temp directory (excluding .git, evals/, node_modules)
TMPDIR_PATH=$(mktemp -d)
rsync -a --exclude='.git' --exclude='evals/' --exclude='node_modules/' "$REPO_ROOT/" "$TMPDIR_PATH/"
cd "$TMPDIR_PATH"

# 2. Run scaffold.sh
echo "Running scaffold.sh test-project..."
set +e
bash "$SCRIPT_DIR/scaffold.sh" test-project > /dev/null 2>&1
setup_exit=$?
set -e

if [ "$setup_exit" -ne 0 ]; then
  echo "  FAIL: scaffold.sh exited with code $setup_exit"
  FAIL=$(( FAIL + 1 ))
  echo ""
  echo "Smoke tests: $PASS passed, $FAIL failed"
  exit 1
fi

# 3. Assert bun install succeeded
assert_true "bun install succeeded (node_modules exists)" test -d node_modules

# 4. Assert bun run test exits cleanly
echo "Running bun run test..."
set +e
bun run test > /dev/null 2>&1
test_exit=$?
set -e
if [ "$test_exit" -eq 0 ]; then
  echo "  PASS: bun run test exits cleanly"
  PASS=$(( PASS + 1 ))
else
  echo "  FAIL: bun run test exited with code $test_exit"
  FAIL=$(( FAIL + 1 ))
fi

# 5. Assert bun run typecheck exits cleanly
echo "Running bun run typecheck..."
set +e
bun run typecheck > /dev/null 2>&1
typecheck_exit=$?
set -e
if [ "$typecheck_exit" -eq 0 ]; then
  echo "  PASS: bun run typecheck exits cleanly"
  PASS=$(( PASS + 1 ))
else
  echo "  FAIL: bun run typecheck exited with code $typecheck_exit"
  FAIL=$(( FAIL + 1 ))
fi

# 6. Assert git repo initialised with initial commit
assert_true "git repo initialised" test -d .git
commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
if [ "$commit_count" -ge 1 ]; then
  echo "  PASS: initial commit exists"
  PASS=$(( PASS + 1 ))
else
  echo "  FAIL: no initial commit"
  FAIL=$(( FAIL + 1 ))
fi

# 7. Assert placeholder replacement
assert_contains "CLAUDE.md contains test-project" "CLAUDE.md" "test-project"
assert_contains "package.json contains test-project" "package.json" "test-project"
assert_contains "architecture.md contains test-project" "specs/architecture.md" "test-project"

# 8. Assert eval/scaffold artefacts stripped
assert_false "evals/ directory does not exist" test -d evals
assert_false "create-project.sh does not exist" test -f create-project.sh
assert_false "setup.sh does not exist" test -f setup.sh

# 9. Assert Ralph machinery present
assert_true "engine/ralph.sh exists" test -f engine/ralph.sh
assert_true "engine/kickoff.sh exists" test -f engine/kickoff.sh
assert_true "engine/prompt.md exists" test -f engine/prompt.md
assert_true "engine/snapshot.sh exists" test -f engine/snapshot.sh
assert_true "specs/architecture.md exists" test -f specs/architecture.md
assert_true "skills/tdd/SKILL.md exists" test -f skills/tdd/SKILL.md
assert_true ".claude/hooks/block-dangerous-git.sh exists" test -f .claude/hooks/block-dangerous-git.sh
assert_true "progress.txt exists" test -f progress.txt
assert_true ".ralphrc exists" test -f .ralphrc
assert_true ".gitignore exists" test -f .gitignore

echo ""
echo "Smoke tests: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
