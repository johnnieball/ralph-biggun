#!/bin/bash
set -e

# mock-claude.sh — Replaces the real Claude CLI for deterministic loop testing.
# Reads MOCK_SCENARIO env var to determine behaviour.
# Outputs stream-json format that ralph.sh expects:
#   1. {"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}
#   2. {"type":"result","result":"..."}

# Silently consume all CLI flags (ralph.sh passes these)
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) shift; shift ;; # -p takes a value
    --output-format|--allowedTools) shift; shift ;;
    --dangerously-skip-permissions|--print|--verbose) shift ;;
    *) shift ;;
  esac
done

SCENARIO="${MOCK_SCENARIO:-normal}"

emit_assistant() {
  local text="$1"
  jq -nc --arg t "$text" '{"type":"assistant","message":{"content":[{"type":"text","text":$t}]}}'
}

emit_result() {
  local result="$1"
  jq -nc --arg r "$result" '{"type":"result","result":$r}'
}

case "$SCENARIO" in
  normal)
    emit_assistant "Mock iteration complete. Making progress."

    result_text="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
      '---RALPH_STATUS---' \
      'STATUS: IN_PROGRESS' \
      'TASKS_COMPLETED_THIS_LOOP: 1' \
      'FILES_MODIFIED: 1' \
      'TESTS_STATUS: PASSING' \
      'WORK_TYPE: IMPLEMENTATION' \
      'EXIT_SIGNAL: false' \
      'RECOMMENDATION: Continue' \
      '---END_RALPH_STATUS---')"
    emit_result "$result_text"

    # Create a RALPH-prefixed commit so circuit breaker sees progress
    touch .mock-iteration-marker
    git add .mock-iteration-marker 2>/dev/null || true
    git commit -m "RALPH: mock progress" --allow-empty 2>/dev/null || true
    ;;

  exit-promise)
    emit_assistant "All stories complete."
    emit_result "<promise>COMPLETE</promise>"
    ;;

  exit-signal)
    result_text="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
      '---RALPH_STATUS---' \
      'STATUS: COMPLETE' \
      'TASKS_COMPLETED_THIS_LOOP: 1' \
      'FILES_MODIFIED: 1' \
      'TESTS_STATUS: PASSING' \
      'WORK_TYPE: IMPLEMENTATION' \
      'EXIT_SIGNAL: true' \
      'RECOMMENDATION: All requirements met' \
      '---END_RALPH_STATUS---')"
    emit_assistant "All stories complete with exit signal."
    emit_result "$result_text"
    ;;

  no-commit)
    result_text="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
      '---RALPH_STATUS---' \
      'STATUS: IN_PROGRESS' \
      'TASKS_COMPLETED_THIS_LOOP: 0' \
      'FILES_MODIFIED: 0' \
      'TESTS_STATUS: PASSING' \
      'WORK_TYPE: IMPLEMENTATION' \
      'EXIT_SIGNAL: false' \
      'RECOMMENDATION: Continue' \
      '---END_RALPH_STATUS---')"
    emit_assistant "Working but no commit."
    emit_result "$result_text"
    ;;

  same-error)
    result_text="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
      '---RALPH_STATUS---' \
      'STATUS: BLOCKED' \
      'TASKS_COMPLETED_THIS_LOOP: 0' \
      'FILES_MODIFIED: 0' \
      'TESTS_STATUS: FAILING' \
      'WORK_TYPE: DEBUGGING' \
      'EXIT_SIGNAL: false' \
      "RECOMMENDATION: Stuck on module resolution error" \
      '---END_RALPH_STATUS---')"
    emit_assistant "Encountering error."
    emit_result "$result_text"
    # Create a RALPH commit so no-progress circuit breaker doesn't fire first
    touch .mock-error-marker
    git add .mock-error-marker 2>/dev/null || true
    git commit -m "RALPH: mock error iteration" --allow-empty 2>/dev/null || true
    ;;

  abort)
    emit_assistant "Cannot proceed, aborting."
    emit_result "<promise>ABORT</promise>"
    ;;

  missing-status-block)
    emit_assistant "Iteration done but no status block."
    emit_result "Work completed without status block."

    touch .mock-nostatus-marker
    git add .mock-nostatus-marker 2>/dev/null || true
    git commit -m "RALPH: mock no-status progress" --allow-empty 2>/dev/null || true
    ;;

  committed-with-story)
    # EXIT_SIGNAL is false (not true as in exit-signal scenario) so the loop
    # reaches the summary-line construction code. Use MAX_ITERATIONS=1 in the
    # test's .ralphrc to exit cleanly after one full iteration.
    result_text="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
      '---RALPH_STATUS---' \
      'STATUS: IN_PROGRESS' \
      'CURRENT_STORY: US-001' \
      'TASKS_COMPLETED_THIS_LOOP: 1' \
      'FILES_MODIFIED: 1' \
      'TESTS_STATUS: PASSING' \
      'WORK_TYPE: IMPLEMENTATION' \
      'EXIT_SIGNAL: false' \
      'RECOMMENDATION: Making progress on US-001' \
      '---END_RALPH_STATUS---')"
    emit_assistant "Story US-001 progress."
    emit_result "$result_text"

    touch .mock-story-marker
    git add .mock-story-marker 2>/dev/null || true
    git commit -m "RALPH: feat: [US-001] - Setup Project" --allow-empty 2>/dev/null || true
    ;;

  # --- task-build scenarios ---
  # Use MOCK_TASKS_PATH env var to know where the task file goes.

  task-converge)
    # Iteration 1: create task list. Iteration 2+: leave it unchanged (triggers convergence).
    if [ ! -f "$MOCK_TASKS_PATH" ]; then
      cat > "$MOCK_TASKS_PATH" << 'TASKSJSON'
{"project":"test","branchName":"feature/test","description":"Test project","techStack":["bun","typescript"],"environment":{"runtime":"bun","testFramework":"vitest","notes":""},"userStories":[{"id":"US-001","title":"Setup","description":"Project setup","acceptanceCriteria":["Project initialises"],"priority":"high","passes":false,"dependsOn":[],"notes":""}]}
TASKSJSON
      emit_assistant "Generated task list from spec.\n\n---TASK_BUILD_STATUS---\nITERATION: 1\nMECHANICAL_FIXES: 0\nHUMAN_ITEMS: 0\nVERDICT: READY\n---END_TASK_BUILD_STATUS---"
      emit_result "Task list generated."
    else
      emit_assistant "No mechanical issues found.\n\n---TASK_BUILD_STATUS---\nITERATION: 2\nMECHANICAL_FIXES: 0\nHUMAN_ITEMS: 0\nVERDICT: READY\n---END_TASK_BUILD_STATUS---"
      emit_result "Task list unchanged."
    fi
    ;;

  task-always-change)
    # Always modify the task list (prevents convergence — tests max-iterations cap).
    cat > "$MOCK_TASKS_PATH" << TASKSJSON
{"project":"test","branchName":"feature/test","description":"Test project","techStack":["bun"],"environment":{"runtime":"bun","testFramework":"vitest","notes":""},"userStories":[{"id":"US-001","title":"Setup $(date +%s%N)","description":"Project setup","acceptanceCriteria":["Project initialises"],"priority":"high","passes":false,"dependsOn":[],"notes":""}]}
TASKSJSON
    emit_assistant "Fixed issues in task list.\n\n---TASK_BUILD_STATUS---\nITERATION: 1\nMECHANICAL_FIXES: 2\nHUMAN_ITEMS: 1\nVERDICT: IN_PROGRESS\n---END_TASK_BUILD_STATUS---"
    emit_result "Task list updated."
    ;;

  task-needs-human-no-converge)
    # Always modify task list + emit human items (tests max-iterations exit with NEEDS_HUMAN).
    cat > "$MOCK_TASKS_PATH" << TASKSJSON
{"project":"test","branchName":"feature/test","description":"Test project","techStack":["bun"],"environment":{"runtime":"bun","testFramework":"vitest","notes":""},"userStories":[{"id":"US-001","title":"Setup $(date +%s%N)","description":"Project setup","acceptanceCriteria":["Project initialises"],"priority":"high","passes":false,"dependsOn":[],"notes":""}]}
TASKSJSON
    emit_assistant "Fixed issues but human decisions remain.\n\n---HUMAN_DECISION_ITEMS---\n- caching: Redis or in-memory LRU?\n---END_HUMAN_DECISION_ITEMS---\n\n---TASK_BUILD_STATUS---\nITERATION: 1\nMECHANICAL_FIXES: 1\nHUMAN_ITEMS: 1\nVERDICT: NEEDS_HUMAN\n---END_TASK_BUILD_STATUS---"
    emit_result "Task list updated."
    ;;

  task-needs-human)
    # Create task list on iteration 1, then converge with human items on iteration 2+.
    if [ ! -f "$MOCK_TASKS_PATH" ]; then
      cat > "$MOCK_TASKS_PATH" << 'TASKSJSON'
{"project":"test","branchName":"feature/test","description":"Test project","techStack":["bun","typescript"],"environment":{"runtime":"bun","testFramework":"vitest","notes":""},"userStories":[{"id":"US-001","title":"Setup","description":"Project setup","acceptanceCriteria":["Project initialises"],"priority":"high","passes":false,"dependsOn":[],"notes":""}]}
TASKSJSON
      emit_assistant "Generated task list.\n\n---HUMAN_DECISION_ITEMS---\n- auth: should sessions use JWT or server-side cookies?\n- search: full-text search via SQLite FTS5 or external service like Algolia?\n---END_HUMAN_DECISION_ITEMS---\n\n---TASK_BUILD_STATUS---\nITERATION: 1\nMECHANICAL_FIXES: 0\nHUMAN_ITEMS: 2\nVERDICT: NEEDS_HUMAN\n---END_TASK_BUILD_STATUS---"
      emit_result "Task list generated with human items."
    else
      emit_assistant "No mechanical issues.\n\n---HUMAN_DECISION_ITEMS---\n- auth: should sessions use JWT or server-side cookies?\n- search: full-text search via SQLite FTS5 or external service like Algolia?\n---END_HUMAN_DECISION_ITEMS---\n\n---TASK_BUILD_STATUS---\nITERATION: 2\nMECHANICAL_FIXES: 0\nHUMAN_ITEMS: 2\nVERDICT: NEEDS_HUMAN\n---END_TASK_BUILD_STATUS---"
      emit_result "Task list unchanged."
    fi
    ;;

  task-no-write)
    # Never create the task file (tests the missing-file guard).
    emit_assistant "I could not generate the task list."
    emit_result "Failed."
    ;;

  *)
    echo "Unknown MOCK_SCENARIO: $SCENARIO" >&2
    exit 1
    ;;
esac
