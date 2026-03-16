#!/bin/bash
set -e

# Detect repo root: if we're in .ralph/engine/, go up two levels; else up one
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "$SCRIPT_DIR" == */.ralph/engine ]]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
else
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
SRC_DIR="$REPO_ROOT/${SNAPSHOT_SOURCE_DIR:-src}"
OUTPUT="$REPO_ROOT/codebase-snapshot.md"

# Exit silently if source dir doesn't exist
if [ ! -d "$SRC_DIR" ]; then
  exit 0
fi

# Config with defaults matching original behaviour
FILE_EXTENSIONS="${SNAPSHOT_FILE_EXTENSIONS:-ts,tsx,js,jsx}"
TEST_PATTERNS="${SNAPSHOT_TEST_PATTERNS:-*.test.*,*.spec.*}"
PARSER="${SNAPSHOT_PARSER:-typescript}"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Build find expressions from config
build_ext_args() {
  local exts="$1" first=true
  IFS=',' read -ra EXT_ARR <<< "$exts"
  for ext in "${EXT_ARR[@]}"; do
    if [ "$first" = true ]; then
      printf -- "-name '*.%s'" "$ext"
      first=false
    else
      printf -- " -o -name '*.%s'" "$ext"
    fi
  done
}

build_test_exclude() {
  local patterns="$1"
  IFS=',' read -ra PAT_ARR <<< "$patterns"
  for pat in "${PAT_ARR[@]}"; do
    printf -- " ! -name '%s'" "$pat"
  done
}

build_test_find() {
  local exts="$1" patterns="$2" first=true
  IFS=',' read -ra EXT_ARR <<< "$exts"
  IFS=',' read -ra PAT_ARR <<< "$patterns"
  for pat in "${PAT_ARR[@]}"; do
    local ext_part="${pat##*.}"
    if [[ "$pat" == *.* ]] && [[ "$ext_part" != "*" ]]; then
      # Pattern has a concrete extension (e.g., *_test.py) — use as-is
      if [ "$first" = true ]; then
        printf -- "-name '%s'" "$pat"
        first=false
      else
        printf -- " -o -name '%s'" "$pat"
      fi
    else
      # Pattern ends with .* or has no extension — combine with each ext
      local base="${pat%.\*}"  # Strip trailing .* if present
      for ext in "${EXT_ARR[@]}"; do
        if [ "$first" = true ]; then
          printf -- "-name '%s.%s'" "$base" "$ext"
          first=false
        else
          printf -- " -o -name '%s.%s'" "$base" "$ext"
        fi
      done
    fi
  done
}

# Collect source files into temp files (avoids mapfile / process substitution)
SRC_LIST=$(mktemp)
TEST_LIST=$(mktemp)
trap 'rm -f "$SRC_LIST" "$TEST_LIST"' EXIT

# Build and execute find for source files (exclude tests)
eval "find \"$SRC_DIR\" -type f \\( $(build_ext_args "$FILE_EXTENSIONS") \\) $(build_test_exclude "$TEST_PATTERNS") ! -path '*/node_modules/*'" | sort > "$SRC_LIST"

# Build and execute find for test files
eval "find \"$REPO_ROOT\" -type f \\( $(build_test_find "$FILE_EXTENSIONS" "$TEST_PATTERNS") \\) ! -path '*/node_modules/*'" | sort > "$TEST_LIST"

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
    case "$PARSER" in
      typescript)
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
            inner=$(echo "$line" | sed -E 's/.*\{(.*)\}.*/\1/')
            OLD_IFS="$IFS"
            IFS=','
            for part in $inner; do
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
        ;;

      python)
        while IFS= read -r f; do
          REL="${f#$REPO_ROOT/}"
          NAMES=""
          while IFS= read -r name; do
            if [ -n "$name" ]; then
              if [ -n "$NAMES" ]; then NAMES="$NAMES, $name"; else NAMES="$name"; fi
            fi
          done <<EOF_PYEXPORT
$(sed -nE 's/^(def|class)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/p' "$f")
EOF_PYEXPORT
          if [ -n "$NAMES" ]; then
            echo "  $REL: $NAMES"
          fi
        done < "$SRC_LIST"
        ;;

      generic)
        echo "  (generic parser — exports not analysed)"
        ;;
    esac
  fi
  echo ""

  # --- Import Graph ---
  echo "## Import Graph"
  if [ "$SRC_COUNT" -eq 0 ]; then
    echo "None"
  else
    case "$PARSER" in
      typescript)
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
        ;;

      python)
        while IFS= read -r f; do
          REL="${f#$REPO_ROOT/}"
          IMPORTS=""
          while IFS= read -r mod; do
            if [ -n "$mod" ]; then
              if [ -n "$IMPORTS" ]; then IMPORTS="$IMPORTS, $mod"; else IMPORTS="$mod"; fi
            fi
          done <<EOF_PYIMPORTS
$(sed -nE 's/^from[[:space:]]+(\.[A-Za-z_.]*)[[:space:]]+import.*/\1/p' "$f" | sort -u)
EOF_PYIMPORTS
          if [ -n "$IMPORTS" ]; then
            echo "  $REL → $IMPORTS"
          fi
        done < "$SRC_LIST"
        ;;

      generic)
        echo "  (generic parser — imports not analysed)"
        ;;
    esac
  fi
  echo ""

  # --- Tests ---
  echo "## Tests"
  if [ "$TEST_COUNT" -eq 0 ]; then
    echo "None"
  else
    while IFS= read -r f; do
      REL="${f#$REPO_ROOT/}"
      case "$PARSER" in
        typescript)
          COUNT=$(grep -cE '\b(it|test)\(' "$f" 2>/dev/null || echo "0")
          ;;
        python)
          COUNT=$(grep -cE '^\s*def test_' "$f" 2>/dev/null || echo "0")
          ;;
        generic)
          COUNT=$(wc -l < "$f" | tr -d ' ')
          COUNT="$COUNT lines"
          ;;
      esac
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
