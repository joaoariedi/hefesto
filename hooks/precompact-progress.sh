#!/bin/bash
# precompact-progress.sh — write the progress checkpoint context-management.md asks for, mechanically.
#
# PreCompact fires right before the conversation is summarised — the moment the rule says "write a
# progress file". A rule the model has to remember at the exact moment its context is fullest is the
# rule least likely to run. This hook runs instead: branch, tree state, spec artifacts, open tasks,
# recent commits — the facts a resumed session needs and a summary tends to lose.
#
# Written OUTSIDE the repo (XDG cache), keyed by cwd, so a hook never dirties a working tree.
# session-start-context.sh reads it back. Never blocks; never spends a model call.
set -uo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "unknown"')
[ -z "$CWD" ] && exit 0
[ "$CWD" = "$HOME" ] || [ "$CWD" = "/" ] && exit 0
git -C "$CWD" rev-parse --show-toplevel >/dev/null 2>&1 || exit 0

DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hefesto/progress"
mkdir -p "$DIR" 2>/dev/null || exit 0
KEY=$(printf '%s' "$CWD" | sha1sum | cut -c1-16)
OUT="$DIR/$KEY.md"

BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
SPEC_DIR="$CWD/.specify/specs/${BRANCH#feature/}"

{
  echo "# Progress checkpoint"
  echo "- when: $(date -u +%Y-%m-%dT%H:%M:%SZ) (trigger: $TRIGGER)"
  echo "- repo: $CWD"
  echo "- branch: ${BRANCH:-detached}"
  echo
  echo "## Working tree"
  git -C "$CWD" status --short 2>/dev/null | head -30
  echo
  echo "## Recent commits"
  git -C "$CWD" log --oneline -5 2>/dev/null
  if [ -d "$SPEC_DIR" ]; then
    echo
    echo "## Spec artifacts ($SPEC_DIR)"
    for f in spec.md plan.md tasks.md; do
      [ -f "$SPEC_DIR/$f" ] && echo "- $f: present" || echo "- $f: missing"
    done
    if [ -f "$SPEC_DIR/tasks.md" ]; then
      echo
      echo "## Open tasks"
      grep -E '^\s*- \[[ ~]\]' "$SPEC_DIR/tasks.md" 2>/dev/null | head -20
    fi
  fi
  for m in plan implement; do
    [ -f "$CWD/.specify/.$m-in-progress" ] && echo "- phase marker: $m-in-progress is SET"
  done
} > "$OUT" 2>/dev/null

echo "hefesto: progress checkpoint written to $OUT" >&2
exit 0
