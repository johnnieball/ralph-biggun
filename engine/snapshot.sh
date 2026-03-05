#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$REPO_ROOT/src"
OUTPUT="$REPO_ROOT/codebase-snapshot.md"

# Exit silently if src/ doesn't exist
if [ ! -d "$SRC_DIR" ]; then
  exit 0
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Collect source files into temp files (avoids mapfile / process substitution)
SRC_LIST=$(mktemp)
TEST_LIST=$(mktemp)
trap 'rm -f "$SRC_LIST" "$TEST_LIST"' EXIT

find "$SRC_DIR" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \) \
  ! -name '*.test.*' ! -name '*.spec.*' \
  ! -path '*/node_modules/*' | sort > "$SRC_LIST"

find "$REPO_ROOT" -type f \( -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.js' -o -name '*.test.jsx' \
  -o -name '*.spec.ts' -o -name '*.spec.tsx' -o -name '*.spec.js' -o -name '*.spec.jsx' \) \
  ! -path '*/node_modules/*' | sort > "$TEST_LIST"

SRC_COUNT=$(wc -l < "$SRC_LIST" | tr -d ' ')
TEST_COUNT=$(wc -l < "$TEST_LIST" | tr -d ' ')

{
  echo "# Codebase Snapshot"
  echo "Generated: $TIMESTAMP"
  echo ""

  # --- Files ---
  echo "## Files"
  if [ "$SRC_COUNT" -eq 0 ]; then
    echo "None"
  else
    while IFS= read -r f; do
      REL="${f#$REPO_ROOT/}"
      LINES=$(wc -l < "$f" | tr -d ' ')
      echo "  $REL ($LINES lines)"
    done < "$SRC_LIST"
  fi
  echo ""

  # --- Exports ---
  echo "## Exports"
  if [ "$SRC_COUNT" -eq 0 ]; then
    echo "None"
  else
    while IFS= read -r f; do
      REL="${f#$REPO_ROOT/}"
      NAMES=""

      # export (async )?(function|const|class|type|interface|enum) NAME
      while IFS= read -r name; do
        if [ -n "$name" ]; then
          if [ -n "$NAMES" ]; then NAMES="$NAMES, $name"; else NAMES="$name"; fi
        fi
      done <<EOF_NAMED
$(sed -nE 's/^export (async )?(function|const|class|type|interface|enum)[[:space:]*]+([A-Za-z_][A-Za-z0-9_]*).*/\3/p' "$f")
EOF_NAMED

      # export default function NAME / export default class NAME
      while IFS= read -r name; do
        if [ -n "$name" ]; then
          entry="default($name)"
          if [ -n "$NAMES" ]; then NAMES="$NAMES, $entry"; else NAMES="$entry"; fi
        fi
      done <<EOF_DEFAULT_NAMED
$(sed -nE 's/^export default (async )?(function|class)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3/p' "$f")
EOF_DEFAULT_NAMED

      # export default (anonymous) - only if no named default was found
      if grep -qE '^export default ' "$f" 2>/dev/null; then
        if ! grep -qE '^export default (async )?(function|class) [A-Za-z_]' "$f" 2>/dev/null; then
          if [ -n "$NAMES" ]; then NAMES="$NAMES, default"; else NAMES="default"; fi
        fi
      fi

      # export { foo, bar } from './baz' or export { foo, bar }
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        # Extract contents between { and }
        inner=$(echo "$line" | sed -E 's/.*\{(.*)\}.*/\1/')
        # Split on comma
        OLD_IFS="$IFS"
        IFS=','
        for part in $inner; do
          # Handle "foo as bar" - take the alias (bar)
          cleaned=$(echo "$part" | sed 's/.*as //' | tr -d ' ')
          if [ -n "$cleaned" ]; then
            if [ -n "$NAMES" ]; then NAMES="$NAMES, $cleaned"; else NAMES="$cleaned"; fi
          fi
        done
        IFS="$OLD_IFS"
      done <<EOF_REEXPORT
$(grep -E '^export \{' "$f" 2>/dev/null || true)
EOF_REEXPORT

      if [ -n "$NAMES" ]; then
        echo "  $REL: $NAMES"
      fi
    done < "$SRC_LIST"
  fi
  echo ""

  # --- Import Graph ---
  echo "## Import Graph"
  if [ "$SRC_COUNT" -eq 0 ]; then
    echo "None"
  else
    while IFS= read -r f; do
      REL="${f#$REPO_ROOT/}"
      IMPORTS=""

      while IFS= read -r mod; do
        if [ -n "$mod" ]; then
          if [ -n "$IMPORTS" ]; then IMPORTS="$IMPORTS, $mod"; else IMPORTS="$mod"; fi
        fi
      done <<EOF_IMPORTS
$(sed -nE "s/.*from ['\"](\\.?\\.\/[^'\"]*)['\"].*/\1/p" "$f" | sort -u)
EOF_IMPORTS

      if [ -n "$IMPORTS" ]; then
        echo "  $REL → $IMPORTS"
      fi
    done < "$SRC_LIST"
  fi
  echo ""

  # --- Tests ---
  echo "## Tests"
  if [ "$TEST_COUNT" -eq 0 ]; then
    echo "None"
  else
    while IFS= read -r f; do
      REL="${f#$REPO_ROOT/}"
      COUNT=$(grep -cE '\b(it|test)\(' "$f" 2>/dev/null || echo "0")
      echo "  $REL: $COUNT tests"
    done < "$TEST_LIST"
  fi
  echo ""

  # --- Alerts ---
  echo "## Alerts"
  ALERT_COUNT=0
  if [ "$SRC_COUNT" -gt 0 ]; then
    while IFS= read -r f; do
      REL="${f#$REPO_ROOT/}"
      LINES=$(wc -l < "$f" | tr -d ' ')
      if [ "$LINES" -gt 150 ]; then
        echo "  ⚠ $REL: $LINES lines - may contain long functions"
        ALERT_COUNT=$((ALERT_COUNT + 1))
      fi
    done < "$SRC_LIST"
  fi
  if [ "$ALERT_COUNT" -eq 0 ]; then
    echo "None"
  fi

} > "$OUTPUT"

echo "Snapshot generated: codebase-snapshot.md"
