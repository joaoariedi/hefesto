#!/bin/bash
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [ -z "$FILE_PATH" ] || [ -z "$CWD" ]; then
  exit 0
fi

FILENAME=$(basename "$FILE_PATH")
RELPATH="${FILE_PATH#"$CWD"/}"

# Skip non-source files: configs, docs, lock files, hidden files
case "$FILENAME" in
  *.md|*.txt|*.json|*.yaml|*.yml|*.toml|*.lock|*.log|.*)
    exit 0 ;;
esac

# Skip test files to avoid infinite loops
case "$RELPATH" in
  *test*|*spec*)  # covers __tests__, _test., .test., .spec. as well
    exit 0 ;;
esac

# Skip if no test runner is detectable
RUNNER=""
RUNNER_CMD=""

if [ -f "$CWD/package.json" ]; then
  # Check if test script exists in package.json
  if jq -e '.scripts.test' "$CWD/package.json" > /dev/null 2>&1; then
    TEST_SCRIPT=$(jq -r '.scripts.test' "$CWD/package.json")
    if [ "$TEST_SCRIPT" != "null" ] && [ -n "$TEST_SCRIPT" ]; then
      RUNNER="npm"
      RUNNER_CMD="npm test --prefix $CWD -- --passWithNoTests 2>&1 | tail -5"
    fi
  fi
elif [ -f "$CWD/pyproject.toml" ] || [ -f "$CWD/setup.py" ]; then
  if command -v pytest &>/dev/null; then
    RUNNER="pytest"
    RUNNER_CMD="cd $CWD && pytest -q --tb=line --no-header 2>&1 | tail -5"
  fi
elif [ -f "$CWD/Cargo.toml" ]; then
  if command -v cargo &>/dev/null; then
    RUNNER="cargo"
    RUNNER_CMD="cargo test --manifest-path $CWD/Cargo.toml --quiet 2>&1 | tail -5"
  fi
elif [ -f "$CWD/go.mod" ]; then
  if command -v go &>/dev/null; then
    RUNNER="go"
    RUNNER_CMD="cd $CWD && go test ./... 2>&1 | tail -5"
  fi
fi

if [ -z "$RUNNER" ]; then
  exit 0
fi

# Throttle: skip if tests ran less than 15 seconds ago
STAMP_FILE="${TMPDIR:-/tmp}/.claude-test-stamp-$(echo "$CWD" | md5sum | cut -d' ' -f1)"
NOW=$(date +%s)
if [ -f "$STAMP_FILE" ]; then
  LAST_RUN=$(cat "$STAMP_FILE")
  ELAPSED=$((NOW - LAST_RUN))
  if [ "$ELAPSED" -lt 15 ]; then
    exit 0
  fi
fi
echo "$NOW" > "$STAMP_FILE"

# Run tests and output results (non-blocking, always exit 0)
RESULT=$(eval "$RUNNER_CMD" 2>&1) || true
if [ -n "$RESULT" ]; then
  echo "[auto-test: $RUNNER] $RESULT"
fi

exit 0
