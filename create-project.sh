#!/bin/bash
set -e

# create-project.sh — Create a new Ralph project from the template
# Usage: ./create-project.sh <target-path> [prd.json]
#
# Examples:
#   ./create-project.sh ~/projects/my-app
#   ./create-project.sh ~/projects/my-app specs/my-app-prd.json
#   ./create-project.sh /tmp/throwaway-app prd.json

TEMPLATE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$1" ]; then
  echo "Usage: ./create-project.sh <target-path> [prd.json]"
  echo ""
  echo "Examples:"
  echo "  ./create-project.sh ~/projects/my-app"
  echo "  ./create-project.sh ~/projects/my-app specs/my-prd.json"
  exit 1
fi

TARGET="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")" || TARGET="$1"
PRD_SOURCE="$2"
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

# Plans (Ralph machinery) — without the template's own prd.json
mkdir -p "$TARGET/plans"
for f in ralph.sh kickoff.sh prompt.md snapshot.sh architecture.md; do
  [ -f "$TEMPLATE_DIR/plans/$f" ] && cp "$TEMPLATE_DIR/plans/$f" "$TARGET/plans/"
done

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
portable_sed "s/PROJECT_NAME/$PROJECT_NAME/g" "$TARGET/plans/architecture.md"

# Copy user's PRD if provided
if [ -n "$PRD_SOURCE" ]; then
  cp "$PRD_SOURCE" "$TARGET/plans/prd.json"
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
chmod +x "$TARGET/plans/ralph.sh"
chmod +x "$TARGET/plans/kickoff.sh"
[ -f "$TARGET/plans/snapshot.sh" ] && chmod +x "$TARGET/plans/snapshot.sh"
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
  echo "  2. ./plans/kickoff.sh"
  echo "  3. ./plans/ralph.sh 20"
else
  echo "  1. Add your PRD:  cp your-prd.json $TARGET/plans/prd.json"
  echo "  2. cd $TARGET"
  echo "  3. ./plans/kickoff.sh"
  echo "  4. ./plans/ralph.sh 20"
fi
