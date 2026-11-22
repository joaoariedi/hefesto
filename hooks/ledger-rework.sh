# shellcheck shell=bash
# shellcheck disable=SC2154  # DIR, HERE, ID, E come from ledger.sh, which sources this file
# ledger-rework.sh — `ledger.sh rework`: a verify FAIL goes back to the build stage with its findings (verify-fix-loop,
# HEF-57; plan Sketches 1–3). SOURCED by ledger.sh behind `[ -f ] || die`; never run on its own. Uses ledger.sh's
# globals and helpers (DIR, HERE, ID, E, die, usage, entry, write_entry, cfgp, hef_sha256, is_terminal_entry,
# am_not_worker, am_lane_role, am_is_launcher).
#
#   rework <id> [--summary-file <f>] [--head <sha>] [--past-cap --by <name>]
#   record <id> --rework-consumed | --rework-asked <dispute|other>     (the record arms; launcher-only)
#
# The shape is merge forward's (ledger-lifecycle.sh forward_*): every refusal before the first write (constitution 5);
# the cap is not a refusal but one written verdict block whose question file `ledger.sh questions` serves, exit 0, so
# the verify transcription that calls this never loops; the move is one rewrite with a generated, hashed brief.

[ -f "$HERE/rework-pairs.sh" ] || die "ledger: $HERE/rework-pairs.sh not found — the plugin install is incomplete (reinstall it)"
# shellcheck source=hooks/rework-pairs.sh
. "$HERE/rework-pairs.sh"

REWORK_SUMMARY_MAX=32768   # FR-003: the verifier's summary is ≤ 2000 chars by schema; anything near this is not one
REWORK_QUESTION_MAX=8000   # FR-006: what `ledger.sh questions` keeps of a question file

rework_cmd() {   # rework <id> [--summary-file f] [--head sha] [--past-cap --by <name>] — Sketch 1: refusals → cap → write
  local id="${1:-}" sf="" head="" past=0 by="" e open cap
  [ -n "$id" ] || usage; shift; rework_args "$id" "$@"
  [ -z "${HEFESTO_WORKER:-}" ] || [ "$HEFESTO_WORKER" = 0 ] || die "ledger rework $id: never from inside a launched worker — the launcher reworks from the verifier's structured output"
  # FR-003/D1: the plain form is the verify launcher's own move (launcher_gate's marker); no session bounces an entry
  [ "$past" = 1 ] || am_is_launcher \
    || die "ledger rework $id: the verify launcher's own move (HEFESTO_LAUNCHER=1, no session id) — a person past the cap uses ledger.sh rework $id --past-cap --by <name>"
  e=$(entry "$id") || exit 1; rework_guards "$id" "$e" "$past" "$sf"
  open=$(rework_findings "$e") || die "ledger rework $id: cannot read the entry's verdicts"
  [ "$open" != "[]" ] || die "ledger rework $id: no gate's latest verdict of this verify round is FAIL — nothing to fix"
  cap=$(verify_rounds_value) || exit 1
  if [ "$past" = 0 ] && [ "$(rework_rows_since_reopen "$e")" -ge "$cap" ]; then rework_cap_block "$id" "$e" "$open" "$cap"; return 0; fi
  rework_write "$id" "$e" "$open" "$sf" "$by" "$cap" "$head"
}

rework_args() { # $1 id, then the options → sets rework_cmd's sf, head, past, by; every malformed option dies here
  local id="$1"; shift
  while [ $# -gt 0 ]; do case "$1" in
    --summary-file) sf="${2:-}"; shift ;; --head) head="${2:-}"; shift ;; --past-cap) past=1 ;; --by) by="${2:-}"; shift ;;
    *) die "ledger rework $id: unexpected '$1' (expected --summary-file <f>, --head <sha>, --past-cap --by <name>)" ;; esac; shift; done
  # FR-013a: the commit the verifier saw — a full sha or nothing; it reaches the brief and the builder's prompt
  [ -z "$head" ] || [[ "$head" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] \
    || die "ledger rework $id: --head must be the full 40- or 64-hex commit the verifier saw, or empty (got '$head')"
  # FR-007/FR-016: --past-cap is a person's decision and names them — the parser refuses it bare, not only is_launcher_sub
  if [ "$past" = 0 ]; then [ -z "$by" ] || die "ledger rework $id: --by goes with --past-cap only (a routine rework records no person)"; return 0; fi
  [[ "$by" =~ ^[A-Za-z0-9]([A-Za-z0-9._@\ -]{0,62}[A-Za-z0-9._@-])?$ ]] \
    || die "ledger rework $id: --past-cap is a person's decision and needs --by <your name> (got '${by:-<none>}')"
}

rework_guards() { # $1 id, $2 entry JSON, $3 past-cap 0|1, $4 summary file — the refusals of FR-003; nothing is written
  local ph bk
  ! is_terminal_entry "$2" || die "ledger rework $1: the entry is $(jq -r .phase <<<"$2") — a closed item is never reworked"
  ph=$(jq -r '.phase // ""' <<<"$2")
  [ "$ph" = verify ] || die "ledger rework $1: phase is '$ph', not verify — only a verified entry goes back to the build stage"
  rework_pr_branch_ok "$1" "$2"
  [ "$(jq -r '.owner == null' <<<"$2")" = true ] \
    || die "ledger rework $1: owned by $(jq -r '.owner.session_name // "an unnamed owner"' <<<"$2") — the verify run releases it before its transcription reworks it"
  bk=$(jq -r '.blocked_on.kind // empty' <<<"$2")
  if [ "$3" = 1 ]; then [ "$bk" = verdict ] || die "ledger rework $1: --past-cap takes an entry blocked on verdict (the cap's block) — it is blocked on ${bk:-nothing}"
  else [ -z "$bk" ] || die "ledger rework $1: blocked on $bk — the command that block names clears it first"; fi
  # D8 / FR-003: a rework and a merge forward never overlap — "open" is forward_open_row's definition (a stale row
  # across a reopen is closed and does not refuse)
  [ "$(jq -r "$REWORK_PAIRS_JQ"' rework_reopen_at as $r | [(.forwards // [])[] | select(.consumed != true and (.at // "") > $r)] | length' <<<"$2")" = 0 ] \
    || die "ledger rework $1: a merge-forward row is open — the forward runs first, and a rework follows its verify"
  rework_summary_ok "$1" "$4"
}

rework_pr_branch_ok() { # $1 id, $2 entry JSON — the PR URL and the branch reach the builder's prompt (FR-003; forward's rules)
  local u b
  u=$(jq -r '.pr.url // empty' <<<"$2"); b=$(jq -r '.branch // empty' <<<"$2")
  [ -n "$u" ] || die "ledger rework $1: no PR URL is recorded — the builder has no pull request to fix"
  # the shape a forge gives, a plain path tail at most (ledger-lifecycle.sh forward_guards, HEF-31 verify r3)
  [[ "$u" =~ ^https://[A-Za-z0-9.-]+/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+(/[A-Za-z0-9._-]+)*$ ]] \
    || die "ledger rework $1: the recorded PR URL '$u' is not https://<host>/<owner>/<repo>/pull/<n>[/<path>]"
  # the branch reaches the builder's `git push origin HEAD:<branch>` unquoted (forward_cmd, scan 2026-11-22)
  [[ "$b" =~ ^[A-Za-z0-9._/-]+$ && "$b" != -* ]] \
    || die "ledger rework $1: the recorded branch '${b:-<none>}' is not a plain ref (letters, digits, . _ / -, no leading -)"
}

rework_summary_ok() { # $1 id, $2 summary file or "" — read into the brief, so never through a link and never huge
  [ -n "$2" ] || return 0
  [ ! -L "$2" ] || die "ledger rework $1: --summary-file '$2' is a link — the launcher writes a plain file"
  [ -f "$2" ] || die "ledger rework $1: --summary-file '$2' does not exist"
  [ "$(wc -c < "$2" | tr -d ' ')" -le "$REWORK_SUMMARY_MAX" ] || die "ledger rework $1: --summary-file '$2' is over 32 KB — the verifier's summary is ≤ 2000 chars"
}

rework_findings() { # $1 entry JSON → the open findings [{gate, by, evidence}] (D2, Sketch 2)
  # P9: only this round — verdicts written at or after the last implement run (no such run: all of them); then the
  # latest verdict per gate (the reduce session-launch.sh's verified-head check applies) and its FAILs
  jq -c '([(.runs // [])[] | select(.role == "implement") | .at] | max // "") as $t
    | [reduce ((.verdicts // [])[] | select((.at // "") >= $t)) as $v ({}; .[$v.gate] = $v) | to_entries[] | .value
    | select(.verdict == "FAIL") | {gate, by, evidence}]' <<<"$1"
}

verify_rounds_value() { # → orchestrate.verify_rounds, an integer 0–10 (absent → 3); FR-005: anything else dies
  # `// 3` would take false for absent (the plan_review_rounds precedent, session-launch.sh); a string is never a count
  local v; v=$(cfgp '.orchestrate.verify_rounds | if . == null then "3" elif type == "number" then tostring else "bad: " + tojson end')
  [[ "${v:-3}" =~ ^([0-9]|10)$ ]] || die "ledger rework: orchestrate.verify_rounds must be an integer from 0 to 10 (default 3) — got '$v'"
  printf '%s\n' "${v:-3}"
}

rework_rows_since_reopen() { # $1 entry JSON → how many rework rows since the last reopen (the count the cap compares, D6)
  jq "$REWORK_PAIRS_JQ"' rework_reopen_at as $r | [(.reworks // [])[] | select((.at // "") > $r)] | length' <<<"$1"
}

rework_brief() { # $1 id, $2 round, $3 cap, $4 entry JSON, $5 findings, $6 head, $7 summary file or "" → the fixed template
  # FR-004/D3: generated, never authored — the verifier's evidence and summary are data inside it, and the caller
  # rewrites every <!-- so a comment strip downstream cannot cut the brief short
  jq -r --arg id "$1" --arg n "$2" --arg c "$3" --arg h "$6" --argjson f "$5" '"# Rework round \($n) of \($c) — \($id)

- Pull request: \(.pr.url)
- Head the verifier saw: \(if $h == "" then "not recorded" else $h end)

## Open findings (the latest verdict of each gate this round: FAIL)
" + ($f | map("
### \(.gate) — FAIL (verifier session \(.by // "?"))

\(.evidence // "(no evidence recorded)")
") | join(""))' <<<"$4" || return 1
  [ -z "$7" ] || { printf '\n## The verifier'"'"'s run summary\n\n'; cat -- "$7"; printf '\n'; }
}

rework_write() { # $1 id, $2 entry JSON, $3 findings, $4 summary file, $5 by, $6 cap, $7 head → brief, hash, one rewrite
  local n dst h round
  n=$(( $(jq '.reworks // [] | length' <<<"$2") + 1 )); dst="$DIR/$1.rework-$n.md"
  round=$(( $(rework_rows_since_reopen "$2") + 1 ))   # P11.8: the round is the count since the last reopen, as the cap's
  rm -f -- "$dst"   # never written through a link (FR-004)
  rework_brief "$1" "$round" "$6" "$2" "$3" "$7" "$4" | sed 's/<!--/<!-\\-/g' > "$dst" || die "ledger rework $1: cannot write the brief $dst"
  h=$(hef_sha256 < "$dst")
  # FR-002/FR-013/FR-013a: attempts reset (each round gets the stall cap afresh); every earlier answer consumed (an
  # answer to a plan question never steers a fix — P4); every earlier row consumed, so one row is open (P6)
  jq --argjson n "$n" --arg h "$h" --arg by "$5" --arg hs "$7" '(if $by == "" then null else $by end) as $b
    | (if $hs == "" then null else $hs end) as $head
    | .phase = "implement" | .owner = null | .attempts = 0 | .blocked_on = null
    | (if .answers then .answers |= map(.consumed = true) else . end)
    | .reworks = (((.reworks // []) | map(.consumed = true))
        + [{n: $n, pr_url: .pr.url, head_sha: $head, sha256: $h, at: (now | todate), by: $b, consumed: false, asked: [], ruling: []}])
    | .events = ((.events // []) + [{kind: "rework", at: (now | todate), n: $n, head_sha: $head, by: $b}])' <<<"$2" \
    | write_entry "$1" || exit 1
  rm -f "$DIR/$1.lease"; echo "$1 verify → implement (rework $round of $6)"
}

rework_cap_question() { # $1 id, $2 entry JSON, $3 findings, $4 cap, $5 rounds taken → the cap's question text (FR-006)
  jq -r --arg id "$1" --arg c "$4" --arg k "$5" --argjson f "$3" "$REWORK_PAIRS_JQ"' rework_reopen_at as $r
    | "Verify of \($id) failed again after \($k) rework round(s) since its last reopen — orchestrate.verify_rounds is \($c), so the loop stops and a person decides.

Rounds taken: \($k)
" + ([(.reworks // [])[] | select((.at // "") > $r)] | to_entries | map("- round \(.key + 1): brief #\(.value.n) at \(.value.at), head \(.value.head_sha // "not recorded")\n") | join(""))
    + "
Open findings (the latest verdict of each gate this round: FAIL):
" + ($f | map("- \(.gate) (verifier session \(.by // "?")): \(.evidence // "(no evidence recorded)")\n") | join(""))
    + "
Another round: ledger.sh rework \($id) --past-cap --by <name> · Re-verify the same head: ledger.sh unblock \($id) · or later."' <<<"$2"
}

rework_cap_block() { # $1 id, $2 entry JSON, $3 findings, $4 cap → one verdict block with the findings question, exit 0 (FR-006)
  local q t k note
  k=$(rework_rows_since_reopen "$2"); q="$DIR/$1.question-$(date +%s).md"; t="$q.tmp"
  rm -f -- "$q" "$t"   # never written through a link
  rework_cap_question "$1" "$2" "$3" "$4" "$k" | sed 's/<!--/<!-\\-/g' > "$t" || { rm -f -- "$t"; die "ledger rework $1: cannot write the question $q"; }
  # ≤ 8000 bytes: what `ledger.sh questions` keeps; the head (the findings) survives the cut
  if [ "$(wc -c < "$t" | tr -d ' ')" -gt "$REWORK_QUESTION_MAX" ]; then { head -c 7900 "$t"; printf '\n[… cut to fit 8000 bytes …]\n'; } > "$q"; rm -f -- "$t"
  else mv -- "$t" "$q"; fi || die "ledger rework $1: cannot write the question $q"
  note="verify_rounds $4 reached after $k rework round(s) — a person decides: ledger.sh questions $1"
  # forward_block_reason's shape (ledger-lifecycle.sh): the block and its event in ONE write, so no half state
  jq --arg q "$q" --arg r "$note" '.blocked_on = {kind: "verdict", since: (now | todate), question_path: $q}
    | .events = ((.events // []) + [{kind: "rework-blocked", at: (now | todate), by: "ledger", note: $r}])' <<<"$2" \
    | write_entry "$1" || exit 1
  echo "$1 blocked_on verdict ($note)"
}

# --- record <id> --rework-consumed | --rework-asked <dispute|other> (FR-010, plan P13) -------------------------------
# The launcher's own records: a session that could close the open row would turn a rework run into an ordinary
# implement transcription, and one that could append to asked[] would plant a "dispute" whose answer waives a gate.
rework_record_gate() { # $1 the flag — verified_head_set's gate (ledger-automerge.sh:44-49): not a worker, not a lane, the marker
  am_not_worker "record $ID $1"
  [ -z "$(am_lane_role)" ] || die "ledger record $ID: $1 is the launcher's own record (session-launch.sh writes it after an implement run), never a lane's"
  am_is_launcher || die "ledger record $ID: $1 is the launcher's own record — only session-launch.sh writes it (HEFESTO_LAUNCHER=1, no session id)"
}

rework_consumed_set() { # updates E (record's entry): stamps the open row's ruling[] from rework_pairs, then consumes the
  # row and every unconsumed answer — in ONE jq step, so no flag order can consume the answers before they are paired (P10)
  local out
  rework_record_gate --rework-consumed
  out=$(jq -e "$REWORK_PAIRS_JQ"' rework_open_key as $k | if $k == null then null else rework_pairs as $p
      | .reworks[$k].ruling = ((.reworks[$k].ruling // []) + $p) | .reworks[$k].consumed = true
      | (if .answers then .answers |= map(.consumed = true) else . end) end' <<<"$E") \
    || die "ledger record $ID: --rework-consumed found no open rework row (unconsumed, newer than the last reopen) — nothing to consume"
  E="$out"
}

rework_asked_add() { # $1 dispute|other — updates E: the block's OWN question appended to the open row's asked[] (P13)
  local qp k out d=false
  rework_record_gate --rework-asked
  case "${1:-}" in dispute) d=true ;; other) ;; *) die "ledger record $ID: --rework-asked takes dispute or other (got '${1:-<none>}')" ;; esac
  [ -n "$(jq -r '.blocked_on.kind // empty' <<<"$E")" ] || die "ledger record $ID: --rework-asked records the question of a block, and the entry is not blocked"
  qp=$(jq -r '.blocked_on.question_path // empty' <<<"$E")   # never a caller-chosen file
  [ -n "$qp" ] || die "ledger record $ID: --rework-asked: the $(jq -r .blocked_on.kind <<<"$E") block carries no question_path"
  [ ! -L "$qp" ] && [ -f "$qp" ] || die "ledger record $ID: --rework-asked: the block's question file '$qp' is missing or a link"
  k=$(jq "$REWORK_PAIRS_JQ"' rework_open_key' <<<"$E")
  [[ "$k" =~ ^[0-9]+$ ]] || die "ledger record $ID: --rework-asked: no open rework row (unconsumed, newer than the last reopen) to record the question on"
  # answers_before: the ordinal rework_pairs matches exactly — the answer that clears this block gets this index
  out=$(jq --argjson k "$k" --arg p "$qp" --arg s "$(hef_sha256 < "$qp")" --argjson d "$d" \
    '.reworks[$k].asked = ((.reworks[$k].asked // []) + [{path: $p, sha256: $s, at: (now | todate), dispute: $d, answers_before: ((.answers // []) | length)}])' <<<"$E") \
    && [ -n "$out" ] || die "ledger record $ID: --rework-asked: cannot append to the rework row"
  E="$out"
}
