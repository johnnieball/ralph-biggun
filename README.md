# ralph-greenfield

Scaffold for autonomous greenfield TypeScript projects using the Ralph loop pattern.

## Usage

```bash
git clone https://github.com/axiiom/ralph-greenfield.git
cd ralph-greenfield
./create-project.sh ~/projects/my-app
```

Or with a PRD and named plan:

```bash
./create-project.sh ~/projects/my-app path/to/prd.json my-plan
```

Then review and run the loop:

```bash
cd ~/projects/my-app
./engine/kickoff.sh my-plan
./engine/ralph.sh 20 my-plan
```

Set `RALPH_PLAN=my-plan` in `.ralphrc` to avoid passing the plan name each time. Multiple plans live as `specs/prd-<name>.json`. If you omit the plan name from `create-project.sh`, it defaults to the project name.

## PRD format

Each user story needs: `id`, `title`, `description`, `acceptanceCriteria` (array), `priority` (int), `passes` (boolean, starts false), `notes` (string).

Stories must be small enough to complete in ONE iteration. Order by dependency. Include "Typecheck passes" and "Tests pass" in acceptance criteria.

```json
{
  "id": "US-001",
  "title": "Add priority field to database",
  "description": "As a developer, I need to store task priority so it persists across sessions.",
  "acceptanceCriteria": [
    "Add priority column to tasks table: 'high' | 'medium' | 'low' (default 'medium')",
    "Typecheck passes",
    "Tests pass"
  ],
  "priority": 1,
  "passes": false,
  "notes": ""
}
```

For complex projects, consider using [OpenSpec](https://github.com/Fission-AI/OpenSpec) to generate structured specs, then convert to the prd.json format.

## What's inside

- `engine/ralph.sh` — The loop. Fresh context per iteration, circuit breaker, rate limiting, dual exit detection.
- `engine/kickoff.sh` — PRD review gate. Validates stories before AFK execution.
- `engine/prompt.md` — The iteration prompt. 10-phase TDD workflow with verification gates.
- `engine/snapshot.sh` — Codebase snapshot generator (file tree, exports, import graph, test counts).
- `skills/tdd/` — TDD methodology (Matt Pocock + obra/superpowers). Non-negotiable.
- `.claude/hooks/` — Git guardrails blocking dangerous commands.
- `.ralphrc` — Loop configuration (rate limits, circuit breaker thresholds).
- `create-project.sh` — Bootstrap a new project from this template.

## Architecture decisions

Synthesised from [snarktank/ralph](https://github.com/snarktank/ralph), [frankbria/ralph-claude-code](https://github.com/frankbria/ralph-claude-code), [mattpocock's skills and workshops](https://github.com/mattpocock), and [obra/superpowers](https://github.com/obra/superpowers). See commit history and inline comments for provenance.
