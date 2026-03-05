# Eval System

Three testing layers for the Ralph loop template.

## Layers

### 1. Loop Mechanics (`evals/loop-tests/`)

Deterministic tests for ralph.sh's bash logic. Uses `mock-claude.sh` to simulate Claude CLI output with zero API calls. Tests circuit breakers, exit detection, rate limiting, and git hook blocking.

```bash
./evals/run-eval.sh loop
```

### 2. Skeleton Integrity (`evals/smoke-test.sh`)

Tests that the project scaffolds correctly: `bun install`, `bun run test`, `bun run typecheck`, git init, placeholder replacement, and self-cleanup of eval artefacts.

```bash
./evals/run-eval.sh smoke
```

### 3. Prompt Effectiveness (`evals/toy-projects/`)

End-to-end eval using real API calls against toy projects. Runs the full Ralph loop and captures results for manual scoring.

```bash
./evals/run-eval.sh prompt                 # calculator (default, 15 iterations)
./evals/run-eval.sh prompt calculator      # explicit calculator
./evals/run-eval.sh prompt task-queue      # task-queue (20 iterations default)
./evals/run-eval.sh prompt task-queue 25   # task-queue with custom iteration limit
```

#### Toy Projects

**calculator** — Baseline project. 5 simple stories (add, subtract, multiply, divide, expression parser). Validates the basic loop works: vertical slicing, TDD, clean exit. Run this first.

**task-queue** — Stress-test project. 10 stories covering architectural decisions, async testing, refactoring existing code, system boundary mocking (timers, file system), cross-module integration, dependency injection, and TypeScript generics. Designed to expose failure modes that trivial projects cannot. Run this after the calculator baseline passes.

### 4. Beast Mode (`evals/beast-wrapper.sh`)

Overnight eval for large, multi-workstream projects. Runs the full Ralph loop in rounds with skip-and-continue logic — when the agent gets stuck on a story, the wrapper marks it as skipped and starts a new round.

```bash
./evals/run-eval.sh beast              # defaults: 5 rounds, 30 iterations per round
./evals/run-eval.sh beast 3 20         # 3 rounds, 20 iterations per round
./evals/beast-wrapper.sh 5 30          # direct invocation
```

**What it tests:** Infrastructure-first architecture, file I/O, external dependencies (Puppeteer, markdown libraries), schema-driven development with Zod discriminated unions, multi-workstream projects (4 semi-independent workstreams, 20 stories), cross-cutting refactors, plugin architecture, and configuration layering.

**How it works:**

1. Scaffolds a fresh build directory from the template
2. Copies the beast `prd.json` (20 stories) into `plans/`
3. Runs `ralph.sh` for up to N iterations per round
4. When Ralph exits (circuit breaker, max iterations, or timeout):
   - Detects API-level failures (zero commits + few iterations) and pauses gracefully
   - Otherwise identifies the stuck story from the output log
   - Marks it as `"skipped"` in `prd.json` and appends a skip notice to `progress.txt`
   - Starts a new round — Ralph picks up the next unfinished story
5. Repeats for up to M rounds or until all stories are done
6. Produces per-round logs, a final summary, and a scorecard template

**Morning debrief:** Check `evals/runs/<timestamp>-beast/`:

- `summary.txt` — total rounds, per-round breakdown, final tally of passed/skipped/remaining
- `round-N-ralph-output.log` — full Ralph output for each round
- `round-N-prd.json` — prd.json snapshot after each round (shows progression)
- `final-prd.json` — final state of all stories
- `scorecard.md` — scoring template
- `paused-build-dir.txt` — if the run paused due to API failure, contains the temp dir path for manual resumption

**Important:** Beast mode is designed for overnight unattended runs. It is NOT included in `./evals/run-eval.sh all` — run it separately. Must be run from a plain terminal (not inside Claude Code).

## Directory Layout

```
evals/
  README.md              # This file
  run-eval.sh            # Orchestrator: loop | smoke | prompt | beast | all
  analyse-run.sh         # Post-run analysis (detects standard vs beast runs)
  beast-wrapper.sh       # Overnight multi-round runner with skip-and-continue
  scorecard-template.md  # Manual scoring template
  failure-taxonomy.md    # Catalogue of observed failure modes
  prompt-changelog.md    # Track prompt changes vs eval results
  loop-tests/
    mock-claude.sh       # Fake Claude CLI for deterministic testing
    test-circuit-breaker.sh
    test-exit-detection.sh
    test-rate-limiting.sh
    test-hook-blocking.sh
    run-loop-tests.sh    # Runs all loop tests
  scaffold.sh            # In-place project scaffolding for eval runs
  smoke-test.sh
  toy-projects/
    calculator/
      prd.json           # Toy PRD with 5 user stories
      expected.md        # What a successful run looks like
    task-queue/
      prd.json           # Stress-test PRD with 10 user stories
      expected.md        # Expected outcomes and failure modes to watch for
    beast/
      prd.json           # 20-story static site generator PRD
      expected.md        # Expected outcomes, workstream map, failure points
  runs/                  # Gitignored — prompt eval output goes here
    .gitkeep
```

## Notes

- `evals/runs/` is gitignored. Eval output stays local.
- The `evals/` directory is stripped during scaffolding (both `create-project.sh` and `evals/scaffold.sh`).
- Loop tests and smoke tests are free (no API calls). Run them liberally.
- Prompt evals cost API credits. Run sparingly and review results with `analyse-run.sh`.
- Use `scorecard-template.md` for manual assessment after prompt evals.
- Track failure patterns in `failure-taxonomy.md`.
