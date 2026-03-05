#!/bin/bash
set -e

# evals/scaffold.sh — In-place project scaffolding for eval runs
# Called from a temp copy of the repo (rsync'd by eval scripts).
# Replaces placeholders, installs deps, inits git. Runs in the current directory.
#
# Usage: bash <path-to>/evals/scaffold.sh <project-name>

if [ -z "$1" ]; then
  echo "Usage: scaffold.sh <project-name>"
  exit 1
fi

PROJECT_NAME="$1"

# Portable in-place sed (macOS requires '' as separate arg)
portable_sed() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Replace placeholders
portable_sed "s/PROJECT_NAME/$PROJECT_NAME/g" package.json
portable_sed "s/\[Project Name\]/$PROJECT_NAME/g" CLAUDE.md
portable_sed "s/PROJECT_NAME/$PROJECT_NAME/g" plans/architecture.md

# Strip eval infrastructure (not needed in scaffolded projects)
rm -rf evals/
rm -f setup.sh create-project.sh upgrade-spec.md

# Create empty progress.txt
cat > progress.txt << 'EOF'
# Ralph Progress Log

## Codebase Patterns
(Patterns will be added here by Ralph as it discovers reusable conventions)

## Technical Debt
(refactoring needs noted during the build - address when capacity allows)

---

Started: (date will be filled by first iteration)
---
EOF

# Set permissions
chmod +x plans/ralph.sh
chmod +x plans/kickoff.sh
[ -f plans/snapshot.sh ] && chmod +x plans/snapshot.sh
[ -f .claude/hooks/block-dangerous-git.sh ] && chmod +x .claude/hooks/block-dangerous-git.sh

# Initialise git (must happen before bun install so husky's prepare script works)
rm -rf .git
git init -q

# Install dependencies
bun install

# Create pre-commit hook
mkdir -p .husky
cat > .husky/pre-commit << 'HOOKEOF'
bunx lint-staged
bun run typecheck
bun run test
HOOKEOF

# Initial commit
git add -A
git commit -q -m "chore: scaffold $PROJECT_NAME via ralph-greenfield"
