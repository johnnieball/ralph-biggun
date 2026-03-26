---
name: task-review
description: Reviews a Ralph task list JSON file for robustness. Auto-fixes mechanical issues (oversized stories, missing dependencies, ambiguous criteria) and flags items needing human decisions. Use before running ralph.sh.
argument-hint: "[plan-name]"
---

# Task Review

You are reviewing a Ralph task list (`specs/tasks-<plan>.json`) to make it robust before handing it to the autonomous TDD agent. The agent works one story at a time with no human in the loop, so the task list must be unambiguous and well-structured.

## Find the Task List

Determine which task list to review. Check both `.ralph/` (new layout) and root (legacy layout):

1. If `$ARGUMENTS` is provided, try `.ralph/specs/tasks-$ARGUMENTS.json` first, then `specs/tasks-$ARGUMENTS.json`
2. Otherwise, read `.ralph/config.sh` (or `.ralphrc`) and use the `RALPH_PLAN` value
3. If neither exists, list available task lists in `.ralph/specs/` and `specs/` and ask

Read the task list JSON file.

## Review Criteria

Analyse the task list against these categories:

### Mechanical Issues (auto-fix these)

1. **Oversized stories** — more than 5 acceptance criteria. Split into smaller stories, preserving IDs with a/b suffixes (e.g. {PREFIX}-012 becomes {PREFIX}-012a, {PREFIX}-012b, where {PREFIX} is the task list's `storyPrefix` value). Update any dependency references.
2. **Missing infrastructure stories** — stories that assume setup (project init, config, schema) without a prior story providing it. Add infrastructure stories at the start.
3. **Implicit dependencies** — stories that must be done in a specific order but don't declare it. Add `dependsOn` arrays where the ordering is unambiguous.
4. **Ambiguous acceptance criteria** — criteria that can't be turned into a deterministic test assertion. Tighten them with specific values, thresholds, or observable behaviours.
5. **ID gaps or duplicates** — ensure story IDs are sequential and unique.
6. **Integration gate hygiene** — if integration validation stories exist: exactly one has a `gate` field (the first), they have `dependsOn` referencing build stories, and they have `priority: "low"`.
7. **Phase completeness** — every story belongs to a phase, phases are sequential (PH-1, PH-2, etc.) with no gaps or missing stories.
8. **Journey coverage** — every phase with UI stories has at least one journey. Each journey spans at least 2 stories.
9. **Journey dependencies** — each journey's `dependsOn` includes all stories referenced by its steps. The `phase` field matches the phase that contains the journey.
10. **Locator consistency** — `data-testid` values referenced in journey steps appear in acceptance criteria of the stories they depend on. Flag missing testids.
11. **Phase sizing** — flag phases with more than 8 stories (too large, suggest splitting).
12. **Journey length** — flag journeys with more than 10 steps (too complex, suggest splitting).

### Human Decisions (flag these, do not fix)

1. **Architecture choices** — which database, auth provider, UI framework, hosting platform, etc.
2. **Scope questions** — stories that could mean very different things depending on intent
3. **Spike/research stories** — exploratory work with no clear pass/fail that can't be TDD'd
4. **Business logic ambiguity** — rules that require domain knowledge to resolve
5. **Integration scope** — if the spec mentions deployment or external services, does the task list include integration validation stories? Flag if missing.

For each human-decision item, provide **opinionated guidance** so the user can decide without reading the task list themselves. Every item must include:

- **Recommendation**: Lead with what you'd do. If the right answer is obvious, say so directly ("Do X. It's straightforward because…"). If it's genuinely a judgement call, say that too.
- **Why it matters**: What breaks, slows down, or gets worse if this isn't addressed — concrete impact on the TDD agent, story count, dependencies, or delivery risk.
- **Tradeoffs** (when the answer isn't obvious): Present the options as "If you go with A → [consequence]. If you go with B → [consequence]." Give the user enough context to choose without further research.
- **What I'd pick** (when there's a genuine choice): State your leaning and why, even if you're not certain. The user can override — but never leave them without a starting position.

## Process

Run up to 3 passes. Each pass:

1. Read the task list (re-read it — you may have edited it in a previous pass)
2. Identify all issues in both categories
3. Auto-fix every mechanical issue directly in the file
4. Collect human-decision items (don't fix these, just note them)
5. If you made fixes, do another pass to verify they didn't introduce new issues

Stop early if a pass finds no mechanical issues.

After fixing, verify the JSON is valid by reading it back and checking it parses correctly.

## Output

After all passes, present a summary:

```
Task Review: [project name]

Auto-fixed ([count]):
  - [what was changed and why, one line each]

Human review needed ([count]):

  [number]. [One-line problem statement]
     Recommendation: [What to do — be direct and opinionated]
     Why: [Impact if ignored — on agent, timeline, test coverage, etc.]
     [If genuinely ambiguous: "Option A → [consequence]. Option B → [consequence]. I'd lean toward [X] because [reason]."]

Verdict: READY / NEEDS_HUMAN_INPUT
```

If verdict is READY, the user can proceed to `.ralph/engine/ralph.sh` (or `engine/ralph.sh` for legacy layout).
If verdict is NEEDS_HUMAN_INPUT, list the items clearly so the user can address them and re-run `/task-review`.

Keep human items concise but complete — the user should never need to open the task list to make a decision. If the fix is obvious, say "Do X" and move on. If it's a real choice, give them everything they need to pick in 30 seconds.
