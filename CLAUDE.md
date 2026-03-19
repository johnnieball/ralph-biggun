# ralph-greenfield

Autonomous TDD development loop powered by Claude Code. Scaffolds greenfield projects or initialises in existing (brownfield) codebases.

## Entry Points

- `ralph` — CLI dispatcher: `ralph init`, `ralph run`, `ralph task-build`
- `create-project.sh` — Greenfield: scaffolds Bun/TS project with `.ralph/` inside
- `commands/init.sh` — Brownfield: initialises `.ralph/` in any existing project
- `commands/task-build.sh` — Generates task list JSON from a markdown spec via iterative refinement
- `commands/run.sh` — Unified run wrapper: detects `.ralph/` or legacy layout

## Workflows

### Greenfield (new Bun/TS project)

1. `./create-project.sh ~/projects/my-app my-tasks.json [plan-name]`
2. `/task-review [plan-name]` in Claude Code
3. `ralph run 20 [plan-name]`

### Brownfield (existing project, any stack)

1. `ralph init [--stack <preset>] [target-dir]`
2. `ralph task-build my-spec.md [plan-name]` — generates `.ralph/specs/tasks-<plan>.json`
3. `/task-review [plan-name]` in Claude Code
4. `ralph run 20 [plan-name]`

`task-build` is the automated linter — fixes mechanical issues (oversized stories, missing deps, ambiguous AC). `/task-review` is the interactive code review — qualitative issues, scope, architecture.

## Engine

- `engine/ralph.sh` — The loop: fresh Claude `--print` per iteration, circuit breakers, rate limiting
- `engine/prompt.md` — Iteration prompt (RED-GREEN-REFACTOR, `__PLACEHOLDER__` tokens)
- `engine/task-build-prompt.md` — Task list generation/refinement prompt (`__PLACEHOLDER__` tokens)
- `engine/snapshot.sh` — Codebase snapshot between iterations (typescript, python, generic parsers)

Config variables in `.ralph/config.sh` or `.ralphrc` control layout paths, test/lint/typecheck commands, and snapshot settings. See `presets/` for stack-specific defaults.

## Testing

TDD is mandatory. RED-GREEN-REFACTOR. Vertical slices only.

- Tests verify behaviour through public interfaces
- Mock only at system boundaries (external APIs, databases, time, file system)
- Never mock your own code
- One test, one implementation, repeat — no horizontal slicing
- See `skills/tdd/SKILL.md` for complete methodology

Infrastructure tests: `tests/run-tests.sh` (no API calls needed).

## Agent Usage

Use sub-agents liberally for independent tasks to maximise time efficiency and preserve context window.

## Progress File Hygiene

`progress.txt` costs context budget every iteration. Keep entries concise. When a sprint completes, archive old entries to `progress-archive-YYYY-MM-DD.txt` and keep only the last 5-10 entries plus the `## Codebase Patterns` section.
