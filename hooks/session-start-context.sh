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
# Which hefesto THIS process loaded — read from the tree the hook runs from, not the profile registry
# (which names what the NEXT process will load). After a `plugin update`, a resumed transcript still
# shows the old process's output; this line is the current process's own evidence (fxcube 2026-10-06).
HROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
HVER="$(jq -r '.version // empty' "$HROOT/.claude-plugin/plugin.json" 2>/dev/null)"
[ -n "$HVER" ] && echo "hefesto $HVER hooks loaded from $HROOT"
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

# Blocked ledger entries (session-orchestration FR-015): one line per entry waiting on a human or a
# failed gate, read from the repository's COMMON git dir so every worktree sees the same list. A
# blocked item that nobody can see is the escalation gap no vendor documents (report 17 §5d).
LDIR="${HEFESTO_LEDGER_DIR:-$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/hefesto/ledger}"
PCFG="$CWD/.claude/project-status.json"
# external-board: a pane in a code repo sees the CENTRAL ledger and the board's panes, as `ledger.sh board`
# resolves them. Fail open — a missing, slow or failing resolution keeps the in-repo reading above and never
# fails the session start.
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
if [ -f "$HERE/ledger.sh" ]; then
  TO=(); command -v timeout >/dev/null 2>&1 && TO=(timeout 5)   # coreutils; macOS may lack it — then unbounded
  BCTX="$(cd "$CWD" 2>/dev/null && "${TO[@]}" bash "$HERE/ledger.sh" board 2>/dev/null)" || BCTX=""
  if [ "$(jq -r '.mode // empty' <<<"$BCTX" 2>/dev/null)" = external ]; then
    LDIR="$(jq -r .ledger_dir <<<"$BCTX")"; PCFG="$(jq -r .config <<<"$BCTX")"
  fi
fi
if [ -d "$LDIR" ]; then
  # Every blocked line names the pane that owns the kind (stage-roles FR-010; report 18 addendum A3), from
  # orchestrate.panes in the project config merged over the built-in map. The config's entries come AFTER
  # the default's and from_entries is last-wins, so a config pane that names a kind already in a default
  # pane takes it over. A malformed map must never cost the line: `panes` that is not an object → {}
  # (select() would yield EMPTY output at exit 0 and an || would not fire); a pane value that is not an
  # array breaks `.value[]` → the fallback below; an empty result is caught before --argjson.
  PANES_DEFAULT='{"orchestrator":["human:intake"],"plan":["human:clarify","human:plan-review"],"build":["verdict","stall","budget","conflict"],"deploy":["ci","human:merge"]}'
  CFG_PANES="$(jq -c '(.orchestrate.panes // {}) | if type == "object" then . else {} end' "$PCFG" 2>/dev/null)"; [ -n "$CFG_PANES" ] || CFG_PANES='{}'
  KIND2PANE="$(jq -nc --argjson d "$PANES_DEFAULT" --argjson c "$CFG_PANES" '[$d, $c] | map(to_entries[]) | map(.key as $p | .value[] | select(type == "string") | {key: ., value: $p}) | from_entries' 2>/dev/null)"
  [ -n "$KIND2PANE" ] || KIND2PANE="$(jq -nc --argjson d "$PANES_DEFAULT" '$d | to_entries | map(.key as $p | .value[] | {key: ., value: $p}) | from_entries')"
  for f in "$LDIR"/*.json; do
    [ -f "$f" ] || continue
    jq -r --argjson k "$KIND2PANE" 'select(.blocked_on != null) | "ledger: \(.id) blocked_on \(.blocked_on.kind) since \(.blocked_on.since) → \($k[.blocked_on.kind] // "orchestrator") pane — " + (if .blocked_on.kind == "human:intake" then "a person reads the item (status-board.sh --item \(.id)) and clears it: ledger.sh unblock \(.id) --reviewed-by-human --by <name>" else "resolve with the human command it names, then ledger.sh unblock \(.id)" end)' "$f" 2>/dev/null
  done
  # The intake gate is a permission dialog the person answers — there is none under auto, bypassPermissions
  # or dontAsk. Best effort: the last defaultMode among user, project and local settings.
  if grep -lq '"human:intake"' "$LDIR"/*.json 2>/dev/null; then
    PMODE=""
    for sf in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" "$CWD/.claude/settings.json" "$CWD/.claude/settings.local.json"; do
      m="$(jq -r '.permissions.defaultMode // empty' "$sf" 2>/dev/null)"; [ -n "$m" ] && PMODE="$m"
    done
    case "$PMODE" in auto|bypassPermissions|dontAsk)
      echo "hefesto WARNING: a human:intake block is open and this session's permission mode is '$PMODE' — no dialog will ask you before 'ledger.sh unblock --reviewed-by-human' runs; clear intake blocks from a pane in default mode (docs/install.md §7)" ;;
    esac
  fi
fi

KEY=$(printf '%s' "$CWD" | sha1sum | cut -c1-16)
CKPT="${XDG_CACHE_HOME:-$HOME/.cache}/hefesto/progress/$KEY.md"
if [ -f "$CKPT" ] && [ -n "$(find "$CKPT" -mtime -7 2>/dev/null)" ]; then
  echo "last checkpoint ($(sed -n 's/^- when: //p' "$CKPT" | head -1)): $CKPT — read it before resuming interrupted work"
fi
exit 0
