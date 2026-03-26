#!/bin/bash
set -e

# Eval runner — point at any task list JSON, run the eval
# Usage: ./evals/run-eval.sh <tasks.json> [--rounds N] [--iterations M]
#
# Examples:
#   ./evals/run-eval.sh evals/specs/calculator/tasks.json
#   ./evals/run-eval.sh evals/specs/beast/tasks.json --rounds 5
#   ./evals/run-eval.sh ~/my-project/tasks.json --iterations 25 --rounds 3

# Ensure bun is on PATH (installed to ~/.bun by default)
export PATH="$HOME/.bun/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/lib/utils.sh"

# --- Argument parsing ---

TASKS_PATH=""
rounds=1
iterations=20

while [ $# -gt 0 ]; do
  case "$1" in
    --rounds)
      rounds="${2:?ERROR: --rounds requires a number}"
      shift 2
      ;;
    --iterations)
      iterations="${2:?ERROR: --iterations requires a number}"
      shift 2
      ;;
    -*)
      echo "ERROR: Unknown flag '$1'"
      echo "Usage: $0 <tasks.json> [--rounds N] [--iterations M]"
      exit 1
      ;;
    *)
      if [ -z "$TASKS_PATH" ]; then
        TASKS_PATH="$1"
      else
        echo "ERROR: Unexpected argument '$1'"
        echo "Usage: $0 <tasks.json> [--rounds N] [--iterations M]"
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$TASKS_PATH" ]; then
  echo "Usage: $0 <tasks.json> [--rounds N] [--iterations M]"
  echo ""
  echo "  <tasks.json>       Path to task list file (required)"
  echo "  --rounds N       Number of rounds (default: 1)"
  echo "  --iterations M   Max iterations per round (default: 20)"
  echo ""
  echo "Examples:"
  echo "  $0 evals/specs/calculator/tasks.json"
  echo "  $0 evals/specs/beast/tasks.json --rounds 5 --iterations 30"
  exit 1
fi

# Resolve to absolute path
tasks_dir_resolved="$(cd "$(dirname "$TASKS_PATH")" 2>/dev/null && pwd || true)"
if [ -z "$tasks_dir_resolved" ] || [ ! -f "$tasks_dir_resolved/$(basename "$TASKS_PATH")" ]; then
  echo "ERROR: Task file not found: $TASKS_PATH"
  exit 1
fi
TASKS_PATH="$tasks_dir_resolved/$(basename "$TASKS_PATH")"

# --- Derive names from task list ---

project_name=$(jq -r '.project' "$TASKS_PATH" 2>/dev/null || echo "eval")
plan_name=$(echo "$project_name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
tasks_dir="$(dirname "$TASKS_PATH")"

echo ""
echo "=== Ralph Eval ==="
echo "Tasks: $TASKS_PATH"
echo "Project: $project_name (plan: $plan_name)"
echo "Iterations: $iterations | Rounds: $rounds"

# --- Multi-round: delegate to multi-round.sh ---

if [ "$rounds" -gt 1 ]; then
  # Nested Claude Code detection — multi-round cannot run inside Claude Code
  if [ -n "$CLAUDECODE" ]; then
    echo "ERROR: Multi-round evals cannot run inside Claude Code — nested sessions not supported. Run from a plain terminal."
    exit 1
  fi

  # Create timestamped run directory
  TIMESTAMP=$(date +"%Y-%m-%d-%H%M%S")
  RUN_DIR="$SCRIPT_DIR/runs/$TIMESTAMP-$plan_name"
  mkdir -p "$RUN_DIR"

  # Scaffold project
  TMPDIR_PATH=$(mktemp -d)
  rm -rf "$TMPDIR_PATH"
  trap "rm -rf $TMPDIR_PATH" EXIT

  echo "Scaffolding $project_name..."
  bash "$REPO_ROOT/ralph" init --blueprint bun-typescript-webapp "$TMPDIR_PATH"
  cd "$TMPDIR_PATH"
  # Override with eval task list
  cp "$TASKS_PATH" "$TMPDIR_PATH/.ralph/specs/tasks-${plan_name}.json"
  portable_sed "s/^RALPH_PLAN=.*/RALPH_PLAN=$plan_name/" "$TMPDIR_PATH/.ralph/config.sh"
  cp "$TASKS_PATH" "$RUN_DIR/input-tasks.json"

  # Delegate to multi-round runner
  bash "$SCRIPT_DIR/multi-round.sh" "$TASKS_PATH" "$rounds" "$iterations" "$RUN_DIR" "$TMPDIR_PATH"
  multi_round_exit=$?

  # If multi-round paused for API failure, don't clean up the build dir
  if [ -f "$RUN_DIR/paused-build-dir.txt" ]; then
    trap - EXIT
  fi
  exit $multi_round_exit
fi

# --- Single round ---

# Create timestamped run directory
TIMESTAMP=$(date +"%Y-%m-%d-%H%M%S")
RUN_DIR="$SCRIPT_DIR/runs/$TIMESTAMP-$plan_name"
mkdir -p "$RUN_DIR"

# Scaffold project
TMPDIR_PATH=$(mktemp -d)
rm -rf "$TMPDIR_PATH"
trap "rm -rf $TMPDIR_PATH" EXIT

echo "Scaffolding $project_name..."
bash "$REPO_ROOT/ralph" init --blueprint bun-typescript-webapp "$TMPDIR_PATH"
cd "$TMPDIR_PATH"
# Override with eval task list
cp "$TASKS_PATH" "$TMPDIR_PATH/.ralph/specs/tasks-${plan_name}.json"
portable_sed "s/^RALPH_PLAN=.*/RALPH_PLAN=$plan_name/" "$TMPDIR_PATH/.ralph/config.sh"
cp "$TASKS_PATH" "$RUN_DIR/input-tasks.json"

# Run ralph.sh, capturing output
echo "Running Ralph loop (max $iterations iterations)..."
set +e
RALPH_SKIP_KICKOFF=1 bash .ralph/engine/ralph.sh "$iterations" "$plan_name" 2>&1 | tee "$RUN_DIR/ralph-output.log"
RALPH_EXIT=${PIPESTATUS[0]}
set -e

# Copy artefacts to run directory
echo "$RALPH_EXIT" > "$RUN_DIR/exit-code.txt"
cp ".ralph/specs/tasks-${plan_name}.json" "$RUN_DIR/tasks.json" 2>/dev/null || true
cp .ralph/progress.txt "$RUN_DIR/progress.txt" 2>/dev/null || true
git log --oneline --all > "$RUN_DIR/git-log.txt" 2>/dev/null || true

INITIAL_SHA=$(git rev-list --max-parents=0 HEAD 2>/dev/null || echo "")
if [ -n "$INITIAL_SHA" ]; then
  git diff --stat "$INITIAL_SHA" HEAD > "$RUN_DIR/diff-stat.txt" 2>/dev/null || true
fi

# Build summary
SUMMARY_FILE="$RUN_DIR/summary.txt"

echo "Project: $plan_name" > "$SUMMARY_FILE"

# Iteration count
iteration_count=$(grep -cE '^\[[0-9]+/[0-9]+\]' "$RUN_DIR/ralph-output.log" 2>/dev/null || echo "0")
echo "Iterations: $iteration_count (max $iterations)" >> "$SUMMARY_FILE"

# Stories passed
total_stories="?"
passed_stories="?"
if [ -f "$RUN_DIR/tasks.json" ]; then
  total_stories=$(jq '.userStories | length' "$RUN_DIR/tasks.json" 2>/dev/null || echo "?")
  passed_stories=$(jq '[.userStories[] | select(.passes == true)] | length' "$RUN_DIR/tasks.json" 2>/dev/null || echo "?")
  echo "Stories: $passed_stories/$total_stories passed" >> "$SUMMARY_FILE"
fi

# Exit condition
exit_condition="Unknown"
if grep -q "Ralph complete" "$RUN_DIR/ralph-output.log" 2>/dev/null; then
  exit_condition="Ralph complete (promise)"
elif grep -q "Ralph received EXIT_SIGNAL" "$RUN_DIR/ralph-output.log" 2>/dev/null; then
  exit_condition="EXIT_SIGNAL"
elif grep -q "CIRCUIT BREAKER" "$RUN_DIR/ralph-output.log" 2>/dev/null; then
  exit_condition="Circuit breaker"
elif grep -q "Ralph reached max iterations" "$RUN_DIR/ralph-output.log" 2>/dev/null; then
  exit_condition="Max iterations"
elif grep -q "Ralph aborted" "$RUN_DIR/ralph-output.log" 2>/dev/null; then
  exit_condition="Abort"
fi

echo "Exit condition: $exit_condition" >> "$SUMMARY_FILE"
echo "Exit code: $RALPH_EXIT" >> "$SUMMARY_FILE"

# Generate scorecard from template with auto-filled values

# Build audit points section from expected.md if it exists alongside the task list
audit_points=""
expected_file="$tasks_dir/expected.md"
if [ -f "$expected_file" ]; then
  # Extract the "What to look for in the scorecard" section
  section=$(sed -n '/^## What to look for in the scorecard/,/^## /{ /^## What to look for/d; /^## /d; p; }' "$expected_file" 2>/dev/null || true)
  if [ -n "$section" ]; then
    audit_points="## Project-Specific Audit Points

(From \`expected.md\` — examine these beyond standard behaviour checks)

$section"
  fi
fi

sed \
  -e "s|{{TIMESTAMP}}|$TIMESTAMP|g" \
  -e "s|{{PROJECT}}|$plan_name|g" \
  -e "s|{{STORY_COUNT}}|${total_stories:-?}|g" \
  -e "s|{{ITERATION_COUNT}}|$iteration_count|g" \
  -e "s|{{EXIT_CONDITION}}|$exit_condition|g" \
  -e "s|{{EXIT_CODE}}|$RALPH_EXIT|g" \
  "$SCRIPT_DIR/scorecard-template.md" > "$RUN_DIR/scorecard.md"

# Replace the audit points placeholder (multi-line, so use a temp file approach)
if [ -n "$audit_points" ]; then
  audit_tmp=$(mktemp)
  echo "$audit_points" > "$audit_tmp"
  awk -v file="$audit_tmp" '/\{\{AUDIT_POINTS\}\}/ { while ((getline line < file) > 0) print line; next } 1' "$RUN_DIR/scorecard.md" > "$RUN_DIR/scorecard.md.tmp"
  mv "$RUN_DIR/scorecard.md.tmp" "$RUN_DIR/scorecard.md"
  rm -f "$audit_tmp"
else
  # No audit points — remove the placeholder line
  portable_sed '/{{AUDIT_POINTS}}/d' "$RUN_DIR/scorecard.md"
fi

# Print summary
echo ""
echo "--- Run Summary ---"
cat "$SUMMARY_FILE"
echo ""
echo "Full run data: $RUN_DIR"
echo "Review: $RUN_DIR/scorecard.md"
