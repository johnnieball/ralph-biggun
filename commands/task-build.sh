#!/bin/bash
set -e

# commands/task-build.sh — Automated task list generation loop
# Usage: commands/task-build.sh <spec-file> [plan-name] [max-iterations]
#
# Reads a spec file and iteratively generates/refines a task list JSON using
# the same fresh-context-per-iteration pattern as ralph.sh.

RALPH_HOME="$(cd "$(dirname "$0")/.." && pwd)"

# Source configuration (detect layout)
RALPH_CONFIG="${RALPH_CONFIG:-.ralphrc}"
if [ ! -f "$RALPH_CONFIG" ] && [ -f ".ralph/config.sh" ]; then
  RALPH_CONFIG=".ralph/config.sh"
fi
if [ -f "$RALPH_CONFIG" ]; then
  source "$RALPH_CONFIG"
fi

# Defaults
SPECS_DIR="${SPECS_DIR:-specs}"
ENGINE_DIR="${ENGINE_DIR:-engine}"
LOG_DIR="${LOG_DIR:-logs}"
RALPH_MAX_RETRIES=${RALPH_MAX_RETRIES:-3}
RALPH_RETRY_BACKOFF=${RALPH_RETRY_BACKOFF:-30}
RATE_LIMIT_WAIT=${RATE_LIMIT_WAIT:-120}
RATE_LIMIT_MAX_RETRIES=${RATE_LIMIT_MAX_RETRIES:-5}

# Parse arguments
SPEC_FILE="${1:-}"
PLAN_NAME="${2:-}"
MAX_ITERATIONS="${3:-5}"

if [ -z "$SPEC_FILE" ]; then
  echo "Usage: ralph task-build <spec-file> [plan-name] [max-iterations]"
  echo ""
  echo "  spec-file       Path to the spec/requirements file (required)"
  echo "  plan-name       Name for the task list (default: spec filename stem)"
  echo "  max-iterations  Max refinement passes (default: 5)"
  exit 1
fi

if [ ! -f "$SPEC_FILE" ]; then
  echo "ERROR: Spec file not found: $SPEC_FILE"
  exit 1
fi

# Derive plan name from spec filename if not provided
if [ -z "$PLAN_NAME" ]; then
  PLAN_NAME=$(basename "$SPEC_FILE" | sed 's/\.[^.]*$//')
fi

TASKS_PATH="$SPECS_DIR/tasks-${PLAN_NAME}.json"
mkdir -p "$SPECS_DIR"

# Resolve prompt template — check .ralph/engine first, then ralph-home engine
PROMPT_TEMPLATE=""
if [ -f "$ENGINE_DIR/task-build-prompt.md" ]; then
  PROMPT_TEMPLATE="$ENGINE_DIR/task-build-prompt.md"
elif [ -f "$RALPH_HOME/engine/task-build-prompt.md" ]; then
  PROMPT_TEMPLATE="$RALPH_HOME/engine/task-build-prompt.md"
else
  echo "ERROR: task-build-prompt.md not found in $ENGINE_DIR/ or $RALPH_HOME/engine/"
  exit 1
fi

# Logging
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/task-build-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Task Build: $SPEC_FILE → $TASKS_PATH"
echo "Plan: $PLAN_NAME | Max iterations: $MAX_ITERATIONS"
echo "Log: $LOG_FILE"
echo ""

# jq filters for stream-json output
# Show assistant text + tool use activity so the user sees progress
stream_progress='
  if .type == "assistant" then
    (.message.content[]? |
      if .type == "text" then
        .text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"
      elif .type == "tool_use" then
        "  → " + .name + ": " + (.input.file_path // .input.command // "" | split("/") | last) + "\r\n"
      else empty end)
  else empty end
'

detect_rate_limit() {
  local file="$1"
  # Only flag rate limits when there's NO valid assistant content — avoids
  # false positives from Claude's response text containing "429" etc.
  if grep -q '"type":"result"' "$file" 2>/dev/null; then
    return 1
  fi
  grep -qiE '(hit your limit|rate.?limit|429|quota.?exceeded|too many requests|overloaded|resource_exhausted|try again later)' "$file" 2>/dev/null
}

fmt_time() {
  local secs=$1
  if [ "$secs" -ge 60 ]; then
    printf "%dm%02ds" $(( secs / 60 )) $(( secs % 60 ))
  else
    printf "%ds" "$secs"
  fi
}

# Cleanup temp files on exit
TMPFILES=()
trap 'rm -f "${TMPFILES[@]}"' EXIT

last_sha=""
rate_limit_retries=0
loop_start=$(date +%s)

for (( i=1; i<=MAX_ITERATIONS; i++ )); do
  iter_start=$(date +%s)

  # Progress banner
  if [ "$i" -eq 1 ] && [ ! -f "$TASKS_PATH" ]; then
    echo "━━━ Iteration $i/$MAX_ITERATIONS — Generating task list from spec ━━━"
  else
    echo "━━━ Iteration $i/$MAX_ITERATIONS — Reviewing and refining task list ━━━"
  fi
  echo ""

  # Build prompt with placeholder injection
  prompt="$(sed \
    -e "s|__SPEC_FILE__|$SPEC_FILE|g" \
    -e "s|__TASKS_PATH__|$TASKS_PATH|g" \
    -e "s|__SPECS_DIR__|$SPECS_DIR|g" \
    -e "s|__ITERATION__|$i|g" \
    "$PROMPT_TEMPLATE")"

  tmpfile=$(mktemp)
  TMPFILES+=("$tmpfile")

  # Run claude with retry for API outages
  claude_ok=false
  backoff=$RALPH_RETRY_BACKOFF

  for (( attempt=1; attempt<=RALPH_MAX_RETRIES; attempt++ )); do
    > "$tmpfile"

    set +e
    claude --print --dangerously-skip-permissions --output-format stream-json --verbose \
      --allowedTools "Read,Write,Edit" \
      -p "$prompt" \
      | grep --line-buffered '^{' \
      | tee "$tmpfile" \
      | jq --unbuffered -rj "$stream_progress"
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
    echo "Claude API failed after $RALPH_MAX_RETRIES attempts. Aborting."
    exit 1
  fi

  # Detect API rate limit in output
  if detect_rate_limit "$tmpfile"; then
    rate_limit_retries=$(( rate_limit_retries + 1 ))
    if [ "$rate_limit_retries" -ge "$RATE_LIMIT_MAX_RETRIES" ]; then
      echo ""
      echo "Rate limit: max retries ($RATE_LIMIT_MAX_RETRIES) exceeded. Aborting."
      exit 1
    fi
    echo ""
    echo "Rate limit detected. Waiting $(fmt_time $RATE_LIMIT_WAIT) before retry..."
    sleep "$RATE_LIMIT_WAIT"
    # Decrement i so this iteration is retried
    (( i-- )) || true
    continue
  fi

  # Verify task file exists (guards against false convergence if Claude
  # fails to write the file — shasum of empty input is deterministic)
  if [ ! -f "$TASKS_PATH" ]; then
    echo ""
    echo "WARNING: Task file not created at $TASKS_PATH after iteration $i"
    if [ "$i" -ge "$MAX_ITERATIONS" ]; then
      echo "ERROR: Task file was never created. Check the log: $LOG_FILE"
      exit 1
    fi
    continue
  fi

  # Check convergence via SHA comparison (jq -S normalises key order)
  current_sha=$(jq -S . "$TASKS_PATH" 2>/dev/null | shasum | awk '{print $1}')

  iter_end=$(date +%s)
  iter_elapsed=$(( iter_end - iter_start ))
  total_elapsed=$(( iter_end - loop_start ))

  # Extract status from output (macOS-compatible — no grep -P)
  # tmpfile contains JSON-encoded text where \n is literal, so grep -oE
  # can match multiple tokens on one JSON line — head -1 takes the first
  fixes=$(grep 'MECHANICAL_FIXES:' "$tmpfile" 2>/dev/null | tail -1 | sed 's/.*MECHANICAL_FIXES:[[:space:]]*//' | grep -oE '[0-9]+' | head -1 || true)
  human=$(grep 'HUMAN_ITEMS:' "$tmpfile" 2>/dev/null | tail -1 | sed 's/.*HUMAN_ITEMS:[[:space:]]*//' | grep -oE '[0-9]+' | head -1 || true)
  verdict=$(grep 'VERDICT:' "$tmpfile" 2>/dev/null | tail -1 | sed 's/.*VERDICT:[[:space:]]*//' | grep -oE '[A-Z_]+' | head -1 || true)
  fixes="${fixes:-?}"
  human="${human:-?}"
  verdict="${verdict:-?}"

  # Extract human decision items from structured block
  # In stream-json output, newlines are JSON-encoded as \n (literal backslash-n)
  human_items=$(grep -o 'HUMAN_DECISION_ITEMS---.*---END_HUMAN_DECISION_ITEMS' "$tmpfile" 2>/dev/null \
    | sed 's/.*HUMAN_DECISION_ITEMS---//; s/---END_HUMAN_DECISION_ITEMS.*//' \
    | sed 's/\\n/\'$'\n''/g' \
    | grep '^- ' \
    || true)

  # Count stories in the task list
  story_count=$(jq '.userStories | length' "$TASKS_PATH" 2>/dev/null || echo "?")

  echo ""
  echo "[$i/$MAX_ITERATIONS] ${fixes} fixes | ${human} human items | ${story_count} stories | verdict: ${verdict} | $(fmt_time $iter_elapsed)"

  if [ "$current_sha" = "$last_sha" ]; then
    total_elapsed=$(( $(date +%s) - loop_start ))
    echo ""
    echo "═══════════════════════════════════════════════════"
    if [ "$verdict" = "NEEDS_HUMAN" ]; then
      echo "  TASK BUILD COMPLETE — NEEDS HUMAN INPUT"
    else
      echo "  TASK BUILD COMPLETE"
    fi
    echo "═══════════════════════════════════════════════════"
    echo "Converged after:  $i iterations ($(fmt_time $total_elapsed))"
    echo "Stories:          $story_count"
    echo "Human items:      $human"
    echo "Verdict:          $verdict"
    echo "Output:           $TASKS_PATH"
    echo "Log:              $LOG_FILE"
    echo "═══════════════════════════════════════════════════"

    if [ -n "$human_items" ]; then
      echo ""
      echo "  Decisions needed:"
      echo ""
      item_num=0
      echo "$human_items" | while IFS= read -r line; do
        item_num=$(( item_num + 1 ))
        echo "  ${item_num}. ${line#- }"
      done
      echo ""
      echo "  To resolve: add your decisions to the spec file,"
      echo "  then re-run:"
      echo ""
      echo "    ralph task-build $SPEC_FILE $PLAN_NAME"
      echo ""
      echo "═══════════════════════════════════════════════════"
    else
      echo ""
      echo "Next: /task-review ${PLAN_NAME}  (in Claude Code)"
    fi
    exit 0
  fi

  last_sha="$current_sha"
done

total_elapsed=$(( $(date +%s) - loop_start ))
echo ""
echo "═══════════════════════════════════════════════════"
if [ "$verdict" = "NEEDS_HUMAN" ]; then
  echo "  TASK BUILD — MAX ITERATIONS (NEEDS HUMAN INPUT)"
else
  echo "  TASK BUILD — MAX ITERATIONS"
fi
echo "═══════════════════════════════════════════════════"
echo "Iterations:       $MAX_ITERATIONS ($(fmt_time $total_elapsed))"
echo "Stories:          $(jq '.userStories | length' "$TASKS_PATH" 2>/dev/null || echo "?")"
echo "Human items:      $human"
echo "Verdict:          $verdict"
echo "Output:           $TASKS_PATH"
echo "Log:              $LOG_FILE"
echo "═══════════════════════════════════════════════════"

if [ -n "$human_items" ]; then
  echo ""
  echo "  Decisions needed:"
  echo ""
  item_num=0
  echo "$human_items" | while IFS= read -r line; do
    item_num=$(( item_num + 1 ))
    echo "  ${item_num}. ${line#- }"
  done
  echo ""
  echo "  To resolve: add your decisions to the spec file,"
  echo "  then re-run:"
  echo ""
  echo "    ralph task-build $SPEC_FILE $PLAN_NAME"
else
  echo ""
  echo "Task list may need further review. Re-run or use /task-review ${PLAN_NAME}"
fi
exit 0
