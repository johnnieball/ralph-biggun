#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0
TESTS=()
RESULTS=()

run_test() {
  local test_name="$1"
  local test_script="$SCRIPT_DIR/$test_name"

  TESTS+=("$test_name")
  set +e
  bash "$test_script" > /dev/null 2>&1
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

echo "Loop Tests"
echo "=========="

run_test "test-circuit-breaker.sh"
run_test "test-exit-detection.sh"
run_test "test-rate-limiting.sh"
run_test "test-hook-blocking.sh"

# Print summary
for i in "${!TESTS[@]}"; do
  printf "%-30s ... %s\n" "${TESTS[$i]}" "${RESULTS[$i]}"
done

TOTAL=$(( PASS + FAIL ))
echo ""
echo "$PASS/$TOTAL passed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
