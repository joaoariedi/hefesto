#!/bin/bash
# session-start-context.sh — the session-start ritual, mechanically.
#
# Anthropic's long-running-agent harness starts every session by reading the progress file, the git
# log, and the task list before touching code. SessionStart stdout is added to the model's context,
# so this hook does that reading once, cheaply, and hands over ~20 lines: branch, dirty files, spec
# artifacts, open tasks, and the last checkpoint precompact-progress.sh wrote (if it is recent).
#
# Prints nothing outside a git repo, so it costs zero context where it has nothing to say.
set -uo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"')
[ -z "$CWD" ] && exit 0
[ "$CWD" = "$HOME" ] || [ "$CWD" = "/" ] && exit 0
git -C "$CWD" rev-parse --show-toplevel >/dev/null 2>&1 || exit 0

BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
SPEC_DIR="$CWD/.specify/specs/${BRANCH#feature/}"
DIRTY=$(git -C "$CWD" status --short 2>/dev/null | wc -l | tr -d ' ')

echo "hefesto session context ($SOURCE): branch ${BRANCH:-detached}, $DIRTY uncommitted path(s)"
if [ -d "$SPEC_DIR" ]; then
  have=""
  for f in spec.md plan.md tasks.md; do [ -f "$SPEC_DIR/$f" ] && have="$have $f"; done
  echo "spec artifacts for this branch:${have:- none}"
  if [ -f "$SPEC_DIR/tasks.md" ]; then
    open=$(grep -cE '^\s*- \[[ ~]\]' "$SPEC_DIR/tasks.md" 2>/dev/null || echo 0)
    done_=$(grep -cE '^\s*- \[x\]' "$SPEC_DIR/tasks.md" 2>/dev/null || echo 0)
    echo "tasks: $done_ done, $open open — next:"
    grep -E '^\s*- \[[ ~]\]' "$SPEC_DIR/tasks.md" 2>/dev/null | head -3 | sed 's/^/  /'
  fi
fi
for m in plan implement; do
  [ -f "$CWD/.specify/.$m-in-progress" ] && echo "phase marker SET: .specify/.$m-in-progress (hooks are enforcing the $m phase)"
done

KEY=$(printf '%s' "$CWD" | sha1sum | cut -c1-16)
CKPT="${XDG_CACHE_HOME:-$HOME/.cache}/hefesto/progress/$KEY.md"
if [ -f "$CKPT" ] && [ -n "$(find "$CKPT" -mtime -7 2>/dev/null)" ]; then
  echo "last checkpoint ($(sed -n 's/^- when: //p' "$CKPT" | head -1)): $CKPT — read it before resuming interrupted work"
fi
exit 0
