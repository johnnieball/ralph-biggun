# Prompt Changelog

Track changes to prompt.md and TDD skills, paired with eval results.

## [v1.0] - Initial template

- 10-phase iteration prompt
- 6 exit scenarios as specification-by-example
- TDD skill with Iron Law, rationalisation table, red flags list
- **Baseline eval run:** `2026-02-26-135010`
- **Results:** 5/5 stories, 5 iterations, clean exit (exit code 0), 19 tests passing
- **TDD compliance:** Consistent RED-GREEN-REFACTOR. Stubs return 0, verify failure, then implement.
- **Vertical slicing:** One story per iteration, never batched.
- **Exit detection:** Clean `<promise>COMPLETE</promise>` + `EXIT_SIGNAL: true` after final story.
- **Commit format:** `RALPH: feat: [US-XXX]` prefix on every commit.
- **No gold-plating:** Nothing beyond task list scope.
- **Notes:** This is the baseline. All future changes measured against this.
- **Stress-test eval run:** `2026-02-26-153254` (task-queue)
- **Results:** 10/10 stories, 10 iterations, clean EXIT_SIGNAL (exit code 0), 42 tests passing
- **TDD compliance:** Consistent RED-GREEN. Some tests passed immediately due to comprehensive GREEN steps — agent acknowledged correctly each time. Minor PE-10 (test errors not failures) self-corrected throughout.
- **Vertical slicing:** Exactly one story per iteration across all 10. No batching.
- **Audit points:** DI done correctly at US-006 (no fs mocking), handler signature change at US-007 backward-compatible via TS bivariance, FIFO tests unchanged after priority refactor at US-008, generics threaded through full stack at US-010.
- **Behaviour score:** 37/40. Full scorecard at `evals/runs/2026-02-26-153254-task-queue/scorecard.md`.
- **Notes:** Optimal run — minimum possible iterations for 10 stories. No circuit breaker activations, no wasted iterations. Confirms v1.0 prompt handles complex multi-module projects, not just trivial calculators.
