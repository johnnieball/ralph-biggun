# Ralph — Autonomous TDD Development Loop

Ralph is an autonomous TDD development loop powered by Claude Code. This file contains Ralph-specific instructions for the autonomous agent.

## Commands

- `__TEST_CMD__` — run tests
- `__TYPECHECK_CMD__` — type checking
- `__LINT_CMD__` — linting

## How It Works

1. User starts autonomous loop: `.ralph/engine/ralph.sh 20 [plan-name]`
2. Each iteration: fresh Claude process reads task list + progress, picks highest-priority incomplete story, does RED-GREEN-REFACTOR, commits, appends to progress
3. Circuit breakers halt on: no progress (3 loops), same error (5 loops), rate limits

## Testing Strategy

TDD is mandatory. RED-GREEN-REFACTOR. Vertical slices only.

- Tests verify behaviour through public interfaces
- Mock only at system boundaries (external APIs, databases, time, file system)
- Never mock your own code
- One test, one implementation, repeat — no horizontal slicing
- See `.ralph/skills/tdd/SKILL.md` for complete methodology

## Ralph Loop

This project is developed autonomously via `.ralph/engine/ralph.sh`.

- Each iteration reads the active task list from `.ralph/specs/tasks-<plan>.json`
- Plan selection: CLI arg > `RALPH_PLAN` in `.ralph/config.sh`
- Progress is tracked in `.ralph/progress.txt`
- Commits use `RALPH:` prefix
- Protected files: `.ralph/engine/`, `.ralph/specs/`, `.ralph/skills/`, `.ralph/config.sh`, `.ralph/progress.txt`, `CLAUDE.md`
- Run with: `.ralph/engine/ralph.sh 20 [plan-name]`
- If `.ralph/specs/architecture.md` exists and has been filled in, read it at the start of each iteration. Check your planned changes against the dependency rules and hard constraints.

## Progress File Hygiene

`.ralph/progress.txt` is consumed on every iteration and costs context budget. Keep entries concise — sacrifice grammar for brevity. When a sprint or major feature is complete, archive old entries:

1. Move completed entries to `progress-archive-YYYY-MM-DD.txt`
2. Keep only the `## Codebase Patterns` section and the last 5-10 entries in `.ralph/progress.txt`
3. The archive is for human reference only — Ralph doesn't read it

## Agent Usage

Use sub-agents liberally for independent tasks to maximise time efficiency and preserve context window.

## Codebase Patterns

(Patterns will be added here by Ralph during iterations)
