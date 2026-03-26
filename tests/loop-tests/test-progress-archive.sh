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
  local ralphrc_content="$1"
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

  # Provide RALPH_PLAN and a dummy task file
  mkdir -p specs
  echo '{"userStories":[]}' > specs/tasks-test.json
  {
    echo "RALPH_PLAN=test"
    echo "$ralphrc_content"
  } > .ralphrc

  mkdir -p "$tmpdir/bin"
  cp "$SCRIPT_DIR/mock-claude.sh" "$tmpdir/bin/claude"
  chmod +x "$tmpdir/bin/claude"
  export PATH="$tmpdir/bin:$PATH"
  export RALPH_SKIP_KICKOFF=1
  # Pre-set log file to skip tee process substitution (hangs in $())
  export RALPH_LOG_FILE="$tmpdir/logs/ralph-test.log"
  mkdir -p "$tmpdir/logs"
  OUTPUT_FILE="$tmpdir/output.txt"
}

COMMON_RC="$(cat <<'EOF'
MAX_CALLS_PER_HOUR=100
MAX_ITERATIONS=1
CB_NO_PROGRESS_THRESHOLD=3
CB_SAME_ERROR_THRESHOLD=5
ALLOWED_TOOLS=""
EOF
)"

# --- Subtest 1: Template-only progress is not archived ---
echo "Subtest: Template-only progress is not archived"

setup_temp_repo "$COMMON_RC"

# Write template progress file (no real iteration entries)
cat > progress.txt << 'EOF'
# Ralph Progress Log

## Codebase Patterns
(Patterns will be added here by Ralph as it discovers reusable conventions)

## Technical Debt
(refactoring needs noted during the build - address when capacity allows)

---

Started: (date will be filled by first iteration)
---
EOF

export MOCK_SCENARIO=exit-promise
set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
set -e
output=$(cat "$OUTPUT_FILE")

# No archive should exist
archive_count=$(find logs -name 'progress-archive-*' 2>/dev/null | wc -l | tr -d ' ')
assert_exit_code "no archive created for template" "0" "$archive_count"
assert_output_not_contains "no archive message" "$output" "Archived previous progress"

# --- Subtest 2: Real entries get archived, sections preserved ---
echo ""
echo "Subtest: Real entries get archived with sections preserved"

setup_temp_repo "$COMMON_RC"

cat > progress.txt << 'EOF'
# Ralph Progress Log

## Codebase Patterns
- Use repository pattern for data access
- All API routes follow /api/v1/ prefix

## Technical Debt
- Logger module needs refactoring

---

## 2026-03-25 10:00 - US-001
- Implemented user auth
- Files changed: src/auth.ts
---
## 2026-03-25 11:00 - US-002
- Implemented profile page
- Files changed: src/profile.ts
---
EOF

export MOCK_SCENARIO=exit-promise
set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
set -e
output=$(cat "$OUTPUT_FILE")

# Archive should exist
archive_count=$(find logs -name 'progress-archive-*' 2>/dev/null | wc -l | tr -d ' ')
assert_exit_code "archive created" "1" "$archive_count"
assert_output_contains "archive message printed" "$output" "Archived previous progress"

# Fresh progress file should have preserved sections
progress_content=$(cat progress.txt)
assert_output_contains "codebase patterns heading preserved" "$progress_content" "## Codebase Patterns"
assert_output_contains "pattern content preserved" "$progress_content" "repository pattern for data access"
assert_output_contains "api prefix pattern preserved" "$progress_content" "/api/v1/ prefix"
assert_output_contains "tech debt heading preserved" "$progress_content" "## Technical Debt"
assert_output_contains "tech debt content preserved" "$progress_content" "Logger module needs refactoring"

# Old iteration entries should be gone
assert_output_not_contains "old US-001 entry removed" "$progress_content" "US-001"
assert_output_not_contains "old US-002 entry removed" "$progress_content" "US-002"
assert_output_not_contains "old files changed removed" "$progress_content" "src/auth.ts"

# Archive should contain the full original
archive_file=$(find logs -name 'progress-archive-*' | head -1)
archive_content=$(cat "$archive_file")
assert_output_contains "archive has old entries" "$archive_content" "US-001"
assert_output_contains "archive has old entries 2" "$archive_content" "US-002"

# --- Subtest 3: RALPH_SKIP_ARCHIVE suppresses archiving ---
echo ""
echo "Subtest: RALPH_SKIP_ARCHIVE suppresses archiving"

setup_temp_repo "$COMMON_RC"

cat > progress.txt << 'EOF'
# Ralph Progress Log

## Codebase Patterns
(empty)

## Technical Debt
(empty)

---

## 2026-03-25 10:00 - US-001
- Old entry that should persist when archive is suppressed
---
EOF

export MOCK_SCENARIO=exit-promise
export RALPH_SKIP_ARCHIVE=1
set +e
bash engine/ralph.sh > "$OUTPUT_FILE" 2>&1
set -e
unset RALPH_SKIP_ARCHIVE
output=$(cat "$OUTPUT_FILE")

# No archive should exist
archive_count=$(find logs -name 'progress-archive-*' 2>/dev/null | wc -l | tr -d ' ')
assert_exit_code "no archive when suppressed" "0" "$archive_count"

# Progress file should still have old entries
progress_content=$(cat progress.txt)
assert_output_contains "old entry preserved when suppressed" "$progress_content" "US-001"

print_summary "Progress archive tests"
