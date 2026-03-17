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

  # --- prd-build scenarios ---
  # Use MOCK_PRD_PATH env var to know where the PRD file goes.

  prd-converge)
    # Iteration 1: create PRD. Iteration 2+: leave it unchanged (triggers convergence).
    if [ ! -f "$MOCK_PRD_PATH" ]; then
      cat > "$MOCK_PRD_PATH" << 'PRDJSON'
{"project":"test","branchName":"feature/test","description":"Test project","techStack":["bun","typescript"],"environment":{"runtime":"bun","testFramework":"vitest","notes":""},"userStories":[{"id":"US-001","title":"Setup","description":"Project setup","acceptanceCriteria":["Project initialises"],"priority":"high","passes":false,"dependsOn":[],"notes":""}]}
PRDJSON
      emit_assistant "Generated PRD from spec.\n\n---PRD_BUILD_STATUS---\nITERATION: 1\nMECHANICAL_FIXES: 0\nHUMAN_ITEMS: 0\nVERDICT: READY\n---END_PRD_BUILD_STATUS---"
      emit_result "PRD generated."
    else
      emit_assistant "No mechanical issues found.\n\n---PRD_BUILD_STATUS---\nITERATION: 2\nMECHANICAL_FIXES: 0\nHUMAN_ITEMS: 0\nVERDICT: READY\n---END_PRD_BUILD_STATUS---"
      emit_result "PRD unchanged."
    fi
    ;;

  prd-always-change)
    # Always modify the PRD (prevents convergence — tests max-iterations cap).
    cat > "$MOCK_PRD_PATH" << PRDJSON
{"project":"test","branchName":"feature/test","description":"Test project","techStack":["bun"],"environment":{"runtime":"bun","testFramework":"vitest","notes":""},"userStories":[{"id":"US-001","title":"Setup $(date +%s%N)","description":"Project setup","acceptanceCriteria":["Project initialises"],"priority":"high","passes":false,"dependsOn":[],"notes":""}]}
PRDJSON
    emit_assistant "Fixed issues in PRD.\n\n---PRD_BUILD_STATUS---\nITERATION: 1\nMECHANICAL_FIXES: 2\nHUMAN_ITEMS: 1\nVERDICT: IN_PROGRESS\n---END_PRD_BUILD_STATUS---"
    emit_result "PRD updated."
    ;;

  prd-no-write)
    # Never create the PRD file (tests the missing-file guard).
    emit_assistant "I could not generate the PRD."
    emit_result "Failed."
    ;;

  *)
    echo "Unknown MOCK_SCENARIO: $SCENARIO" >&2
    exit 1
    ;;
esac
