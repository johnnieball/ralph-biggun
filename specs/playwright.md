# Three-Tier Browser Testing for Ralph

## What This Is

Ralph gains browser-based testing at three levels, integrated into the existing TDD loop:

1. **Component tests** — mount individual components in a browser during TDD (fast, no full app)
2. **Phase-end E2E** — run journey tests at phase boundaries during the build (catch integration bugs early)
3. **Final E2E gate** — full journey suite after all stories complete (final validation before exit)

This spec covers the task schema changes, engine changes, skill updates, and the E2E runner needed to support all three tiers.

---

## The Stack

**Playwright** (`@playwright/test`) with JSON reporter. Headless Chromium. CLI execution via bash — no MCP server.

**Accessibility tree** is the primary page representation for diagnostics. When a test fails, capture `page.accessibility.snapshot()` — not raw HTML. The a11y tree uses 51-79% fewer tokens than DOM HTML while giving better signal about what a user can interact with. Output is YAML: roles, labels, hierarchy.

**Screenshots on failure** as secondary diagnostic. Base64 in the JSON report. Use alongside a11y tree when the tree alone doesn't explain layout/visual issues.

**Component testing** via `@playwright/experimental-ct-react` (or Vue/Svelte equivalents). Mounts a single component in a real browser without the full app. Added as a later-phase optimisation after the E2E gate is working.

---

## Task Schema Changes

### New top-level fields

```json
{
  "phases": [
    {
      "id": "PH-1",
      "name": "Authentication",
      "description": "Sign up, log in, password reset",
      "stories": ["US-001", "US-002", "US-003", "US-004"],
      "journeys": ["J-1", "J-2"]
    }
  ],
  "journeys": [
    {
      "id": "J-1",
      "title": "New user sign-up to dashboard",
      "phase": "PH-1",
      "steps": [
        "Navigate to /signup",
        "Fill email [data-testid=signup-email] and password [data-testid=signup-password]",
        "Click submit [data-testid=signup-submit]",
        "Expect redirect to /dashboard",
        "Expect welcome message visible [data-testid=welcome-banner]"
      ],
      "dependsOn": ["US-001", "US-003"]
    }
  ]
}
```

### Journey format

Each journey is a cross-story user flow. Steps are natural language with embedded locator hints (`[data-testid=...]`). Claude generates the Playwright test file from these steps.

Rules for journeys:

- Each journey spans at least 2 stories (single-story flows are unit tests, not journeys)
- Steps reference `data-testid` values that must exist in the app code
- A journey's `dependsOn` lists every story that must pass before this journey is testable
- `phase` links the journey to when it should first run
- Keep journeys focused — one user goal per journey, 3-8 steps typical

### Phase structure

Phases group related stories into logical build stages. Task-build assigns phases; they don't need to be explicit in the input spec.

Rules for phases:

- Every story belongs to exactly one phase
- Phases are ordered — PH-1 before PH-2, etc.
- A phase is "complete" when all its stories have `passes: true`
- Infrastructure/setup stories (US-001 etc.) typically form PH-1
- Integration validation stories form the final phase

### Story-level additions

Stories gain one optional field:

```json
{
  "e2eTestFile": null
}
```

When Claude generates a Playwright test file during a TDD iteration, it records the path here. The E2E runner uses this to find test files. This is set by the engine during story execution, not by task-build.

---

## When Each Tier Runs

### Tier 1: Component tests (during TDD)

Deferred — implement after tiers 2 and 3 are working. When added:

- Run during the normal TDD iteration alongside unit tests
- Use `@playwright/experimental-ct-*` to mount single components
- Same RED-GREEN-REFACTOR cycle, just in a real browser
- Configured via `COMPONENT_TEST_CMD` in config

### Tier 2: Phase-end E2E (during build)

After the engine marks the last story in a phase as `passes: true`:

1. Check if the completed phase has journeys
2. If yes, spin up the app and run only that phase's journey tests
3. If all pass, continue to next phase
4. If any fail, enter the repair loop (see below)
5. Phase-end runs are quick — typically 2-4 journey tests, 30-60 seconds

The engine detects phase completion by checking: "Did I just set `passes: true` on a story, and are all stories in that story's phase now passing?"

### Tier 3: Final E2E gate (after all stories)

After the engine detects COMPLETE (all stories pass):

1. Run the full journey suite — every journey across all phases
2. If all pass, exit successfully
3. If any fail, enter the repair loop
4. This is the last thing before Ralph exits

---

## Playwright Configuration

Generated into the target project during `ralph init` (or the first E2E story):

```
retries: 0              // Ralph owns retry logic
workers: 4              // parallel execution
timeout: 10000          // 10s per action
reporter: json          // structured output
screenshot: only-on-failure
trace: on-first-retry
webServer: {
  command: E2E_START_CMD from config
  port: E2E_PORT from config
  reuseExistingServer: true
}
```

Test files live in `e2e/` at the project root. One file per journey, named `e2e/j-001-sign-up-to-dashboard.spec.ts`.

---

## Test Authoring (Engine Prompt Instructions)

During TDD iterations, when a story involves UI:

- Add `data-testid` attributes to all interactive elements. Non-negotiable.
- Generate the Playwright test file for any journey that becomes fully testable (all `dependsOn` stories now pass). Write the file but don't execute it.
- Record the test file path in the story's `e2eTestFile` field.
- Use semantic locators: `getByRole('button', { name: 'Submit' })` preferred, `getByTestId('submit')` as fallback.
- Test user-visible behaviour, not implementation.

---

## E2E Runner (`engine/e2e-gate.sh`)

Called by `ralph.sh` at phase boundaries and after COMPLETE.

### Interface

```bash
# Phase-end: run specific phase's journeys
./engine/e2e-gate.sh --phase PH-1 --tasks-path .ralph/specs/tasks-plan.json

# Final gate: run all journeys
./engine/e2e-gate.sh --all --tasks-path .ralph/specs/tasks-plan.json
```

### Flow

1. Read task JSON, extract journeys to run (filtered by phase or all)
2. Find corresponding test files in `e2e/`
3. Start the app if not running (`E2E_START_CMD`)
4. Run Playwright: `npx playwright test [files] --reporter=json`
5. Parse JSON results
6. If all pass → exit 0
7. If failures → enter repair loop

### Repair Loop

For each failed test:

1. **Capture** — error message + a11y tree snapshot + screenshot (from Playwright JSON output)
2. **Triage** — classify by pattern matching on error message:
   - Timeout / waitFor → `flaky` → retry (up to 2 retries)
   - "locator not found" / "no element matches" / assertion mismatch → `stale_test` → repair test
   - HTTP 5xx / business logic failure → `real_bug` → repair app code
   - ECONNREFUSED / EADDRINUSE → `environment` → retry or skip
   - Inconclusive → call Claude to classify
3. **Repair** — run `claude --print` with: error, a11y tree, screenshot, test file, relevant app code. Prompt asks Claude to fix the test (stale) or the app code (real bug).
4. **Rerun** — rerun only the failed test
5. **Circuit breakers**:
   - Max 3 repair attempts per individual test
   - Max 5 total failures across all tests in one E2E run → abort (systemic issue)
   - 15-minute time budget for entire E2E gate (phase-end or final) → abort if exceeded

Exit codes:

- 0 = all journeys pass
- 1 = failures remain after repair attempts (escalate to human)
- 2 = aborted (circuit breaker or timeout)

---

## Config Additions

Added to preset templates and `.ralph/config.sh`:

```bash
# E2E testing
E2E_ENABLED=false          # opt-in per project
E2E_START_CMD=""           # e.g. "npm run dev", "bun run dev"
E2E_PORT=3000              # port the app listens on
E2E_SEED_CMD=""            # e.g. "npm run db:seed" — runs before each E2E suite
E2E_MAX_FAILURES=5         # abort after this many failures in one run
E2E_TIMEOUT=900            # 15 minutes total budget per gate
E2E_REPAIR_MAX=3           # max repair attempts per failed test
```

---

## Data Seeding

Before each E2E run (phase-end or final):

1. If `E2E_SEED_CMD` is set, run it
2. This resets the app to a known state — clean database, test fixtures loaded
3. Journeys must be written assuming the seeded state, not state left over from previous tests
4. If no seed command, journeys must be self-contained (create their own data, clean up after)

---

## Failure Triage Detail

| Signal                                    | Category    | Action                  |
| ----------------------------------------- | ----------- | ----------------------- |
| `TimeoutError`, `waitFor` timeout         | Flaky       | Retry with 2x timeout   |
| `locator not found`, `no element matches` | Stale test  | Repair test selectors   |
| Assertion mismatch (expected vs received) | Stale test  | Repair test assertions  |
| HTTP 500, 502, server error in response   | Real bug    | Repair app code via TDD |
| Form validation not matching spec         | Real bug    | Repair app code via TDD |
| `ECONNREFUSED`, `EADDRINUSE`              | Environment | Retry once, then skip   |
| Crash / segfault                          | Environment | Abort                   |

Pattern matching handles ~80% of cases. For the remaining ~20%, the repair prompt includes the error + a11y tree and asks Claude to classify before fixing.

---

## Task-Build Prompt Changes

Task-build needs to:

1. **Group stories into phases** — assign a `phase` to each story based on functional area
2. **Generate journeys** — for each phase, identify cross-story user flows and write journey definitions with locator hints
3. **Place phase markers** — ensure phases are ordered and every story belongs to one
4. **Include data-testid hints in acceptance criteria** — when a criterion involves UI interaction, specify the testid value in the criterion text
5. **Only generate journeys when the project has a UI** — API-only projects skip browser testing entirely

---

## Task-Review Skill Changes

Task-review gains these additional mechanical checks:

1. **Phase completeness** — every story belongs to a phase, phases are sequential
2. **Journey coverage** — every phase with UI stories has at least one journey
3. **Journey dependencies** — journey `dependsOn` includes all stories referenced by its steps
4. **Locator consistency** — `data-testid` values referenced in journey steps appear in acceptance criteria of the stories they depend on
5. **Phase sizing** — flag phases with more than 8 stories (too large, suggest splitting)
6. **Journey length** — flag journeys with more than 10 steps (too complex, suggest splitting)

---

## Engine Prompt Changes

Add to the engine prompt:

1. **data-testid rule** — "When implementing UI elements, add `data-testid` attributes to all interactive elements (buttons, inputs, links, forms). Use descriptive kebab-case names. This is required for E2E testing."
2. **E2E test generation** — "After completing a story, check if any journey now has all its `dependsOn` stories passing. If so, generate the Playwright test file in `e2e/` and record the path in the story's `e2eTestFile` field. Write the test but do not execute it."
3. **Phase awareness** — "After marking a story as `passes: true`, check if all stories in its phase now pass. If so, note `PHASE_COMPLETE: PH-X` in the RALPH_STATUS block."

New RALPH_STATUS field:

```
PHASE_COMPLETE: PH-X  (or empty if no phase just completed)
```

---

## TDD Skill Changes

Add a section on the three testing tiers:

- **Unit/integration tests** — run every iteration. Test logic through public interfaces. No browser.
- **E2E test files** — written during TDD when journeys become testable. Not executed during TDD.
- **Component tests** (future) — mount single components in a real browser during TDD.

Emphasise: writing the E2E test file is part of the TDD iteration. Executing it is not. The test file captures the expected journey behaviour while Claude has full context of the code it just wrote.

---

## `ralph.sh` Changes

After the iteration loop, before final exit:

```
if E2E_ENABLED and exit_reason == "complete":
    run engine/e2e-gate.sh --all --tasks-path $TASKS_PATH
    if exit code != 0:
        # E2E failures — re-enter loop with E2E repair context
        # (or escalate to human if circuit breaker tripped)
```

During the iteration loop, after marking a story complete:

```
if E2E_ENABLED and RALPH_STATUS contains PHASE_COMPLETE:
    run engine/e2e-gate.sh --phase PH-X --tasks-path $TASKS_PATH
    if exit code != 0:
        # Phase E2E failures — next iteration gets repair context
```

---

## What NOT to Do

- Don't use the Playwright MCP server. CLI execution via bash is simpler and sufficient.
- Don't set up visual regression testing (Percy, Chromatic, Applitools). Consider later on a nightly schedule.
- Don't send raw HTML to the LLM. Use the accessibility tree.
- Don't build a separate triage agent. Triage logic lives in the E2E runner script.
- Don't use Playwright's built-in retry mechanism. Ralph owns retries.
- Don't use AI-native testing platforms (Shortest, QA Wolf, Autify). Ralph needs programmatic control.
- Don't use computer-use/browser-use agents. 10-15x slower than Playwright.
- Don't implement component testing (tier 1) until tiers 2 and 3 are proven.
- Don't generate journeys for API-only projects.

---

## Implementation Order

1. Task schema changes (add phases, journeys, e2eTestFile to JSON schema)
2. Task-build prompt (phase grouping, journey generation, data-testid hints)
3. Task-review skill (phase/journey validation checks)
4. Engine prompt (data-testid rule, E2E test generation, PHASE_COMPLETE signal)
5. TDD skill (three-tier testing section)
6. E2E runner script (`engine/e2e-gate.sh`)
7. `ralph.sh` integration (phase-end and final gate hooks)
8. Config/preset additions (E2E settings)
9. Tests for E2E runner and phase detection
10. Component testing tier (deferred — after above is proven)

---

## Token Budget

Per triage-and-repair cycle: ~2,500-5,000 tokens (a11y tree keeps it manageable — ~10K tokens for a typical page vs 20-77K for raw HTML).

Phase-end E2E: 2-4 journeys, 30-60 seconds. Negligible cost if tests pass. ~5K tokens per failure if repair needed.

Final gate: full suite, 2-5 minutes. Fine for autonomous runs.

The real cost is time, not tokens. Each phase-end E2E adds 30-60 seconds. Acceptable tradeoff for catching integration bugs 15 stories earlier.
