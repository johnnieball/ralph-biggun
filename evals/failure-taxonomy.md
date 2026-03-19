# Failure Taxonomy

Catalogue of observed failure modes across eval runs. Add new entries as they appear.

## Loop Mechanics

- **CB-01: False circuit breaker** — Circuit breaker fires despite agent making progress (e.g. agent modifies files but doesn't commit)
- **CB-02: Circuit breaker too slow** — Agent spins for many iterations before breaker fires
- **CB-03: Exit not detected** — Agent outputs exit signals but ralph.sh doesn't catch them (format mismatch)

## Prompt Effectiveness

- **PE-01: Horizontal slicing** — Agent writes multiple tests before implementing any
- **PE-02: GREEN before RED** — Agent writes implementation without a failing test first
- **PE-03: Batching stories** — Agent completes more than one story per iteration
- **PE-04: Gold-plating** — Agent adds features not in the task list
- **PE-05: No exit** — All stories pass but agent keeps running (refactoring, adding tests, etc.)
- **PE-06: Wrong exit** — Agent exits before all stories are complete
- **PE-07: Progress rot** — progress.txt grows verbose or stops being updated
- **PE-08: Ignored reference files** — Agent doesn't read TDD skill or supporting docs when relevant
- **PE-09: Mock overuse** — Agent mocks its own code instead of only system boundaries
- **PE-10: Test errors not failures** — Tests error (import, syntax) instead of failing on missing behaviour

## Skeleton

- **SK-01: Bun install failure** — Dependencies don't resolve
- **SK-02: TypeScript config issues** — typecheck fails on fresh scaffold
- **SK-03: Husky not wired** — pre-commit hook doesn't run
