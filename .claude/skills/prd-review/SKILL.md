---
name: prd-review
description: Reviews a Ralph PRD JSON file for robustness. Auto-fixes mechanical issues (oversized stories, missing dependencies, ambiguous criteria) and flags items needing human decisions. Use before running ralph.sh.
argument-hint: "[plan-name]"
---

# PRD Review

You are reviewing a Ralph PRD (`specs/prd-<plan>.json`) to make it robust before handing it to the autonomous TDD agent. The agent works one story at a time with no human in the loop, so the PRD must be unambiguous and well-structured.

## Find the PRD

Determine which PRD to review. Check both `.ralph/` (new layout) and root (legacy layout):

1. If `$ARGUMENTS` is provided, try `.ralph/specs/prd-$ARGUMENTS.json` first, then `specs/prd-$ARGUMENTS.json`
2. Otherwise, read `.ralph/config.sh` (or `.ralphrc`) and use the `RALPH_PLAN` value
3. If neither exists, list available PRDs in `.ralph/specs/` and `specs/` and ask

Read the PRD JSON file.

## Review Criteria

Analyse the PRD against these categories:

### Mechanical Issues (auto-fix these)

1. **Oversized stories** — more than 5 acceptance criteria. Split into smaller stories, preserving IDs with a/b suffixes (e.g. US-012 becomes US-012a, US-012b). Update any dependency references.
2. **Missing infrastructure stories** — stories that assume setup (project init, config, schema) without a prior story providing it. Add infrastructure stories at the start.
3. **Implicit dependencies** — stories that must be done in a specific order but don't declare it. Add `dependsOn` arrays where the ordering is unambiguous.
4. **Ambiguous acceptance criteria** — criteria that can't be turned into a deterministic test assertion. Tighten them with specific values, thresholds, or observable behaviours.
5. **ID gaps or duplicates** — ensure story IDs are sequential and unique.

### Human Decisions (flag these, do not fix)

1. **Architecture choices** — which database, auth provider, UI framework, hosting platform, etc.
2. **Scope questions** — stories that could mean very different things depending on intent
3. **Spike/research stories** — exploratory work with no clear pass/fail that can't be TDD'd
4. **Business logic ambiguity** — rules that require domain knowledge to resolve

## Process

Run up to 3 passes. Each pass:

1. Read the PRD (re-read it — you may have edited it in a previous pass)
2. Identify all issues in both categories
3. Auto-fix every mechanical issue directly in the file
4. Collect human-decision items (don't fix these, just note them)
5. If you made fixes, do another pass to verify they didn't introduce new issues

Stop early if a pass finds no mechanical issues.

After fixing, verify the JSON is valid by reading it back and checking it parses correctly.

## Output

After all passes, present a summary:

```
PRD Review: [project name]

Auto-fixed ([count]):
- [what was changed and why, one line each]

Human review needed ([count]):
- [issue description + suggestion, one line each]

Verdict: READY / NEEDS_HUMAN_INPUT
```

If verdict is READY, the user can proceed to `.ralph/engine/ralph.sh` (or `engine/ralph.sh` for legacy layout).
If verdict is NEEDS_HUMAN_INPUT, list the items clearly so the user can address them and re-run `/prd-review`.
