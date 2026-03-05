#!/bin/bash
set -e

# engine/kickoff.sh — PRD planning phase
# Validates prd.json and runs a one-shot Claude analysis before AFK execution.
# Writes .ralph-kickoff-complete on approval; ralph.sh gates on this file.

# Ensure bun is on PATH (installed to ~/.bun by default)
export PATH="$HOME/.bun/bin:$PATH"

# Source configuration
if [ -f ".ralphrc" ]; then
  source .ralphrc
fi

# Plan selection: CLI arg > RALPH_PLAN config
if [ -n "$1" ]; then
  RALPH_PLAN="$1"
fi

if [ -z "$RALPH_PLAN" ]; then
  echo "ERROR: No plan selected. Set RALPH_PLAN in .ralphrc or pass as argument."
  echo "  Usage: $0 <plan-name>"
  echo "Available plans:"
  for f in specs/prd-*.json; do
    [ -f "$f" ] && echo "  - $(basename "$f" | sed 's/^prd-//;s/\.json$//')"
  done
  exit 1
fi

PRD_PATH="specs/prd-${RALPH_PLAN}.json"

# 1. Validate PRD exists and has stories
if [ ! -f "$PRD_PATH" ]; then
  echo "ERROR: PRD not found at $PRD_PATH"
  echo "Available plans:"
  for f in specs/prd-*.json; do
    [ -f "$f" ] && echo "  - $(basename "$f" | sed 's/^prd-//;s/\.json$//')"
  done
  exit 1
fi

story_count=$(jq '.userStories | length' "$PRD_PATH" 2>/dev/null || echo "0")
if [ "$story_count" -eq 0 ]; then
  echo "ERROR: $PRD_PATH has no user stories."
  exit 1
fi

project_name=$(jq -r '.project // "unknown"' "$PRD_PATH" 2>/dev/null)
echo "Kickoff: $project_name ($story_count stories) — $PRD_PATH"
echo ""

# 2. Build analysis prompt
prd_contents=$(cat "$PRD_PATH")

analysis_prompt="You are a senior technical reviewer auditing a PRD before it is handed to an autonomous TDD agent (Ralph). The agent works one story at a time, writes a failing test first, then implements to make it pass. It has no human in the loop during execution.

Review the following PRD and check for:
1. **Oversized stories** — more than 5 acceptance criteria, or vague scope that could expand
2. **Missing infrastructure stories** — e.g. project setup, CI config, database schema that other stories depend on
3. **Implicit dependencies** — stories that must be done in a specific order but don't say so
4. **Ambiguous acceptance criteria** — criteria that can't be turned into a deterministic test assertion
5. **Architecture decisions that should be human choices** — e.g. which database, which auth provider, which UI framework
6. **Spike/research stories that can't be TDD'd** — exploratory work with no clear pass/fail

The agent uses strict RED-GREEN-REFACTOR TDD (see skills/tdd/SKILL.md). Every story must be expressible as: write failing test → implement → pass.

Format your response as:

## PRD Analysis: [project name]

### Issues Found
(numbered list, or \"None\" if clean)

For each issue:
- **Story**: [story ID]
- **Problem**: [what's wrong]
- **Suggestion**: [how to fix]

### Summary
- Stories: [count]
- Issues: [count]
- **VERDICT: READY** or **VERDICT: NEEDS_CHANGES**

---

PRD:
\`\`\`json
$prd_contents
\`\`\`"

# 3. Spawn one-shot Claude analysis
echo "Analysing PRD..."
echo ""

analysis=$(claude --print -p "$analysis_prompt" 2>&1 || echo "ERROR: Claude analysis failed. Check the output above for details.")

# 4. Display analysis
echo "$analysis"
echo ""

# 5. Prompt user based on verdict
if echo "$analysis" | grep -q "VERDICT: READY"; then
  echo "---"
  read -rp "PRD looks ready. Proceed with Ralph? (y/n) " answer
else
  echo "---"
  read -rp "Issues found. Proceed anyway? (y/n) " answer
fi

# 6. Handle response
if [[ "$answer" =~ ^[Yy] ]]; then
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > .ralph-kickoff-complete
  echo ""
  echo "Kickoff complete. Run ./engine/ralph.sh to start."
else
  echo ""
  echo "Kickoff cancelled. Fix the issues in $PRD_PATH and re-run."
  exit 1
fi
