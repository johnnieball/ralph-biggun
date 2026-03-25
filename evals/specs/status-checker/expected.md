# Status Checker Eval — Expected Outcomes

## Purpose

This eval tests the **integration gate** mechanism. It has 4 build stories (mocked TDD) and 2 integration stories (gated). The eval validates that:

1. Ralph completes build stories normally
2. Ralph hits the gate on US-005 and pauses (or exits in non-interactive mode)
3. Integration stories remain `passes: false` after a non-interactive run

## Success Criteria

### Build phase (US-001 through US-004)

- All 4 build stories reach `passes: true`
- Expected iteration count: 4-8
- Tests use injected fetcher (mock at system boundary), not real HTTP
- Agent follows RED-GREEN-REFACTOR for each story

### Integration gate (US-005)

- Ralph displays the "INTEGRATION GATE" banner
- Gate message mentions `STATUS_CHECKER_API_URL` and `STATUS_CHECKER_DB_URL`
- In non-interactive mode (eval default): Ralph exits with code 2
- In interactive mode: Ralph pauses for user input, then continues

### Post-gate (if run interactively past the gate)

- US-005 and US-006 use real `fetch`, no mocks
- Tests exercise actual HTTP connectivity
- If endpoints are unreachable, agent sets STATUS: BLOCKED (not stuck in a retry loop)

## Expected Flow

1. US-001: Creates `src/status-checker.ts`, implements `checkEndpoint` with DI fetcher
2. US-002: Adds `checkAll` with concurrent execution
3. US-003: Adds `summarise` function
4. US-004: Adds `getAlerts` with threshold rules
5. **GATE** — Ralph pauses (interactive) or exits code 2 (non-interactive)
6. US-005: Tests real connectivity (only if user proceeds past gate)
7. US-006: Full pipeline smoke test (only if user proceeds past gate)

## Failure Modes to Watch For

- **Gate not firing** — US-005 has `priority: "low"` and `dependsOn` build stories, so it should only be picked after US-001-004 pass. If the gate fires too early, story selection priority sorting is broken.
- **Gate firing on US-006** — Only US-005 has the `gate` field. US-006 should proceed normally after US-005.
- **Mocking in integration stories** — US-005/006 must use real fetch. If the agent mocks HTTP in these stories, the integration gate guidance in prompt.md isn't working.
- **Build stories using real HTTP** — US-001-004 should mock the fetcher. If they make real HTTP calls, DI pattern wasn't followed.
- **Not exiting on gate (non-interactive)** — In piped/eval mode, Ralph should detect `[ -t 0 ]` is false and exit code 2. If it hangs, the terminal detection is broken.

## Scoring Guide

| Metric           | Excellent                          | Acceptable            | Poor                  |
| ---------------- | ---------------------------------- | --------------------- | --------------------- |
| Build stories    | 4/4 pass                           | 3/4 pass              | < 3/4                 |
| Gate fires at    | US-005 (after build phase)         | —                     | During build phase    |
| Non-interactive  | Exits code 2 with banner           | —                     | Hangs or exits code 1 |
| Build iterations | 4-6                                | 7-8                   | > 8                   |
| Mock discipline  | DI fetcher in build, real in integ | Mostly correct        | Mocks in integration  |
| Exit condition   | Code 2 (gate)                      | Code 0 (all complete) | Circuit breaker       |
