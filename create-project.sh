#!/bin/bash
set -e

# create-project.sh — Create a new greenfield Ralph project (Bun + TypeScript)
# Usage: ./create-project.sh <target-path> [prd.json] [plan-name]
#
# PRD is placed at .ralph/specs/prd-<plan-name>.json and RALPH_PLAN is set in .ralph/config.sh.
# If plan-name is omitted, the project name is used as the plan name.
#
# Examples:
#   ./create-project.sh ~/projects/my-app
#   ./create-project.sh ~/projects/my-app specs/my-app-prd.json
#   ./create-project.sh ~/projects/my-app specs/my-app-prd.json my-app

TEMPLATE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$1" ]; then
  echo "Usage: ./create-project.sh <target-path> [prd.json] [plan-name]"
  echo ""
  echo "Examples:"
  echo "  ./create-project.sh ~/projects/my-app"
  echo "  ./create-project.sh ~/projects/my-app specs/my-prd.json"
  echo "  ./create-project.sh ~/projects/my-app specs/my-prd.json my-app"
  exit 1
fi

TARGET="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")" || TARGET="$1"
PRD_SOURCE="$2"
PLAN_NAME="$3"
PROJECT_NAME="$(basename "$TARGET")"

# Validate
if [ -d "$TARGET" ]; then
  echo "ERROR: $TARGET already exists."
  exit 1
fi

if [ -n "$PRD_SOURCE" ] && [ ! -f "$PRD_SOURCE" ]; then
  echo "ERROR: PRD file not found: $PRD_SOURCE"
  exit 1
fi

echo "Creating $PROJECT_NAME at $TARGET..."

# Create target directory
mkdir -p "$TARGET"

# Portable in-place sed (macOS requires '' as separate arg)
portable_sed() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# --- Copy build tooling (Bun/TS scaffolding) ---
cp "$TEMPLATE_DIR/package.json" "$TARGET/"
cp "$TEMPLATE_DIR/tsconfig.json" "$TARGET/"
cp "$TEMPLATE_DIR/vitest.config.ts" "$TARGET/"
cp "$TEMPLATE_DIR/.oxlintrc.json" "$TARGET/"
cp "$TEMPLATE_DIR/.prettierrc" "$TARGET/"
cp "$TEMPLATE_DIR/.lintstagedrc" "$TARGET/"
cp "$TEMPLATE_DIR/.gitignore" "$TARGET/"

# Replace placeholders with project name
portable_sed "s/PROJECT_NAME/$PROJECT_NAME/g" "$TARGET/package.json"

# Create starter src file
mkdir -p "$TARGET/src"
cat > "$TARGET/src/index.ts" << 'EOF'
export {};
EOF

# --- Initialise Ralph via init.sh ---
# Create a bun.lock marker so init detects bun-typescript stack
touch "$TARGET/bun.lock"
"$TEMPLATE_DIR/commands/init.sh" --stack bun-typescript "$TARGET"

# --- Greenfield-specific: write project CLAUDE.md (init already added directive) ---
cat > "$TARGET/CLAUDE.md" << CLAUDEEOF
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
if [ -f "$TARGET/.ralph/specs/architecture.md" ]; then
  portable_sed "s/PROJECT_NAME/$PROJECT_NAME/g" "$TARGET/.ralph/specs/architecture.md"
fi

# --- PRD handling ---
if [ -n "$PRD_SOURCE" ]; then
  PLAN_NAME="${PLAN_NAME:-$PROJECT_NAME}"
  cp "$PRD_SOURCE" "$TARGET/.ralph/specs/prd-${PLAN_NAME}.json"
  # Set RALPH_PLAN in config.sh
  portable_sed "s/^RALPH_PLAN=$/RALPH_PLAN=$PLAN_NAME/" "$TARGET/.ralph/config.sh"
fi

# --- Initialise git (must happen before bun install so husky's prepare script works) ---
cd "$TARGET"
git init -q

# Install dependencies
bun install

# Create husky pre-commit hook
mkdir -p .husky
cat > .husky/pre-commit << 'HOOKEOF'
bunx lint-staged
bun run typecheck
bun run test
HOOKEOF

# Initial commit
git add -A
git commit -q -m "chore: scaffold $PROJECT_NAME via ralph-greenfield"

echo ""
echo "Created $PROJECT_NAME at $TARGET"
echo ""
echo "Next steps:"
if [ -n "$PRD_SOURCE" ]; then
  echo "  1. cd $TARGET"
  echo "  2. /prd-review $PLAN_NAME      (in Claude Code)"
  echo "  3. .ralph/engine/ralph.sh 20 $PLAN_NAME"
else
  echo "  1. Add your PRD:  cp your-prd.json $TARGET/.ralph/specs/prd-my-plan.json"
  echo "  2. Set RALPH_PLAN=my-plan in $TARGET/.ralph/config.sh"
  echo "  3. cd $TARGET"
  echo "  4. /prd-review my-plan          (in Claude Code)"
  echo "  5. .ralph/engine/ralph.sh 20 my-plan"
fi
