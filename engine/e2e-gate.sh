#!/bin/bash
set -e

# engine/e2e-gate.sh — E2E test runner for Ralph
# Called at phase boundaries and after COMPLETE to run Playwright journey tests.
#
# Usage:
#   ./engine/e2e-gate.sh --phase PH-1 --tasks-path .ralph/specs/tasks-plan.json
#   ./engine/e2e-gate.sh --all --tasks-path .ralph/specs/tasks-plan.json
#
# Exit codes:
#   0 = all journeys pass
#   1 = failures remain after repair attempts (escalate to human)
#   2 = aborted (circuit breaker or timeout)

# --- Parse arguments ---
PHASE=""
RUN_ALL=false
TASKS_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      PHASE="$2"
      shift 2
      ;;
    --all)
      RUN_ALL=true
      shift
      ;;
    --tasks-path)
      TASKS_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$TASKS_PATH" ]; then
  echo "ERROR: --tasks-path is required" >&2
  exit 1
fi

if [ ! -f "$TASKS_PATH" ]; then
  echo "ERROR: Task file not found: $TASKS_PATH" >&2
  exit 1
fi

if [ "$RUN_ALL" = false ] && [ -z "$PHASE" ]; then
  echo "ERROR: Specify --phase PH-X or --all" >&2
  exit 1
fi

# --- Load config ---
RALPH_CONFIG="${RALPH_CONFIG:-.ralphrc}"
if [ ! -f "$RALPH_CONFIG" ] && [ -f ".ralph/config.sh" ]; then
  RALPH_CONFIG=".ralph/config.sh"
fi
if [ -f "$RALPH_CONFIG" ]; then
  source "$RALPH_CONFIG"
fi

E2E_ENABLED="${E2E_ENABLED:-false}"
E2E_START_CMD="${E2E_START_CMD:-}"
E2E_PORT="${E2E_PORT:-3000}"
E2E_SEED_CMD="${E2E_SEED_CMD:-}"
E2E_MAX_FAILURES="${E2E_MAX_FAILURES:-5}"
E2E_TIMEOUT="${E2E_TIMEOUT:-900}"
E2E_REPAIR_MAX="${E2E_REPAIR_MAX:-3}"

if [ "$E2E_ENABLED" != "true" ]; then
  echo "E2E testing is disabled (E2E_ENABLED=$E2E_ENABLED). Skipping."
  exit 0
fi

# --- Determine which journeys to run ---
if [ "$RUN_ALL" = true ]; then
  journeys=$(jq -c '.journeys // [] | .[]' "$TASKS_PATH" 2>/dev/null)
  echo "E2E Gate: Running ALL journeys"
else
  journeys=$(jq -c --arg phase "$PHASE" '[.journeys // [] | .[] | select(.phase == $phase)] | .[]' "$TASKS_PATH" 2>/dev/null)
  echo "E2E Gate: Running journeys for phase $PHASE"
fi

if [ -z "$journeys" ]; then
  echo "No journeys to run. Skipping E2E gate."
  exit 0
fi

# Collect journey IDs and test files
declare -a journey_ids journey_titles test_files
while IFS= read -r journey; do
  jid=$(echo "$journey" | jq -r '.id')
  jtitle=$(echo "$journey" | jq -r '.title')
  journey_ids+=("$jid")
  journey_titles+=("$jtitle")

  # Find test file: check e2eTestFile on dependent stories, or derive from journey ID
  test_file=""
  dep_stories=$(echo "$journey" | jq -r '.dependsOn[]' 2>/dev/null)
  for sid in $dep_stories; do
    candidate=$(jq -r --arg id "$sid" '.userStories[] | select(.id == $id) | .e2eTestFile // empty' "$TASKS_PATH" 2>/dev/null)
    if [ -n "$candidate" ] && [ -f "$candidate" ]; then
      test_file="$candidate"
      break
    fi
  done

  # Fallback: derive from journey ID
  if [ -z "$test_file" ]; then
    kebab=$(echo "$jtitle" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    jnum=$(echo "$jid" | sed 's/J-//' | xargs printf '%03d')
    test_file="e2e/j-${jnum}-${kebab}.spec.ts"
  fi

  test_files+=("$test_file")
done <<< "$journeys"

# Check that test files exist
missing_files=()
existing_files=()
for idx in "${!test_files[@]}"; do
  if [ -f "${test_files[$idx]}" ]; then
    existing_files+=("${test_files[$idx]}")
  else
    missing_files+=("${journey_ids[$idx]}: ${test_files[$idx]}")
  fi
done

if [ ${#existing_files[@]} -eq 0 ]; then
  echo "No E2E test files found. Journeys may not have been generated yet."
  for m in "${missing_files[@]}"; do
    echo "  Missing: $m"
  done
  echo "Skipping E2E gate."
  exit 0
fi

if [ ${#missing_files[@]} -gt 0 ]; then
  echo "Warning: Some test files missing:"
  for m in "${missing_files[@]}"; do
    echo "  $m"
  done
fi

echo "Running ${#existing_files[@]} E2E test file(s)..."

# --- Data seeding ---
if [ -n "$E2E_SEED_CMD" ]; then
  echo "Running seed command: $E2E_SEED_CMD"
  eval "$E2E_SEED_CMD" || {
    echo "ERROR: Seed command failed"
    exit 1
  }
fi

# --- Start app if needed ---
APP_PID=""
cleanup_app() {
  if [ -n "$APP_PID" ]; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
}
trap cleanup_app EXIT

if [ -n "$E2E_START_CMD" ]; then
  # Check if already running on the port
  if ! curl -s -o /dev/null "http://localhost:${E2E_PORT}" 2>/dev/null; then
    echo "Starting app: $E2E_START_CMD (port $E2E_PORT)"
    eval "$E2E_START_CMD" &
    APP_PID=$!

    # Wait for app to be ready (up to 30 seconds)
    for attempt in $(seq 1 30); do
      if curl -s -o /dev/null "http://localhost:${E2E_PORT}" 2>/dev/null; then
        echo "App ready on port $E2E_PORT"
        break
      fi
      if [ "$attempt" -eq 30 ]; then
        echo "ERROR: App did not start within 30 seconds"
        exit 2
      fi
      sleep 1
    done
  else
    echo "App already running on port $E2E_PORT"
  fi
fi

# --- Run Playwright tests ---
gate_start=$(date +%s)
total_failures=0
total_repairs=0

classify_failure() {
  local error_msg="$1"

  # Timeout / waitFor
  if echo "$error_msg" | grep -qiE '(TimeoutError|waitFor.*timeout|exceeded.*timeout|waiting for)'; then
    echo "flaky"
    return
  fi

  # Locator not found
  if echo "$error_msg" | grep -qiE '(locator not found|no element matches|could not find|strict mode violation)'; then
    echo "stale_test"
    return
  fi

  # Assertion mismatch
  if echo "$error_msg" | grep -qiE '(expected.*received|toEqual|toContain|toBe|assertion.*failed|expect\()'; then
    echo "stale_test"
    return
  fi

  # HTTP errors
  if echo "$error_msg" | grep -qiE '(HTTP 5[0-9][0-9]|status code 5|Internal Server Error|502|503)'; then
    echo "real_bug"
    return
  fi

  # Environment issues
  if echo "$error_msg" | grep -qiE '(ECONNREFUSED|EADDRINUSE|connection refused|address already in use)'; then
    echo "environment"
    return
  fi

  # Crash
  if echo "$error_msg" | grep -qiE '(segfault|SIGSEGV|SIGABRT|crash)'; then
    echo "crash"
    return
  fi

  echo "unknown"
}

run_playwright() {
  local files=("$@")
  local result_file
  result_file=$(mktemp)

  set +e
  npx playwright test "${files[@]}" --reporter=json > "$result_file" 2>&1
  local pw_exit=$?
  set -e

  echo "$result_file"
  return $pw_exit
}

# Main test execution
for idx in "${!existing_files[@]}"; do
  test_file="${existing_files[$idx]}"
  repair_count=0

  echo ""
  echo "--- Running: $test_file ---"

  while true; do
    # Check time budget
    now=$(date +%s)
    elapsed=$(( now - gate_start ))
    if [ "$elapsed" -ge "$E2E_TIMEOUT" ]; then
      echo "E2E TIMEOUT: ${E2E_TIMEOUT}s budget exceeded. Aborting."
      exit 2
    fi

    # Check total failure circuit breaker
    if [ "$total_failures" -ge "$E2E_MAX_FAILURES" ]; then
      echo "E2E CIRCUIT BREAKER: $total_failures total failures. Aborting (systemic issue)."
      exit 2
    fi

    # Run test
    set +e
    result_file=$(mktemp)
    npx playwright test "$test_file" --reporter=json > "$result_file" 2>&1
    pw_exit=$?
    set -e

    if [ "$pw_exit" -eq 0 ]; then
      echo "  PASS: $test_file"
      rm -f "$result_file"
      break
    fi

    total_failures=$(( total_failures + 1 ))

    # Extract error message from JSON output
    error_msg=$(jq -r '.suites[]?.specs[]?.tests[]?.results[]? | select(.status == "failed") | .error.message // empty' "$result_file" 2>/dev/null | head -5)
    if [ -z "$error_msg" ]; then
      error_msg=$(tail -20 "$result_file")
    fi

    # Classify failure
    category=$(classify_failure "$error_msg")
    echo "  FAIL ($category): $(echo "$error_msg" | head -1)"

    # Handle by category
    case "$category" in
      crash)
        echo "  Crash detected. Aborting E2E gate."
        rm -f "$result_file"
        exit 2
        ;;

      environment)
        if [ "$repair_count" -lt 1 ]; then
          echo "  Environment issue. Retrying once..."
          repair_count=$(( repair_count + 1 ))
          sleep 2
          rm -f "$result_file"
          continue
        else
          echo "  Environment issue persists. Skipping."
          rm -f "$result_file"
          break
        fi
        ;;

      flaky)
        if [ "$repair_count" -lt 2 ]; then
          echo "  Flaky test. Retrying (attempt $((repair_count + 1))/2)..."
          repair_count=$(( repair_count + 1 ))
          rm -f "$result_file"
          continue
        else
          echo "  Flaky test persists after 2 retries."
          rm -f "$result_file"
          break
        fi
        ;;

      stale_test|real_bug|unknown)
        if [ "$repair_count" -ge "$E2E_REPAIR_MAX" ]; then
          echo "  Max repair attempts ($E2E_REPAIR_MAX) reached for $test_file"
          rm -f "$result_file"
          break
        fi

        repair_count=$(( repair_count + 1 ))
        total_repairs=$(( total_repairs + 1 ))
        echo "  Attempting repair ($repair_count/$E2E_REPAIR_MAX)..."

        # Capture a11y tree if possible
        a11y_snapshot=""
        screenshot_info=""

        # Build repair prompt
        if [ "$category" = "stale_test" ]; then
          repair_instruction="The test selectors or assertions are stale. Fix the TEST file to match the current app code."
        else
          repair_instruction="This is a real bug in the application code. Fix the APP code, not the test."
        fi

        repair_prompt="$(cat <<REPAIR_EOF
A Playwright E2E test is failing. Diagnose and fix it.

## Error
$error_msg

## Test File
$(cat "$test_file")

## Classification
Category: $category
Instruction: $repair_instruction

## Rules
- If stale_test: fix the test selectors/assertions to match current app code
- If real_bug: fix the application code using TDD (write a unit test first if possible)
- Do NOT modify Ralph engine files
- Run the relevant test/typecheck commands after fixing
REPAIR_EOF
)"

        # Call Claude for repair
        set +e
        claude --dangerously-skip-permissions --print -p "$repair_prompt" > /dev/null 2>&1
        set -e

        rm -f "$result_file"
        echo "  Repair applied. Re-running test..."
        continue
        ;;
    esac

    rm -f "$result_file"
    break
  done
done

# --- Final summary ---
echo ""
echo "═══════════════════════════════════════════════════"
echo "  E2E GATE SUMMARY"
echo "═══════════════════════════════════════════════════"
echo "Tests run:    ${#existing_files[@]}"
echo "Failures:     $total_failures"
echo "Repairs:      $total_repairs"

if [ "$total_failures" -gt 0 ]; then
  echo "Result:       FAIL"
  echo "═══════════════════════════════════════════════════"
  exit 1
else
  echo "Result:       PASS"
  echo "═══════════════════════════════════════════════════"
  exit 0
fi
