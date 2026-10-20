#!/bin/bash
# lane-launch.sh — open one of the four permanent sessions of the pipeline (lanes-v2 FR-004), with the flags a
# lane needs and nothing more. Run it from the project's main folder:
#
#   bash ~/.claude-framework/hooks/lane-launch.sh orchestrator|plan|build|deploy [--print] [--keep-statusline]
#
# The session is named <repo>-<lane> and gets HEFESTO_LANE=<lane>, the default permission mode, the sandbox
# off (a lane starts background sessions, which run sandboxed), and an allowlist of hefesto's own helpers only:
# the read-only and registering calls /hef.status and /hef.orchestrate make. The commands that clear or rewrite
# a person's state — ledger.sh unblock, record, claim, advance, handoff, block — are in `ask`, which beats any broader
# allow rule inherited from user or project settings: their dialog always appears. Rules are written for both
# plugin roots (the clone this script runs from, and the profile's installed copy), with single and doubled
# slash, because a permission rule must match the command string exactly.
#   --print            print the command instead of running it
#   --keep-statusline  leave your status line alone (no context gauge)
# Not a hook — a helper.
set -uo pipefail
die() { echo "lane-launch: $*" >&2; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANE=""; PRINT=0; KEEP=0
while [ $# -gt 0 ]; do case "$1" in
  --print) PRINT=1 ;; --keep-statusline) KEEP=1 ;;
  -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  -*) die "unknown option '$1' (expected --print or --keep-statusline)" ;;
  *) [ -z "$LANE" ] || die "one lane at a time (got '$LANE' and '$1')"; LANE="$1" ;;
esac; shift; done
case "$LANE" in orchestrator|plan|build|deploy) ;; *) die "the lane must be orchestrator, plan, build or deploy (got '${LANE:-nothing}')" ;; esac
command -v jq >/dev/null 2>&1 || die "jq not found — install jq: https://jqlang.org"
TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository — run it from the project's main folder"
[ "$PRINT" = 1 ] || command -v claude >/dev/null 2>&1 || die "claude not found on PATH"

CLONE="$(dirname "$HERE")"
CACHE="$(jq -r '[.plugins["hefesto@hefesto"][]? | select(.scope == "user") | .installPath][0] // empty' \
  "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json" 2>/dev/null)"
roots=("$CLONE"); [ -n "$CACHE" ] && [ "$CACHE" != "$CLONE" ] && roots+=("${CACHE%/}")

allow=(); ask=()
for r in "${roots[@]}"; do for h in "$r/hooks" "$r//hooks"; do
  allow+=("Bash($h/status-board.sh)" "Bash($h/status-board.sh --detailed:*)" "Bash($h/status-board.sh --check:*)" "Bash($h/status-board.sh --item:*)"
          "Bash($h/ledger.sh board:*)" "Bash($h/ledger.sh list:*)" "Bash($h/ledger.sh next:*)" "Bash($h/ledger.sh show:*)" "Bash($h/ledger.sh metrics:*)"
          "Bash($h/ledger.sh register:*)" "Bash($h/ledger.sh publish:*)" "Bash($h/ledger.sh escalate:*)"
          "Bash($h/session-launch.sh:*)" "Bash($h/speckit-helper.sh:*)")
  # block too: replacing a person's block with another kind and relaunching was a route around the gate
  ask+=("Bash($h/ledger.sh unblock:*)" "Bash($h/ledger.sh record:*)" "Bash($h/ledger.sh claim:*)" "Bash($h/ledger.sh advance:*)" "Bash($h/ledger.sh handoff:*)" "Bash($h/ledger.sh block:*)")
done; done

SETTINGS="$(jq -nc --argjson allow "$(printf '%s\n' "${allow[@]}" | jq -R . | jq -sc .)" --argjson ask "$(printf '%s\n' "${ask[@]}" | jq -R . | jq -sc .)" \
  --arg gauge "$HERE/context-gauge.sh" --argjson keep "$KEEP" \
  '{sandbox: {enabled: false}, permissions: {allow: $allow, ask: $ask}} + (if $keep == 1 then {} else {statusLine: {type: "command", command: $gauge}} end)')" \
  || die "could not build the settings JSON"
CMD=(env "HEFESTO_LANE=$LANE" claude --name "$(basename "$TOP")-$LANE" --permission-mode default --settings "$SETTINGS")
if [ "$PRINT" = 1 ]; then printf '%q ' "${CMD[@]}"; echo; exit 0; fi
cd "$TOP" || die "cannot enter $TOP"
exec "${CMD[@]}"
