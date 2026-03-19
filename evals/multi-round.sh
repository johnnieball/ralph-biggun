#!/bin/bash
set -e

# Multi-round eval runner — skip-and-continue logic for overnight runs
# Called by run-eval.sh when --rounds > 1
# Usage: multi-round.sh <tasks_path> <rounds> <iterations> <RUN_DIR> <TMPDIR_PATH>

TASKS_PATH="$1"
max_rounds="$2"
iterations_per_round="$3"
RUN_DIR="$4"
TMPDIR_PATH="$5"

if [ -z "$TASKS_PATH" ] || [ -z "$max_rounds" ] || [ -z "$iterations_per_round" ] || [ -z "$RUN_DIR" ] || [ -z "$TMPDIR_PATH" ]; then
  echo "ERROR: multi-round.sh requires 5 arguments: tasks_path rounds iterations RUN_DIR TMPDIR_PATH"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Derive plan name from task list
plan_name=$(jq -r '.project' "$TASKS_PATH" 2>/dev/null || echo "eval")
plan_name=$(echo "$plan_name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
tasks_file="tasks-${plan_name}.json"

echo "=== Multi-Round Eval ==="
echo "Rounds: $max_rounds | Iterations per round: $iterations_per_round"
echo "Plan: $plan_name"
echo "Build directory: $TMPDIR_PATH"
echo "Run directory: $RUN_DIR"
echo ""

cd "$TMPDIR_PATH"

# Track overall timing and round state
overall_start=$(date +%s)
total_iterations=0

# Per-round summary arrays (bash-compatible — indexed by round number)
declare -a round_stories_completed
declare -a round_exit_conditions
declare -a round_iteration_counts
declare -a round_elapsed_times

for (( round=1; round<=max_rounds; round++ )); do
  round_start=$(date +%s)

  echo "=== ROUND $round of $max_rounds ==="
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"

  # Count remaining stories
  remaining=$(jq '[.userStories[] | select(.passes == false)] | length' ".ralph/specs/$tasks_file" 2>/dev/null || echo "0")
  if [ "$remaining" -eq 0 ]; then
    echo "All stories complete!"
    break
  fi
  echo "Stories remaining: $remaining"
  echo ""

  # Snapshot RALPH commits before this round
  ralph_commits_before=$(git log --grep="RALPH" --oneline 2>/dev/null | wc -l | tr -d ' ')

  # Run ralph.sh, capturing output
  set +e
  RALPH_SKIP_KICKOFF=1 bash .ralph/engine/ralph.sh "$iterations_per_round" "$plan_name" 2>&1 | tee "$RUN_DIR/round-${round}-ralph-output.log"
  RALPH_EXIT=${PIPESTATUS[0]}
  # Guard against empty/non-numeric PIPESTATUS
  if ! [[ "$RALPH_EXIT" =~ ^[0-9]+$ ]]; then
    RALPH_EXIT=1
  fi
  set -e

  round_end=$(date +%s)
  round_elapsed=$(( round_end - round_start ))

  # Count iterations this round
  round_iters=$(grep -cE '^\[[0-9]+/[0-9]+\]' "$RUN_DIR/round-${round}-ralph-output.log" 2>/dev/null || echo "0")
  total_iterations=$(( total_iterations + round_iters ))

  # Count RALPH commits this round
  ralph_commits_after=$(git log --grep="RALPH" --oneline 2>/dev/null | wc -l | tr -d ' ')
  new_ralph_commits=$(( ralph_commits_after - ralph_commits_before ))

  # Count stories completed this round
  passed_now=$(jq '[.userStories[] | select(.passes == true)] | length' ".ralph/specs/$tasks_file" 2>/dev/null || echo "0")

  # Write exit code
  echo "$RALPH_EXIT" > "$RUN_DIR/round-${round}-exit-code.txt"

  # Copy artefacts
  cp ".ralph/specs/$tasks_file" "$RUN_DIR/round-${round}-tasks.json" 2>/dev/null || true
  cp .ralph/progress.txt "$RUN_DIR/round-${round}-progress.txt" 2>/dev/null || true
  git log --oneline -20 > "$RUN_DIR/round-${round}-git-log.txt" 2>/dev/null || true

  # Determine exit condition label
  exit_condition="Unknown"
  if grep -q "Ralph complete" "$RUN_DIR/round-${round}-ralph-output.log" 2>/dev/null; then
    exit_condition="Ralph complete (promise)"
  elif grep -q "Ralph received EXIT_SIGNAL" "$RUN_DIR/round-${round}-ralph-output.log" 2>/dev/null; then
    exit_condition="EXIT_SIGNAL"
  elif grep -q "CIRCUIT BREAKER.*No file changes" "$RUN_DIR/round-${round}-ralph-output.log" 2>/dev/null; then
    exit_condition="Circuit breaker: no progress"
  elif grep -q "CIRCUIT BREAKER.*Same output" "$RUN_DIR/round-${round}-ralph-output.log" 2>/dev/null; then
    exit_condition="Circuit breaker: same error"
  elif grep -q "Ralph reached max iterations" "$RUN_DIR/round-${round}-ralph-output.log" 2>/dev/null; then
    exit_condition="Max iterations"
  elif grep -q "Ralph aborted" "$RUN_DIR/round-${round}-ralph-output.log" 2>/dev/null; then
    exit_condition="Abort"
  fi

  # Store round summary data
  round_stories_completed[$round]="$passed_now"
  round_exit_conditions[$round]="$exit_condition"
  round_iteration_counts[$round]="$round_iters"
  round_elapsed_times[$round]="$round_elapsed"

  echo ""
  echo "--- Round $round complete ---"
  echo "Exit condition: $exit_condition | Iterations: $round_iters | New commits: $new_ralph_commits | Stories passed: $passed_now | Time: ${round_elapsed}s"
  echo ""

  # Exit code 0 — clean completion, loop back to check if all stories done
  if [ "$RALPH_EXIT" -eq 0 ]; then
    continue
  fi

  # Exit code 1 — circuit breaker, max iterations, or abort
  # Check for API-level failure
  if [ "$new_ralph_commits" -eq 0 ] && [ "$round_iters" -lt 5 ]; then
    # API rate limit or failure — save state and pause

    # Generate partial summary
    generate_summary() {
      local summary_file="$RUN_DIR/summary.txt"
      local overall_end
      overall_end=$(date +%s)
      local overall_elapsed=$(( overall_end - overall_start ))

      echo "=== Multi-Round Eval Summary (PARTIAL — paused due to API failure) ===" > "$summary_file"
      echo "" >> "$summary_file"
      echo "Rounds completed: $round of $max_rounds" >> "$summary_file"
      echo "Total iterations: $total_iterations" >> "$summary_file"
      echo "Total elapsed time: ${overall_elapsed}s" >> "$summary_file"
      echo "" >> "$summary_file"

      for (( r=1; r<=round; r++ )); do
        echo "Round $r: ${round_iteration_counts[$r]:-0} iterations | ${round_exit_conditions[$r]:-?} | ${round_stories_completed[$r]:-?} stories passed | ${round_elapsed_times[$r]:-0}s" >> "$summary_file"
      done

      echo "" >> "$summary_file"
      local total_stories
      total_stories=$(jq '.userStories | length' ".ralph/specs/$tasks_file" 2>/dev/null || echo "?")
      local final_passed
      final_passed=$(jq '[.userStories[] | select(.passes == true)] | length' ".ralph/specs/$tasks_file" 2>/dev/null || echo "?")
      local final_skipped
      final_skipped=$(jq '[.userStories[] | select(.passes == "skipped")] | length' ".ralph/specs/$tasks_file" 2>/dev/null || echo "0")
      local final_remaining
      final_remaining=$(jq '[.userStories[] | select(.passes == false)] | length' ".ralph/specs/$tasks_file" 2>/dev/null || echo "?")

      echo "Final tally: $final_passed passed / $final_skipped skipped / $final_remaining remaining (of $total_stories)" >> "$summary_file"

      # List skipped stories
      local skipped_list
      skipped_list=$(jq -r '.userStories[] | select(.passes == "skipped") | "  \(.id): \(.skipReason // "no reason")"' ".ralph/specs/$tasks_file" 2>/dev/null || echo "")
      if [ -n "$skipped_list" ]; then
        echo "" >> "$summary_file"
        echo "Skipped stories:" >> "$summary_file"
        echo "$skipped_list" >> "$summary_file"
      fi
    }

    generate_summary

    echo "$TMPDIR_PATH" > "$RUN_DIR/paused-build-dir.txt"

    echo ""
    echo "=== PAUSED: API rate limit or failure detected ==="
    echo "Run data saved to: $RUN_DIR"
    echo "Temp build dir: $TMPDIR_PATH"
    echo ""
    echo "To resume manually:"
    echo "  cd $TMPDIR_PATH && .ralph/engine/ralph.sh $iterations_per_round $plan_name"
    echo "  (then copy results to $RUN_DIR when done)"

    # Don't clean up temp dir — user needs it to resume
    trap - EXIT
    exit 0
  fi

  # Not an API failure — proceed with skip logic

  # Identify the stuck story
  stuck_story_id=""
  log_file="$RUN_DIR/round-${round}-ralph-output.log"

  # Parse last RALPH_STATUS block's RECOMMENDATION for a US-0XX pattern
  last_recommendation=$(grep -E "RECOMMENDATION:" "$log_file" 2>/dev/null | tail -1 || echo "")
  if [ -n "$last_recommendation" ]; then
    stuck_story_id=$(echo "$last_recommendation" | grep -oE 'US-[0-9]+' | head -1 || echo "")
  fi

  # Grep last 200 lines for most frequently mentioned US-0XX
  if [ -z "$stuck_story_id" ]; then
    stuck_story_id=$(tail -200 "$log_file" 2>/dev/null | grep -oE 'US-[0-9]+' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}' || echo "")
  fi

  # Fall back to first story with passes: false
  if [ -z "$stuck_story_id" ]; then
    stuck_story_id=$(jq -r '.userStories[] | select(.passes == false) | .id' ".ralph/specs/$tasks_file" 2>/dev/null | head -1 || echo "")
  fi

  # Build skip reason
  skip_reason="$exit_condition"

  # Skip the stuck story if identified and still has passes: false
  if [ -n "$stuck_story_id" ]; then
    # Check this story actually has passes: false (not already skipped or passed)
    story_status=$(jq -r --arg id "$stuck_story_id" '.userStories[] | select(.id == $id) | .passes' ".ralph/specs/$tasks_file" 2>/dev/null || echo "")

    if [ "$story_status" = "false" ]; then
      echo "Skipping stuck story: $stuck_story_id ($skip_reason)"

      # Update tasks.json
      jq --arg id "$stuck_story_id" --arg reason "$skip_reason" \
        '(.userStories[] | select(.id == $id)) |= (.passes = "skipped" | .skipReason = $reason)' \
        ".ralph/specs/$tasks_file" > ".ralph/specs/${tasks_file}.tmp" && mv ".ralph/specs/${tasks_file}.tmp" ".ralph/specs/$tasks_file"

      # Append skip notice to progress.txt
      cat >> .ralph/progress.txt <<SKIP_EOF

## SKIPPED: $stuck_story_id - $skip_reason
Do not re-attempt. Dependencies may be missing. Move to next available story.
---
SKIP_EOF

    else
      # Story already passed or skipped — check if there are any remaining false stories
      remaining_false=$(jq '[.userStories[] | select(.passes == false)] | length' ".ralph/specs/$tasks_file" 2>/dev/null || echo "0")
      if [ "$remaining_false" -eq 0 ]; then
        echo "WARNING: No more stories with passes: false. All remaining stories already passed or skipped."
        break
      fi

      # Try the next false story instead
      next_false=$(jq -r '.userStories[] | select(.passes == false) | .id' ".ralph/specs/$tasks_file" 2>/dev/null | head -1 || echo "")
      if [ -n "$next_false" ]; then
        echo "Story $stuck_story_id already handled. Skipping next stuck candidate: $next_false ($skip_reason)"
        jq --arg id "$next_false" --arg reason "$skip_reason" \
          '(.userStories[] | select(.id == $id)) |= (.passes = "skipped" | .skipReason = $reason)' \
          ".ralph/specs/$tasks_file" > ".ralph/specs/${tasks_file}.tmp" && mv ".ralph/specs/${tasks_file}.tmp" ".ralph/specs/$tasks_file"

        cat >> .ralph/progress.txt <<SKIP_EOF

## SKIPPED: $next_false - $skip_reason
Do not re-attempt. Dependencies may be missing. Move to next available story.
---
SKIP_EOF
      else
        echo "WARNING: Could not identify a story to skip. Breaking loop."
        break
      fi
    fi
  else
    # No stuck story identified
    echo "WARNING: Could not identify stuck story. Breaking loop."
    break
  fi
done

# Generate final summary
overall_end=$(date +%s)
overall_elapsed=$(( overall_end - overall_start ))

total_stories=$(jq '.userStories | length' ".ralph/specs/$tasks_file" 2>/dev/null || echo "?")
final_passed=$(jq '[.userStories[] | select(.passes == true)] | length' ".ralph/specs/$tasks_file" 2>/dev/null || echo "?")
final_skipped=$(jq '[.userStories[] | select(.passes == "skipped")] | length' ".ralph/specs/$tasks_file" 2>/dev/null || echo "0")
final_remaining=$(jq '[.userStories[] | select(.passes == false)] | length' ".ralph/specs/$tasks_file" 2>/dev/null || echo "?")

SUMMARY_FILE="$RUN_DIR/summary.txt"

{
  echo "=== Multi-Round Eval Summary ==="
  echo ""
  # Count rounds that actually ran (have iteration data)
  rounds_ran=0
  for (( r=1; r<=max_rounds; r++ )); do
    if [ -n "${round_iteration_counts[$r]:-}" ]; then
      rounds_ran=$r
    fi
  done
  echo "Total rounds: $rounds_ran of $max_rounds"
  echo "Total iterations: $total_iterations"
  echo "Total elapsed time: ${overall_elapsed}s ($(( overall_elapsed / 60 ))m$(( overall_elapsed % 60 ))s)"
  echo ""
  echo "--- Per-Round Breakdown ---"

  for (( r=1; r<=max_rounds; r++ )); do
    if [ -z "${round_iteration_counts[$r]:-}" ]; then
      break
    fi
    echo "Round $r: ${round_iteration_counts[$r]} iterations | ${round_exit_conditions[$r]} | ${round_stories_completed[$r]} stories passed total | ${round_elapsed_times[$r]}s"
  done

  echo ""
  echo "--- Final Tally ---"
  echo "Passed:    $final_passed / $total_stories"
  echo "Skipped:   $final_skipped / $total_stories"
  echo "Remaining: $final_remaining / $total_stories"

  # List skipped stories with reasons
  skipped_list=$(jq -r '.userStories[] | select(.passes == "skipped") | "  \(.id) (\(.title)): \(.skipReason // "no reason")"' ".ralph/specs/$tasks_file" 2>/dev/null || echo "")
  if [ -n "$skipped_list" ]; then
    echo ""
    echo "--- Skipped Stories ---"
    echo "$skipped_list"
  fi

  echo ""
  echo "--- Iterations ---"
  echo "Total: $total_iterations across all rounds"
  if [[ "$total_stories" =~ ^[0-9]+$ ]]; then
    echo "Target: ${total_stories}-$(( total_stories * 2 )) for $total_stories stories"
  fi
} > "$SUMMARY_FILE"

# Copy final artefacts
cp ".ralph/specs/$tasks_file" "$RUN_DIR/final-tasks.json" 2>/dev/null || true
cp .ralph/progress.txt "$RUN_DIR/final-progress.txt" 2>/dev/null || true
git log --oneline --all > "$RUN_DIR/final-git-log.txt" 2>/dev/null || true

# Copy scorecard template
if [ -f "$SCRIPT_DIR/scorecard-template.md" ]; then
  cp "$SCRIPT_DIR/scorecard-template.md" "$RUN_DIR/scorecard.md"
fi

# Print summary
echo ""
echo "==========================================="
cat "$SUMMARY_FILE"
echo ""
echo "==========================================="
echo "Full run data: $RUN_DIR"
echo "Scorecard: $RUN_DIR/scorecard.md"
