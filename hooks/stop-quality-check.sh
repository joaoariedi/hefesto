#!/bin/bash
set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [ -z "$CWD" ]; then
  exit 0
fi

# Skip non-project directories (e.g. home dir without a project marker)
if [ "$CWD" = "$HOME" ] || [ "$CWD" = "/" ]; then
  exit 0
fi

# Find the first source file modified in the last minute (≈ "did Claude edit
# code this turn"). Prune heavy dirs (node_modules/.venv/.git/build) so the walk
# stays cheap in large monorepos, and let `find` do the mtime test and quit on
# the first hit. The old version forked `stat` per matched file — ~11.7k forks /
# ~9s in a multi-service repo, which blew the 10s Stop-hook timeout (207/248
# stops timed out); it also false-fired on node_modules churn, which is not
# Claude editing code.
RECENT_EDITS=$(find "$CWD" -maxdepth 5 \
  \( -type d \( -name node_modules -o -name .venv -o -name venv -o -name .git \
     -o -name target -o -name dist -o -name build -o -name __pycache__ \) -prune \) \
  -o \( -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
     -o -name "*.py" -o -name "*.rs" -o -name "*.go" \) -mmin -1 -print -quit \) \
  2>/dev/null || true)

if [ -z "$RECENT_EDITS" ]; then
  exit 0
fi

# Check if tests were run recently (within last 60 seconds)
STAMP_FILE="${TMPDIR:-/tmp}/.claude-test-stamp-$(echo "$CWD" | md5sum | cut -d' ' -f1)"
if [ -f "$STAMP_FILE" ]; then
  LAST_RUN=$(cat "$STAMP_FILE")
  NOW=$(date +%s)
  ELAPSED=$((NOW - LAST_RUN))
  if [ "$ELAPSED" -lt 60 ]; then
    exit 0
  fi
fi

# Source files were edited but tests weren't run
echo "Reminder: source files were modified but tests haven't been run this turn." >&2

exit 0
