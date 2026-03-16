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

  *)
    echo "Unknown MOCK_SCENARIO: $SCENARIO" >&2
    exit 1
    ;;
esac
