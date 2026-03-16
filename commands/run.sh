#!/bin/bash
set -e

# commands/run.sh — Unified Ralph run wrapper
# Detects project layout (.ralph/ or legacy) and delegates to the engine.
# Usage: commands/run.sh [iterations] [plan-name]

# Detect layout
if [ -f ".ralph/config.sh" ]; then
  # New .ralph/ layout
  export RALPH_CONFIG=".ralph/config.sh"
  source "$RALPH_CONFIG"
  export ENGINE_DIR="${ENGINE_DIR:-.ralph/engine}"
  export SPECS_DIR="${SPECS_DIR:-.ralph/specs}"
  export SKILLS_DIR="${SKILLS_DIR:-.ralph/skills}"
  export PROGRESS_FILE="${PROGRESS_FILE:-.ralph/progress.txt}"
  export LOG_DIR="${LOG_DIR:-.ralph/logs}"
  exec "$ENGINE_DIR/ralph.sh" "$@"
elif [ -f ".ralphrc" ]; then
  # Legacy layout (backward compat)
  export RALPH_CONFIG=".ralphrc"
  exec engine/ralph.sh "$@"
else
  echo "ERROR: No Ralph configuration found."
  echo "  Expected .ralph/config.sh (new layout) or .ralphrc (legacy layout)"
  echo ""
  echo "To initialise Ralph in this project:"
  echo "  ralph init"
  exit 1
fi
