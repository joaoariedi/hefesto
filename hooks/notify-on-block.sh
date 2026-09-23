#!/bin/bash
set -euo pipefail

INPUT=$(cat)
MESSAGE=$(echo "$INPUT" | jq -r '.message // "Claude Code needs attention"')

# Throttle: skip if notified less than 30 seconds ago
STAMP_FILE="${TMPDIR:-/tmp}/.claude-notify-stamp"
NOW=$(date +%s)
if [ -f "$STAMP_FILE" ]; then
  LAST_RUN=$(cat "$STAMP_FILE")
  ELAPSED=$((NOW - LAST_RUN))
  if [ "$ELAPSED" -lt 30 ]; then
    exit 0
  fi
fi
echo "$NOW" > "$STAMP_FILE"

# Send desktop notification (platform-specific)
if command -v notify-send &>/dev/null; then
  # Linux (libnotify)
  notify-send "Claude Code" "$MESSAGE" --urgency=normal 2>/dev/null || true
elif command -v osascript &>/dev/null; then
  # macOS
  osascript -e "display notification \"$MESSAGE\" with title \"Claude Code\"" 2>/dev/null || true
fi

exit 0
