#!/bin/bash
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [ -z "$FILE_PATH" ] || [ -z "$CWD" ]; then
  exit 0
fi

FILENAME=$(basename "$FILE_PATH")

# Skip non-source files: configs, docs, lock files, hidden files
case "$FILENAME" in
  *.md|*.txt|*.json|*.yaml|*.yml|*.toml|*.lock|*.log|.*)
    exit 0 ;;
esac

# Skip test files (formatting is handled when tests are written)
RELPATH="${FILE_PATH#"$CWD"/}"
case "$RELPATH" in
  *test*|*spec*)  # covers __tests__, _test., .test., .spec. as well
    exit 0 ;;
esac

# Throttle: skip if formatted less than 10 seconds ago
STAMP_FILE="/tmp/.claude-format-stamp-$(echo "$CWD" | md5sum | cut -d' ' -f1)"
NOW=$(date +%s)
if [ -f "$STAMP_FILE" ]; then
  LAST_RUN=$(cat "$STAMP_FILE")
  ELAPSED=$((NOW - LAST_RUN))
  if [ "$ELAPSED" -lt 10 ]; then
    exit 0
  fi
fi
echo "$NOW" > "$STAMP_FILE"

FORMATTER=""

# Detect language by file extension and run appropriate formatter
case "$FILENAME" in
  *.py)
    if command -v ruff &>/dev/null; then
      FORMATTER="ruff"
      ruff format "$FILE_PATH" >/dev/null 2>&1 || true
    fi
    ;;
  *.js|*.jsx|*.ts|*.tsx)
    if [ -f "$CWD/biome.json" ] || [ -f "$CWD/biome.jsonc" ]; then
      FORMATTER="biome"
      npx biome format --write "$FILE_PATH" >/dev/null 2>&1 || true
    elif command -v prettier &>/dev/null || [ -f "$CWD/.prettierrc" ] || [ -f "$CWD/.prettierrc.json" ]; then
      FORMATTER="prettier"
      npx prettier --write "$FILE_PATH" >/dev/null 2>&1 || true
    fi
    ;;
  *.go)
    if command -v gofmt &>/dev/null; then
      FORMATTER="gofmt"
      gofmt -w "$FILE_PATH" >/dev/null 2>&1 || true
    fi
    ;;
  *.rs)
    if command -v rustfmt &>/dev/null; then
      FORMATTER="rustfmt"
      rustfmt "$FILE_PATH" >/dev/null 2>&1 || true
    fi
    ;;
  *.java)
    # Skip: Java Spotless runs project-wide, handled by pre-commit hook
    exit 0
    ;;
esac

if [ -n "$FORMATTER" ]; then
  echo "[auto-format: $FORMATTER] $FILENAME"
fi

exit 0
