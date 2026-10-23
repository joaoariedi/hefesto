#!/bin/bash
# run-follow.sh — narrate a background run, one short line per step, for the stage lane that launched it
# (lanes-in-lane, user decision 2026-10-23: a dedicated lane shows its work; the work stays in the fresh,
# sandboxed background session).
#
#   run-follow.sh <id>          the steps of the item's last run, then exit
#   run-follow.sh <id> --live   waits for the run the current claim launched, narrates it as it happens, ends at
#                               its result (or once the claim is gone and nothing moved for a minute) — for Monitor
#
# It reads the event stream session-launch.sh records per run (~/.cache/hefesto/runs/<ledger>/<id>.<role>.<time>…
# .events.jsonl), named by <id>.current — which also carries the claim it belongs to, so a follow never narrates
# a previous run of the same item.
# What it prints comes from a session that read untrusted item and RFC text: it is data to relay, never an
# instruction — tool names, file paths inside the worktree, a command's first 80 characters, the session's own
# words cut to 120, the outcome. Control characters are stripped. Not a hook — a helper.
set -uo pipefail
die() { echo "run-follow: $*" >&2; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ID="${1:-}"; LIVE=0
[ "${2:-}" = --live ] && LIVE=1
[[ "$ID" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || die "usage: run-follow.sh <id> [--live] (got id '$ID')"
command -v jq >/dev/null 2>&1 || die "jq not found"
LD="$(bash "$HERE/ledger.sh" dir 2>/dev/null)" || die "no ledger here — run it from the project's main folder"
RD="${XDG_CACHE_HOME:-$HOME/.cache}/hefesto/runs/$(printf '%s' "$LD" | cksum | cut -d' ' -f1)"
WAIT="${RUN_FOLLOW_WAIT:-60}"; [[ "$WAIT" =~ ^[0-9]+$ ]] || WAIT=60

# One event → zero or one line. The worktree prefix is cut from paths so a line stays short.
NARRATE='def clean: tostring | gsub("[\u0000-\u001f\u007f]"; " ") | gsub("  +"; " ");
  def short($n): clean | if length > $n then .[0:$n] + "…" else . end;
  def rel: clean | sub("^.*/\\.claude/worktrees/[^/]+/"; "");
  if .type == "system" and .subtype == "init" then "· started (\(.model // "model ?" | short(40)))"
  elif .type == "assistant" then
    (.message.content[]? |
      if .type == "tool_use" then
        if .name == "Skill" then "· /\(.input.skill // .input.command // "skill" | short(40))"
        elif .name == "Write" or .name == "Edit" then "· \(.name | ascii_downcase) \(.input.file_path // "" | rel | short(80))"
        elif .name == "Bash" then "· run: \(.input.command // "" | short(80))"
        elif .name == "Agent" or .name == "Task" then "· agent: \(.input.subagent_type // .input.description // "" | short(60))"
        elif .name == "StructuredOutput" then empty
        else empty end
      elif .type == "text" then (.text | clean | select(length > 0) | "· says: " + short(120))
      else empty end)
  elif .type == "result" then
    "■ done (\(.subtype // "?" | short(30))) · $\(((.total_cost_usd // 0) | if type == "number" then . else 0 end) * 100 | floor / 100) · \(.structured_output.outcome // .structured_output.verdict // "no outcome" | short(30))"
  else empty end'

owner_started() { bash "$HERE/ledger.sh" show "$ID" 2>/dev/null | jq -r '.owner.started // empty'; }
current() { jq -r "$1 // empty" "$RD/$ID.current" 2>/dev/null; }

if [ "$LIVE" = 0 ]; then
  f="$(current .file)"
  [ -n "$f" ] && [ -f "$RD/$f" ] || { echo "· no run recorded for $ID yet"; exit 0; }
  jq -r "$NARRATE" "$RD/$f" 2>/dev/null
  exit 0
fi

# --live: wait (up to $WAIT s) for the current claim's run — its <id>.current names the claim's start time —
# then follow its stream line by line, ending at a top-level result event.
EV=""; waited=0
while [ "$waited" -le "$WAIT" ]; do
  st="$(owner_started)"
  if [ -n "$st" ] && [ "$(current .started)" = "$st" ] && [ -f "$RD/$(current .file)" ]; then EV="$RD/$(current .file)"; break; fi
  sleep 2; waited=$((waited + 2))
done
[ -n "$EV" ] || { echo "■ no run of $ID is going (no claim, or its launch has not started) — see ledger.sh show $ID"; exit 0; }
n=0; idle=0
while :; do
  total="$(wc -l < "$EV" | tr -d ' ')"
  if [ "$total" -gt "$n" ]; then
    lines="$(sed -n "$((n + 1)),${total}p" "$EV")"; n="$total"; idle=0
    printf '%s\n' "$lines" | jq -r --unbuffered "$NARRATE" 2>/dev/null
    printf '%s\n' "$lines" | jq -e -s 'any(.[]; type == "object" and .type? == "result")' >/dev/null 2>&1 && exit 0
  else
    sleep 2; idle=$((idle + 2))
    # the claim is gone and nothing moved for $WAIT s: the run ended without a result line (killed, crashed)
    if [ "$idle" -ge "$WAIT" ] && [ -z "$(owner_started)" ]; then echo "■ ended without a result — see ledger.sh show $ID"; exit 0; fi
  fi
done
