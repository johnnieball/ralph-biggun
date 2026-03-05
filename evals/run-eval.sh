#!/bin/bash
set -e

# Ensure bun is on PATH (installed to ~/.bun by default)
export PATH="$HOME/.bun/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  echo "Usage: $0 [loop|smoke|prompt|beast|all] [toy-project] [max-iterations]"
  echo ""
  echo "  prompt              Run prompt eval (defaults to calculator, 15 iterations)"
  echo "  prompt <project>    Run prompt eval against a toy project"
  echo "  prompt <project> N  Run prompt eval with N max iterations"
  echo "  beast               Run beast mode overnight eval (5 rounds, 30 iterations)"
  echo "  beast <rounds> <N>  Run beast mode with custom rounds and iterations"
  echo ""
  echo "Available toy projects: $(ls "$SCRIPT_DIR/toy-projects/" 2>/dev/null | tr '\n' ' ')"
  exit 1
}

run_beast() {
  echo ""
  echo "=== Beast Mode Eval ==="
  bash "$SCRIPT_DIR/beast-wrapper.sh" "${1:-}" "${2:-}"
}

run_loop() {
  echo "=== Loop Tests ==="
  bash "$SCRIPT_DIR/loop-tests/run-loop-tests.sh"
}

run_smoke() {
  echo ""
  echo "=== Smoke Test ==="
  bash "$SCRIPT_DIR/smoke-test.sh"
}

run_prompt() {
  local toy_project="${1:-calculator}"
  local toy_dir="$SCRIPT_DIR/toy-projects/$toy_project"

  # Validate toy project exists
  if [ ! -d "$toy_dir" ]; then
    echo "ERROR: Toy project '$toy_project' not found at $toy_dir"
    echo "Available projects: $(ls "$SCRIPT_DIR/toy-projects/" 2>/dev/null | tr '\n' ' ')"
    exit 1
  fi

  if [ ! -f "$toy_dir/prd.json" ]; then
    echo "ERROR: No prd.json found in $toy_dir"
    exit 1
  fi

  # Determine iteration limit: explicit arg > project default > 15
  local max_iterations="${2:-}"
  if [ -z "$max_iterations" ]; then
    if [ "$toy_project" = "calculator" ]; then
      max_iterations=15
    else
      max_iterations=20
    fi
  fi

  local project_name
  project_name=$(jq -r '.project' "$toy_dir/prd.json" 2>/dev/null || echo "$toy_project-eval")

  echo ""
  echo "=== Prompt Effectiveness Eval ==="
  echo "Toy project: $toy_project ($max_iterations max iterations)"

  # 1. Create timestamped run directory (includes toy project name)
  TIMESTAMP=$(date +"%Y-%m-%d-%H%M%S")
  RUN_DIR="$SCRIPT_DIR/runs/$TIMESTAMP-$toy_project"
  mkdir -p "$RUN_DIR"

  # 2. Copy repo to temp build directory
  TMPDIR_PATH=$(mktemp -d)
  trap "rm -rf $TMPDIR_PATH" EXIT
  rsync -a --exclude='.git' --exclude='evals/' --exclude='node_modules/' "$REPO_ROOT/" "$TMPDIR_PATH/"
  cd "$TMPDIR_PATH"

  # 3. Run scaffold.sh
  echo "Scaffolding $project_name..."
  bash "$SCRIPT_DIR/scaffold.sh" "$project_name"

  # 4. Copy toy project prd.json over the placeholder
  cp "$toy_dir/prd.json" plans/prd.json
  cp "$toy_dir/prd.json" "$RUN_DIR/input-prd.json"

  # 5. Run ralph.sh, capturing output
  echo "Running Ralph loop (max $max_iterations iterations)..."
  set +e
  RALPH_SKIP_KICKOFF=1 bash ./plans/ralph.sh "$max_iterations" 2>&1 | tee "$RUN_DIR/ralph-output.log"
  RALPH_EXIT=${PIPESTATUS[0]}
  set -e

  # 6. Copy artefacts to run directory
  echo "$RALPH_EXIT" > "$RUN_DIR/exit-code.txt"
  cp plans/prd.json "$RUN_DIR/prd.json" 2>/dev/null || true
  cp progress.txt "$RUN_DIR/progress.txt" 2>/dev/null || true
  git log --oneline --all > "$RUN_DIR/git-log.txt" 2>/dev/null || true

  INITIAL_SHA=$(git rev-list --max-parents=0 HEAD 2>/dev/null || echo "")
  if [ -n "$INITIAL_SHA" ]; then
    git diff --stat "$INITIAL_SHA" HEAD > "$RUN_DIR/diff-stat.txt" 2>/dev/null || true
  fi

  # 7. Build summary
  SUMMARY_FILE="$RUN_DIR/summary.txt"

  echo "Toy project: $toy_project" > "$SUMMARY_FILE"

  # Iteration count
  iteration_count=$(grep -cE '^\[[0-9]+/[0-9]+\]' "$RUN_DIR/ralph-output.log" 2>/dev/null || echo "0")
  echo "Iterations: $iteration_count (max $max_iterations)" >> "$SUMMARY_FILE"

  # Stories passed
  if [ -f "$RUN_DIR/prd.json" ]; then
    total_stories=$(jq '.userStories | length' "$RUN_DIR/prd.json" 2>/dev/null || echo "?")
    passed_stories=$(jq '[.userStories[] | select(.passes == true)] | length' "$RUN_DIR/prd.json" 2>/dev/null || echo "?")
    echo "Stories: $passed_stories/$total_stories passed" >> "$SUMMARY_FILE"
  fi

  # Exit condition
  local exit_condition
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
  else
    exit_condition="Unknown"
  fi

  echo "Exit condition: $exit_condition" >> "$SUMMARY_FILE"
  echo "Exit code: $RALPH_EXIT" >> "$SUMMARY_FILE"

  # 8. Generate scorecard from template with auto-filled values

  # Build audit points section from expected.md if it exists
  local audit_points=""
  local expected_file="$toy_dir/expected.md"
  if [ -f "$expected_file" ]; then
    # Extract the "What to look for in the scorecard" section
    local section
    section=$(sed -n '/^## What to look for in the scorecard/,/^## /{ /^## What to look for/d; /^## /d; p; }' "$expected_file" 2>/dev/null || true)
    if [ -n "$section" ]; then
      audit_points="## Project-Specific Audit Points

(From \`expected.md\` — examine these beyond standard behaviour checks)

$section"
    fi
  fi

  sed \
    -e "s|{{TIMESTAMP}}|$TIMESTAMP|g" \
    -e "s|{{TOY_PROJECT}}|$toy_project|g" \
    -e "s|{{STORY_COUNT}}|${total_stories:-?}|g" \
    -e "s|{{ITERATION_COUNT}}|$iteration_count|g" \
    -e "s|{{EXIT_CONDITION}}|$exit_condition|g" \
    -e "s|{{EXIT_CODE}}|$RALPH_EXIT|g" \
    "$SCRIPT_DIR/scorecard-template.md" > "$RUN_DIR/scorecard.md"

  # Replace the audit points placeholder (multi-line, so use a temp file approach)
  if [ -n "$audit_points" ]; then
    # Write audit points to a temp file, then use it for replacement
    local audit_tmp
    audit_tmp=$(mktemp)
    echo "$audit_points" > "$audit_tmp"
    # Use awk to replace the placeholder line with file contents
    awk -v file="$audit_tmp" '/\{\{AUDIT_POINTS\}\}/ { while ((getline line < file) > 0) print line; next } 1' "$RUN_DIR/scorecard.md" > "$RUN_DIR/scorecard.md.tmp"
    mv "$RUN_DIR/scorecard.md.tmp" "$RUN_DIR/scorecard.md"
    rm -f "$audit_tmp"
  else
    # No audit points — remove the placeholder line
    sed -i '' '/{{AUDIT_POINTS}}/d' "$RUN_DIR/scorecard.md"
  fi

  # Print summary
  echo ""
  echo "--- Run Summary ---"
  cat "$SUMMARY_FILE"
  echo ""
  echo "Full run data: $RUN_DIR"
  echo "Review: $RUN_DIR/scorecard.md"
}

case "${1:-}" in
  loop)  run_loop ;;
  smoke) run_smoke ;;
  prompt) run_prompt "${2:-}" "${3:-}" ;;
  beast) run_beast "${2:-}" "${3:-}" ;;
  all)
    run_loop
    run_smoke
    run_prompt "${2:-}" "${3:-}"
    ;;
  *) usage ;;
esac
