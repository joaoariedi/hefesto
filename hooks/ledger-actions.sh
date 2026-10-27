#!/bin/bash
# ledger-actions.sh — a person's approval of one lane action, given in the orchestrator, carried out by the lane it
# names (lanes-interactive, 9.0; #132, #138). SOURCED by ledger.sh; never run on its own. Uses ledger.sh's globals
# and helpers: DIR, BCTX, ID, REVIEWED, RBY, die, entry, write_entry, valid_id, person_gate, hef_sha256, hef_cache.
#
#   request <id> --to <lane> --scope-file <f> [--supersedes <aid>]   the orchestrator proposes; nothing is approved
#   approve <aid> --sha <8+ hex> --to <lane> --title <t> --reviewed-by-human --by <name> [--irreversible-confirmed]
#   action take|heads|step|done|stop|show <aid> …                    the target lane carries it out
#   actions [--to <lane>] [--status <s>] [--since <YYYY-MM-DD>]      the history
#   op new --title <t>                                               an item-less entry (OP-<n>) to hang actions on
#
# What makes an approval trustworthy: the scope lives in <ledger>/actions/<aid>.json and its approval in the store,
# ~/.cache/hefesto/approvals/<ledger key>/<aid>.json — both outside every sandbox's write set, written only by this
# helper (which a set-up project runs unsandboxed). The hash covers {entry, to, scope}; `approve` runs behind its
# permission dialog in the orchestrator lane (lane-guard.sh + the second gate below); `take` re-checks the hash and
# that the approval names this lane and was never used. A pending or stopped action is a decision of its own,
# listed by `actions`: it never touches the entry's blocked_on, so a merge request can wait beside human:merge.

store_dir() { printf '%s\n' "$(hef_cache)/approvals/$(basename "$DIR")"; }
action_file() { printf '%s\n' "$DIR/actions/$1.json"; }
valid_aid() { [[ "${1:-}" =~ ^[A-Za-z][A-Za-z0-9_-]*-A[0-9]+$ ]] || die "ledger: invalid action id '${1:-}' (expected <entry id>-A<n>, e.g. DET-7-A2)"; }
action_get() { valid_aid "$1"; [ -f "$(action_file "$1")" ] || die "ledger: no action '$1' (expected $(action_file "$1"))"; cat "$(action_file "$1")"; }
action_put() { # $1 aid; stdin = the new JSON (temp + mv, never torn)
  local t; mkdir -p "$DIR/actions" || die "ledger: cannot create $DIR/actions"
  t=$(mktemp "$DIR/actions/.$1.XXXXXX") || die "ledger: cannot write in $DIR/actions"
  jq -e . > "$t" 2>/dev/null || { rm -f "$t"; die "ledger: refusing to write empty or invalid JSON for action $1"; }
  mv "$t" "$(action_file "$1")" || { rm -f "$t"; die "ledger: cannot write action $1"; }
}
action_hash() { jq -cS '{entry, to, scope}' <<<"$1" | hef_sha256; }   # $1 action JSON
store_get() { cat "$(store_dir)/$1.json" 2>/dev/null; }
store_put() { # $1 aid; stdin = the record
  local d t; d=$(store_dir); mkdir -p "$d" && chmod 700 "$d" 2>/dev/null || die "ledger: cannot create the approval store $d"
  t=$(mktemp "$d/.$1.XXXXXX") || die "ledger: cannot write in $d"
  jq -e . > "$t" 2>/dev/null || { rm -f "$t"; die "ledger: refusing to write an empty approval for $1"; }
  mv "$t" "$d/$1.json" || { rm -f "$t"; die "ledger: cannot write the approval of $1"; }
}
store_consume() { # $1 aid, $2 why — an approval is used once
  local r; r=$(store_get "$1") || return 0; [ -n "$r" ] || return 0
  jq --arg w "$2" 'if .consumed_at then . else .consumed_at = (now | todate) | .consumed_by = $w end' <<<"$r" | store_put "$1"
}
# The lane asking, from its session record (lane-lib.sh) — the second gate beside lane-guard.sh's.
caller_lane_is() { # $1 the lane name the action is for; dies when a lanes session that is another lane asks
  [ -z "${HEFESTO_WORKER:-}" ] || [ "$HEFESTO_WORKER" = 0 ] || die "ledger action: never from inside a launched worker — the lane the action names carries it out"
  local sid="${CLAUDE_CODE_SESSION_ID:-}" f n
  valid_sid "$sid" || return 0; f=$(session_file "$sid"); [ -f "$f" ] || return 0
  [ "$(jq -r '.lanes' "$f" 2>/dev/null)" = true ] || return 0
  n=$(jq -r '.name // empty' "$f"); [ "$n" = "$1" ] || die "ledger action: this action is for the lane '$1', and this session is '${n:-not a lane}'"
}

scope_check() { # $1 scope file → the scope as one JSON line, validated (FR-003, review round 1 #6), or die
  [ -f "$1" ] || die "ledger request: scope file not found: '$1'"
  [ "$(wc -c < "$1" | tr -d ' ')" -le 32768 ] || die "ledger request: the scope is over 32 KB — split the action"
  local out
  out=$(jq -ce '
    def strs($n): type == "array" and length <= $n and all(type == "string" and length <= 2000);
    def cmd_ok: type == "string" and length > 0 and length <= 500 and (test("\n") | not) and (startswith("*") | not)
      and ((split(" ")[0]) as $w | ["sh","bash","zsh","env","eval","exec","xargs","sudo","nohup","timeout","command","builtin"] | index([$w]) | not)
      and ((" " + . + " ") | contains(" -c ") | not)
      and (test("(ledger|session-launch|hefesto-setup|lane-guard)\\.sh") | not);
    if type != "object" then error("the scope must be a JSON object")
    elif (.title | type) != "string" or (.title | length) < 3 or (.title | length) > 200 or (.title | test("[\n\r]")) then error("title: one line of 3–200 characters")
    elif (.steps | strs(50)) != true or (.steps | length) == 0 then error("steps: a list of 1–50 strings")
    elif (.heads // {} | type) != "object" or ((.heads // {}) | to_entries | any((.key | test("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+#[0-9]+$") | not) or (.value | type != "string" or (test("^[0-9a-f]{40}$") | not))))
      then error("heads: {\"<owner>/<repo>#<pr>\": \"<full 40-hex head sha>\"}")
    elif ((.stop_checks // []) | strs(50)) != true or ((.not_covered // []) | strs(50)) != true then error("stop_checks / not_covered: lists of strings")
    elif (.irreversible // false | type) != "boolean" then error("irreversible: true or false")
    elif ((.commands // []) | type == "array" and length <= 50 and all(cmd_ok)) != true
      then error("commands: up to 50 patterns, one line each, not starting with *, no shell or interpreter wrapper, no -c, no hefesto helper")
    else {title, steps, heads: (.heads // {}), stop_checks: (.stop_checks // []), not_covered: (.not_covered // []), irreversible: (.irreversible // false), commands: (.commands // [])} end' "$1" 2>&1) || die "ledger request: the scope in $1 is not valid — ${out#jq: error*: }"
  printf '%s\n' "$out"
}

request_action() { # globals: ID; args parsed by the caller: TO SCOPE SUP
  local sc n aid a old
  op_closed_refuse "$ID" "request $ID"   # also the entry's existence check
  [[ "$TO" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || die "ledger request $ID: --to must be a lane name (got '$TO')"
  if [ -n "${HEFESTO_LANE_MAP:-}" ]; then
    jq -e --arg t "$TO" '(.[$t] // "") as $r | $r != "" and $r != "orchestrator"' <<<"$HEFESTO_LANE_MAP" >/dev/null 2>&1 \
      || die "ledger request $ID: '$TO' is not a stage lane of this project ($(jq -r 'to_entries | map(select(.value != "orchestrator") | .key) | join(", ")' <<<"$HEFESTO_LANE_MAP"))"
  fi
  sc=$(scope_check "$SCOPE") || exit 1
  [ -n "$sc" ] || die "ledger request $ID: the scope in $SCOPE is not valid (jq . $SCOPE shows why)"
  if [ -n "$SUP" ]; then
    old=$(action_get "$SUP") || exit 1
    [ "$(jq -r .entry <<<"$old")" = "$ID" ] || die "ledger request $ID: --supersedes $SUP belongs to entry $(jq -r .entry <<<"$old")"
    case "$(jq -r .status <<<"$old")" in pending|approved|stopped) ;; *) die "ledger request $ID: $SUP is $(jq -r .status <<<"$old") — only a pending, approved or stopped action is superseded" ;; esac
  fi
  n=$(( $(find "$DIR/actions" -name "$ID-A*.json" 2>/dev/null | sed -E 's/.*-A([0-9]+)\.json$/\1/' | sort -n | tail -1 | grep -E '^[0-9]+$' || echo 0) + 1 ))
  aid="$ID-A$n"
  a=$(jq -n --arg aid "$aid" --arg e "$ID" --arg to "$TO" --argjson sc "$sc" --arg sup "$SUP" \
    '{aid: $aid, entry: $e, to: $to, scope: $sc, author: "orchestrator", at: (now | todate), status: "pending",
      supersedes: (if $sup == "" then null else $sup end), steps_done: [], outcome: null}')
  a=$(jq --arg h "$(action_hash "$a")" '.sha256 = $h' <<<"$a")
  action_put "$aid" <<<"$a" || exit 1
  if [ -n "$SUP" ]; then
    jq --arg by "$aid" '.status = "superseded" | .superseded_by = $by' <<<"$old" | action_put "$SUP" || exit 1
    store_consume "$SUP" "superseded by $aid"
  fi
  echo "$aid pending for $TO — sha256 $(jq -r .sha256 <<<"$a" | cut -c1-12): ask the person in a form"
}

approve_action() { # globals: AID SHA ATO ATITLE IRREV REVIEWED RBY
  local a h
  a=$(action_get "$AID") || exit 1; ID=$(jq -r .entry <<<"$a")
  op_closed_refuse "$ID" "approve $AID"
  person_gate human:action approve
  [ "$(jq -r .status <<<"$a")" = pending ] || die "ledger approve $AID: it is $(jq -r .status <<<"$a") — only a pending action is approved"
  h=$(action_hash "$a"); [ "$h" = "$(jq -r .sha256 <<<"$a")" ] || die "ledger approve $AID: the stored scope no longer matches its hash — request it again"
  [[ "$SHA" =~ ^[0-9a-f]{8,64}$ ]] && [[ "$h" == "$SHA"* ]] || die "ledger approve $AID: --sha $SHA is not this scope's hash ($(cut -c1-12 <<<"$h")…) — show the scope again and ask"
  [ "$ATO" = "$(jq -r .to <<<"$a")" ] || die "ledger approve $AID: --to '$ATO' — the scope is for '$(jq -r .to <<<"$a")'"
  [ "$ATITLE" = "$(jq -r .scope.title <<<"$a")" ] || die "ledger approve $AID: --title does not match the scope's title ('$(jq -r .scope.title <<<"$a")')"
  if [ "$(jq -r .scope.irreversible <<<"$a")" = true ] && [ "$IRREV" != 1 ]; then
    die "ledger approve $AID: the scope is irreversible — the person confirms each irreversible step in the form, then --irreversible-confirmed"
  fi
  jq -n --arg aid "$AID" --arg h "$h" --arg to "$ATO" --arg by "$RBY" --argjson ir "$IRREV" \
    '{aid: $aid, sha256: $h, to: $to, by: $by, at: (now | todate), irreversible_confirmed: ($ir == 1), consumed_at: null}' | store_put "$AID" || exit 1
  jq --arg by "$RBY" '.status = "approved" | .approved_by = $by | .approved_at = (now | todate)' <<<"$a" | action_put "$AID" || exit 1
  echo "$AID approved by $RBY for $ATO — ring that lane"
}

action_cmd() { # $1 verb, then its arguments; globals: AID set by the caller
  local verb="$1" a r h f n; shift
  a=$(action_get "$AID") || exit 1
  [ "$verb" = show ] || op_closed_refuse "$(jq -r .entry <<<"$a")" "action $verb $AID"
  case "$verb" in
    show)
      local nonce; nonce=$(od -An -N6 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
      jq -r '"\(.aid) · \(.status) · for \(.to) · sha256 \(.sha256[0:12]) · \(.scope.title | gsub("[[:cntrl:]]"; " "))"' <<<"$a"
      echo "<<<untrusted-scope-begin $AID $nonce"; jq '{scope, steps_done, outcome, approved_by, approved_at}' <<<"$a"; echo "untrusted-scope-end $AID $nonce>>>"
      return 0 ;;
  esac
  caller_lane_is "$(jq -r .to <<<"$a")"
  case "$verb" in
    take)
      [ "$(jq -r .status <<<"$a")" = approved ] || die "ledger action take $AID: it is $(jq -r .status <<<"$a") — only an approved action is taken"
      r=$(store_get "$AID"); [ -n "$r" ] || die "ledger action take $AID: no approval in the store — the person approves it in the orchestrator first"
      h=$(action_hash "$a")
      [ "$h" = "$(jq -r .sha256 <<<"$a")" ] && [ "$h" = "$(jq -r .sha256 <<<"$r")" ] || die "ledger action take $AID: the scope changed after it was approved — stop and report it"
      [ "$(jq -r .to <<<"$r")" = "$(jq -r .to <<<"$a")" ] || die "ledger action take $AID: the approval names another lane"
      [ "$(jq -r '.consumed_at // empty' <<<"$r")" = "" ] || die "ledger action take $AID: the approval was already used ($(jq -r .consumed_by <<<"$r")) — one approval, one use"
      jq '.status = "taken" | .taken_at = (now | todate)' <<<"$a" | action_put "$AID" || exit 1
      echo "$AID taken — check the heads first (action heads $AID), then follow the steps exactly; stop at any stop check" ;;
    heads)
      [ "$(jq -r .status <<<"$a")" = taken ] || die "ledger action heads $AID: take it first"
      local gh="$GH" bad="" k repo pr want got
      command -v "$gh" >/dev/null 2>&1 || die "ledger action heads $AID: gh is not installed — the heads cannot be checked, so the action does not run"
      while IFS=$'\t' read -r k want; do
        [ -n "$k" ] || continue; repo="${k%%#*}"; pr="${k##*#}"
        got=$("$gh" pr view "$pr" -R "$repo" --json headRefOid -q .headRefOid 2>/dev/null) || die "ledger action heads $AID: gh cannot read $repo#$pr — fails closed"
        [ "$got" = "$want" ] || bad="${bad:+$bad; }$k is at $got, the approval names $want"
      done < <(jq -r '.scope.heads | to_entries[] | "\(.key)\t\(.value)"' <<<"$a")
      [ -z "$bad" ] || die "ledger action heads $AID: head differs — $bad. Stop: ledger.sh action stop $AID --step 0 --reason-file <file>"
      jq '.heads_ok_at = (now | todate)' <<<"$a" | action_put "$AID" || exit 1
      echo "$AID heads match ($(jq -r '.scope.heads | length' <<<"$a")) — go on with the steps" ;;
    step|done|stop)
      [ "$(jq -r .status <<<"$a")" = taken ] || die "ledger action $verb $AID: it is $(jq -r .status <<<"$a") — only a taken action records progress"
      n=""; f=""
      while [ $# -gt 0 ]; do case "$1" in --step) n="${2:-}"; shift ;; --evidence-file|--reason-file) f="${2:-}"; shift ;; [0-9]*) n="$1" ;; *) die "ledger action $verb: unexpected '$1'" ;; esac; shift; done
      [ -f "$f" ] || die "ledger action $verb $AID: pass the text as a file (--evidence-file / --reason-file <f>, written with the Write tool)"
      [ "$(wc -c < "$f" | tr -d ' ')" -le 8192 ] || die "ledger action $verb $AID: over 8 KB — keep it to the evidence"
      case "$verb" in
        step) [[ "$n" =~ ^[0-9]+$ ]] || die "ledger action step $AID <n>: the step number"
              jq --argjson n "$n" --rawfile t "$f" '.steps_done += [{n: $n, evidence: $t, at: (now | todate)}]' <<<"$a" | action_put "$AID" || exit 1
              echo "$AID step $n recorded" ;;
        done) jq --rawfile t "$f" '.status = "done" | .outcome = {kind: "done", evidence: $t, at: (now | todate)}' <<<"$a" | action_put "$AID" || exit 1
              store_consume "$AID" "done"; echo "$AID done — ring the orchestrator" ;;
        stop) [[ "$n" =~ ^[0-9]+$ ]] || die "ledger action stop $AID --step <n>: the step where it stopped"
              jq --argjson n "$n" --rawfile t "$f" '.status = "stopped" | .outcome = {kind: "stopped", step: $n, reason: $t, at: (now | todate)}' <<<"$a" | action_put "$AID" || exit 1
              store_consume "$AID" "stopped at step $n"; echo "$AID stopped at step $n — the orchestrator asks the person again" ;;
      esac ;;
    *) die "ledger action: unknown verb '$verb' (expected take, heads, step, done, stop or show)" ;;
  esac
}

actions_list() { # args: [--to <lane>] [--status <s>] [--since <date>]
  local to="" st="" since=""
  while [ $# -gt 0 ]; do case "$1" in --to) to="${2:-}"; shift ;; --status) st="${2:-}"; shift ;; --since) since="${2:-}"; shift ;; *) die "ledger actions: unexpected '$1'" ;; esac; shift; done
  [ -z "$since" ] || [[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "ledger actions --since: YYYY-MM-DD (got '$since')"
  set -- "$DIR"/actions/*.json; [ -f "$1" ] || return 0
  jq -rs --arg to "$to" --arg st "$st" --arg since "$since" 'sort_by(.at) | .[]
    | select(($to == "" or .to == $to) and ($st == "" or .status == $st) and ($since == "" or .at >= $since))
    | "\(.aid)\t\(.status)\t\(.to)\t\(.sha256[0:12])\t\(.approved_by // "-")\t\(.at)\t\(.scope.title | gsub("[[:cntrl:]]"; " "))"' "$@"
}

op_new() { # globals: OTITLE → prints the new OP-<n>
  [[ "$OTITLE" =~ ^[^$'\n\r']{3,120}$ ]] || die "ledger op new: --title must be one line of 3–120 characters"
  local n id
  n=$(( $(find "$DIR" -maxdepth 1 -name 'OP-*.json' 2>/dev/null | sed -E 's/.*OP-([0-9]+)\.json$/\1/' | sort -n | tail -1 | grep -E '^[0-9]+$' || echo 0) + 1 ))
  id="OP-$n"
  jq -n --arg id "$id" --arg t "$OTITLE" '{id: $id, source: {kind: "op", ref: $t, url: null, body_sha256: null}, item_kind: "op",
    route: null, phase: "queued", owner: null, worktree: null, branch: null, spec_dir: null, pr: null, verdicts: [], blocked_on: null,
    budget: {usd_cap: null, usd_spent: 0}, runs: [], attempts: 0, created: (now | todate), updated: (now | todate)}' | write_entry "$id" || exit 1
  echo "$id"
}

# --- op close / op drop: the end of an op (lanes-parity US5, FR-011; plan Data Model "Op entry") ----------------------
# An op is born queued and ends done (close, with its outcome) or dropped (with the reason) — the text is kept, with
# its sha256. Never while one of its actions is approved or taken: that action is still the person's open decision,
# or a lane is carrying it out. A PENDING action is withdrawn by the close instead: it has no other way out (only a
# taken action is stopped), and refusing would leave the op open forever. Once ended, the op takes nothing more —
# request, approve and take refuse (op_closed_refuse). Person-only: `op` is in is_person_sub, and setup writes the
# ask rules.
op_closed_refuse() { # $1 entry id, $2 the command → dies when $1 is an op that has ended (done or dropped)
  local e; e=$(entry "$1") || exit 1
  [ "$(jq -r '.item_kind == "op" and .phase != "queued"' <<<"$e")" != true ] \
    || die "ledger $2: $1 is an op that is already $(jq -r .phase <<<"$e") — a closed op takes no more actions (open a new one: ledger.sh op new)"
}
op_withdraw_pending() { # $1 op id, $2 its end phase, $3 by → marks each pending action of $1 withdrawn; prints their aids
  local f a out=""
  for f in "$DIR"/actions/"$1"-A*.json; do
    [ -f "$f" ] || continue; a=$(cat "$f")
    [ "$(jq -r .status <<<"$a")" = pending ] || continue
    jq --arg by "$3" --arg why "op $1 ended $2 before the person decided" \
      '.status = "withdrawn" | .withdrawn = {by: $by, at: (now | todate), reason: $why}' <<<"$a" | action_put "$(jq -r .aid <<<"$a")" || exit 1
    out="${out:+$out, }$(jq -r .aid <<<"$a")"
  done
  printf '%s\n' "$out"
}
op_open_actions() { # $1 op id → the aids of its approved or taken actions, comma-separated (empty when none)
  set -- "$1" "$DIR"/actions/"$1"-A*.json; [ -f "$2" ] || return 0
  local id="$1"; shift
  jq -rs 'map(select(.status == "approved" or .status == "taken") | "\(.aid) (\(.status))") | join(", ")' "$@" \
    || die "ledger op: an action of $id in $DIR/actions is not valid JSON — repair or remove it"
}
op_end_file_ok() { # $1 verb, $2 id, $3 flag, $4 file
  [ -n "$4" ] || die "ledger op $1 $2: pass the $([ "$1" = close ] && echo outcome || echo reason) as a file ($3 <f>, written with the Write tool)"
  [ -f "$4" ] || die "ledger op $1 $2: the file $4 does not exist"
  [ -s "$4" ] || die "ledger op $1 $2: the file $4 is empty — say what the op came to"
  [ "$(wc -c < "$4" | tr -d ' ')" -le 8192 ] || die "ledger op $1 $2: the file $4 is over 8 KB — keep it to the outcome"
}
op_end() { # op close <OP-n> --outcome-file <f> | op drop <OP-n> --reason-file <f>
  local verb="${1:-}" id="${2:-}" want f="" e ph open by wd
  case "$verb" in close) want=--outcome-file; ph="done" ;; drop) want=--reason-file; ph=dropped ;; *) usage ;; esac
  [ -n "$id" ] || usage; shift 2
  while [ $# -gt 0 ]; do
    [ "$1" = "$want" ] || die "ledger op $verb $id: unexpected '$1' (op $verb takes $want <f>)"
    f="${2:-}"; shift 2 || shift
  done
  e=$(entry "$id") || exit 1
  [ "$(jq -r '.item_kind // empty' <<<"$e")" = op ] || die "ledger op $verb $id: $id is not an op entry (item_kind $(jq -r '.item_kind // "none"' <<<"$e")) — an item ends with drop, fold or supersede"
  [ "$(jq -r .phase <<<"$e")" = queued ] || die "ledger op $verb $id: the op is already $(jq -r .phase <<<"$e") — a closed op stays closed (open a new one)"
  open=$(op_open_actions "$id") || exit 1
  [ -z "$open" ] || die "ledger op $verb $id: its action $open is still open — finish or stop it first (ledger.sh action done|stop), or let the person supersede it"
  op_end_file_ok "$verb" "$id" "$want" "$f"
  by="${USER:-$(id -un 2>/dev/null)}"
  jq --arg p "$ph" --rawfile t "$f" --arg h "$(hef_sha256 < "$f")" --arg by "${by:-person}" '
    .phase = $p | .outcome_sha256 = $h | .outcome = {kind: $p, text: $t, by_person: $by, at: (now | todate)}
    | .events = ((.events // []) + [{kind: (if $p == "done" then "op-closed" else "op-dropped" end), at: (now | todate), by: $by, note: $p}])' <<<"$e" \
    | write_entry "$id" || exit 1
  # The op is written first: if a withdrawal then fails, the op is still closed and op_closed_refuse keeps its
  # pending action from ever being approved — never the reverse, actions withdrawn on an op left open.
  wd=$(op_withdraw_pending "$id" "$ph" "${by:-person}") || exit 1
  echo "$id $ph${wd:+ (withdrew the pending $wd)}"
}
# list: the ops after the items (stable, so each group keeps the id order). metrics: an op is not an item.
# shellcheck disable=SC2034,SC2016  # used by ledger.sh, which sources this part; jq programs, single-quoted on purpose
JQ_OPS_APART='sort_by(.item_kind == "op")'
# shellcheck disable=SC2034,SC2016
JQ_OPS_COUNT='map(select(.item_kind == "op")) | {open: map(select(.phase == "queued")) | length, done: map(select(.phase == "done")) | length, dropped: map(select(.phase == "dropped")) | length}'
