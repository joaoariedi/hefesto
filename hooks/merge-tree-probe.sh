#!/bin/bash
# merge-tree-probe.sh — surface integration conflicts while working, not at PR time.
#
# PostToolUse on Edit|Write, throttled to once a minute per repo. Two facts, both cheap:
#   1. `git merge-tree --write-tree HEAD <base>` (git ≥ 2.38): would the COMMITTED state of this
#      branch merge cleanly into its base? Exit 1 lists the conflicting paths.
#   2. How many commits has the base gained since this branch forked? A branch that drifts far
#      behind is the one whose eventual merge surprises everyone.
#
# Why: 27.7% of agent-authored PRs conflict (arXiv 2604.03551); two branches each green alone can
# be red together, and worktree isolation removes working-directory collisions but not this.
# The probe is advisory (exit 0, stderr) — it cannot see UNCOMMITTED edits, so it reports the
# committed picture plus the drift, which is the part a working agent otherwise never sees.
set -uo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0
[ "$CWD" = "$HOME" ] || [ "$CWD" = "/" ] && exit 0
git -C "$CWD" rev-parse --show-toplevel >/dev/null 2>&1 || exit 0

STAMP="${TMPDIR:-/tmp}/.hefesto-merge-probe-$(printf '%s' "$CWD" | md5sum | cut -d' ' -f1)"
NOW=$(date +%s)
if [ -f "$STAMP" ] && [ $((NOW - $(cat "$STAMP" 2>/dev/null || echo 0))) -lt 60 ]; then exit 0; fi
echo "$NOW" > "$STAMP"

BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
[ -z "$BRANCH" ] && exit 0
case "$BRANCH" in main|master|dev|develop) exit 0 ;; esac

BASE=""
for b in origin/main origin/master main master; do
  if git -C "$CWD" rev-parse --verify -q "$b" >/dev/null 2>&1; then BASE="$b"; break; fi
done
[ -z "$BASE" ] && exit 0
[ "$(git -C "$CWD" rev-parse "$BASE" 2>/dev/null)" = "$(git -C "$CWD" rev-parse HEAD 2>/dev/null)" ] && exit 0

# Textual conflicts, committed state.
out=$(git -C "$CWD" merge-tree --write-tree --name-only HEAD "$BASE" 2>/dev/null); rc=$?
if [ "$rc" -eq 1 ]; then
  # Output shape: <tree oid>, then one conflicted path per line, then a blank line, then git's
  # informational messages. Keep only the path block.
  files=$(printf '%s\n' "$out" | tail -n +2 | sed '/^$/q' | sed '/^$/d' | tr '\n' ' ')
  echo "hefesto: merge-tree probe — the committed state of $BRANCH would CONFLICT with $BASE in: $files" >&2
  echo "  Resolve before the diff grows: merge $BASE into this branch (never rebase a pushed branch)." >&2
fi

# Drift.
behind=$(git -C "$CWD" rev-list --count "HEAD..$BASE" 2>/dev/null || echo 0)
if [ "${behind:-0}" -ge 10 ]; then
  echo "hefesto: $BASE has $behind commit(s) this branch does not — integration risk grows with that number; merge it in soon." >&2
fi
exit 0
