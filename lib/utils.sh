#!/bin/bash

# lib/utils.sh — Shared utilities for Ralph scripts

# Portable in-place sed (macOS requires '' as separate arg)
portable_sed() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}
