#!/bin/bash
# plan-phase-write-block.sh — Enforce read/plan-only mode during /hef.plan.
#
# Activates ONLY when .specify/.plan-in-progress exists (set by speckit-helper.sh
# plan-phase-start, cleared by plan-phase-end). While active, Edit/Write to any
# path outside .specify/ is blocked. Reads remain unrestricted so the agent can
# still build the Truth Map.
#
# RIPER-5 inspired: mechanical phase enforcement instead of trust-based.
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Missing fields — let the tool proceed; other hooks handle their concerns.
if [ -z "$FILE_PATH" ] || [ -z "$CWD" ]; then
  exit 0
fi

# Skip non-project directories
if [ "$CWD" = "$HOME" ] || [ "$CWD" = "/" ]; then
  exit 0
fi

MARKER="$CWD/.specify/.plan-in-progress"
if [ ! -f "$MARKER" ]; then
  exit 0  # Plan phase not active — no restrictions.
fi

# Plan phase active. Allow writes only under .specify/ (plan artifacts,
# research.md, memory/, checklists/, etc.).
case "$FILE_PATH" in
  *"/.specify/"* | ".specify/"* )
    exit 0
    ;;
esac

# Block and explain.
echo "Blocked: /hef.plan is active (plan phase write-block)." >&2
echo "  $FILE_PATH is outside .specify/ — editing it now violates phase boundaries." >&2
echo "  Finish plan.md, then run:  ${CLAUDE_PLUGIN_ROOT:-$HOME}/hooks/speckit-helper.sh plan-phase-end" >&2
echo "  To exit plan phase manually:  rm $MARKER" >&2
exit 2
