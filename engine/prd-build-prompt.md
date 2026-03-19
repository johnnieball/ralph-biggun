# PRD Build — Iteration **ITERATION**

You are generating or refining a PRD JSON file for the Ralph autonomous TDD agent.

## Inputs

1. Read the spec file at `__SPEC_FILE__`
2. Check if a PRD already exists at `__PRD_PATH__`

## If no PRD exists (first iteration)

Generate a complete PRD JSON from the spec. The JSON schema is:

```json
{
  "project": "project-name",
  "branchName": "feature/project-name",
  "description": "One-line project description",
  "techStack": ["list", "of", "technologies"],
  "environment": {
    "runtime": "e.g. bun, node, python",
    "testFramework": "e.g. vitest, pytest",
    "notes": "any environment-specific notes"
  },
  "userStories": [
    {
      "id": "US-001",
      "title": "Short story title",
      "description": "What this story delivers",
      "acceptanceCriteria": [
        "Each criterion must be a deterministic, testable assertion",
        "Use specific values, thresholds, or observable behaviours"
      ],
      "priority": "high|medium|low",
      "passes": false,
      "dependsOn": [],
      "notes": ""
    }
  ]
}
```

Rules for generation:

- **Vertical slices**: each story delivers a thin, end-to-end piece of functionality
- **Max 5 acceptance criteria** per story — split larger stories
- **Infrastructure first**: project setup, config, schema stories come before feature stories
- **Sequential IDs**: US-001, US-002, US-003, etc. with no gaps
- **All `passes: false`**: the agent marks them true as it completes them
- **Explicit dependencies**: if story B requires story A, set `"dependsOn": ["US-001"]`
- **Testable criteria**: every acceptance criterion must be convertible to a deterministic test assertion. No vague language like "should be user-friendly" or "performant"

Write the PRD JSON to `__PRD_PATH__`.

## If PRD already exists (iteration 2+)

Read the existing PRD at `__PRD_PATH__` and review it against these mechanical criteria:

1. **Oversized stories** — any story with more than 5 acceptance criteria must be split. Use a/b suffixes (US-012 → US-012a, US-012b). Update all `dependsOn` references.
2. **Missing infrastructure stories** — stories that assume setup (project init, config, schema, database migrations) without a prior story providing it. Add infrastructure stories at the start and renumber.
3. **Implicit dependencies** — stories that must be done in a specific order but don't declare `dependsOn`. Add the dependency where the ordering is unambiguous.
4. **Ambiguous acceptance criteria** — criteria that can't be turned into a deterministic test assertion. Tighten with specific values, thresholds, or observable behaviours.
5. **ID gaps or duplicates** — ensure story IDs are sequential and unique.

Fix all mechanical issues directly in the PRD JSON.

For human-decision items (architecture choices, scope questions, spike/research stories, business logic ambiguity), fix what you can and flag the rest using the structured block below.

## Convergence rule

If you find **no mechanical issues** in the PRD, do NOT modify the file. Leave it exactly as-is. The build loop detects convergence by comparing file checksums between iterations — any rewrite (even with identical content) risks changing formatting and breaking detection.

## Output

After reviewing/generating the PRD, output these blocks at the end of your response.

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
---PRD_BUILD_STATUS---
ITERATION: __ITERATION__
MECHANICAL_FIXES: <count of mechanical issues fixed>
HUMAN_ITEMS: <count of items needing human review>
VERDICT: READY | NEEDS_HUMAN | IN_PROGRESS
---END_PRD_BUILD_STATUS---
```

Verdict rules:

- `IN_PROGRESS` — mechanical fixes were made, another pass is needed
- `NEEDS_HUMAN` — no mechanical issues remain but human-decision items exist
- `READY` — no mechanical issues and no human-decision items
