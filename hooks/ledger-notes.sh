#!/bin/bash
# ledger-notes.sh — what the orchestrator routes to a lane, and what a lane leaves for its own next start
# (lanes-interactive, 9.0; #135, #140). SOURCED by ledger.sh; never run on its own. Uses ledger.sh's globals and
# helpers: DIR, ID, E, REVIEWED, RBY, die, entry, write_entry, person_gate, lanes_take_text, lanes_sha256, caller_lane_is.
#
#   direct <id> --to <lane> [--file <f>]        a directive (≤ 8 KB): narrows or orders work inside the item's scope
#   directives [--to <lane>] [--open]           the directives, each delimited as data
#   directive <id> <n> --done | --refused-file <f>   the lane it names closes it
#   note <id> --file <f>                        the claiming lane's progress note, read back at its next start
#   park --all                                  before an upgrade: which claims need a fresh note (claims stay)
#   release <id> --reviewed-by-human --by <n>   a person frees an interactive lane's claim
#   lanes                                       the lane map this project runs with
#
# A directive is the orchestrator's routing ("use head 5f3c0a9", "merge dev in first"), recorded and attributable —
# never an approval: no gate reads it, it clears nothing and grants nothing. Its text is data for the lane it names.

direct_item() { # globals: ID E TO TXT
  local n dst
  [[ "$TO" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || die "ledger direct $ID: --to must be a lane name (got '$TO')"
  if [ -n "${HEFESTO_LANE_MAP:-}" ]; then
    jq -e --arg t "$TO" '(.[$t] // "") as $r | $r != "" and $r != "orchestrator"' <<<"$HEFESTO_LANE_MAP" >/dev/null 2>&1 \
      || die "ledger direct $ID: '$TO' is not a stage lane of this project"
  fi
  n=$(( $(jq '.directives // [] | length' <<<"$E") + 1 )); dst="$DIR/$ID.directive-$n.md"
  lanes_take_text "$1" "$dst" direct
  [ "$(wc -c < "$dst" | tr -d ' ')" -le 8192 ] || { rm -f "$dst"; die "ledger direct $ID: over 8 KB — a directive is one instruction"; }
  jq --arg p "$dst" --arg s "$(lanes_sha256 "$dst")" --arg to "$TO" --argjson n "$n" \
    '.directives = ((.directives // []) + [{n: $n, to: $to, path: $p, sha256: $s, at: (now | todate), status: "open"}])' <<<"$E" | write_entry "$ID" || exit 1
  echo "$ID directive $n for $TO — ring that lane"
}

directives_list() { # args: [--to <lane>] [--open]
  local to="" open=0 f nonce
  while [ $# -gt 0 ]; do case "$1" in --to) to="${2:-}"; shift ;; --open) open=1 ;; *) die "ledger directives: unexpected '$1'" ;; esac; shift; done
  for f in "$DIR"/*.json; do
    [ -f "$f" ] || continue
    while IFS=$'\t' read -r id n dto path sha st at; do
      [ -n "$id" ] || continue
      nonce=$(od -An -N6 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
      echo "directive $id #$n for $dto · $st · $at"
      if [ ! -f "$path" ] || [ "$(lanes_sha256 "$path")" != "$sha" ]; then echo "  (its text changed after it was recorded — not shown; ask the orchestrator)"; continue; fi
      echo "<<<untrusted-directive-begin $id $n $nonce"; cat "$path"; echo "untrusted-directive-end $id $n $nonce>>>"
    done < <(jq -r --arg to "$to" --argjson open "$open" '.id as $id | .directives[]? | select(($to == "" or .to == $to) and ($open == 0 or .status == "open"))
      | [$id, .n, .to, .path, .sha256, .status, .at] | @tsv' "$f")
  done
}

directive_close() { # globals: ID E; args: <n> --done | --refused-file <f>
  local n="${1:-}" how="" f="" d; shift || true
  [[ "$n" =~ ^[0-9]+$ ]] || die "ledger directive $ID <n>: the directive's number"
  while [ $# -gt 0 ]; do case "$1" in --done) how="done" ;; --refused-file) how=refused; f="${2:-}"; shift ;; *) die "ledger directive: unexpected '$1'" ;; esac; shift; done
  [ -n "$how" ] || die "ledger directive $ID $n: --done, or --refused-file <f> with the reason"
  d=$(jq -c --argjson n "$n" '.directives[]? | select(.n == $n)' <<<"$E"); [ -n "$d" ] || die "ledger directive $ID: no directive $n"
  caller_lane_is "$(jq -r .to <<<"$d")"
  [ "$(jq -r .status <<<"$d")" = open ] || die "ledger directive $ID $n: already $(jq -r .status <<<"$d")"
  if [ "$how" = refused ]; then
    [ -f "$f" ] && [ "$(wc -c < "$f" | tr -d ' ')" -le 4096 ] || die "ledger directive $ID $n: --refused-file must name a file of at most 4 KB"
    jq --argjson n "$n" --rawfile r "$f" '.directives |= map(if .n == $n then .status = "refused" | .reason = $r | .closed_at = (now | todate) else . end)' <<<"$E" | write_entry "$ID" || exit 1
  else
    jq --argjson n "$n" '.directives |= map(if .n == $n then .status = "done" | .closed_at = (now | todate) else . end)' <<<"$E" | write_entry "$ID" || exit 1
  fi
  echo "$ID directive $n $how"
}

note_item() { # globals: ID E; $1 file
  local o; o=$(jq -r '.owner.session_name // empty' <<<"$E")
  [ -n "$o" ] || die "ledger note $ID: no lane holds it — a note belongs to the lane working on the item"
  caller_lane_is "$o"
  [ -f "${1:-}" ] && [ "$(wc -c < "$1" | tr -d ' ')" -le 16384 ] || die "ledger note $ID: --file must name a file of at most 16 KB"
  cp "$1" "$DIR/$ID.note.md" || die "ledger note $ID: cannot write the note"
  jq --arg by "$o" '.note_at = (now | todate) | .note_by = $by' <<<"$E" | write_entry "$ID" || exit 1
  echo "$ID note saved — the next start of $o reads it"
}

park_all() {
  local f
  for f in "$DIR"/*.json; do
    [ -f "$f" ] || continue
    jq -r 'select(.owner != null) | "\(.id) is held by \(.owner.session_name) (\(.owner.mode // "worker")) — \(if .note_at then "its note is from \(.note_at)" else "it has no note" end): before the upgrade, that lane writes one with ledger.sh note \(.id) --file <f>; the claim stays"' "$f"
  done
}

release_item() { # globals: ID E REVIEWED RBY
  person_gate "interactive claim" release
  [ "$(jq -r '.owner.mode // empty' <<<"$E")" = interactive ] || die "ledger release $ID: only an interactive lane's claim is released by hand — a background run's claim frees itself when its lease runs out"
  jq --arg by "$RBY" '.runs += [{role: .owner.role, session_name: .owner.session_name, exit: 125, usd: 0, note: "released by \($by)", at: (now | todate)}] | .owner = null' <<<"$E" | write_entry "$ID" || exit 1
  echo "$ID released by $RBY"
}

# orchestrate.lane_mode (FR-013): "worker" (the default — background sessions) or "interactive" (the stage lane does
# the work in its own conversation), for every stage or per stage {plan, build, deploy}.
lane_modes() {
  local c; c=$(jq -r '.config // empty' <<<"$BCTX")
  [ -n "$c" ] && [ -f "$c" ] || { echo '{"plan":"worker","build":"worker","deploy":"worker"}'; return; }
  jq -ce '(.orchestrate.lane_mode // "worker") as $m
    | def ok: . == "worker" or . == "interactive";
    if ($m | type) == "string" then (if ($m | ok) then {plan: $m, build: $m, deploy: $m} else error("orchestrate.lane_mode must be \"worker\" or \"interactive\" (got \($m))") end)
    elif ($m | type) == "object" then {plan: ($m.plan // "worker"), build: ($m.build // "worker"), deploy: ($m.deploy // "worker")}
      | if (to_entries | all(.value | ok)) then . else error("orchestrate.lane_mode.<stage> must be \"worker\" or \"interactive\"") end
    else error("orchestrate.lane_mode must be a string or {plan, build, deploy}") end' "$c" 2>&1 \
    || die "ledger lanes: the lane_mode in $c is not valid — \"worker\", \"interactive\" or {plan, build, deploy} of those"
}
lanes_print() {
  if [ "${1:-}" = --modes ]; then lane_modes; return; fi
  if [ -n "${HEFESTO_LANE_MAP:-}" ]; then jq -e . <<<"$HEFESTO_LANE_MAP" || die "ledger lanes: HEFESTO_LANE_MAP in the settings is not JSON — run hefesto-setup.sh --lanes again"; return; fi
  local c; c=$(jq -r '.config // empty' <<<"$BCTX"); [ -n "$c" ] || c="$PWD/.claude/project-status.json"
  resolve_lane_map "$c" "$(jq -r .board_top <<<"$BCTX")" | jq . || die "ledger lanes: the lane names in $c are not valid"
}
