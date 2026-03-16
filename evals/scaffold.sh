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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

# Strip eval infrastructure (not needed in scaffolded projects)
rm -rf evals/
rm -f setup.sh create-project.sh upgrade-spec.md

# Set permissions
chmod +x engine/ralph.sh
[ -f engine/snapshot.sh ] && chmod +x engine/snapshot.sh

# Initialise Ralph via init.sh (creates .ralph/ layout)
# Create a bun.lock marker for stack detection
touch bun.lock
bash commands/init.sh --stack bun-typescript .

# Write project-specific CLAUDE.md (init creates a one-line directive)
cat > CLAUDE.md << CLAUDEEOF
# $PROJECT_NAME

## Commands

- \`bun run dev\` — watch mode (\`bun run --watch src/index.ts\`)
- \`bun run test\` — run tests (Vitest)
- \`bun run typecheck\` — TypeScript type checking
- \`bun run lint\` — linting (oxlint)

## Codebase Patterns

(Patterns will be added here by Ralph during iterations)

<!-- Ralph --> Read .ralph/CLAUDE-ralph.md for autonomous development loop instructions.
CLAUDEEOF

# Replace architecture.md placeholder
if [ -f .ralph/specs/architecture.md ]; then
  portable_sed "s/PROJECT_NAME/$PROJECT_NAME/g" .ralph/specs/architecture.md
fi

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
