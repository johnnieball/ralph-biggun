#!/bin/bash
set -e

if [ -z "$1" ] || [ ! -d "$1" ]; then
  echo "Usage: $0 evals/runs/<timestamp>/"
  exit 1
fi

RUN_DIR="$1"

analyse_standard() {
  echo "=== Run Analysis ==="
  echo "Directory: $RUN_DIR"
  echo ""

  # Exit condition and exit code
  if [ -f "$RUN_DIR/exit-code.txt" ]; then
    exit_code=$(cat "$RUN_DIR/exit-code.txt")
    echo "Exit code: $exit_code"
  fi

  if [ -f "$RUN_DIR/summary.txt" ]; then
    echo ""
    cat "$RUN_DIR/summary.txt"
  fi

  echo ""

  # Iteration count
  if [ -f "$RUN_DIR/ralph-output.log" ]; then
    iteration_count=$(grep -c "ITERATION .* of" "$RUN_DIR/ralph-output.log" 2>/dev/null || echo "0")
    echo "Iteration count: $iteration_count"
  fi

  # Stories completed
  if [ -f "$RUN_DIR/prd.json" ]; then
    total=$(jq '.userStories | length' "$RUN_DIR/prd.json" 2>/dev/null || echo "?")
    passed=$(jq '[.userStories[] | select(.passes == true)] | length' "$RUN_DIR/prd.json" 2>/dev/null || echo "?")
    echo "Stories completed: $passed / $total"
  fi

  echo ""

  # RALPH commits
  if [ -f "$RUN_DIR/git-log.txt" ]; then
    ralph_commits=$(grep "RALPH" "$RUN_DIR/git-log.txt" 2>/dev/null || echo "")
    if [ -n "$ralph_commits" ]; then
      echo "RALPH commits:"
      echo "$ralph_commits" | sed 's/^/  /'
    else
      echo "RALPH commits: none"
    fi
  fi

  echo ""

  # Circuit breaker activations
  if [ -f "$RUN_DIR/ralph-output.log" ]; then
    cb=$(grep "CIRCUIT BREAKER" "$RUN_DIR/ralph-output.log" 2>/dev/null || echo "")
    if [ -n "$cb" ]; then
      echo "Circuit breaker activations:"
      echo "$cb" | sed 's/^/  /'
    else
      echo "Circuit breaker activations: none"
    fi
  fi

  # Progress file
  if [ -f "$RUN_DIR/progress.txt" ]; then
    line_count=$(wc -l < "$RUN_DIR/progress.txt" | tr -d ' ')
    echo "progress.txt: $line_count lines"

    if grep -q "## Codebase Patterns" "$RUN_DIR/progress.txt" 2>/dev/null; then
      echo "Codebase Patterns section: present"
    else
      echo "Codebase Patterns section: MISSING"
    fi
  else
    echo "progress.txt: NOT FOUND"
  fi

  echo ""

  # Flags
  echo "=== Flags ==="
  flags=0

  if [ -f "$RUN_DIR/git-log.txt" ]; then
    ralph_count=$(grep -c "RALPH" "$RUN_DIR/git-log.txt" 2>/dev/null || echo "0")
    if [ "$ralph_count" -eq 0 ]; then
      echo "WARNING: Zero RALPH commits"
      flags=$(( flags + 1 ))
    fi
  fi

  if [ -f "$RUN_DIR/ralph-output.log" ] && [ -f "$RUN_DIR/prd.json" ]; then
    iteration_count=$(grep -c "ITERATION .* of" "$RUN_DIR/ralph-output.log" 2>/dev/null || echo "0")
    story_count=$(jq '.userStories | length' "$RUN_DIR/prd.json" 2>/dev/null || echo "0")
    iteration_threshold=$(( story_count * 2 ))
    if [ "$iteration_count" -gt "$iteration_threshold" ]; then
      echo "WARNING: More than ${iteration_threshold} iterations for ${story_count} stories ($iteration_count iterations)"
      flags=$(( flags + 1 ))
    fi
  fi

  if [ -f "$RUN_DIR/exit-code.txt" ] && [ -f "$RUN_DIR/prd.json" ]; then
    exit_code=$(cat "$RUN_DIR/exit-code.txt")
    total=$(jq '.userStories | length' "$RUN_DIR/prd.json" 2>/dev/null || echo "0")
    passed=$(jq '[.userStories[] | select(.passes == true)] | length' "$RUN_DIR/prd.json" 2>/dev/null || echo "0")
    if [ "$exit_code" = "1" ] && [ "$passed" = "$total" ] && [ "$total" -gt 0 ]; then
      echo "WARNING: Exit code 1 but all stories passing"
      flags=$(( flags + 1 ))
    fi
  fi

  if [ "$flags" -eq 0 ]; then
    echo "No flags raised."
  fi
}

analyse_multi_round() {
  echo "=== Multi-Round Run Analysis ==="
  echo "Directory: $RUN_DIR"
  echo ""

  # Print summary if available
  if [ -f "$RUN_DIR/summary.txt" ]; then
    cat "$RUN_DIR/summary.txt"
    echo ""
  fi

  # Count rounds
  round_count=0
  for f in "$RUN_DIR"/round-*-ralph-output.log; do
    [ -f "$f" ] && round_count=$(( round_count + 1 ))
  done

  echo "--- Per-Round Detail ---"
  echo ""

  total_iterations=0
  prev_passed=0

  for (( r=1; r<=round_count; r++ )); do
    log_file="$RUN_DIR/round-${r}-ralph-output.log"
    prd_file="$RUN_DIR/round-${r}-prd.json"
    exit_file="$RUN_DIR/round-${r}-exit-code.txt"

    if [ ! -f "$log_file" ]; then
      continue
    fi

    # Iteration count
    round_iters=$(grep -cE '^\[[0-9]+/[0-9]+\]' "$log_file" 2>/dev/null || echo "0")
    total_iterations=$(( total_iterations + round_iters ))

    # Exit condition
    exit_code="?"
    [ -f "$exit_file" ] && exit_code=$(cat "$exit_file")

    exit_condition="Unknown"
    if grep -q "Ralph complete" "$log_file" 2>/dev/null; then
      exit_condition="Ralph complete"
    elif grep -q "CIRCUIT BREAKER.*No file changes" "$log_file" 2>/dev/null; then
      exit_condition="CB: no progress"
    elif grep -q "CIRCUIT BREAKER.*Same output" "$log_file" 2>/dev/null; then
      exit_condition="CB: same error"
    elif grep -q "Ralph reached max iterations" "$log_file" 2>/dev/null; then
      exit_condition="Max iterations"
    elif grep -q "Ralph aborted" "$log_file" 2>/dev/null; then
      exit_condition="Abort"
    elif [ "$exit_code" = "124" ]; then
      exit_condition="Timeout"
    fi

    # Stories passed at end of this round
    round_passed=0
    if [ -f "$prd_file" ]; then
      round_passed=$(jq '[.userStories[] | select(.passes == true)] | length' "$prd_file" 2>/dev/null || echo "0")
    fi
    stories_this_round=$(( round_passed - prev_passed ))

    echo "Round $r: $round_iters iterations | $exit_condition | +$stories_this_round stories ($round_passed total passed) | exit $exit_code"
    prev_passed=$round_passed
  done

  echo ""

  # Skipped stories
  final_prd="$RUN_DIR/final-prd.json"
  if [ ! -f "$final_prd" ]; then
    # Fall back to last round's prd
    final_prd="$RUN_DIR/round-${round_count}-prd.json"
  fi

  if [ -f "$final_prd" ]; then
    total_stories=$(jq '.userStories | length' "$final_prd" 2>/dev/null || echo "?")
    final_passed=$(jq '[.userStories[] | select(.passes == true)] | length' "$final_prd" 2>/dev/null || echo "?")
    final_skipped=$(jq '[.userStories[] | select(.passes == "skipped")] | length' "$final_prd" 2>/dev/null || echo "0")
    final_remaining=$(jq '[.userStories[] | select(.passes == false)] | length' "$final_prd" 2>/dev/null || echo "?")

    echo "--- Final State ---"
    echo "Passed:    $final_passed / $total_stories"
    echo "Skipped:   $final_skipped / $total_stories"
    echo "Remaining: $final_remaining / $total_stories"

    # List skipped stories with reasons
    skipped_list=$(jq -r '.userStories[] | select(.passes == "skipped") | "  \(.id) (\(.title)): \(.skipReason // "no reason")"' "$final_prd" 2>/dev/null || echo "")
    if [ -n "$skipped_list" ]; then
      echo ""
      echo "--- Skipped Stories ---"
      echo "$skipped_list"
    fi
  fi

  # Story progression across rounds
  echo ""
  echo "--- Progression ---"
  for (( r=1; r<=round_count; r++ )); do
    prd_file="$RUN_DIR/round-${r}-prd.json"
    if [ -f "$prd_file" ]; then
      rp=$(jq '[.userStories[] | select(.passes == true)] | length' "$prd_file" 2>/dev/null || echo "0")
      rs=$(jq '[.userStories[] | select(.passes == "skipped")] | length' "$prd_file" 2>/dev/null || echo "0")
      echo "  After round $r: $rp passed, $rs skipped"
    fi
  done

  echo ""

  # RALPH commits from final git log
  git_log="$RUN_DIR/final-git-log.txt"
  if [ ! -f "$git_log" ]; then
    git_log="$RUN_DIR/round-${round_count}-git-log.txt"
  fi

  if [ -f "$git_log" ]; then
    ralph_count=$(grep -c "RALPH" "$git_log" 2>/dev/null || echo "0")
    echo "Total RALPH commits: $ralph_count"
  fi

  # Progress file
  progress_file="$RUN_DIR/final-progress.txt"
  if [ ! -f "$progress_file" ]; then
    progress_file="$RUN_DIR/round-${round_count}-progress.txt"
  fi

  if [ -f "$progress_file" ]; then
    line_count=$(wc -l < "$progress_file" | tr -d ' ')
    echo "progress.txt: $line_count lines"
  fi

  echo ""

  # Flags
  echo "=== Flags ==="
  flags=0

  # Flag: same story skipped twice (shouldn't happen)
  if [ -f "$final_prd" ]; then
    skipped_ids=$(jq -r '.userStories[] | select(.passes == "skipped") | .id' "$final_prd" 2>/dev/null || echo "")
    dupes=$(echo "$skipped_ids" | sort | uniq -d)
    if [ -n "$dupes" ]; then
      echo "WARNING: Same story skipped twice: $dupes"
      flags=$(( flags + 1 ))
    fi
  fi

  # Flag: zero stories completed in a round
  prev_passed=0
  for (( r=1; r<=round_count; r++ )); do
    prd_file="$RUN_DIR/round-${r}-prd.json"
    if [ -f "$prd_file" ]; then
      rp=$(jq '[.userStories[] | select(.passes == true)] | length' "$prd_file" 2>/dev/null || echo "0")
      if [ "$rp" -eq "$prev_passed" ] && [ "$r" -gt 1 ]; then
        echo "WARNING: Zero stories completed in round $r"
        flags=$(( flags + 1 ))
      fi
      prev_passed=$rp
    fi
  done

  # Flag: more than 2x story count total iterations
  if [ -f "$final_prd" ]; then
    story_count=$(jq '.userStories | length' "$final_prd" 2>/dev/null || echo "0")
    iteration_threshold=$(( story_count * 2 ))
    if [ "$iteration_threshold" -gt 0 ] && [ "$total_iterations" -gt "$iteration_threshold" ]; then
      echo "WARNING: More than $iteration_threshold total iterations for $story_count stories ($total_iterations iterations)"
      flags=$(( flags + 1 ))
    fi
  fi

  # Flag: zero RALPH commits
  if [ -f "$git_log" ]; then
    ralph_count=$(grep -c "RALPH" "$git_log" 2>/dev/null || echo "0")
    if [ "$ralph_count" -eq 0 ]; then
      echo "WARNING: Zero RALPH commits across all rounds"
      flags=$(( flags + 1 ))
    fi
  fi

  if [ "$flags" -eq 0 ]; then
    echo "No flags raised."
  fi
}

# Detect multi-round vs standard run and dispatch
if [ -f "$RUN_DIR/round-1-ralph-output.log" ]; then
  analyse_multi_round
else
  analyse_standard
fi
