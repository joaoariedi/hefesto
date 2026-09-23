#!/bin/bash
# session-start-context.sh — the session-start ritual, mechanically.
#
# Anthropic's long-running-agent harness starts every session by reading the progress file, the git
# log, and the task list before touching code. SessionStart stdout is added to the model's context,
# so this hook does that reading once, cheaply, and hands over ~20 lines: branch, dirty files, spec
# artifacts, open tasks, and the last checkpoint precompact-progress.sh wrote (if it is recent).
#
# It also states the two routing rules the rest of the plugin assumes (spec before code for
# feature-sized work; root cause before any fix). Eval 2026-09-23: with nothing but the plugin
# installed — no CLAUDE.md, no rules — the model answered "add JWT auth, go ahead" by dispatching an
# implementation agent, in both ablation arms. Commands only route when they are invoked; a
# SessionStart line is the one channel the plugin has to say which command to invoke.
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
echo "hefesto routing: feature-sized work (a new capability, or anything touching an API, a schema, a new dependency, or more than ~5 files) starts with /hef.spec — /hef.brainstorm when the ask is fuzzy, /hef.agent to size and route it — never with implementation from the prompt alone; trivial changes go through /hef.fix"
echo "hefesto iron laws: no fix before a root-cause investigation (systematic-debugging skill) — a failing or flaky test is never skipped, retried, or loosened as a first move; size work by complexity and risk (task-effort-estimation skill), not by hours"
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
