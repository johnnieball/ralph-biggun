#!/bin/bash
set -e

# Architecture note: FRESH CONTEXT PER ITERATION
# ================================================
# Each iteration spawns a fresh Claude process via --print mode.
# State lives in files (prd.json, progress.txt) and git, NOT in
# conversation history. This prevents "context rot" — the degradation
# in output quality as context windows fill up.
#
# DO NOT switch to --continue mode or the stop-hook plugin.
# Accumulated context causes compaction events where the model loses
# track of critical specifications. Fresh context = peak intelligence
# on every iteration.
# ================================================

# Source configuration
RALPH_CONFIG="${RALPH_CONFIG:-.ralphrc}"
if [ ! -f "$RALPH_CONFIG" ] && [ -f ".ralph/config.sh" ]; then
  RALPH_CONFIG=".ralph/config.sh"
fi
if [ -f "$RALPH_CONFIG" ]; then
  source "$RALPH_CONFIG"
fi

# Defaults (overridden by config)
MAX_CALLS_PER_HOUR=${MAX_CALLS_PER_HOUR:-60}
MAX_ITERATIONS=${MAX_ITERATIONS:-20}
CB_NO_PROGRESS_THRESHOLD=${CB_NO_PROGRESS_THRESHOLD:-3}
CB_SAME_ERROR_THRESHOLD=${CB_SAME_ERROR_THRESHOLD:-5}
RALPH_MAX_RETRIES=${RALPH_MAX_RETRIES:-3}
RALPH_RETRY_BACKOFF=${RALPH_RETRY_BACKOFF:-30}
RATE_LIMIT_WAIT=${RATE_LIMIT_WAIT:-120}
RATE_LIMIT_MAX_RETRIES=${RATE_LIMIT_MAX_RETRIES:-5}

# Directory and command config (overridden by config)
ENGINE_DIR="${ENGINE_DIR:-engine}"
SPECS_DIR="${SPECS_DIR:-specs}"
SKILLS_DIR="${SKILLS_DIR:-skills}"
PROGRESS_FILE="${PROGRESS_FILE:-progress.txt}"
LOG_DIR="${LOG_DIR:-logs}"
TEST_CMD="${TEST_CMD:-bun run test}"
TYPECHECK_CMD="${TYPECHECK_CMD:-bun run typecheck}"
LINT_CMD="${LINT_CMD:-bun run lint}"
EXTRA_PATH="${EXTRA_PATH:-$HOME/.bun/bin}"
SNAPSHOT_SOURCE_DIR="${SNAPSHOT_SOURCE_DIR:-src}"
SNAPSHOT_FILE_EXTENSIONS="${SNAPSHOT_FILE_EXTENSIONS:-ts,tsx,js,jsx}"
SNAPSHOT_TEST_PATTERNS="${SNAPSHOT_TEST_PATTERNS:-*.test.*,*.spec.*}"
SNAPSHOT_PARSER="${SNAPSHOT_PARSER:-typescript}"
TEST_COUNT_REGEX="${TEST_COUNT_REGEX:-Tests[[:space:]]+[0-9]+ passed}"

# Add tool runtime to PATH (skip if EXTRA_PATH is empty)
if [ -n "$EXTRA_PATH" ]; then
  export PATH="$EXTRA_PATH:$PATH"
fi

# Export snapshot config for snapshot.sh subprocess
export SNAPSHOT_SOURCE_DIR SNAPSHOT_FILE_EXTENSIONS SNAPSHOT_TEST_PATTERNS SNAPSHOT_PARSER

# Arguments: [iterations] [plan-name]
if [ -n "$1" ]; then
  if [[ "$1" =~ ^[0-9]+$ ]]; then
    MAX_ITERATIONS="$1"
  else
    echo "Usage: $0 [iterations] [plan-name]"
    exit 1
  fi
fi
if [ -n "$2" ]; then
  RALPH_PLAN="$2"
fi

# Resolve PRD path: CLI arg > RALPH_PLAN config
if [ -z "$RALPH_PLAN" ]; then
  echo "ERROR: No plan selected. Set RALPH_PLAN in $RALPH_CONFIG or pass as second arg."
  echo "  Usage: $0 [iterations] <plan-name>"
  echo "Available plans:"
  for f in $SPECS_DIR/prd-*.json; do
    [ -f "$f" ] && echo "  - $(basename "$f" | sed 's/^prd-//;s/\.json$//')"
  done
  exit 1
fi

PRD_PATH="$SPECS_DIR/prd-${RALPH_PLAN}.json"

if [ ! -f "$PRD_PATH" ]; then
  echo "ERROR: PRD not found at $PRD_PATH"
  echo "Available plans:"
  for f in $SPECS_DIR/prd-*.json; do
    [ -f "$f" ] && echo "  - $(basename "$f" | sed 's/^prd-//;s/\.json$//')"
  done
  exit 1
fi

echo "Using PRD: $PRD_PATH"

# Automatic log file — mirror all output to timestamped log
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/ralph-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# jq filters for stream-json output
stream_text='select(.type == "assistant").message.content[]? | select(.type == "text").text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"'
final_result='select(.type == "result").result // empty'

# Circuit breaker state
no_progress_count=0
same_error_count=0
last_error_line=""
last_ralph_sha=""

# Run tracking
completed_iterations=0
cb_activation_count=0
rate_limit_total=0
exit_reason="max_iterations"
last_test_count="?"
declare -a story_ids story_elapsed story_names story_acs

# Rate limiting
CALL_COUNT_FILE=".ralph-call-count"

check_rate_limit() {
  local current_hour
  current_hour=$(date +"%Y%m%d%H")

  if [ -f "$CALL_COUNT_FILE" ]; then
    local stored_hour stored_count
    stored_hour=$(head -1 "$CALL_COUNT_FILE")
    stored_count=$(tail -1 "$CALL_COUNT_FILE")

    if [ "$stored_hour" = "$current_hour" ]; then
      if [ "$stored_count" -ge "$MAX_CALLS_PER_HOUR" ]; then
        local mins_left
        mins_left=$(( 60 - $(date +%-M) ))
        echo "Rate limit reached ($MAX_CALLS_PER_HOUR/hr). Sleeping ${mins_left}m until next hour..."
        sleep $(( mins_left * 60 ))
        echo "$current_hour" > "$CALL_COUNT_FILE"
        echo "1" >> "$CALL_COUNT_FILE"
        return
      fi
      echo "$current_hour" > "$CALL_COUNT_FILE"
      echo "$(( stored_count + 1 ))" >> "$CALL_COUNT_FILE"
      return
    fi
  fi

  echo "$current_hour" > "$CALL_COUNT_FILE"
  echo "1" >> "$CALL_COUNT_FILE"
}

fmt_time() {
  local secs=$1
  if [ "$secs" -ge 60 ]; then
    printf "%dm%02ds" $(( secs / 60 )) $(( secs % 60 ))
  else
    printf "%ds" "$secs"
  fi
}

detect_rate_limit() {
  local file="$1"
  grep -qiE '(hit your limit|rate.?limit|429|quota.?exceeded|too many requests|overloaded|resource_exhausted|try again later)' "$file" 2>/dev/null
}

print_run_summary() {
  # Guard: only print if the loop actually started
  if [ -z "${loop_start:-}" ]; then
    return
  fi

  local now end_elapsed
  now=$(date +%s)
  end_elapsed=$(( now - loop_start ))

  # Final story counts from PRD
  local final_done="?" final_total="?" final_remaining="?"
  if [ -f "$PRD_PATH" ]; then
    final_total=$(jq '.userStories | length' "$PRD_PATH" 2>/dev/null || echo "?")
    final_done=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_PATH" 2>/dev/null || echo "?")
    if [ "$final_total" != "?" ] && [ "$final_done" != "?" ]; then
      final_remaining=$(( final_total - final_done ))
    fi
  fi

  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  RALPH RUN SUMMARY"
  echo "═══════════════════════════════════════════════════"
  echo "Exit reason:        $exit_reason"
  echo "Iterations:         $completed_iterations / $MAX_ITERATIONS"
  echo "Stories passed:     $final_done / $final_total"
  echo "Stories remaining:  $final_remaining"
  echo "Total time:         $(fmt_time $end_elapsed)"
  echo "Total tests:        $last_test_count"
  echo "CB activations:     $cb_activation_count"
  echo "Rate limit retries: $rate_limit_total"
  echo "Log file:           $LOG_FILE"

  # Per-story timing stats
  local count=${#story_ids[@]}
  if [ "$count" -gt 0 ]; then
    echo ""
    echo "Story Timing:"

    local total_story_time=0
    local slowest_time=0 slowest_label="" fastest_time=999999 fastest_label=""

    for (( s=0; s<count; s++ )); do
      local t=${story_elapsed[$s]}
      total_story_time=$(( total_story_time + t ))

      local label="${story_ids[$s]}"
      [ -n "${story_names[$s]}" ] && label="$label (${story_names[$s]})"

      if [ "$t" -gt "$slowest_time" ]; then
        slowest_time=$t
        slowest_label="$label"
      fi
      if [ "$t" -lt "$fastest_time" ]; then
        fastest_time=$t
        fastest_label="$label"
      fi

      local ac_tag=""
      [ -n "${story_acs[$s]}" ] && [ "${story_acs[$s]}" != "?" ] && ac_tag=" [${story_acs[$s]} ACs]"
      echo "  ${story_ids[$s]}${ac_tag}: $(fmt_time ${story_elapsed[$s]})  ${story_names[$s]}"
    done

    local avg_time=$(( total_story_time / count ))
    echo ""
    echo "  Average: $(fmt_time $avg_time)"
    echo "  Slowest: $(fmt_time $slowest_time)  $slowest_label"
    echo "  Fastest: $(fmt_time $fastest_time)  $fastest_label"
  fi

  echo "═══════════════════════════════════════════════════"
}

echo "Starting Ralph - Max iterations: $MAX_ITERATIONS"
echo "Log file: $LOG_FILE"

TMPFILES=()
trap 'print_run_summary 2>/dev/null; rm -f "${TMPFILES[@]}"' EXIT

loop_start=$(date +%s)

for (( i=1; i<=MAX_ITERATIONS; i++ )); do
  rate_limit_retries=0

  iter_start=$(date +%s)
  last_ralph_sha_before="$last_ralph_sha"

  # Rate limit retry loop — retries the same iteration without incrementing
  # the circuit breaker when an API rate limit is detected
  while true; do
    tmpfile=$(mktemp)
    TMPFILES+=("$tmpfile")

    # Rate limit check (hourly call budget)
    check_rate_limit

    # Gather RALPH commit history
    ralph_commits=$(git log --grep="RALPH" -n 10 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No RALPH commits found")

    # Build prompt (inject config placeholders)
    prompt="$(sed \
      -e "s|__PRD_PATH__|$PRD_PATH|g" \
      -e "s|__TEST_CMD__|$TEST_CMD|g" \
      -e "s|__TYPECHECK_CMD__|$TYPECHECK_CMD|g" \
      -e "s|__LINT_CMD__|$LINT_CMD|g" \
      -e "s|__SPECS_DIR__|$SPECS_DIR|g" \
      -e "s|__SKILLS_DIR__|$SKILLS_DIR|g" \
      -e "s|__PROGRESS_FILE__|$PROGRESS_FILE|g" \
      -e "s|__ENGINE_DIR__|$ENGINE_DIR|g" \
      "$ENGINE_DIR/prompt.md")

Previous RALPH commits:
$ralph_commits"

    # Build claude command
    claude_cmd=(claude --dangerously-skip-permissions --print --output-format stream-json --verbose -p "$prompt")
    if [ -n "$ALLOWED_TOOLS" ]; then
      claude_cmd+=(--allowedTools "$ALLOWED_TOOLS")
    fi

    # Run claude with retry for API outages
    claude_ok=false
    backoff=$RALPH_RETRY_BACKOFF

    for (( attempt=1; attempt<=RALPH_MAX_RETRIES; attempt++ )); do
      > "$tmpfile"

      set +e
      "${claude_cmd[@]}" \
        | grep --line-buffered '^{' \
        | tee "$tmpfile" \
        | jq --unbuffered -rj "$stream_text"
      set -e

      if [ -s "$tmpfile" ]; then
        claude_ok=true
        break
      fi

      if [ "$attempt" -lt "$RALPH_MAX_RETRIES" ]; then
        echo ""
        echo "Claude API error (attempt $attempt/$RALPH_MAX_RETRIES). Retrying in ${backoff}s..."
        sleep "$backoff"
        backoff=$(( backoff * 2 ))
      fi
    done

    if [ "$claude_ok" = false ]; then
      echo ""
      echo "Claude API failed after $RALPH_MAX_RETRIES attempts. Skipping iteration $i."
      break
    fi

    # Detect API rate limit in output
    if detect_rate_limit "$tmpfile"; then
      rate_limit_retries=$(( rate_limit_retries + 1 ))
      rate_limit_total=$(( rate_limit_total + 1 ))
      if [ "$rate_limit_retries" -ge "$RATE_LIMIT_MAX_RETRIES" ]; then
        echo ""
        echo "Rate limit: max retries ($RATE_LIMIT_MAX_RETRIES) exceeded. Skipping iteration $i."
        claude_ok=false
        break
      fi
      echo ""
      echo "Rate limit detected. Waiting $(fmt_time $RATE_LIMIT_WAIT) before retry (attempt $rate_limit_retries/$RATE_LIMIT_MAX_RETRIES)..."
      sleep "$RATE_LIMIT_WAIT"
      continue
    fi

    break  # No rate limit — proceed with this iteration's result
  done

  # Even if rate-limited out, check last response for exit signals before skipping
  if [ "$claude_ok" = false ]; then
    if [ -s "$tmpfile" ]; then
      result=$(jq -r "$final_result" "$tmpfile" 2>/dev/null || echo "")
      if [[ "$result" == *"<promise>COMPLETE</promise>"* ]] || [[ "$result" == *"<promise>NO MORE TASKS</promise>"* ]]; then
        echo ""
        echo "Ralph complete after $i iterations (detected in rate-limited response)."
        exit_reason="complete"
        exit 0
      fi
      exit_signal=$(echo "$result" | sed -n '/---RALPH_STATUS---/,/---END_RALPH_STATUS---/p' | grep -i "EXIT_SIGNAL:" | head -1 | awk '{print $2}' || echo "")
      if [ "$exit_signal" = "true" ]; then
        echo ""
        echo "Ralph received EXIT_SIGNAL after $i iterations (detected in rate-limited response)."
        exit_reason="exit_signal"
        exit 0
      fi
    fi
    continue
  fi

  completed_iterations=$i
  result=$(jq -r "$final_result" "$tmpfile")

  # Capture test count from iteration output
  iter_test_count=$(grep -oE "$TEST_COUNT_REGEX" "$tmpfile" | tail -1 | grep -oE '[0-9]+' | head -1 || echo "")
  if [ -n "$iter_test_count" ]; then
    last_test_count="$iter_test_count"
  fi

  # Check <promise> exit signals
  if [[ "$result" == *"<promise>COMPLETE</promise>"* ]] || [[ "$result" == *"<promise>NO MORE TASKS</promise>"* ]]; then
    echo ""
    echo "Ralph complete after $i iterations."
    exit_reason="complete"
    exit 0
  fi

  if [[ "$result" == *"<promise>ABORT</promise>"* ]]; then
    echo "Ralph aborted after $i iterations."
    exit_reason="abort"
    exit 1
  fi

  # Check RALPH_STATUS block for EXIT_SIGNAL
  exit_signal=$(echo "$result" | sed -n '/---RALPH_STATUS---/,/---END_RALPH_STATUS---/p' | grep -i "EXIT_SIGNAL:" | head -1 | awk '{print $2}' || echo "")
  if [ "$exit_signal" = "true" ]; then
    echo ""
    echo "Ralph received EXIT_SIGNAL after $i iterations."
    exit_reason="exit_signal"
    exit 0
  fi

  # Circuit breaker: no progress detection (check for new RALPH commit)
  latest_ralph_sha=$(git log --grep="RALPH" -n 1 --format="%H" 2>/dev/null || echo "")
  if [ "$latest_ralph_sha" = "$last_ralph_sha" ]; then
    no_progress_count=$(( no_progress_count + 1 ))
  else
    no_progress_count=0
  fi
  last_ralph_sha="$latest_ralph_sha"

  if [ "$no_progress_count" -ge "$CB_NO_PROGRESS_THRESHOLD" ]; then
    echo ""
    echo "CIRCUIT BREAKER: No file changes in $no_progress_count consecutive iterations. Halting."
    cb_activation_count=$(( cb_activation_count + 1 ))
    exit_reason="circuit_breaker_no_progress"
    exit 1
  fi

  # Circuit breaker: same error detection
  current_last_line=$(echo "$result" | sed -n '/---RALPH_STATUS---/,/---END_RALPH_STATUS---/p' | grep -i "RECOMMENDATION:" | head -1 || echo "")
  if [ "$current_last_line" = "$last_error_line" ] && [ -n "$current_last_line" ]; then
    same_error_count=$(( same_error_count + 1 ))
  else
    same_error_count=0
  fi
  last_error_line="$current_last_line"

  if [ "$same_error_count" -ge "$CB_SAME_ERROR_THRESHOLD" ]; then
    echo ""
    echo "CIRCUIT BREAKER: Same output repeated $same_error_count times. Halting."
    cb_activation_count=$(( cb_activation_count + 1 ))
    exit_reason="circuit_breaker_same_error"
    exit 1
  fi

  # Build end-of-iteration summary line
  iter_end=$(date +%s)
  iter_elapsed=$(( iter_end - iter_start ))
  total_elapsed=$(( iter_end - loop_start ))

  # Parse story progress from PRD
  story_done="?"
  story_total="?"
  if [ -f "$PRD_PATH" ]; then
    story_total=$(jq '.userStories | length' "$PRD_PATH" 2>/dev/null || echo "?")
    story_done=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_PATH" 2>/dev/null || echo "?")
  fi

  # Parse current story ID from RALPH_STATUS
  current_story=$(echo "$result" | sed -n '/---RALPH_STATUS---/,/---END_RALPH_STATUS---/p' | grep -i "CURRENT_STORY:" | head -1 | awk '{print $2}' || echo "")

  # Parse test status from RALPH_STATUS
  test_status=$(echo "$result" | sed -n '/---RALPH_STATUS---/,/---END_RALPH_STATUS---/p' | grep -i "TESTS_STATUS:" | head -1 | awk '{print $2}' || echo "")
  test_status=$(echo "$test_status" | tr '[:upper:]' '[:lower:]')
  if [ -z "$test_status" ]; then
    test_status="unknown"
  fi

  # Get AC count for current story
  ac_count="?"
  story_title=""
  if [ -n "$current_story" ] && [ -f "$PRD_PATH" ]; then
    ac_count=$(jq -r --arg id "$current_story" '.userStories[] | select(.id == $id) | .acceptanceCriteria | length' "$PRD_PATH" 2>/dev/null || echo "?")
  fi

  # Determine commit status and build summary line
  if [ "$latest_ralph_sha" != "$last_ralph_sha_before" ]; then
    commit_label="committed"
    # Try to get story ID from latest commit message
    if [ -z "$current_story" ]; then
      current_story=$(git log --grep="RALPH" -n 1 --format="%s" 2>/dev/null | grep -oE 'US-[0-9]+' | head -1 || echo "")
    fi
    summary_line="[$i/$MAX_ITERATIONS]"
    if [ -n "$current_story" ]; then
      # Get story title from PRD
      story_title=$(jq -r --arg id "$current_story" '.userStories[] | select(.id == $id) | .title // empty' "$PRD_PATH" 2>/dev/null || echo "")
      if [ -n "$story_title" ]; then
        summary_line="$summary_line [$current_story] - $story_title"
      else
        summary_line="$summary_line [$current_story]"
      fi
      # Re-fetch AC count in case current_story was set from commit message
      if [ "$ac_count" = "?" ]; then
        ac_count=$(jq -r --arg id "$current_story" '.userStories[] | select(.id == $id) | .acceptanceCriteria | length' "$PRD_PATH" 2>/dev/null || echo "?")
      fi
    fi
    summary_line="$summary_line | $story_done/$story_total done | $commit_label | tests: $test_status | ${ac_count} ACs | cb: $no_progress_count/$CB_NO_PROGRESS_THRESHOLD | $(fmt_time $iter_elapsed) ($(fmt_time $total_elapsed) total)"

    # Track per-story timing for run summary
    if [ -n "$current_story" ]; then
      story_ids+=("$current_story")
      story_elapsed+=("$iter_elapsed")
      story_names+=("$story_title")
      story_acs+=("$ac_count")
    fi
  else
    summary_line="[$i/$MAX_ITERATIONS] no commit | $story_done/$story_total done | tests: $test_status | cb: $no_progress_count/$CB_NO_PROGRESS_THRESHOLD | $(fmt_time $iter_elapsed) ($(fmt_time $total_elapsed) total)"
  fi

  echo ""
  echo "$summary_line"

  # Generate codebase snapshot between iterations
  if [ -x "$ENGINE_DIR/snapshot.sh" ]; then
    "$ENGINE_DIR/snapshot.sh" 2>/dev/null || true
  fi
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS)."
exit 1
