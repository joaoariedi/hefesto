#!/bin/bash
# ledger.sh — the machine-readable state of one board item as it moves through the session
# pipeline (/hef.orchestrate, session-launch.sh). One JSON file per item, written ONLY by this
# helper, in the repository's git COMMON dir:
#
#   <git-common-dir>/hefesto/ledger/<id>.json      (HEFESTO_LEDGER_DIR overrides, for tests)
#
# Why there: it is shared by every worktree of the repository, never committed, never a merge
# conflict, not under .claude/ (constitution 1), and inside the sandbox's writable root — the
# ~/.cache location report 17 proposed is not writable from a sandboxed Bash tool.
#
# FETCHER (speckit-helper.sh contract): the answer on stdout at exit 0, or the offending value and
# the expected shape on stderr at non-zero. No exit-0 sentinel (constitution 5). Usage errors exit 2.
#
# Every guard here is a `die` the smoke suite mutation-checks: a second claim, a backwards phase,
# a review verdict by the author, a human:* block cleared without the artifact evidence the human's
# action leaves behind (a control that lives only as text is the failure class of the Replit and
# "Comment and Control" incidents — report 17 §1f).
#
# Zero-install: bash, jq, git, sha256sum (constitution 4).
set -uo pipefail

die() { echo "$*" >&2; exit 1; }
usage() {
  cat >&2 <<'EOF'
usage: ledger.sh <subcommand> …
  dir                                                   print the ledger directory
  init <id> --kind <tasks-repo|github-project> --ref <ref> [--url <u>] [--body-file <f>]
  claim <id> --session <name> --role <role>             exclusive; attempts > 2 → stall
  advance <id> <phase>                                  forward-only along the phase enum
  verdict <id> --gate <g> --verdict <PASS|FAIL|SKIPPED> --by <session> [--evidence <text>]
  block <id> --kind <kind> [--question <path>]
  unblock <id> [--reviewed-by-human]                    human:* kinds need artifact evidence
  run <id> --role <role> --exit <n> --usd <x> [--session-id <s>]   records the run, releases owner
  record <id> [--worktree w] [--branch b] [--route r] [--pr url] [--spec-dir d] [--body-file f]   (--body-file re-hashes the item)
  show <id> | list [--phase p] [--blocked] [--active] [--today] | next
  metrics [--since YYYY-MM-DD] [--json]                 delivery numbers from the entries (report 17 §7)
EOF
  exit 2
}

command -v jq >/dev/null 2>&1 || die "ledger: jq not found — install jq: https://jqlang.org"

# Sort ids by prefix then NUMERIC suffix: lexical order would dispatch HEF-10 before HEF-9 (review 2026-09-27).
ID_SORT='sort_by(.id | (capture("^(?<p>.*?)(?<n>[0-9]+)$") // {p: ., n: "0"}) | [.p, (.n | tonumber)])'
PHASES=(queued intake spec plan plan-review tasks implement verify quality security pr merged released)
KINDS="human:clarify human:plan-review human:merge human:intake ci conflict budget stall verdict"
GATES="verify review quality scan mutate"

ledger_dir() {
  if [ -n "${HEFESTO_LEDGER_DIR:-}" ]; then mkdir -p "$HEFESTO_LEDGER_DIR" || die "ledger: cannot create $HEFESTO_LEDGER_DIR"; echo "$HEFESTO_LEDGER_DIR"; return; fi
  local common
  # The plugin-eval sandbox denies the git binary while the workspace is still a git repository
  # (evals/README.md): fall back to the checkout's own .git so the evals can read the ledger.
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || { [ -d "$PWD/.git" ] && common="$PWD/.git"; } \
    || die "ledger: not inside a git repository (cwd: $PWD)"
  mkdir -p "$common/hefesto/ledger" || die "ledger: cannot create $common/hefesto/ledger"
  echo "$common/hefesto/ledger"
}

phase_index() { # name → index, or die
  local i; for i in "${!PHASES[@]}"; do [ "${PHASES[$i]}" = "$1" ] && { echo "$i"; return; }; done
  die "ledger: unknown phase '$1' (expected one of: ${PHASES[*]})"
}
in_list() { local w; for w in $2; do [ "$w" = "$1" ] && return 0; done; return 1; }

valid_id() { # ids become file names, worktree names and regex atoms: one shape, checked once
  [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || die "ledger: invalid id '$1' (expected [A-Za-z][A-Za-z0-9_-]*, e.g. HEF-12)"
}
entry() { # $1 id → JSON on stdout, or die
  valid_id "$1" || exit 1
  local f="$DIR/$1.json"
  [ -f "$f" ] || die "ledger: no entry '$1' (expected $f — run: ledger.sh init $1 --kind … --ref …)"
  cat "$f"
}
write_entry() { # $1 id; stdin = new JSON. temp + mv in the same dir: a reader never sees a torn file
  # Callers MUST append `|| exit 1`: this runs as the last stage of a pipeline, i.e. in a subshell,
  # so a `die` here ends only that subshell — pipefail carries the failure to the caller, which must
  # act on it. Quality gate 2026-09-27 reproduced both a wiped entry (empty jq output, exit 0) and a
  # failed write reported as success; the -s test and the `|| exit 1` convention are the fixes.
  local f="$DIR/$1.json" t
  t=$(mktemp "$DIR/.$1.XXXXXX") || die "ledger: cannot write in $DIR"
  # jq -e exits 4 on EMPTY input (a failed upstream jq) and 1 on null — plain jq would exit 0 and
  # replace the entry with an empty file.
  if ! jq -e '.updated = (now | todate)' > "$t" 2>/dev/null; then rm -f "$t"; die "ledger: refusing to write empty or invalid JSON for $1"; fi
  mv "$t" "$f" || { rm -f "$t"; die "ledger: cannot replace $f"; }
}

# --- metrics (plan-review-and-metrics FR-105): compute in jq, render in bash --------------------
# The Phase 1 numbers report 17 §7 committed to, from what the launcher wrote — never from memory.
# Two figures are approximations and say so: implement→verify uses the first run of each role;
# verify→merge uses the merged entry's `updated` (normally the `advance merged` write). `median` on
# an even count returns the upper-middle value.
metrics_compute() { # $1 since (or ""), $@ files → one JSON object on stdout
  local since="$1"; shift
  jq -s --arg since "$since" '
      def hours($a; $b): (($b | fromdate) - ($a | fromdate)) / 3600;
      def median: if length == 0 then null else (sort | .[(length / 2) | floor]) end;
      def r1: if . == null then null else ((. * 10) | round) / 10 end;
      map(select($since == "" or .created >= $since)) as $e
      | ($e | map(select(.phase == "merged" or .phase == "released"))) as $m
      | ($e | map(select(.phase == "pr" or .phase == "merged" or .phase == "released" or .pr != null))) as $p
      | ($e | map(select(any(.runs[]?; .role == "verify")))) as $v
      | { entries: ($e | length),
          by_phase: ($e | group_by(.phase) | map({key: .[0].phase, value: length}) | from_entries),
          dispatched: ($e | map(select(any(.runs[]?; .role == "implement"))) | length),
          prs_opened: ($p | length),
          merged: ($m | length),
          merge_rate: (if ($p | length) > 0 then ($m | length) / ($p | length) else null end),
          verified: ($v | length),
          verify_fail_rate: (if ($v | length) > 0 then (($v | map(select(any(.verdicts[]?; .verdict == "FAIL"))) | length) / ($v | length)) else null end),
          usd_total: ($e | map(.budget.usd_spent // 0) | add // 0),
          usd_per_merged_pr: (if ($m | length) > 0 then (($m | map(.budget.usd_spent // 0) | add) / ($m | length)) else null end),
          median_hours_implement_to_verify: ($e | map(select(any(.runs[]?; .role == "implement") and any(.runs[]?; .role == "verify"))
              | hours((.runs | map(select(.role == "implement")) | .[0].at); (.runs | map(select(.role == "verify")) | .[0].at))) | median | r1),
          median_hours_verify_to_merge: ($m | map(select(any(.runs[]?; .role == "verify"))
              | hours((.runs | map(select(.role == "verify")) | .[-1].at); .updated)) | median | r1),
          blocked: ($e | map(select(.blocked_on != null)) | group_by(.blocked_on.kind)
              | map({key: .[0].blocked_on.kind, value: {count: length, oldest_since: (map(.blocked_on.since) | min)}}) | from_entries),
          stalled: ($e | map(select((.blocked_on.kind? // "") == "stall")) | length) }' "$@"
}
metrics_render() { # stdin = the JSON object; $1 since (or "")
  local M since="$1"; M=$(cat)
  pct() { jq -r "$1 | if . == null then \"n/a\" else \"\(((. * 100) | round))%\" end" <<<"$M"; }
  usd() { local v; v=$(jq -r "$1 // \"n/a\"" <<<"$M"); [ "$v" = n/a ] && echo n/a || LC_NUMERIC=C printf '%.2f USD' "$v"; }   # LC_NUMERIC: never a decimal comma
  hrs() { local v; v=$(jq -r "$1 // \"n/a\"" <<<"$M"); [ "$v" = n/a ] && echo n/a || LC_NUMERIC=C printf '%.1f' "$v"; }
  printf '  AI delivery (ledger: %s entries%s)\n' "$(jq -r .entries <<<"$M")" "${since:+ created since $since}"
  printf '  entries   %s — %s\n' "$(jq -r .entries <<<"$M")" "$(jq -r '.by_phase | to_entries | map("\(.key) \(.value)") | join(" · ")' <<<"$M")"
  printf '  dispatched %s · PRs opened %s · merged %s · merge rate %s\n' "$(jq -r .dispatched <<<"$M")" "$(jq -r .prs_opened <<<"$M")" "$(jq -r .merged <<<"$M")" "$(pct .merge_rate)"
  printf '  verify    FAIL rate %s (%s verified)\n' "$(pct .verify_fail_rate)" "$(jq -r .verified <<<"$M")"
  printf '  spend     %s total · per merged PR %s\n' "$(usd .usd_total)" "$(usd .usd_per_merged_pr)"
  printf '  hours     implement→verify median %s · verify→merge median %s (approx.)\n' "$(hrs .median_hours_implement_to_verify)" "$(hrs .median_hours_verify_to_merge)"
  printf '  blocked   %s — %s\n' "$(jq -r '[.blocked[].count] | add // 0' <<<"$M")" "$(jq -r '.blocked | to_entries | map("\(.key) \(.value.count) (oldest \(.value.oldest_since[0:10]))") | join(" · ") | if . == "" then "none" else . end' <<<"$M")"
}

[ $# -ge 1 ] || usage
SUB="$1"; shift
DIR=$(ledger_dir) || exit 1

case "$SUB" in
  dir) echo "$DIR" ;;

  init)
    ID="${1:-}"; [ -n "$ID" ] || usage; shift
    KIND=""; REF=""; URL=""; BODY=""
    while [ $# -gt 0 ]; do case "$1" in
      --kind) KIND="${2:-}"; shift ;; --ref) REF="${2:-}"; shift ;; --url) URL="${2:-}"; shift ;; --body-file) BODY="${2:-}"; shift ;;
      *) usage ;; esac; shift; done
    valid_id "$ID" || exit 1
    if [ -f "$DIR/$ID.json" ]; then echo "$DIR/$ID.json"; exit 0; fi      # idempotent: unchanged, path printed
    in_list "$KIND" "tasks-repo github-project" || die "ledger init $ID: --kind must be tasks-repo or github-project (got '${KIND:-<none>}')"
    [ -n "$REF" ] || die "ledger init $ID: --ref is required (e.g. tasks/TODO.md#$ID)"
    SHA=null
    if [ -n "$BODY" ]; then [ -f "$BODY" ] || die "ledger init $ID: body file not found: $BODY"; SHA="\"$(sha256sum "$BODY" | cut -c1-64)\""; fi
    jq -n --arg id "$ID" --arg kind "$KIND" --arg ref "$REF" --arg url "$URL" --argjson sha "$SHA" '{
      id: $id, source: {kind: $kind, ref: $ref, url: (if $url == "" then null else $url end), body_sha256: $sha},
      route: null, phase: "queued", owner: null, worktree: null, branch: null, spec_dir: null, pr: null,
      verdicts: [], blocked_on: null, budget: {usd_cap: null, usd_spent: 0}, runs: [], attempts: 0,
      created: (now | todate), updated: (now | todate) }' | write_entry "$ID" || exit 1
    echo "$DIR/$ID.json" ;;

  claim)
    ID="${1:-}"; [ -n "$ID" ] || usage; shift; SESSION=""; ROLE=""
    while [ $# -gt 0 ]; do case "$1" in --session) SESSION="${2:-}"; shift ;; --role) ROLE="${2:-}"; shift ;; *) usage ;; esac; shift; done
    [ -n "$SESSION" ] && [ -n "$ROLE" ] || die "ledger claim $ID: --session <name> and --role <role> are required"
    E=$(entry "$ID") || exit 1
    OWNER=$(jq -r '.owner.session_name // empty' <<<"$E")
    [ -z "$OWNER" ] || die "ledger claim $ID: already owned by $OWNER (expected owner=null; wait for its run to finish)"
    # attempts count IMPLEMENT claims only: a verify claim after each run would otherwise stall an
    # entry on its second implement attempt.
    INC=0; [ "$ROLE" = implement ] && INC=1
    N=$(jq --argjson i "$INC" '.attempts + $i' <<<"$E")
    if [ "$N" -gt 2 ]; then
      jq '.blocked_on = {kind: "stall", since: (now | todate), question_path: null} | .attempts += 1' <<<"$E" | write_entry "$ID" || exit 1
      die "ledger claim $ID: attempt $N exceeds 2 — blocked_on: stall (a human decides whether to split or drop it)"
    fi
    jq --arg s "$SESSION" --arg r "$ROLE" --argjson p "$$" --argjson i "$INC" \
      '.owner = {session_name: $s, role: $r, pid: $p, started: (now | todate)} | .attempts += $i' <<<"$E" | write_entry "$ID" || exit 1
    echo "$ID claimed by $SESSION (attempt $N)" ;;

  advance)
    ID="${1:-}"; TO="${2:-}"; [ -n "$ID" ] && [ -n "$TO" ] || usage
    E=$(entry "$ID") || exit 1
    CUR=$(jq -r .phase <<<"$E"); CI=$(phase_index "$CUR") || exit 1; TI=$(phase_index "$TO") || exit 1
    [ "$TI" -gt "$CI" ] || die "ledger advance $ID: '$TO' is not after '$CUR' (phases move forward only: ${PHASES[*]})"
    jq --arg p "$TO" '.phase = $p' <<<"$E" | write_entry "$ID" || exit 1; echo "$ID $CUR → $TO" ;;

  verdict)
    ID="${1:-}"; [ -n "$ID" ] || usage; shift; GATE=""; V=""; BY=""; EV=""
    while [ $# -gt 0 ]; do case "$1" in
      --gate) GATE="${2:-}"; shift ;; --verdict) V="${2:-}"; shift ;; --by) BY="${2:-}"; shift ;; --evidence) EV="${2:-}"; shift ;;
      *) usage ;; esac; shift; done
    in_list "$GATE" "$GATES" || die "ledger verdict $ID: --gate must be one of: $GATES (got '${GATE:-<none>}')"
    in_list "$V" "PASS FAIL SKIPPED" || die "ledger verdict $ID: --verdict must be PASS, FAIL or SKIPPED (got '${V:-<none>}')"
    [ -n "$BY" ] || die "ledger verdict $ID: --by <session> is required"
    E=$(entry "$ID") || exit 1
    if [ "$GATE" = review ]; then
      # Reviewer ≠ author, structurally: the current owner AND every session that ran the implement
      # role are authors (the owner is released after a run, so the owner alone would be vacuous).
      AUTHORS=$(jq -r '[.owner.session_name // empty] + [.runs[] | select(.role == "implement") | .session_name] | .[]' <<<"$E")
      in_list "$BY" "$AUTHORS" && die "ledger verdict $ID: review by '$BY' refused — that session authored the change (reviewer must differ from: $(tr '\n' ' ' <<<"$AUTHORS"))"
    fi
    jq --arg g "$GATE" --arg v "$V" --arg b "$BY" --arg e "$EV" \
      '.verdicts += [{gate: $g, verdict: $v, by: $b, at: (now | todate), evidence: (if $e == "" then null else $e end)}]' <<<"$E" | write_entry "$ID" || exit 1
    echo "$ID $GATE $V by $BY" ;;

  block)
    ID="${1:-}"; [ -n "$ID" ] || usage; shift; KIND=""; Q=""
    while [ $# -gt 0 ]; do case "$1" in --kind) KIND="${2:-}"; shift ;; --question) Q="${2:-}"; shift ;; *) usage ;; esac; shift; done
    in_list "$KIND" "$KINDS" || die "ledger block $ID: --kind must be one of: $KINDS (got '${KIND:-<none>}')"
    E=$(entry "$ID") || exit 1
    jq --arg k "$KIND" --arg q "$Q" '.blocked_on = {kind: $k, since: (now | todate), question_path: (if $q == "" then null else $q end)}' <<<"$E" | write_entry "$ID" || exit 1
    echo "$ID blocked_on $KIND" ;;

  unblock)
    ID="${1:-}"; [ -n "$ID" ] || usage; shift; REVIEWED=0
    while [ $# -gt 0 ]; do case "$1" in --reviewed-by-human) REVIEWED=1 ;; *) usage ;; esac; shift; done
    E=$(entry "$ID") || exit 1
    KIND=$(jq -r '.blocked_on.kind // empty' <<<"$E"); [ -n "$KIND" ] || die "ledger unblock $ID: not blocked"
    SPEC_DIR=$(jq -r '.spec_dir // empty' <<<"$E"); BRANCH=$(jq -r '.branch // empty' <<<"$E")
    case "$KIND" in
      human:plan-review)
        [ -n "$SPEC_DIR" ] || die "ledger unblock $ID: $KIND needs spec_dir recorded (ledger.sh record $ID --spec-dir …)"
        grep -q '^## Reviewed' "$SPEC_DIR/plan.md" 2>/dev/null || die "ledger unblock $ID: $KIND needs a '## Reviewed' section in $SPEC_DIR/plan.md (run /hef.review)" ;;
      human:clarify)
        [ -n "$SPEC_DIR" ] || die "ledger unblock $ID: $KIND needs spec_dir recorded"
        [ -f "$SPEC_DIR/spec.md" ] || die "ledger unblock $ID: $KIND needs $SPEC_DIR/spec.md"
        ! grep -q 'NEEDS CLARIFICATION' "$SPEC_DIR/spec.md" || die "ledger unblock $ID: $KIND — [NEEDS CLARIFICATION] markers remain in $SPEC_DIR/spec.md (run /hef.clarify)" ;;
      human:merge)
        [ -n "$BRANCH" ] || die "ledger unblock $ID: $KIND needs branch recorded"
        git merge-base --is-ancestor "$BRANCH" main 2>/dev/null || die "ledger unblock $ID: $KIND — '$BRANCH' is not merged into main (git fetch first if it was merged remotely)" ;;
      human:intake)
        { [ "$REVIEWED" = 1 ] && [ -t 0 ]; } || die "ledger unblock $ID: $KIND needs --reviewed-by-human from an interactive shell (a person read the item text)" ;;
    esac
    jq '.blocked_on = null' <<<"$E" | write_entry "$ID" || exit 1; echo "$ID unblocked ($KIND)" ;;

  run)
    ID="${1:-}"; [ -n "$ID" ] || usage; shift; ROLE=""; RC=""; USD=""; SID=""
    while [ $# -gt 0 ]; do case "$1" in
      --role) ROLE="${2:-}"; shift ;; --exit) RC="${2:-}"; shift ;; --usd) USD="${2:-}"; shift ;; --session-id) SID="${2:-}"; shift ;;
      *) usage ;; esac; shift; done
    [ -n "$ROLE" ] && [ -n "$RC" ] && [ -n "$USD" ] || die "ledger run $ID: --role, --exit and --usd are required"
    E=$(entry "$ID") || exit 1
    [[ "$RC" =~ ^-?[0-9]+$ ]] && [[ "$USD" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "ledger run $ID: --exit must be an integer and --usd a non-negative number (got '$RC', '$USD')"
    jq --arg r "$ROLE" --argjson rc "$RC" --argjson usd "$USD" --arg sid "$SID" \
      '.runs += [{role: $r, session_name: (.owner.session_name // null), session_id: (if $sid == "" then null else $sid end), exit: $rc, usd: $usd, at: (now | todate)}]
       | .budget.usd_spent += $usd | .owner = null' <<<"$E" | write_entry "$ID" || exit 1
    echo "$ID run recorded ($ROLE exit $RC, $USD USD); owner released" ;;

  record)
    ID="${1:-}"; [ -n "$ID" ] || usage; shift; E=$(entry "$ID") || exit 1
    setf() { E=$(jq --arg v "$2" "$1" <<<"$E") && [ -n "$E" ] || die "ledger record $ID: cannot set $1 to '$2'"; }
    while [ $# -gt 0 ]; do case "$1" in
      --body-file) [ -f "${2:-}" ] || die "ledger record $ID: body file not found: '${2:-}'"; setf '.source.body_sha256 = $v' "$(sha256sum "$2" | cut -c1-64)"; shift ;;
      --worktree) setf '.worktree = $v' "${2:-}"; shift ;;
      --branch)   setf '.branch = $v' "${2:-}"; shift ;;
      --route)    in_list "${2:-}" "fix light full" || die "ledger record $ID: --route must be fix, light or full (got '${2:-}')"; setf '.route = $v' "$2"; shift ;;
      --pr)       setf '.pr = {url: $v, number: (($v | capture("/(?<n>[0-9]+)$").n | tonumber)? // null)}' "${2:-}"; shift ;;
      --spec-dir) setf '.spec_dir = $v' "${2:-}"; shift ;;
      *) usage ;; esac; shift; done
    write_entry "$ID" <<<"$E" || exit 1; echo "$ID recorded" ;;

  show) ID="${1:-}"; [ -n "$ID" ] || usage; entry "$ID" ;;

  list)
    PH=""; BLOCKED=0; ACTIVE=0; TODAY=0
    while [ $# -gt 0 ]; do case "$1" in
      --phase) PH="${2:-}"; shift ;; --blocked) BLOCKED=1 ;; --active) ACTIVE=1 ;; --today) TODAY=1 ;; *) usage ;; esac; shift; done
    D=$(date -u +%Y-%m-%d)
    shopt -s nullglob; FILES=("$DIR"/*.json); shopt -u nullglob
    [ "${#FILES[@]}" -gt 0 ] || { echo '[]'; exit 0; }              # an empty ledger is an answer; an unreadable one is not
    jq -s --arg ph "$PH" --argjson b "$BLOCKED" --argjson a "$ACTIVE" --argjson t "$TODAY" --arg d "$D" "
      map(select((\$ph == \"\" or .phase == \$ph) and (\$b == 0 or .blocked_on != null) and (\$a == 0 or .owner != null)
                 and (\$t == 0 or (.updated | startswith(\$d))))) | $ID_SORT" "${FILES[@]}" \
      || die "ledger list: an entry in $DIR is not valid JSON — repair or remove it (jq . $DIR/*.json names it)" ;;

  next)
    shopt -s nullglob; FILES=("$DIR"/*.json); shopt -u nullglob
    [ "${#FILES[@]}" -gt 0 ] || die "ledger next: no entries in $DIR (run: ledger.sh init <id> …)"
    N=$(jq -rs "map(select(.owner == null and .blocked_on == null and (.phase == \"queued\" or .phase == \"implement\"))) | $ID_SORT | .[0].id // empty" "${FILES[@]}") \
      || die "ledger next: an entry in $DIR is not valid JSON — repair or remove it"
    [ -n "$N" ] || die "ledger next: no dispatchable entry (queued or implement, unowned, unblocked) in $DIR"
    echo "$N" ;;

  metrics)
    SINCE=""; JSON=0
    while [ $# -gt 0 ]; do case "$1" in
      --since) SINCE="${2:-}"; [[ "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "ledger metrics: --since takes YYYY-MM-DD (got '${SINCE:-<none>}')"; shift ;;
      --json) JSON=1 ;; *) usage ;; esac; shift; done
    shopt -s nullglob; FILES=("$DIR"/*.json); shopt -u nullglob
    [ "${#FILES[@]}" -gt 0 ] || die "ledger metrics: no entries in $DIR"
    M=$(metrics_compute "$SINCE" "${FILES[@]}") || die "ledger metrics: an entry in $DIR is not valid JSON — repair or remove it (jq . $DIR/*.json names it)"
    [ "$(jq '.entries' <<<"$M")" -gt 0 ] || die "ledger metrics: no entries${SINCE:+ created since $SINCE} in $DIR"
    if [ "$JSON" = 1 ]; then echo "$M"; else metrics_render "$SINCE" <<<"$M"; fi ;;

  *) echo "ledger: unknown subcommand '$SUB'" >&2; usage ;;
esac
