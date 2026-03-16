# ralph-greenfield

Project template for Ralph — an autonomous TDD development loop powered by Claude Code. Supports both greenfield scaffolding (`create-project.sh`) and brownfield initialisation (`ralph init`).

## Key Files

### Entry Points

- `ralph` — CLI dispatcher: `ralph init` or `ralph run`
- `create-project.sh` — Greenfield: scaffolds Bun/TS project with `.ralph/` inside
- `commands/init.sh` — Brownfield: initialises `.ralph/` in any existing project
- `commands/run.sh` — Unified run wrapper: detects `.ralph/` or legacy layout

### Engine (copied into target projects)

- `engine/ralph.sh` — The autonomous loop: spawns fresh Claude `--print` iterations, tracks progress, circuit breakers
- `engine/prompt.md` — Prompt injected into each iteration (RED-GREEN-REFACTOR workflow, uses `__PLACEHOLDER__` tokens)
- `engine/snapshot.sh` — Generates `codebase-snapshot.md` between iterations (supports typescript, python, generic parsers)

### Configuration

- `presets/` — Stack presets (bun-typescript, node-typescript, python, generic)
- `templates/CLAUDE-ralph.md` — CLAUDE-ralph.md template with `__PLACEHOLDER__` tokens
- `.claude/skills/prd-review/` — PRD review skill: `/prd-review [plan-name]`
- `skills/tdd/` — TDD methodology reference files

### Project Layout (`.ralph/` in target projects)

```
.ralph/
├── config.sh              # Stack config (from preset)
├── engine/                # ralph.sh, prompt.md, snapshot.sh
├── skills/tdd/            # TDD methodology files
├── specs/                 # architecture.md, prd-<plan>.json
├── hooks/                 # block-dangerous-git.sh
├── progress.txt           # Append-only progress log
├── CLAUDE-ralph.md        # Ralph instructions for Claude
└── logs/                  # Iteration logs
```

### Evals

- `evals/loop-tests/` — Mock-claude engine tests (circuit breakers, exit detection, rate limiting, hook blocking)
- `evals/smoke-test.sh` — End-to-end scaffold + build test
- `evals/test-ralph-init.sh` — Init command tests (stack detection, merging, idempotency)
- `evals/test-brownfield-loop.sh` — Engine tests with `.ralph/` layout

## Commands

- `bun run dev` — watch mode (`bun run --watch src/index.ts`)
- `bun run test` — run tests (Vitest)
- `bun run typecheck` — TypeScript type checking
- `bun run lint` — linting (oxlint)
- `bun run build` — production build

## How It Works

### Greenfield (new Bun/TS project)

1. `./create-project.sh ~/projects/my-app my-prd.json [plan-name]`
2. `/prd-review [plan-name]` (in Claude Code)
3. `.ralph/engine/ralph.sh 20 [plan-name]`

### Brownfield (existing project, any stack)

1. `ralph init [--stack <preset>] [target-dir]`
2. Copy PRD to `.ralph/specs/prd-<plan>.json`, set `RALPH_PLAN` in `.ralph/config.sh`
3. `/prd-review [plan-name]` (in Claude Code)
4. `.ralph/engine/ralph.sh 20 [plan-name]` (or `ralph run 20 [plan-name]`)

### Engine Parameterisation

The engine uses config variables with defaults matching the original Bun/TS behaviour:

- `ENGINE_DIR`, `SPECS_DIR`, `SKILLS_DIR`, `PROGRESS_FILE`, `LOG_DIR` — directory layout
- `TEST_CMD`, `TYPECHECK_CMD`, `LINT_CMD` — verification commands
- `SNAPSHOT_SOURCE_DIR`, `SNAPSHOT_FILE_EXTENSIONS`, `SNAPSHOT_PARSER` — codebase snapshot config
- `TEST_COUNT_REGEX` — pattern to extract test count from output

## Agent Usage

Use sub-agents liberally for independent tasks to maximise time efficiency and preserve context window.

## Testing Strategy

TDD is mandatory. RED-GREEN-REFACTOR. Vertical slices only.

- Tests verify behaviour through public interfaces
- Mock only at system boundaries (external APIs, databases, time, file system)
- Never mock your own code
- One test, one implementation, repeat — no horizontal slicing
- See `skills/tdd/SKILL.md` for complete methodology

## Progress File Hygiene

`progress.txt` is consumed on every iteration and costs context budget. Keep entries concise — sacrifice grammar for brevity. When a sprint or major feature is complete, archive old entries:

1. Move completed entries to `progress-archive-YYYY-MM-DD.txt`
2. Keep only the `## Codebase Patterns` section and the last 5-10 entries in `progress.txt`
3. The archive is for human reference only — Ralph doesn't read it
