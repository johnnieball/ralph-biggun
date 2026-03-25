#!/bin/bash
set -e

# commands/init.sh — Initialise or upgrade Ralph in an existing project (brownfield)
# Usage: commands/init.sh [--stack <preset>] [--upgrade] [target-dir]
#
# Detects the tech stack from project files, or accepts --stack override.
# Creates .ralph/ with engine, skills, specs, hooks, and config.
# Merges into .claude/ without clobbering existing files.
#
# --upgrade: Updates engine, skills, hooks, and CLAUDE-ralph.md in an existing
#            .ralph/ installation. Preserves user data: specs/, progress.txt,
#            logs/, config.sh. Migrates legacy prd-*.json → tasks-*.json.

RALPH_HOME="$(cd "$(dirname "$0")/.." && pwd)"
source "$RALPH_HOME/lib/utils.sh"

# Parse arguments
STACK=""
TARGET_DIR=""
UPGRADE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack)
      STACK="$2"
      shift 2
      ;;
    --upgrade)
      UPGRADE=true
      shift
      ;;
    *)
      TARGET_DIR="$1"
      shift
      ;;
  esac
done

TARGET_DIR="${TARGET_DIR:-.}"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || { echo "ERROR: Target directory does not exist: $TARGET_DIR"; exit 1; }

# --- Stack detection ---
detect_stack() {
  local dir="$1"
  if [ -f "$dir/bun.lock" ] || [ -f "$dir/bun.lockb" ]; then
    echo "bun-typescript"
  elif [ -f "$dir/package.json" ]; then
    echo "node-typescript"
  elif [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ] || [ -f "$dir/requirements.txt" ]; then
    echo "python"
  else
    echo "generic"
  fi
}

if [ -z "$STACK" ]; then
  STACK=$(detect_stack "$TARGET_DIR")
  echo "Detected stack: $STACK"
else
  echo "Using stack: $STACK"
fi

# Validate preset exists
PRESET_FILE="$RALPH_HOME/presets/${STACK}.sh"
if [ ! -f "$PRESET_FILE" ]; then
  echo "ERROR: Unknown stack preset: $STACK"
  echo "Available presets:"
  for f in "$RALPH_HOME"/presets/*.sh; do
    echo "  - $(basename "$f" .sh)"
  done
  exit 1
fi

# --- Handle existing .ralph/ ---
if [ "$UPGRADE" = true ] && [ ! -d "$TARGET_DIR/.ralph" ]; then
  echo "ERROR: No .ralph/ directory found in $TARGET_DIR"
  echo ""
  echo "To initialise Ralph for the first time, run:"
  echo ""
  echo "  ralph init $TARGET_DIR"
  exit 1
fi

if [ -d "$TARGET_DIR/.ralph" ]; then
  if [ "$UPGRADE" = false ]; then
    echo "Ralph is already initialised in $TARGET_DIR"
    echo ""
    echo "To upgrade to the latest version, run:"
    echo ""
    echo "  ralph init --upgrade $TARGET_DIR"
    echo ""
    echo "This will update engine files, skills, and hooks while"
    echo "preserving your specs, progress, logs, and config."
    exit 1
  fi

  # --- Upgrade mode ---
  echo "Upgrading Ralph in $TARGET_DIR..."
  echo ""
  UPGRADED=()
  MIGRATED=()
  SKIPPED=()

  # Ensure directories exist (in case older version was missing any)
  mkdir -p "$TARGET_DIR/.ralph/engine"
  mkdir -p "$TARGET_DIR/.ralph/skills/tdd"
  mkdir -p "$TARGET_DIR/.ralph/specs"
  mkdir -p "$TARGET_DIR/.ralph/hooks"
  mkdir -p "$TARGET_DIR/.ralph/logs"

  # Engine files — always overwrite (these are Ralph internals)
  cp "$RALPH_HOME/engine/ralph.sh" "$TARGET_DIR/.ralph/engine/"
  cp "$RALPH_HOME/engine/prompt.md" "$TARGET_DIR/.ralph/engine/"
  cp "$RALPH_HOME/engine/task-build-prompt.md" "$TARGET_DIR/.ralph/engine/"
  cp "$RALPH_HOME/engine/snapshot.sh" "$TARGET_DIR/.ralph/engine/"
  chmod +x "$TARGET_DIR/.ralph/engine/ralph.sh"
  chmod +x "$TARGET_DIR/.ralph/engine/snapshot.sh"
  UPGRADED+=("engine/ralph.sh" "engine/prompt.md" "engine/task-build-prompt.md" "engine/snapshot.sh")

  # Clean up legacy engine files
  if [ -f "$TARGET_DIR/.ralph/engine/prd-build-prompt.md" ]; then
    rm "$TARGET_DIR/.ralph/engine/prd-build-prompt.md"
    MIGRATED+=("Removed legacy engine/prd-build-prompt.md (replaced by task-build-prompt.md)")
  fi

  # Skills — always overwrite
  cp "$RALPH_HOME"/skills/tdd/* "$TARGET_DIR/.ralph/skills/tdd/"
  UPGRADED+=("skills/tdd/*")

  # Hooks — always overwrite
  cp "$RALPH_HOME/.claude/hooks/block-dangerous-git.sh" "$TARGET_DIR/.ralph/hooks/"
  chmod +x "$TARGET_DIR/.ralph/hooks/block-dangerous-git.sh"
  UPGRADED+=("hooks/block-dangerous-git.sh")

  # CLAUDE-ralph.md — regenerate from template
  source "$PRESET_FILE"
  sed \
    -e "s|__TEST_CMD__|${TEST_CMD}|g" \
    -e "s|__TYPECHECK_CMD__|${TYPECHECK_CMD}|g" \
    -e "s|__LINT_CMD__|${LINT_CMD}|g" \
    "$RALPH_HOME/templates/CLAUDE-ralph.md" > "$TARGET_DIR/.ralph/CLAUDE-ralph.md"
  UPGRADED+=("CLAUDE-ralph.md")

  # Specs — preserve contents, but rename prd-*.json → tasks-*.json
  for prd_file in "$TARGET_DIR/.ralph/specs"/prd-*.json; do
    [ -f "$prd_file" ] || continue
    base=$(basename "$prd_file")
    plan_name="${base#prd-}"  # strip "prd-" prefix, keeps "<name>.json"
    new_name="tasks-${plan_name}"
    mv "$prd_file" "$TARGET_DIR/.ralph/specs/$new_name"
    MIGRATED+=("Renamed specs/$base → specs/$new_name")
  done

  # Config.sh — preserve user values, patch stale comments
  if [ -f "$TARGET_DIR/.ralph/config.sh" ]; then
    if grep -qF 'prd-<name>.json' "$TARGET_DIR/.ralph/config.sh"; then
      portable_sed 's|prd-<name>\.json|tasks-<name>.json|g' "$TARGET_DIR/.ralph/config.sh"
      MIGRATED+=("Updated config.sh comment: prd-<name>.json → tasks-<name>.json")
    fi
    SKIPPED+=("config.sh (preserved — your custom values are unchanged)")
  fi

  # Progress file — always preserve
  SKIPPED+=("progress.txt (preserved)")

  # Specs content — always preserve (just renamed above)
  SKIPPED+=("specs/ contents (preserved)")

  # Logs — always preserve
  SKIPPED+=("logs/ (preserved)")

  # Architecture — preserve if it exists (user may have filled it in)
  if [ -f "$TARGET_DIR/.ralph/specs/architecture.md" ]; then
    SKIPPED+=("specs/architecture.md (preserved)")
  elif [ -f "$RALPH_HOME/templates/architecture.md" ]; then
    cp "$RALPH_HOME/templates/architecture.md" "$TARGET_DIR/.ralph/specs/architecture.md"
    UPGRADED+=("specs/architecture.md (new)")
  fi

  # .claude/skills/task-review — update
  if [ -d "$RALPH_HOME/.claude/skills/task-review" ]; then
    mkdir -p "$TARGET_DIR/.claude/skills"
    rm -rf "$TARGET_DIR/.claude/skills/task-review"
    cp -R "$RALPH_HOME/.claude/skills/task-review" "$TARGET_DIR/.claude/skills/"
    UPGRADED+=(".claude/skills/task-review")
  fi

  # .claude/settings.json — ensure hook is present
  SETTINGS_FILE="$TARGET_DIR/.claude/settings.json"
  HOOK_ENTRY='{"matcher":"Bash","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.ralph/hooks/block-dangerous-git.sh"}]}'
  if [ -f "$SETTINGS_FILE" ]; then
    if ! grep -q '.ralph/hooks/block-dangerous-git.sh' "$SETTINGS_FILE"; then
      if command -v jq &>/dev/null; then
        jq --argjson hook "$HOOK_ENTRY" '.hooks.PreToolUse += [$hook]' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        UPGRADED+=(".claude/settings.json (added hook)")
      else
        echo "WARNING: jq not found — cannot merge settings.json hook. Add it manually."
      fi
    fi
  fi

  # CLAUDE.md — ensure directive is present
  CLAUDE_MD="$TARGET_DIR/CLAUDE.md"
  RALPH_DIRECTIVE='<!-- Ralph --> Read .ralph/CLAUDE-ralph.md for autonomous development loop instructions.'
  if [ -f "$CLAUDE_MD" ]; then
    if ! grep -qF '<!-- Ralph -->' "$CLAUDE_MD"; then
      echo "" >> "$CLAUDE_MD"
      echo "$RALPH_DIRECTIVE" >> "$CLAUDE_MD"
      UPGRADED+=("CLAUDE.md (added Ralph directive)")
    fi
  fi

  # .gitignore — ensure entries
  GITIGNORE="$TARGET_DIR/.gitignore"
  add_gitignore() {
    local pattern="$1"
    if [ -f "$GITIGNORE" ]; then
      grep -qF "$pattern" "$GITIGNORE" || echo "$pattern" >> "$GITIGNORE"
    else
      echo "$pattern" > "$GITIGNORE"
    fi
  }
  add_gitignore ".ralph/logs/"
  add_gitignore ".ralph-call-count"
  add_gitignore "codebase-snapshot.md"

  # --- Upgrade summary ---
  echo "Upgrade complete."
  echo ""
  if [ ${#UPGRADED[@]} -gt 0 ]; then
    echo "Updated:"
    for item in "${UPGRADED[@]}"; do
      echo "  + $item"
    done
  fi
  if [ ${#MIGRATED[@]} -gt 0 ]; then
    echo ""
    echo "Migrated:"
    for item in "${MIGRATED[@]}"; do
      echo "  ~ $item"
    done
  fi
  if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo ""
    echo "Preserved (not modified):"
    for item in "${SKIPPED[@]}"; do
      echo "  - $item"
    done
  fi
  echo ""
  echo "Ready to use. Next steps:"
  echo "  1. Build tasks:    ralph task-build your-spec.md [plan-name]"
  echo "  2. Review tasks:   /task-review [plan-name]  (in Claude Code)"
  echo "  3. Run Ralph:      ralph run 20 [plan-name]"
  exit 0
fi

echo "Initialising Ralph in $TARGET_DIR..."

# --- Create .ralph/ structure ---
mkdir -p "$TARGET_DIR/.ralph/engine"
mkdir -p "$TARGET_DIR/.ralph/skills/tdd"
mkdir -p "$TARGET_DIR/.ralph/specs"
mkdir -p "$TARGET_DIR/.ralph/hooks"
mkdir -p "$TARGET_DIR/.ralph/logs"

# Config — copy preset and prepend ralph-specific paths
{
  echo "# Ralph configuration — generated from preset: $STACK"
  echo "# Edit these values to customise Ralph for your project."
  echo ""
  echo "# Active plan — resolves to .ralph/specs/tasks-<name>.json"
  echo "RALPH_PLAN="
  echo ""
  echo "# Directory layout (relative to project root)"
  echo "ENGINE_DIR=.ralph/engine"
  echo "SPECS_DIR=.ralph/specs"
  echo "SKILLS_DIR=.ralph/skills"
  echo "PROGRESS_FILE=.ralph/progress.txt"
  echo "LOG_DIR=.ralph/logs"
  echo ""
  echo "# Loop behaviour"
  echo "MAX_CALLS_PER_HOUR=60"
  echo "MAX_ITERATIONS=20"
  echo "CB_NO_PROGRESS_THRESHOLD=3"
  echo "CB_SAME_ERROR_THRESHOLD=5"
  echo "RATE_LIMIT_WAIT=120"
  echo "RATE_LIMIT_MAX_RETRIES=5"
  echo ""
  echo "# Stack-specific settings (from $STACK preset)"
  cat "$PRESET_FILE"
} > "$TARGET_DIR/.ralph/config.sh"

# Engine files
cp "$RALPH_HOME/engine/ralph.sh" "$TARGET_DIR/.ralph/engine/"
cp "$RALPH_HOME/engine/prompt.md" "$TARGET_DIR/.ralph/engine/"
cp "$RALPH_HOME/engine/task-build-prompt.md" "$TARGET_DIR/.ralph/engine/"
cp "$RALPH_HOME/engine/snapshot.sh" "$TARGET_DIR/.ralph/engine/"
chmod +x "$TARGET_DIR/.ralph/engine/ralph.sh"
chmod +x "$TARGET_DIR/.ralph/engine/snapshot.sh"

# Skills
cp "$RALPH_HOME"/skills/tdd/* "$TARGET_DIR/.ralph/skills/tdd/"

# Specs — architecture template (use clean template, not repo's populated version)
if [ -f "$RALPH_HOME/templates/architecture.md" ]; then
  cp "$RALPH_HOME/templates/architecture.md" "$TARGET_DIR/.ralph/specs/architecture.md"
fi

# Hooks
cp "$RALPH_HOME/.claude/hooks/block-dangerous-git.sh" "$TARGET_DIR/.ralph/hooks/"
chmod +x "$TARGET_DIR/.ralph/hooks/block-dangerous-git.sh"

# Progress file
cat > "$TARGET_DIR/.ralph/progress.txt" << 'EOF'
# Ralph Progress Log

## Codebase Patterns
(Patterns will be added here by Ralph as it discovers reusable conventions)

## Technical Debt
(refactoring needs noted during the build - address when capacity allows)

---

Started: (date will be filled by first iteration)
---
EOF

# --- Generate CLAUDE-ralph.md from template ---
# Read preset values for template substitution
source "$PRESET_FILE"
sed \
  -e "s|__TEST_CMD__|${TEST_CMD}|g" \
  -e "s|__TYPECHECK_CMD__|${TYPECHECK_CMD}|g" \
  -e "s|__LINT_CMD__|${LINT_CMD}|g" \
  "$RALPH_HOME/templates/CLAUDE-ralph.md" > "$TARGET_DIR/.ralph/CLAUDE-ralph.md"

# --- Set up .claude/ (merge, don't clobber) ---
mkdir -p "$TARGET_DIR/.claude/skills"

# Settings.json — merge hook entry
SETTINGS_FILE="$TARGET_DIR/.claude/settings.json"
HOOK_ENTRY='{"matcher":"Bash","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.ralph/hooks/block-dangerous-git.sh"}]}'

if [ -f "$SETTINGS_FILE" ]; then
  # Check if hook is already present
  if ! grep -q '.ralph/hooks/block-dangerous-git.sh' "$SETTINGS_FILE"; then
    # Merge: add hook entry to existing PreToolUse array
    if command -v jq &>/dev/null; then
      jq --argjson hook "$HOOK_ENTRY" '.hooks.PreToolUse += [$hook]' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    else
      echo "WARNING: jq not found — cannot merge settings.json. Add the hook manually."
    fi
  fi
else
  cat > "$SETTINGS_FILE" << 'SETTINGS_EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.ralph/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
SETTINGS_EOF
fi

# Copy task-review skill if not present (already handles both .ralph/ and legacy paths)
if [ ! -d "$TARGET_DIR/.claude/skills/task-review" ]; then
  cp -R "$RALPH_HOME/.claude/skills/task-review" "$TARGET_DIR/.claude/skills/"
fi

# --- CLAUDE.md: append directive if not already present ---
CLAUDE_MD="$TARGET_DIR/CLAUDE.md"
RALPH_DIRECTIVE='<!-- Ralph --> Read .ralph/CLAUDE-ralph.md for autonomous development loop instructions.'

if [ -f "$CLAUDE_MD" ]; then
  if ! grep -qF '<!-- Ralph -->' "$CLAUDE_MD"; then
    echo "" >> "$CLAUDE_MD"
    echo "$RALPH_DIRECTIVE" >> "$CLAUDE_MD"
  fi
else
  echo "$RALPH_DIRECTIVE" > "$CLAUDE_MD"
fi

# --- .gitignore: add Ralph entries ---
GITIGNORE="$TARGET_DIR/.gitignore"
add_gitignore() {
  local pattern="$1"
  if [ -f "$GITIGNORE" ]; then
    grep -qF "$pattern" "$GITIGNORE" || echo "$pattern" >> "$GITIGNORE"
  else
    echo "$pattern" > "$GITIGNORE"
  fi
}

add_gitignore ".ralph/logs/"
add_gitignore ".ralph-call-count"
add_gitignore "codebase-snapshot.md"

echo ""
echo "Ralph initialised in $TARGET_DIR"
echo ""
echo "Created:"
echo "  .ralph/              — Ralph engine, skills, specs, config"
echo "  .ralph/config.sh     — Edit to customise commands and behaviour"
echo "  .ralph/specs/        — Specs and generated task lists go here"
echo "  .claude/settings.json — Hook to block dangerous git commands"
echo ""
echo "Next steps:"
echo "  1. Write your spec:  Describe what you want built in a markdown file"
echo "  2. Build tasks:      ralph task-build your-spec.md [plan-name]"
echo "  3. Review tasks:     /task-review [plan-name]  (in Claude Code)"
echo "  4. Run Ralph:        ralph run 20 [plan-name]"
