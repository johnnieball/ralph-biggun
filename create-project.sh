#!/bin/bash
set -e

# create-project.sh — Create a new Ralph project from the template
# Usage: ./create-project.sh <target-path> [prd.json] [plan-name]
#
# PRD is placed at specs/prd-<plan-name>.json and RALPH_PLAN is set in .ralphrc.
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

# --- Copy template files ---

# Engine (Ralph machinery)
mkdir -p "$TARGET/engine"
for f in ralph.sh kickoff.sh prompt.md snapshot.sh; do
  [ -f "$TEMPLATE_DIR/engine/$f" ] && cp "$TEMPLATE_DIR/engine/$f" "$TARGET/engine/"
done

# Specs (architecture template)
mkdir -p "$TARGET/specs"
[ -f "$TEMPLATE_DIR/specs/architecture.md" ] && cp "$TEMPLATE_DIR/specs/architecture.md" "$TARGET/specs/"

# Skills
cp -R "$TEMPLATE_DIR/skills" "$TARGET/skills"

# Project config
cp "$TEMPLATE_DIR/CLAUDE.md" "$TARGET/"
cp "$TEMPLATE_DIR/.gitignore" "$TARGET/"
cp "$TEMPLATE_DIR/.ralphrc" "$TARGET/"

# Build tooling
cp "$TEMPLATE_DIR/package.json" "$TARGET/"
cp "$TEMPLATE_DIR/tsconfig.json" "$TARGET/"
cp "$TEMPLATE_DIR/vitest.config.ts" "$TARGET/"
cp "$TEMPLATE_DIR/.oxlintrc.json" "$TARGET/"
cp "$TEMPLATE_DIR/.prettierrc" "$TARGET/"
cp "$TEMPLATE_DIR/.lintstagedrc" "$TARGET/"

# Claude Code hooks
mkdir -p "$TARGET/.claude/hooks"
[ -f "$TEMPLATE_DIR/.claude/settings.json" ] && cp "$TEMPLATE_DIR/.claude/settings.json" "$TARGET/.claude/"
[ -f "$TEMPLATE_DIR/.claude/hooks/block-dangerous-git.sh" ] && cp "$TEMPLATE_DIR/.claude/hooks/block-dangerous-git.sh" "$TARGET/.claude/hooks/"

# --- Set up the new project ---

# Portable in-place sed (macOS requires '' as separate arg)
portable_sed() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Replace placeholders with project name
portable_sed "s/PROJECT_NAME/$PROJECT_NAME/g" "$TARGET/package.json"
portable_sed "s/\[Project Name\]/$PROJECT_NAME/g" "$TARGET/CLAUDE.md"
portable_sed "s/PROJECT_NAME/$PROJECT_NAME/g" "$TARGET/specs/architecture.md"

# Copy user's PRD if provided
if [ -n "$PRD_SOURCE" ]; then
  # Default plan name to project name if not specified
  PLAN_NAME="${PLAN_NAME:-$PROJECT_NAME}"
  cp "$PRD_SOURCE" "$TARGET/specs/prd-${PLAN_NAME}.json"
  # Set RALPH_PLAN in .ralphrc
  portable_sed "s/^RALPH_PLAN=$/RALPH_PLAN=$PLAN_NAME/" "$TARGET/.ralphrc"
fi

# Create empty progress.txt
cat > "$TARGET/progress.txt" << 'EOF'
# Ralph Progress Log

## Codebase Patterns
(Patterns will be added here by Ralph as it discovers reusable conventions)

## Technical Debt
(refactoring needs noted during the build - address when capacity allows)

---

Started: (date will be filled by first iteration)
---
EOF

# Create starter src file
mkdir -p "$TARGET/src"
cat > "$TARGET/src/index.ts" << 'EOF'
export {};
EOF

# Set permissions
chmod +x "$TARGET/engine/ralph.sh"
chmod +x "$TARGET/engine/kickoff.sh"
[ -f "$TARGET/engine/snapshot.sh" ] && chmod +x "$TARGET/engine/snapshot.sh"
[ -f "$TARGET/.claude/hooks/block-dangerous-git.sh" ] && chmod +x "$TARGET/.claude/hooks/block-dangerous-git.sh"

# Initialise git (must happen before bun install so husky's prepare script works)
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
  echo "  2. ./engine/kickoff.sh $PLAN_NAME"
  echo "  3. ./engine/ralph.sh 20 $PLAN_NAME"
else
  echo "  1. Add your PRD:  cp your-prd.json $TARGET/specs/prd-my-plan.json"
  echo "  2. Set RALPH_PLAN=my-plan in $TARGET/.ralphrc"
  echo "  3. cd $TARGET"
  echo "  4. ./engine/kickoff.sh my-plan"
  echo "  5. ./engine/ralph.sh 20 my-plan"
fi
