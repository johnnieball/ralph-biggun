# Calculator Eval — Expected Outcomes

## Success Criteria

- All 5 user stories reach `passes: true`
- Expected iteration count: 5-10 (one story per iteration, plus possible refactoring iterations)
- Tests should exist for each story (at minimum 5 test files or 5 describe blocks)
- `progress.txt` should have entries for each story
- The agent should exit via EXIT_SIGNAL or `<promise>COMPLETE</promise>`
- Exit code should be 0

## Expected Flow

1. US-001 (add): Tracer bullet. Creates `src/calculator.ts`, writes first test, implements `add()`.
2. US-002 (subtract): Adds `subtract()` function and tests.
3. US-003 (multiply): Adds `multiply()` function and tests.
4. US-004 (divide): Adds `divide()` with division-by-zero error handling.
5. US-005 (evaluate): String expression parser using the four operations above.

## Failure Modes to Watch For

- **Getting stuck on US-005 string parsing** — The expression evaluator is the hardest story. Watch for the agent over-engineering a parser when simple regex/split would suffice.
- **Gold-plating** — Agent adds operator precedence, parentheses support, or other features not in the task list.
- **Not exiting when done** — All stories pass but agent keeps running (refactoring, adding more tests, improving code quality).
- **Horizontal slicing** — Agent writes tests for multiple stories before implementing any.
- **Batching stories** — Agent completes more than one story per iteration.
- **Mock overuse** — Agent mocks calculator functions in calculator tests instead of testing real implementations.

## Scoring Guide

| Metric            | Excellent                   | Acceptable          | Poor               |
| ----------------- | --------------------------- | ------------------- | ------------------ |
| Stories completed | 5/5                         | 4/5                 | < 4/5              |
| Iterations        | 5-7                         | 8-10                | > 10               |
| Exit condition    | Clean exit                  | Max iterations      | Circuit breaker    |
| TDD compliance    | RED before GREEN every time | Mostly RED-first    | GREEN before RED   |
| Vertical slicing  | One story per iteration     | Occasional batching | Horizontal slicing |
