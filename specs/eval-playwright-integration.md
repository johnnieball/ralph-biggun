# Eval: Playwright E2E Integration

Run this eval to verify the three-tier browser testing integration described in `specs/playwright.md`. Execute every section in order. Report PASS/FAIL for each check. Stop and report if any critical check fails.

---

## Section 1: Infrastructure Tests

Run the existing test suites. These must all pass before proceeding.

```bash
bash tests/run-tests.sh
```

**Checks:**

- [ ] All test suites pass (including `test-e2e-gate.sh` and `test-phase-detection.sh`)
- [ ] Loop tests show 7/7 passed (5 existing + 2 new E2E/phase suites)

---

## Section 2: Schema Verification

Verify the task-build prompt contains the correct schema. Read `engine/task-build-prompt.md` and check:

- [ ] JSON schema includes `phases` array with fields: `id`, `name`, `description`, `stories`, `journeys`
- [ ] JSON schema includes `journeys` array with fields: `id`, `title`, `phase`, `steps`, `dependsOn`
- [ ] Each journey step example contains `[data-testid=...]` locator hints
- [ ] `userStories` schema includes `e2eTestFile: null`
- [ ] Generation rules include "data-testid hints in acceptance criteria"
- [ ] Phases section exists with rules (every story in one phase, sequential IDs, max 8 stories)
- [ ] Journeys section exists with rules (span 2+ stories, 3-8 steps, locator hints, API-only skip)
- [ ] Refinement criteria include items 7-10: phase completeness, journey coverage, journey dependencies, locator consistency

---

## Section 3: Task-Build End-to-End

Create a small UI-focused spec, run task-build, and verify the output has all new fields.

### 3a. Create a test spec

Write this file to a temp location:

```markdown
# Todo App

A simple web-based todo list application.

## Tech Stack

- Bun + TypeScript
- React with Vite
- Vitest for testing

## Features

### Authentication

- Sign up with email and password
- Log in with existing credentials
- Log out from any page

### Todo Management

- Create a new todo item with a title
- Mark a todo as complete
- Delete a todo item
- View all todos on a dashboard

### UI

- Navigation bar with login/logout button
- Dashboard page showing all todos
- Sign-up and login forms
```

### 3b. Run task-build

```bash
ralph task-build <temp-spec-path> eval-pw-test 5
```

### 3c. Verify the generated task list

Read the generated task file (`.ralph/specs/tasks-eval-pw-test.json` or `specs/tasks-eval-pw-test.json` depending on layout) and check:

- [ ] `phases` array exists and has at least 2 phases
- [ ] Every phase has `id` (PH-N format), `name`, `stories`, `journeys`
- [ ] Every story ID in every phase's `stories` array exists in `userStories`
- [ ] No story appears in more than one phase
- [ ] All stories appear in exactly one phase
- [ ] `journeys` array exists and has at least 2 journeys
- [ ] Every journey has `id` (J-N format), `title`, `phase`, `steps`, `dependsOn`
- [ ] Every journey spans at least 2 stories in its `dependsOn`
- [ ] Journey steps contain `[data-testid=...]` hints
- [ ] `data-testid` values in journey steps appear in acceptance criteria of dependent stories
- [ ] Every `userStories` entry has `e2eTestFile` field (should be `null`)
- [ ] At least some acceptance criteria contain `[data-testid=...]` hints
- [ ] Phases are sequential (PH-1, PH-2, PH-3, etc.)
- [ ] No phase has more than 8 stories

### 3d. Clean up

Delete the generated task file and temp spec.

---

## Section 4: Task-Review Skill Verification

Read `.claude/skills/task-review/SKILL.md` and check:

- [ ] Mechanical issues section includes item 7: "Phase completeness"
- [ ] Mechanical issues section includes item 8: "Journey coverage"
- [ ] Mechanical issues section includes item 9: "Journey dependencies"
- [ ] Mechanical issues section includes item 10: "Locator consistency"
- [ ] Mechanical issues section includes item 11: "Phase sizing" (flag >8 stories)
- [ ] Mechanical issues section includes item 12: "Journey length" (flag >10 steps)

---

## Section 5: Engine Prompt Verification

Read `engine/prompt.md` and check:

- [ ] DATA-TESTID RULE section exists with instruction to add `data-testid` to interactive elements
- [ ] E2E TEST GENERATION section exists with instructions to generate Playwright test files
- [ ] E2E test files go in `e2e/` directory, named `e2e/j-NNN-kebab-title.spec.ts`
- [ ] `e2eTestFile` field gets recorded on the story
- [ ] RALPH_STATUS block includes `PHASE_COMPLETE: <PH-X or empty>`
- [ ] Phase completion detection section explains when to set PHASE_COMPLETE

---

## Section 6: TDD Skill Verification

Read `skills/tdd/SKILL.md` and check:

- [ ] "Three-Tier Browser Testing" section exists
- [ ] Tier 1 described: unit/integration tests during TDD (no browser)
- [ ] Tier 2 described: E2E test files written during TDD but NOT executed
- [ ] Tier 3 described: component tests (deferred)
- [ ] Emphasis that writing E2E file is part of TDD iteration, executing is not

---

## Section 7: E2E Gate Script Verification

Read `engine/e2e-gate.sh` and check:

- [ ] Accepts `--phase PH-X` and `--all` flags
- [ ] Accepts `--tasks-path` flag
- [ ] Loads E2E config from `.ralphrc` or `.ralph/config.sh`
- [ ] Exits 0 immediately when `E2E_ENABLED=false`
- [ ] Exits 0 when no journeys match the filter
- [ ] Exits 0 with warning when no test files exist
- [ ] Filters journeys by phase when `--phase` is used
- [ ] Runs all journeys when `--all` is used
- [ ] Runs seed command (`E2E_SEED_CMD`) before tests
- [ ] Starts app via `E2E_START_CMD` if not already running
- [ ] Runs Playwright via `npx playwright test`
- [ ] `classify_failure` function handles: flaky, stale_test, real_bug, environment, crash, unknown
- [ ] Repair loop calls `claude --print` with error context
- [ ] Circuit breakers: max failures (`E2E_MAX_FAILURES`), time budget (`E2E_TIMEOUT`), per-test repair limit (`E2E_REPAIR_MAX`)
- [ ] Exit codes: 0=pass, 1=failures remain, 2=aborted
- [ ] File is executable (`chmod +x`)

---

## Section 8: ralph.sh Integration Verification

Read `engine/ralph.sh` and check:

- [ ] E2E config defaults declared: `E2E_ENABLED`, `E2E_START_CMD`, `E2E_PORT`, `E2E_SEED_CMD`, `E2E_MAX_FAILURES`, `E2E_TIMEOUT`, `E2E_REPAIR_MAX`
- [ ] E2E config vars exported for `e2e-gate.sh` subprocess
- [ ] Phase-end E2E gate: after snapshot generation, parses `PHASE_COMPLETE` from RALPH_STATUS and calls `e2e-gate.sh --phase`
- [ ] Final E2E gate on `<promise>COMPLETE</promise>`: calls `e2e-gate.sh --all` before exiting
- [ ] Final E2E gate on `EXIT_SIGNAL: true`: calls `e2e-gate.sh --all` before exiting
- [ ] Both final gates: if E2E fails, sets `exit_reason="e2e_gate_failed"` and exits 1
- [ ] Phase-end gate: does NOT abort the build on failure (continues with repair context)
- [ ] Guard: `E2E_ENABLED = "true"` AND `-x "$ENGINE_DIR/e2e-gate.sh"` before calling

---

## Section 9: Config & Preset Verification

Check all 4 preset files and the init script:

### Presets

For each of `presets/bun-typescript.sh`, `presets/node-typescript.sh`, `presets/python.sh`, `presets/generic.sh`:

- [ ] Contains `E2E_ENABLED=false`
- [ ] Contains `E2E_START_CMD=""`
- [ ] Contains `E2E_PORT=3000`
- [ ] Contains `E2E_SEED_CMD=""`
- [ ] Contains `E2E_MAX_FAILURES=5`
- [ ] Contains `E2E_TIMEOUT=900`
- [ ] Contains `E2E_REPAIR_MAX=3`

### Init script

Read `commands/init.sh` and check:

- [ ] Fresh init copies `e2e-gate.sh` to `.ralph/engine/`
- [ ] Fresh init sets `chmod +x` on `e2e-gate.sh`
- [ ] Upgrade copies `e2e-gate.sh` to `.ralph/engine/`
- [ ] Upgrade sets `chmod +x` on `e2e-gate.sh`
- [ ] Upgrade UPGRADED array includes `engine/e2e-gate.sh`

---

## Section 10: Init Upgrade Smoke Test

Verify that `ralph init --upgrade` correctly deploys the new files to an existing project.

```bash
# Create a temp directory, init ralph, then upgrade
tmpdir=$(mktemp -d)
ralph init "$tmpdir"
ralph init --upgrade "$tmpdir"
```

- [ ] `$tmpdir/.ralph/engine/e2e-gate.sh` exists and is executable
- [ ] `$tmpdir/.ralph/engine/prompt.md` contains "PHASE_COMPLETE"
- [ ] `$tmpdir/.ralph/engine/task-build-prompt.md` contains "phases"
- [ ] `$tmpdir/.ralph/engine/task-build-prompt.md` contains "journeys"
- [ ] `$tmpdir/.ralph/config.sh` contains E2E config from preset
- [ ] `$tmpdir/.ralph/skills/tdd/SKILL.md` contains "Three-Tier Browser Testing"

Clean up: `rm -rf "$tmpdir"`

---

## Results

Tally all checks above. Report:

```
Eval: Playwright E2E Integration
=================================
Section 1 (Infrastructure Tests):  _/2
Section 2 (Schema Verification):   _/8
Section 3 (Task-Build E2E):        _/14
Section 4 (Task-Review Skill):     _/6
Section 5 (Engine Prompt):         _/6
Section 6 (TDD Skill):             _/5
Section 7 (E2E Gate Script):       _/16
Section 8 (ralph.sh Integration):  _/8
Section 9 (Config & Presets):      _/33
Section 10 (Init Upgrade Smoke):   _/6
---------------------------------
Total:                              _/104

Verdict: PASS / FAIL
```

A passing eval requires 100% on sections 1-2 and 4-10 (static checks). Section 3 (task-build E2E) requires a Claude API call — if unavailable, mark as SKIPPED and note why. The eval passes if all non-skipped sections are 100%.
