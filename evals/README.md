# Eval System

Point at any task list JSON, run the eval.

## Usage

```bash
# Single round (default: 20 iterations)
./evals/run-eval.sh evals/specs/calculator/tasks.json
./evals/run-eval.sh evals/specs/task-queue/tasks.json --iterations 25

# Multi-round (overnight, skip-and-continue)
./evals/run-eval.sh evals/specs/beast/tasks.json --rounds 5 --iterations 30

# Any task list — not limited to bundled examples
./evals/run-eval.sh ~/my-project/tasks.json --iterations 25 --rounds 3
```

### Flags

- `--rounds N` — Number of rounds (default: 1). When >1, uses multi-round logic with skip-and-continue.
- `--iterations M` — Max iterations per round (default: 20).

### Multi-round mode

When `--rounds > 1`, the runner uses skip-and-continue logic: when Ralph gets stuck on a story, it marks it as skipped and starts a new round. Designed for overnight unattended runs. Must be run from a plain terminal (not inside Claude Code).

### Post-run analysis

```bash
bash evals/analyse-run.sh evals/runs/<timestamp>/
```

Auto-detects single vs multi-round runs.

## Toy Projects

**calculator** — Baseline. 5 simple stories. Run this first.

**task-queue** — Stress-test. 10 stories covering async testing, refactoring, cross-module integration.

**beast** — Large-scale. 20 stories, 4 workstreams, infrastructure-first architecture.

## Infrastructure Tests

Infrastructure tests (loop mechanics, smoke, init, CLI, etc.) live in `tests/`:

```bash
bash tests/run-tests.sh
```

These are free (no API calls). Eval runs cost API credits.

## Directory Layout

```
evals/
  run-eval.sh              # Single entry point: takes task list path + flags
  multi-round.sh           # Multi-round loop logic (used when --rounds > 1)
  analyse-run.sh           # Post-run diagnostics
  scorecard-template.md    # Manual scoring template
  failure-taxonomy.md      # Reference: known failure patterns
  prompt-changelog.md      # Reference: prompt version tracking
  README.md
  specs/
    calculator/tasks.json, expected.md
    task-queue/tasks.json, expected.md
    beast/tasks.json, expected.md
  runs/                    # Gitignored — eval output

tests/
  run-tests.sh             # Runs all infrastructure tests
  smoke-test.sh            # Scaffold + build validation
  test-ralph-init.sh       # ralph init command tests
  test-brownfield-loop.sh  # Engine tests with .ralph/ layout
  test-ralph-cli.sh        # CLI dispatcher tests
  test-run-sh.sh           # run.sh error path tests
  lib/
    assert.sh              # Shared test helpers
  loop-tests/
    run-loop-tests.sh, mock-claude.sh
    test-circuit-breaker.sh, test-exit-detection.sh
    test-rate-limiting.sh, test-hook-blocking.sh
```

## Notes

- `evals/runs/` is gitignored. Eval output stays local.
- Use `scorecard-template.md` for manual assessment after eval runs.
- Track failure patterns in `failure-taxonomy.md`.
