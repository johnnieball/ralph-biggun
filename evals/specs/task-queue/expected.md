# Stress Test: Task Queue - Expected Outcomes

## What this project tests

This is deliberately harder than calculator. It's designed to probe the failure modes that appear on real projects but not on trivial ones.

| Story  | What it stress-tests                                            |
| ------ | --------------------------------------------------------------- |
| US-001 | Foundational architecture choices that ripple forward           |
| US-002 | Async testing, time mocking, observing mid-execution state      |
| US-003 | Forced refactoring of earlier code, timer mocking               |
| US-004 | Cross-module integration, error isolation in callbacks          |
| US-005 | Major architectural shift mid-project, promise-based testing    |
| US-006 | Dependency injection, system boundary mocking done right        |
| US-007 | Retrofitting into existing pipeline, handler signature change   |
| US-008 | Data structure refactor with backward compatibility             |
| US-009 | State machine complexity, interaction between multiple features |
| US-010 | TypeScript generics threading through existing code             |

## Success criteria

- All 10 stories reach `passes: true`
- Expected iteration count: 10-18 (one per story, plus likely refactoring iterations at US-003, US-005, US-007)
- Tests should number 30+ (multiple behaviours per story)
- Clean exit via EXIT_SIGNAL or `<promise>COMPLETE</promise>`
- No circuit breaker activations

## Acceptable outcomes

- 15-20 iterations (some refactoring needed is fine)
- Minor gold-plating in later stories (e.g. adding helper methods)
- Needing a couple of extra iterations on US-005 or US-007 (these are genuinely hard pivot points)

## Failure modes to watch for

### High probability

- **PE-03 (Batching)** at US-001/US-002 - these look simple enough the agent might try to knock both out
- **PE-01 (Horizontal slicing)** at US-003 - multiple retry behaviours tempt writing all tests first
- **PE-04 (Gold-plating)** at US-005 - queue is a natural place to add features not in the task list
- **PE-08 (Ignored reference files)** - does the agent read the TDD skill before US-001?

### Medium probability

- **PE-09 (Mock overuse)** at US-006 - mocking the logger in job tests instead of injecting it
- **CB-01 (False circuit breaker)** at US-005/US-007 - if a refactoring iteration modifies files but doesn't commit (e.g. tests fail, agent can't fix in one iteration)
- **PE-02 (GREEN before RED)** at US-007 - timeout is tempting to implement first then test

### Lower probability but severe

- **PE-05 (No exit)** - with 10 stories there's more surface area for the agent to find "improvements"
- **PE-10 (Test errors not failures)** at US-010 - TypeScript generics can cause compilation errors that look like test failures
- Agent breaks earlier tests when retrofitting US-007 (handler signature change) or US-008 (queue internals)

## What to look for in the scorecard

Beyond the standard behaviour checks, specifically examine:

1. **Refactoring quality at US-003** - did it restructure execute() or just wrap it in a retry loop?
2. **DI pattern at US-006** - did it inject the logger or mock the filesystem?
3. **Handler signature at US-007** - did it update all existing tests when adding the abort signal?
4. **Backward compatibility at US-008** - do the US-005 FIFO tests still pass unchanged?
5. **Generic threading at US-010** - do generics flow through createJob → queue.add → getJob correctly?

## Comparison with calculator baseline

The calculator baseline was: 5 stories, 5 iterations, 19 tests, clean exit.

This project should surface failure modes the calculator couldn't. If it achieves a clean run on the first attempt, either the prompt is excellent or the project isn't hard enough - consider adding an 11th story that requires a cross-cutting refactor (e.g. "all operations are cancellable").
