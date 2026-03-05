# ralph-greenfield

Project template for Ralph — an autonomous TDD development loop powered by Claude Code. Not an application itself; it scaffolds new projects via `create-project.sh`.

## Key Files

- `create-project.sh` — Creates a new project from this template at a target path
- `engine/ralph.sh` — The autonomous loop: spawns fresh Claude `--print` iterations, tracks progress, circuit breakers
- `engine/kickoff.sh` — Pre-flight PRD validation via one-shot Claude analysis
- `engine/prompt.md` — Prompt injected into each Ralph iteration (RED-GREEN-REFACTOR workflow)
- `engine/snapshot.sh` — Generates `codebase-snapshot.md` between iterations (file tree, exports, imports, tests)
- `specs/prd-<plan>.json` — Product requirements documents (user stories with acceptance criteria)
- `specs/architecture.md` — Module boundaries and dependency rules (populated at first iteration)
- `.ralphrc` `RALPH_PLAN=` — Selects which PRD file to use (`specs/prd-<name>.json`)
- `skills/tdd/` — TDD methodology reference (SKILL.md, mocking.md, deep-modules.md, interface-design.md, refactoring.md)
- `.ralphrc` — Loop config: rate limits, circuit breaker thresholds, allowed tools
- `.claude/settings.json` — Claude Code hooks config
- `.claude/hooks/block-dangerous-git.sh` — Blocks destructive git commands (push, reset --hard, clean -f, etc.)
- `progress.txt` — Append-only progress log consumed each iteration
- `evals/` — Evaluation tests and toy projects for testing the loop

## Commands

- `bun run dev` — watch mode (`bun run --watch src/index.ts`)
- `bun run test` — run tests (Vitest)
- `bun run typecheck` — TypeScript type checking
- `bun run lint` — linting (oxlint)
- `bun run build` — production build

## How It Works

1. User creates a project: `./create-project.sh ~/projects/my-app my-prd.json [plan-name]`
2. User reviews PRD: `./engine/kickoff.sh [plan-name]`
3. User starts autonomous loop: `./engine/ralph.sh 20 [plan-name]`
4. Each iteration: fresh Claude process reads PRD + progress, picks highest-priority incomplete story, does RED-GREEN-REFACTOR, commits, appends to progress.txt
5. Circuit breakers halt on: no progress (3 loops), same error (5 loops), rate limits

## Codebase Patterns

(Patterns will be added here by Ralph during iterations)

## Testing Strategy

TDD is mandatory. RED-GREEN-REFACTOR. Vertical slices only.

- Tests verify behaviour through public interfaces
- Mock only at system boundaries (external APIs, databases, time, file system)
- Never mock your own code
- One test, one implementation, repeat - no horizontal slicing
- See `skills/tdd/SKILL.md` for complete methodology

## Ralph Loop

This project is developed autonomously via `engine/ralph.sh`.

- Each iteration reads the active PRD from `specs/prd-<plan>.json`
- Plan selection: CLI arg > `RALPH_PLAN` in `.ralphrc`
- Progress is tracked in `progress.txt`
- Commits use `RALPH:` prefix
- Protected files: `engine/`, `specs/`, `skills/`, `.ralphrc`, `CLAUDE.md`, `progress.txt`
- Run with: `./engine/ralph.sh 20 [plan-name]`
- If `specs/architecture.md` exists and has been filled in, read it at the start of each iteration. Check your planned changes against the dependency rules and hard constraints.

## Progress File Hygiene

`progress.txt` is consumed on every iteration and costs context budget. Keep entries concise — sacrifice grammar for brevity. When a sprint or major feature is complete, archive old entries:

1. Move completed entries to `progress-archive-YYYY-MM-DD.txt`
2. Keep only the `## Codebase Patterns` section and the last 5-10 entries in `progress.txt`
3. The archive is for human reference only — Ralph doesn't read it
