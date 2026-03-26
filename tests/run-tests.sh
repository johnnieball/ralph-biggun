#!/bin/bash
set -e

# Run all infrastructure tests (no API calls required)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0
SUITES=()
RESULTS=()

run_suite() {
  local name="$1"
  local script="$2"

  SUITES+=("$name")
  echo ""
  echo "=== $name ==="
  set +e
  bash "$script"
  local code=$?
  set -e

  if [ "$code" -eq 0 ]; then
    RESULTS+=("PASS")
    PASS=$(( PASS + 1 ))
  else
    RESULTS+=("FAIL")
    FAIL=$(( FAIL + 1 ))
  fi
}

run_suite "Loop Tests"          "$SCRIPT_DIR/loop-tests/run-loop-tests.sh"
run_suite "Smoke Test"          "$SCRIPT_DIR/smoke-test.sh"
run_suite "Ralph Init Tests"    "$SCRIPT_DIR/test-ralph-init.sh"
run_suite "Brownfield Loop"     "$SCRIPT_DIR/test-brownfield-loop.sh"
run_suite "Ralph CLI Tests"     "$SCRIPT_DIR/test-ralph-cli.sh"
run_suite "Run.sh Tests"        "$SCRIPT_DIR/test-run-sh.sh"
run_suite "Task Build Tests"    "$SCRIPT_DIR/test-task-build.sh"
run_suite "E2E Run"             "$SCRIPT_DIR/test-e2e-run.sh"
run_suite "E2E Task Build"      "$SCRIPT_DIR/test-e2e-task-build.sh"

# Summary
echo ""
echo "==========================================="
echo "Test Suites"
echo "==========================================="
for i in "${!SUITES[@]}"; do
  printf "%-25s ... %s\n" "${SUITES[$i]}" "${RESULTS[$i]}"
done

TOTAL=$(( PASS + FAIL ))
echo ""
echo "$PASS/$TOTAL suites passed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
