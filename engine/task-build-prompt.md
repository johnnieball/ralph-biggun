# Task Build — Iteration **ITERATION**

You are generating or refining a task list JSON file for the Ralph autonomous TDD agent.

## Inputs

1. Read the spec file at `__SPEC_FILE__`
2. Check if a task list already exists at `__TASKS_PATH__`

## If no task list exists (first iteration)

Generate a complete task list JSON from the spec. The JSON schema is:

```json
{
  "project": "project-name",
  "storyPrefix": "PN",
  "branchName": "feature/project-name",
  "description": "One-line project description",
  "techStack": ["list", "of", "technologies"],
  "environment": {
    "runtime": "e.g. bun, node, python",
    "testFramework": "e.g. vitest, pytest",
    "notes": "any environment-specific notes"
  },
  "requiredEnv": [
    {
      "var": "ENV_VAR_NAME",
      "for": "what needs this variable (e.g. Integration tests US-005)"
    }
  ],
  "phases": [
    {
      "id": "PH-1",
      "name": "Phase name",
      "description": "What this phase covers",
      "stories": ["PN-001", "PN-002"],
      "journeys": ["J-1"]
    }
  ],
  "journeys": [
    {
      "id": "J-1",
      "title": "User flow description",
      "phase": "PH-1",
      "steps": [
        "Navigate to /path",
        "Fill field [data-testid=field-name]",
        "Click submit [data-testid=submit-btn]",
        "Expect redirect to /destination",
        "Expect element visible [data-testid=element-name]"
      ],
      "dependsOn": ["PN-001", "PN-002"]
    }
  ],
  "userStories": [
    {
      "id": "PN-001",
      "title": "Short story title",
      "description": "What this story delivers",
      "acceptanceCriteria": [
        "Each criterion must be a deterministic, testable assertion",
        "Use specific values, thresholds, or observable behaviours"
      ],
      "priority": "high|medium|low",
      "passes": false,
      "dependsOn": [],
      "notes": "",
      "gate": null,
      "e2eTestFile": null
    }
  ]
}
```

Rules for generation:

- **Story prefix**: Derive `storyPrefix` from the `project` field by taking the first letter of each hyphen-separated word and uppercasing it (e.g. `deck-manipulation` → `DM`, `visual-design-system` → `VDS`, `my-app` → `MA`). Before committing to the prefix, run `git log --oneline | grep '{PREFIX}-'` to check for existing use. If a clash is found, append a single digit to disambiguate (e.g. `DM` → `DM2`). Store the chosen prefix in the top-level `storyPrefix` field. Use it in all story IDs, `dependsOn` references, phase `stories` arrays, journey `dependsOn` arrays, and commit messages. Format: `{PREFIX}-{NNN}`.
- **Vertical slices**: each story delivers a thin, end-to-end piece of functionality
- **Max 5 acceptance criteria** per story — split larger stories
- **Infrastructure first**: project setup, config, schema stories come before feature stories
- **Sequential IDs**: {PREFIX}-001, {PREFIX}-002, {PREFIX}-003, etc. with no gaps (where {PREFIX} is the `storyPrefix` value)
- **All `passes: false`**: the agent marks them true as it completes them
- **Explicit dependencies**: if story B requires story A, set `"dependsOn": ["{PREFIX}-001"]`
- **Testable criteria**: every acceptance criterion must be convertible to a deterministic test assertion. No vague language like "should be user-friendly" or "performant"
- **data-testid hints in acceptance criteria**: when a criterion involves UI interaction (clicking, filling, reading), specify the `data-testid` value in the criterion text. Example: "User sees welcome banner [data-testid=welcome-banner] after login"

Write the task list JSON to `__TASKS_PATH__`.

### Phases

Group stories into phases — logical build stages that represent functional areas:

- Every story belongs to exactly one phase
- Phases are ordered: PH-1 before PH-2, etc.
- Infrastructure/setup stories (project init, config, schema) typically form PH-1
- Integration validation stories form the final phase
- A phase is "complete" when all its stories have `passes: true`
- Avoid phases with more than 8 stories — split large phases into sub-phases

### Journeys (UI projects only)

If the project has a UI (web app, frontend), generate journeys — cross-story user flows that will become E2E tests:

- Each journey spans at least 2 stories (single-story flows are unit tests, not journeys)
- Steps are natural language with embedded locator hints (`[data-testid=...]`)
- A journey's `dependsOn` lists every story that must pass before this journey is testable
- `phase` links the journey to when it should first run
- Keep journeys focused — one user goal per journey, 3-8 steps typical
- Every phase with UI stories should have at least one journey
- `data-testid` values in journey steps must appear in acceptance criteria of the stories they depend on

If the project is API-only (no browser UI), omit the `journeys` array entirely. Do not generate journeys for backend-only projects.

### Integration boundaries

When the spec involves external systems (cloud providers, third-party APIs, databases requiring provisioning, deployment targets, payment processors, auth providers, etc.), apply the two-phase model:

**Phase 1 — Build**: Generate stories as normal. Mock all external dependencies at system boundaries. Standard TDD.

**Phase 2 — Integration validation**: After all build stories, append stories that verify wiring against real infrastructure:

1. Connectivity — services can reach declared dependencies (network, auth, DNS)
2. Configuration — env vars, secrets, and config match between application and infrastructure
3. Runtime dependencies — required packages, binaries, and services are present
4. Entry points — all endpoints, commands, and triggers are functional (no stubs)
5. End-to-end smoke — one request flows through the entire real stack

Rules:

- Integration stories get `"priority": "low"` (execute after build phase)
- Set `"dependsOn"` to include the build stories they validate
- Mark the FIRST integration story with a `"gate"` field describing what the user must set up
- Gate message should be generic — reference the tech stack from the spec but don't hardcode provider-specific commands unless the spec names them
- Only ONE story gets the gate
- The `"gate"` field is optional and defaults to `null`. Only set it on integration validation stories.

If the spec has no external integration, do not add integration stories or use the gate field.

### Required environment variables

When integration stories reference environment variables (API keys, database URLs, service endpoints), declare them in the top-level `requiredEnv` array. Ralph validates these before the loop starts — missing variables cause an immediate, actionable failure instead of a surprise 100+ iterations later.

- `var` — the environment variable name (e.g. `MY_API_KEY`)
- `for` — human-readable description shown in the error message (e.g. `"Integration tests (US-005, US-006)"`)
- Only declare variables the build actually reads at runtime. Do not list optional or test-only convenience vars.
- If the spec has no external integration, omit `requiredEnv` entirely (or leave it as an empty array).

## If task list already exists (iteration 2+)

Read the existing task list at `__TASKS_PATH__` and review it against these mechanical criteria:

1. **Oversized stories** — any story with more than 5 acceptance criteria must be split. Use a/b suffixes ({PREFIX}-012 → {PREFIX}-012a, {PREFIX}-012b). Update all `dependsOn` references.
2. **Missing infrastructure stories** — stories that assume setup (project init, config, schema, database migrations) without a prior story providing it. Add infrastructure stories at the start and renumber.
3. **Implicit dependencies** — stories that must be done in a specific order but don't declare `dependsOn`. Add the dependency where the ordering is unambiguous.
4. **Ambiguous acceptance criteria** — criteria that can't be turned into a deterministic test assertion. Tighten with specific values, thresholds, or observable behaviours.
5. **ID gaps or duplicates** — ensure story IDs are sequential and unique.
6. **Gate placement** — if integration validation stories exist, exactly one should have a `gate` field on the first integration story. Fix if multiple have `gate` or if none do.
7. **Phase completeness** — every story must belong to exactly one phase. Phases must be sequential (PH-1, PH-2, etc.) with no gaps.
8. **Journey coverage** — every phase with UI stories must have at least one journey. Journeys must span at least 2 stories.
9. **Journey dependencies** — each journey's `dependsOn` must include all stories referenced by its steps.
10. **Locator consistency** — `data-testid` values in journey steps must appear in acceptance criteria of the dependent stories.

Fix all mechanical issues directly in the task list JSON.

For human-decision items (architecture choices, scope questions, spike/research stories, business logic ambiguity), fix what you can and flag the rest using the structured block below.

## Convergence rule

If you find **no mechanical issues** in the task list, do NOT modify the file. Leave it exactly as-is. The build loop detects convergence by comparing file checksums between iterations — any rewrite (even with identical content) risks changing formatting and breaking detection.

## Output

After reviewing/generating the task list, output these blocks at the end of your response.

If there are human-decision items, output this block **before** the status block:

```
---HUMAN_DECISION_ITEMS---
- <concise description of the decision needed>
- <another decision needed>
---END_HUMAN_DECISION_ITEMS---
```

Each item should be a single line starting with `- `. Be specific about what needs deciding — not just "auth is ambiguous" but "auth: should sessions use JWT or server-side cookies?". Omit this block entirely if there are no human items.

Then output the status block:

```
---TASK_BUILD_STATUS---
ITERATION: __ITERATION__
MECHANICAL_FIXES: <count of mechanical issues fixed>
HUMAN_ITEMS: <count of items needing human review>
VERDICT: READY | NEEDS_HUMAN | IN_PROGRESS
---END_TASK_BUILD_STATUS---
```

Verdict rules:

- `IN_PROGRESS` — mechanical fixes were made, another pass is needed
- `NEEDS_HUMAN` — no mechanical issues remain but human-decision items exist
- `READY` — no mechanical issues and no human-decision items
