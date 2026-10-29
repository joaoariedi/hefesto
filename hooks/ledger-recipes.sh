#!/bin/bash
# ledger-recipes.sh — a deploy request's scope built from config (lanes-parity, 9.1): a recipe
# (`orchestrate.deploy.recipes.<env>`), a train (`orchestrate.deploy.trains.<name>`) or a generated merge, for
# `request --recipe/--train/--merge`, with validation and placeholder substitution. SOURCED by ledger.sh behind
# `[ -f ] || die`; never run on its own. Uses ledger.sh's globals and helpers (DIR, ID, E, die, cfgp).
#
# ledger.sh is over the file limit, so the logic lives here and ledger.sh keeps only dispatch and call-site lines.

# --- request <OP-n> --recipe <env> --version <v> [--sha <s>] (US7, FR-014, FR-018; plan Sketch 7) -------------------
# Config only DRAFTS the scope: `.claude/project-status.json` is a file a lane can write, so what makes the run
# trustworthy is the person approving the drafted scope as shown, and the action carrying that scope and its hash —
# an edit to the recipe after approve changes nothing (NR-003). A recipe hangs on an op (note 9): a deploy is not an
# item's phase, and an op is what the orchestrator opens for work that is not an item.
RECIPE_PH_ALLOWED='["{version}", "{sha}", "{env}"]'
recipe_args_ok() { # $1 env, $2 version, $3 sha (may be empty) — they are substituted into commands, so they are narrow
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || die "ledger request --recipe: pass the environment name (--recipe <env>, got '$1')"
  [[ "$2" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$ ]] || die "ledger request --recipe $1: --version must be a version like 1.4.2 (letters, digits, . _ + -; got '$2')"
  [ -z "$3" ] || [[ "$3" =~ ^[0-9a-f]{7,40}$ ]] || die "ledger request --recipe $1: --sha must be 7–40 lowercase hex (got '$3')"
}
recipe_get() { # $1 env → the recipe as one JSON line, or die listing the configured environments
  local all r
  all=$(cfgp -c '.orchestrate.deploy.recipes // {} | if type == "object" then . else {} end'); [ -n "$all" ] || all='{}'
  r=$(jq -ce --arg e "$1" '.[$e] // empty' <<<"$all") \
    || die "ledger request --recipe $1: no such recipe in orchestrate.deploy.recipes (configured: $(jq -r 'keys | if length == 0 then "none" else join(", ") end' <<<"$all"))"
  printf '%s\n' "$r"
}
recipe_validate() { # $1 env, $2 recipe JSON, $3 sha — dies naming the unknown placeholder or the empty step
  local bad
  bad=$(jq -r --argjson ok "$RECIPE_PH_ALLOWED" '[.. | strings | scan("\\{[A-Za-z_][A-Za-z0-9_-]*\\}")] - $ok | first // empty' <<<"$2")
  [ -z "$bad" ] || die "ledger request --recipe $1: unknown placeholder $bad (only {version}, {sha} and {env})"
  bad=$(jq -r 'if (.steps | type) != "array" or (.steps | length) == 0 then "the recipe has no steps"
    else .steps | to_entries | map(select((.value | type) != "object" or (.value.title | type) != "string" or (.value.title | length) == 0
      or (.value.commands | type) != "array" or (.value.commands | length) == 0 or (.value.commands | all(type == "string" and length > 0) | not)))
      | first | if . then "step \(.key + 1) (\(.value.title? // "untitled")) is an empty step" else empty end end' <<<"$2")
  [ -z "$bad" ] || die "ledger request --recipe $1: $bad — every step needs a title and at least one command"
  if [ -z "$3" ] && jq -e '[.. | strings | select(contains("{sha}"))] | length > 0' <<<"$2" >/dev/null; then
    die "ledger request --recipe $1: the recipe uses {sha} — pass --sha <commit>"
  fi
}
# A step's commands wait for every step before it (after_step = the previous step; step 1's run at take), so a failed
# version check (FR-017) stops what comes after it, not only the record of it.
recipe_scope() { # $1 env, $2 version, $3 sha → the drafted scope as one JSON line, or die naming the offending command
  local r out bad
  r=$(recipe_get "$1") || exit 1
  recipe_validate "$1" "$r" "$3"
  # shellcheck disable=SC2016  # a jq program: $v, $s and $e are jq variables
  out=$(jq -c --arg v "$2" --arg s "$3" --arg e "$1" 'def sub3: gsub("\\{version\\}"; $v) | gsub("\\{sha\\}"; $s) | gsub("\\{env\\}"; $e);
    {kind: "recipe", repo: null, pr: null, title: "deploy \($e) \($v)", heads: {}, not_covered: [], irreversible: (.irreversible // false),
     steps: [.steps[] | .title + (if .expect then " — expect " + (.expect | sub3) else "" end)],
     commands: [.steps | to_entries[] | .key as $i | .value.commands[] | {cmd: sub3, after_step: (if $i == 0 then null else $i end)}], expects: [.steps[] | if .expect then .expect | sub3 else null end],
     stop_checks: [.steps[] | (.stop_checks // [])[] | sub3]}' <<<"$r") || die "ledger request --recipe $1: the recipe is not valid JSON in the expected shape"
  # FR-018: name the command scope_check would reject, which its own message does not
  bad=$(jq -r "$SCOPE_JQ_DEFS"' .commands[].cmd | select((cmd_ok and merge_ok) | not)' <<<"$out" | head -1)
  [ -z "$bad" ] || die "ledger request --recipe $1: the command '$bad' is refused (no shell or interpreter wrapper, no -c, no hefesto helper, no * in the program name; a gh pr merge is --merge --match-head-commit only)"
  printf '%s\n' "$out"
}
request_recipe() { # globals: ID TO SCOPE RENV RVER RSHA — drafts the scope into a temp file, then the ordinary request
  [ -z "$SCOPE" ] || die "ledger request $ID: --recipe or --scope-file, not both"
  [ -n "$RENV" ] || die "ledger request $ID: --version and --sha go with --recipe <env>"
  [ -n "$RVER" ] || die "ledger request $ID --recipe $RENV: pass --version <v>"
  local e; e=$(entry "$ID") || exit 1
  [ "$(jq -r '.item_kind // empty' <<<"$e")" = op ] || die "ledger request $ID --recipe: a recipe run hangs on an op (ledger.sh op new --title …), and $ID is not an op"
  recipe_args_ok "$RENV" "$RVER" "$RSHA"
  local sc; sc=$(recipe_scope "$RENV" "$RVER" "$RSHA") || exit 1
  scope_tmp "$sc"; request_action
}
scope_tmp() { # $1 a drafted scope → SCOPE names a temp file holding it, removed on exit
  RECIPE_TMP=$(mktemp "${TMPDIR:-/tmp}/hef-recipe.XXXXXX") || die "ledger request $ID: cannot create a temp file"
  trap 'rm -f "$RECIPE_TMP" "${MERGE_STATE_TMP:-}"' EXIT
  printf '%s\n' "$1" > "$RECIPE_TMP"; SCOPE="$RECIPE_TMP"
}

# --- action step on a recipe: the version check (FR-017) ------------------------------------------------------------
# expects[n] set → one line of the evidence (whitespace and CR trimmed) must be exactly it; otherwise the action stops
# here, the approval is used up (so lane-guard grants nothing more), and both values are kept in the outcome.
recipe_expect_check() { # $1 action JSON, $2 step number, $3 evidence file → returns when the step may be recorded
  local want got
  want=$(jq -r --argjson n "$2" 'if .scope.kind == "recipe" and $n >= 1 then (.scope.expects // [])[$n - 1] // empty else empty end' <<<"$1")
  [ -n "$want" ] || return 0
  got=$(tr -d '\r' < "$3" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  grep -qxF -- "$want" <<<"$got" && return 0
  got=$(grep -m1 -v '^$' <<<"$got" || true)
  jq --argjson n "$2" --arg w "$want" --arg g "$got" --rawfile t "$3" '.status = "stopped"
    | .outcome = {kind: "stopped", step: $n, reason: "step \($n) expected \($w), got \($g)", expected: $w, got: $g, evidence: $t, at: (now | todate)}' <<<"$1" \
    | action_put "$AID" || exit 1
  store_consume "$AID" "stopped at step $2 (expected $want)"
  die "ledger action step $AID $2: expected $want, got ${got:-nothing} — the action is stopped; the orchestrator asks the person again"
}

# --- request <id> --to <lane> --merge (US9, FR-020–FR-023, NR-004; plan Sketch 8, notes 4, 10, 11, 16) ----------------
# The person's **Merge** answer approves a drafted action, so a lane merges through the 9.0 grant path: step 1 is the
# state (read here, by `action step`, never the lane's word — note 11), the checks are granted only once it is
# recorded, and the one gh write is the merge pinned to the head read now, granted only after the last check. GitHub
# refuses `--match-head-commit` on a moved head; `action heads` and step 1 stop the action before it gets that far.
merge_pr_of() { # $1 entry JSON → "<owner/repo> <n> <url>" of the current PR, or die
  local url; url=$(jq -r '.pr.url // empty' <<<"$1")
  [[ "$url" =~ ^https://github\.com/([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)/pull/([0-9]+)$ ]] \
    || die "ledger request $ID --merge: no GitHub PR is recorded (ledger.sh record $ID --pr <url>; got '${url:-none}')"
  printf '%s %s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$url"
}
merge_checks_get() { # → orchestrate.merge.checks as one JSON line (default []), or die naming the bad entry
  local ch bad; ch=$(cfgp -c '.orchestrate.merge.checks // []'); [ -n "$ch" ] || ch='[]'
  jq -e 'type == "array" and all(type == "string" and length > 0)' <<<"$ch" >/dev/null \
    || die "ledger request $ID --merge: orchestrate.merge.checks must be a list of commands (got $(head -c 200 <<<"$ch"))"
  bad=$(jq -r '[.. | strings | scan("\\{[A-Za-z_][A-Za-z0-9_-]*\\}")] - ["{repo_path}", "{base}"] | first // empty' <<<"$ch")
  [ -z "$bad" ] || die "ledger request $ID --merge: unknown placeholder $bad in orchestrate.merge.checks (only {repo_path} and {base})"
  printf '%s\n' "$ch"
}
merge_repo_ctx() { # $1 entry JSON → "<repo path>\t<integration branch>" of the entry's repo; a subshell keeps the cwd
  ( cd_entry_repo "$1" || exit 1
    p=$(main_top || git rev-parse --show-toplevel) || die "ledger request $ID --merge: not in a git repository"
    p=$(cd "$p" && pwd -P) || die "ledger request $ID --merge: cannot enter $p"
    b=$(branches_model | jq -r .integration) || exit 1
    printf '%s\t%s\n' "$p" "$b" )
}
merge_scope() { # $1 entry JSON → the drafted scope as one JSON line: state, checks after step 1, the pinned merge last
  local pr r n url sha ch ctx rp base out bad
  pr=$(merge_pr_of "$1") || exit 1; read -r r n url <<<"$pr"
  gh_present || die "ledger request $ID --merge: gh is not installed — the head cannot be pinned, so no merge is drafted"
  sha=$("$GH" pr view "$n" -R "$r" --json headRefOid -q .headRefOid 2>/dev/null) || die "ledger request $ID --merge: gh cannot read $r#$n — fails closed"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "ledger request $ID --merge: gh gave '$sha' as $r#$n's head, not a 40-hex sha"
  ch=$(merge_checks_get) || exit 1; ctx=$(merge_repo_ctx "$1") || exit 1; IFS=$'\t' read -r rp base <<<"$ctx"
  check_path_plain "$rp" "--merge"
  # shellcheck disable=SC2016  # a jq program
  out=$(jq -nc --arg n "$n" --arg r "$r" --arg s "$sha" --arg rp "$rp" --arg b "$base" --arg repo "$(jq -r '.repo // empty' <<<"$1")" --argjson ch "$ch" '
    ($ch | map(gsub("\\{repo_path\\}"; $rp) | gsub("\\{base\\}"; $b))) as $c
    | {kind: "merge", repo: (if $repo == "" then null else $repo end), pr: ($n | tonumber), title: "merge \($r)#\($n)", heads: {"\($r)#\($n)": $s},
       steps: (["state: ledger.sh reads pr-watch.sh state \($n) — mergeable at \($s[0:12]), else the action stops (a conflict blocks the entry conflict)"]
               + ($c | map("check: " + .)) + ["merge \($r)#\($n) with a merge commit pinned to \($s[0:12]), then ledger.sh action done"]),
       commands: (($c | map({cmd: ., after_step: 1})) + [{cmd: "gh pr merge \($n) -R \($r) --merge --match-head-commit \($s)", after_step: (($c | length) + 1)}]),
       expects: [], stop_checks: ["pr-watch.sh state is mergeable", "the head is still \($s)", "every check passes"],
       not_covered: ["any gh write but this merge", "a push"], irreversible: true}')
  bad=$(jq -r "$SCOPE_JQ_DEFS"' .commands[].cmd | select((cmd_ok and merge_ok) | not)' <<<"$out" | head -1)
  [ -z "$bad" ] || die "ledger request $ID --merge: the check '$bad' is refused (no shell or interpreter wrapper, no -c, no hefesto helper, no * in the program name)"
  printf '%s\n' "$out"
}
request_merge() { # globals: ID TO SCOPE RENV RVER RSHA — drafts the merge scope, then the ordinary request
  [ -z "$SCOPE$RENV$RVER$RSHA" ] || die "ledger request $ID: --merge drafts its own scope — not with --scope-file or --recipe"
  local e sc; e=$(entry "$ID") || exit 1
  [ "$(jq -r .phase <<<"$e")" = pr ] || die "ledger request $ID --merge: $ID is $(jq -r .phase <<<"$e") — a merge action is drafted for an entry at pr"
  sc=$(merge_scope "$e") || exit 1
  scope_tmp "$sc"; request_action
}

# FR-022: one merging action per repository, over approved and taken actions. A scope MERGES when it is a merge or a
# train, or carries any `gh pr merge` (a hand-written scope may, since merge_ok admits the pinned form — code review
# of PR B: keying on kind alone let one sit beside a kind-merge action on the same repo). Its repositories are its
# heads' owner/repo plus each merge command's -R/--repo; a merge command with neither names "*", every repository.
# Two pending drafts may exist; only one is ever approved — so the check runs at request and at approve.
# shellcheck disable=SC2016  # a jq program
# GitHub owner/repo names are case-insensitive, so the comparison is too.
MERGE_JQ_DEFS='def mcmds: [.commands[]? | if type == "object" then .cmd else . end | strings | select(startswith("gh pr merge "))];
  def merging: .kind == "merge" or .kind == "train" or (mcmds | length > 0);
  def repos: (((.heads // {}) | keys | map(sub("#[0-9]+$"; ""))) + [mcmds[] | (capture("(^| )(-R|--repo)[ =](?<r>[^ ]+)").r // "*")]) | map(ascii_downcase);
  def overlaps($a; $b): any($a[]; . as $x | any($b[]; . == $x or . == "*" or $x == "*"));'
merge_exclusive() { # $1 scope JSON, $2 own aid (or ""), $3 the command for the message → dies naming the open action
  jq -e "$MERGE_JQ_DEFS"' merging' <<<"$1" >/dev/null 2>&1 || return 0
  local sc="$1" own="$2" what="$3" hit
  set -- "$DIR"/actions/*.json; [ -f "$1" ] || return 0
  hit=$(jq -rs --argjson sc "$sc" --arg own "$own" "$MERGE_JQ_DEFS"' ($sc | repos) as $mine
    | map(select(.aid != $own and (.status == "approved" or .status == "taken") and (.scope | merging)
        and overlaps(.scope | repos; $mine)) | "\(.aid) (\(.status), \(.scope.title))") | join(", ")' "$@") \
    || die "ledger $what: an action in $DIR/actions is not valid JSON — repair or remove it"
  [ -z "$hit" ] || die "ledger $what: $hit is open on the same repository — one merge or train action per repository at a time (FR-022); it ends done or stopped first"
}
scope_fetch() { # $1 action JSON, $2 verb — kinds merge and train: git fetch --prune origin in each repo (note 10), fails closed
  case "$(jq -r '.scope.kind // empty' <<<"$1")" in
    merge) local e; e=$(entry "$(jq -r .entry <<<"$1")") || exit 1
           ( cd_entry_repo "$e" || exit 1; hef_fetch_origin >/dev/null 2>&1 ) \
             || die "ledger action $2 $AID: git fetch --prune origin failed in the entry's repo — the checks would see a stale base, so the action does not go on" ;;
    train) train_fetch "$1" "$2" ;;
  esac
}
# A train's repos are the board names its own steps start with ("<repo>: state — …", train_part): the hashed scope
# names them, so nothing the lane can write picks the repo. Its PATH is read from the board config's repos map, a file
# a lane can write — so the fetch runs as every hefesto git call does, with the program-running keys pinned
# (hef_git_neutral) and the repo's own upload-pack overridden (hef_fetch_origin). Each is fetched before any placement check reads
# origin/<base> (T022 verifier, 2026-10-27: without it a train compared against whatever the clone last fetched).
train_fetch() { # $1 action JSON, $2 verb
  local nm p
  while IFS= read -r nm; do
    p=$(jq -r --arg n "$nm" '.repos[$n] // empty' <<<"$BCTX")
    [ -n "$p" ] || die "ledger action $2 $AID: the train names repo '$nm', which the board does not feed ($(repo_names)) — the action does not go on"
    ( cd "$p" && hef_fetch_origin >/dev/null 2>&1 ) \
      || die "ledger action $2 $AID: git fetch --prune origin failed in $nm ($p) — its checks would see a stale base, so the action does not go on"
  done < <(jq -r '.scope.steps[] | capture("^(?<n>[a-z0-9_-]+): state — ").n' <<<"$1")
}
merge_stop() { # $1 action JSON, $2 step, $3 reason, $4 evidence — the action stops and its approval is used up
  jq --argjson n "$2" --arg r "$3" --arg t "$4" '.status = "stopped" | .outcome = {kind: "stopped", step: $n, reason: $r, evidence: $t, at: (now | todate)}' <<<"$1" \
    | action_put "$AID" || exit 1
  store_consume "$AID" "stopped at step $2 ($3)"
  merge_stop_event "$1" "$AID stopped at step $2: $3"
}
# FR-023: a stopped merge returns its entry to human:merge WITH the evidence — the entry, not only the action, says why
# ("head moved from <a> to <b>"), so the next form shows it.
merge_stop_event() { # $1 action JSON, $2 note — kind merge only
  [ "$(jq -r '.scope.kind // empty' <<<"$1")" = merge ] || return 0
  local id e; id=$(jq -r .entry <<<"$1"); e=$(entry "$id") || exit 1
  jq --arg n "${2:0:500}" '.events = ((.events // []) + [{kind: "merge-stopped", at: (now | todate), by: "ledger", note: $n}])' <<<"$e" \
    | write_entry "$id" || exit 1
}
merge_block_ok() { # $1 action JSON, $2 verb, $3 the --block value — only `action stop --block conflict` on a merge action
  [ -n "$3" ] || return 0
  [ "$2" = stop ] && [ "$3" = conflict ] && [ "$(jq -r '.scope.kind // empty' <<<"$1")" = merge ] \
    || die "ledger action $2 $AID: --block takes only conflict, on action stop of a merge action (got '$3')"
}
merge_block_conflict() { # $1 action JSON — the entry's human:merge becomes conflict: the PR goes back to its builder
  local id e; id=$(jq -r .entry <<<"$1"); e=$(entry "$id") || exit 1
  jq '.blocked_on = {kind: "conflict", since: (now | todate), question_path: null}' <<<"$e" | write_entry "$id" || exit 1
  echo "$id blocked_on conflict (was $(jq -r '.blocked_on.kind // "none"' <<<"$e"))"
}
# Step 1 of a merge action is not the lane's report: this reads `pr-watch.sh state` and records only `mergeable` at
# the pinned head. `pending` (checks running) records nothing and leaves the action taken, for a later try.
merge_state_step() { # $1 action JSON, $2 step, $3 the lane's file — sets the caller's f (dynamic scope) to the state read
  [ "$2" -eq 1 ] && [ "$(jq -r '.scope.kind // empty' <<<"$1")" = merge ] || return 0
  local e url want st v head ms ck
  e=$(entry "$(jq -r .entry <<<"$1")") || exit 1; url=$(jq -r '.pr.url // empty' <<<"$e")
  want=$(jq -r '.scope.heads | to_entries[0].value // empty' <<<"$1")
  st=$(cd_entry_repo "$e" && bash "$HERE/pr-watch.sh" state "$url" 2>&1) || die "ledger action step $AID 1: pr-watch.sh state $url failed — nothing recorded: $(tail -1 <<<"$st")"
  v=$(jq -r '.verdict // empty' <<<"$st" 2>/dev/null); head=$(jq -r '.headRefOid // empty' <<<"$st" 2>/dev/null)
  if [ "$head" != "$want" ]; then
    merge_stop "$1" 1 "head moved from $want to ${head:-unknown}" "$st"
    die "ledger action step $AID 1: head moved from $want to ${head:-unknown} ($url) — the action is stopped before the merge"
  fi
  # FR-023: CLEAN (or HAS_HOOKS, CLEAN with hooks) and green. pr-watch's verdict also calls BEHIND "mergeable" — right
  # for a babysitter, wrong for a merge: behind its base is routed back to the builder like a conflict (T021 verifier).
  ms=$(jq -r '.mergeStateStatus // empty' <<<"$st" 2>/dev/null); ck=$(jq -r '.checks // empty' <<<"$st" 2>/dev/null)
  if [ "$v" = mergeable ]; then
    case "$ms" in BEHIND) v=behind ;; CLEAN|HAS_HOOKS) [ "$ck" = pass ] || v="checks $ck" ;; *) v="state ${ms:-unknown}" ;; esac
  fi
  case "$v" in
    mergeable) MERGE_STATE_TMP=$(mktemp "${TMPDIR:-/tmp}/hef-state.XXXXXX") || die "ledger action step $AID 1: cannot create a temp file"
               trap 'rm -f "${RECIPE_TMP:-}" "$MERGE_STATE_TMP"' EXIT
               printf 'pr-watch.sh state: mergeable at %s\n%s\n' "$head" "$st" > "$MERGE_STATE_TMP"
               # shellcheck disable=SC2034  # f is action_cmd's local: the step records this file, not the lane's
               f="$MERGE_STATE_TMP" ;;
    pending) die "ledger action step $AID 1: $url is pending (checks running) — nothing recorded; try step 1 again later" ;;
    *) merge_stop "$1" 1 "pr-watch.sh state is ${v:-unreadable}, not mergeable" "$st"
       case "$v" in conflict|behind) merge_block_conflict "$1" ;; esac
       die "ledger action step $AID 1: $url is ${v:-unreadable}, not mergeable — the action is stopped before the merge" ;;
  esac
}
# FR-021, note 4: done records the merge through the ONE evidence check, with the PR's merge commit from gh, then
# clears human:merge and advances to merged (advance re-checks the evidence and the earlier PRs' stamps).
merge_done() { # $1 action JSON — returns when the merge is recorded; dies (the action stays taken) without evidence
  [ "$(jq -r '.scope.kind // empty' <<<"$1")" != train ] || { train_done "$1"; return 0; }   # US8: per head, no phase moves
  [ "$(jq -r '.scope.kind // empty' <<<"$1")" = merge ] || return 0
  local id e url bk fact st oid via sha
  id=$(jq -r .entry <<<"$1"); e=$(entry "$id") || exit 1; url=$(jq -r '.pr.url // empty' <<<"$e"); bk=$(jq -r '.blocked_on.kind // empty' <<<"$e")
  [ -z "$bk" ] || [ "$bk" = human:merge ] || die "ledger action done $AID: $id is blocked on $bk — not a merge to record"
  fact=$(gh_pr_fact "$url") || die "ledger action done $AID: gh cannot read $url — the merge is never recorded unchecked; retry"
  read -r st _ oid <<<"$fact"
  [ "$st" = MERGED ] && [ "$oid" != - ] || die "ledger action done $AID: $url is $st (merge commit $oid), not merged — the action stays taken"
  via=$(cd_entry_repo "$e" && { hef_fetch_origin >/dev/null 2>&1; merge_evidence "$e" "$oid" recorded; }) \
    || die "ledger action done $AID: no merge evidence for $url (see above) — the action stays taken"
  read -r _ sha _ <<<"$via"
  jq --arg m "$sha" '.blocked_on = null | .pr.merge_sha = $m | del(.pr.merge_unverified)' <<<"$e" | pr_stamp_merged commit "$sha" false | write_entry "$id" || exit 1
  bash "$0" advance "$id" merged >/dev/null || die "ledger action done $AID: $id is stamped and unblocked, but advance to merged failed (see above)"
}

# --- request <OP-n> --to <lane> --train <name> --env <env> --pr <repo>=<n> … (US8, FR-019; plan Sketch 13, 14) -------
# One action promotes several repos in the train's order. Per repo: a state step, one step per merge check
# ({repo_path} = the board's path, {base} = the env, checked against `branches --repo`), then the merge pinned to the
# head read now. Every command waits for its step (after_step), and a train's steps are recorded in order, so a
# repo's merge is never granted before every earlier repo's steps — an earlier failure stops the later repos.
# Each step's text starts with "<board repo>: ", which `done` reads back: the steps are covered by the action hash.
train_repos_get() { # $1 train name → the board repo names in order, one per line, or die listing the trains
  local all t
  all=$(cfgp -c '.orchestrate.deploy.trains // {} | if type == "object" then . else {} end'); [ -n "$all" ] || all='{}'
  t=$(jq -ce --arg n "$1" '.[$n] // empty' <<<"$all") \
    || die "ledger request $ID --train $1: no such train in orchestrate.deploy.trains (configured: $(jq -r 'keys | if length == 0 then "none" else join(", ") end' <<<"$all"))"
  jq -re '(.order // .repos) | if type == "array" and length > 0 and all(type == "string" and test("^[a-z0-9_-]+$")) then .[] else error("x") end' <<<"$t" 2>/dev/null \
    || die "ledger request $ID --train $1: .order (or .repos) must be a non-empty list of board repo names (got $(head -c 200 <<<"$t"))"
}
train_pr_for() { # $1 board repo, $2 the --pr list ("<repo>=<n> …") → the PR number, or die naming the repo
  local p; for p in $2; do [ "${p%%=*}" != "$1" ] || { printf '%s\n' "${p#*=}"; return 0; }; done
  die "ledger request $ID --train $RTRAIN: no PR for $1 — pass --pr $1=<n> for every repo of the train"
}
train_prs_ok() { # $1 the train's repos (lines), $2 the --pr list → dies on a malformed --pr, a repeated one, or one outside the train
  local p seen=""; for p in $2; do
    [[ "$p" =~ ^[a-z0-9_-]+=[1-9][0-9]*$ ]] || die "ledger request $ID --train $RTRAIN: --pr takes <repo>=<PR number> (got '$p')"
    grep -qxF -- "${p%%=*}" <<<"$1" || die "ledger request $ID --train $RTRAIN: --pr ${p%%=*} names a repo outside the train ($(paste -sd, - <<<"$1" | sed 's/,/, /g'))"
    case " $seen " in *" ${p%%=*} "*) die "ledger request $ID --train $RTRAIN: --pr ${p%%=*} is given twice — one PR per repo" ;; esac
    seen="$seen ${p%%=*}"
  done
}
train_repo_head() { # $1 board repo, $2 PR number, $3 env → "<path>\t<owner/repo>\t<head sha>", or die naming what is wrong
  local p bm fact url sha base r
  p=$(jq -r --arg n "$1" '.repos[$n] // empty' <<<"$BCTX")
  [ -n "$p" ] || die "ledger request $ID --train $RTRAIN: repo $1 is not in the board's repos ($(repo_names | sed 's/^$/none/'))"
  bm=$(branches_cli --repo "$1") || die "ledger request $ID --train $RTRAIN: ledger.sh branches --repo $1 failed (see above)"
  jq -e --arg e "$3" '.environments | index($e) != null' <<<"$bm" >/dev/null \
    || die "ledger request $ID --train $RTRAIN: --env $3 is not in $1's branch model ($(jq -r '.environments | join(", ")' <<<"$bm"))"
  fact=$(cd "$p" && "$GH" pr view "$2" --json url,headRefOid,baseRefName -q '"\(.url) \(.headRefOid) \(.baseRefName)"' 2>/dev/null) || die "ledger request $ID --train $RTRAIN: gh cannot read $1's PR #$2 — fails closed"
  read -r url sha base <<<"$fact"
  # the checks compare against origin/<env> and done accepts the merge in the PR's own base, so a PR into another
  # branch would be approved as a promotion to <env> and merged elsewhere (code review of PR B)
  [ "$base" = "$3" ] || die "ledger request $ID --train $RTRAIN: $1's PR #$2 targets '$base', not $3 — a train to $3 merges PRs into $3"
  [[ "$url" =~ ^https://github\.com/([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)/pull/$2$ ]] || die "ledger request $ID --train $RTRAIN: gh gave '$url' for $1's PR #$2, not a GitHub PR URL"
  r="${BASH_REMATCH[1]}"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "ledger request $ID --train $RTRAIN: gh gave '$sha' as $1's PR #$2 head, not a 40-hex sha"
  printf '%s\t%s\t%s\n' "$p" "$r" "$sha"
}
# {repo_path} lands inside a granted command pattern, where a space would split it and a * would widen the grant
# (lane-guard's glob_re), so a path outside this class is refused at request, never escaped into a pattern.
check_path_plain() { # $1 repo path, $2 the request flag → returns, or dies naming the path
  [[ "$1" =~ ^[A-Za-z0-9._/~+@-]+$ ]] || die "ledger request $ID $2: the repo path '$1' has a character a granted command cannot carry (letters, digits, . _ / ~ + @ - only)"
}
train_part() { # $1 scope so far, $2 board repo, $3 PR n, $4 env, $5 checks JSON → the scope with this repo's steps appended
  local h p r sha; h=$(train_repo_head "$2" "$3" "$4") || exit 1; IFS=$'\t' read -r p r sha <<<"$h"
  check_path_plain "$p" "--train"
  # shellcheck disable=SC2016  # a jq program
  jq -c --arg nm "$2" --arg n "$3" --arg r "$r" --arg s "$sha" --arg rp "$p" --arg b "$4" --argjson ch "$5" '
    ($ch | map(gsub("\\{repo_path\\}"; $rp) | gsub("\\{base\\}"; $b))) as $c | (.steps | length + 1) as $st
    | .heads += {"\($r)#\($n)": $s}
    | .steps += ["\($nm): state — pr-watch.sh state https://github.com/\($r)/pull/\($n) is mergeable at \($s[0:12]), else stop the action"]
               + ($c | map("\($nm): check — " + .)) + ["\($nm): merge \($r)#\($n) with a merge commit pinned to \($s[0:12])"]
    | .commands += ($c | map({cmd: ., after_step: $st})) + [{cmd: "gh pr merge \($n) -R \($r) --merge --match-head-commit \($s)", after_step: ($st + ($c | length))}]' <<<"$1"
}
train_scope() { # $1 train, $2 env, $3 the --pr list → the drafted scope as one JSON line, or die naming the offender
  local repos ch out nm n bad
  repos=$(train_repos_get "$1") || exit 1; train_prs_ok "$repos" "$3"
  [[ "$2" =~ ^[A-Za-z0-9._][A-Za-z0-9._/-]{0,63}$ ]] || die "ledger request $ID --train $1: --env must be a branch name of the repos' model (got '$2')"
  gh_present || die "ledger request $ID --train $1: gh is not installed — the heads cannot be pinned, so no train is drafted"
  ch=$(merge_checks_get) || exit 1
  out=$(jq -nc --arg t "$1" --arg e "$2" '{kind: "train", repo: null, pr: null, title: "promote \($t) to \($e)", heads: {}, steps: [], commands: [], expects: [],
    stop_checks: ["each repo is mergeable before its own merge", "the heads are unchanged", "every check passes", "a failed repo stops the train before the next"],
    not_covered: ["any gh write but these merges", "a push", "an item phase: items reach released through deployed"], irreversible: true}')
  while IFS= read -r nm; do n=$(train_pr_for "$nm" "$3") || exit 1; out=$(train_part "$out" "$nm" "$n" "$2" "$ch") || exit 1; done <<<"$repos"
  bad=$(jq -r "$SCOPE_JQ_DEFS"' .commands[].cmd | select((cmd_ok and merge_ok) | not)' <<<"$out" | head -1)
  [ -z "$bad" ] || die "ledger request $ID --train $1: the check '$bad' is refused (no shell or interpreter wrapper, no -c, no hefesto helper, no * in the program name)"
  printf '%s\n' "$out"
}
request_train() { # globals: ID TO SCOPE RENV RVER RSHA RTRAIN RTENV RPRS — drafts the train scope, then the ordinary request
  [ -z "$SCOPE$RENV$RVER$RSHA" ] || die "ledger request $ID: --train drafts its own scope — not with --scope-file or --recipe"
  [ -n "$RTRAIN" ] && [ -n "$RTENV" ] || die "ledger request $ID: a train is --train <name> --env <env> --pr <repo>=<n> …"
  local e sc; e=$(entry "$ID") || exit 1
  [ "$(jq -r '.item_kind // empty' <<<"$e")" = op ] || die "ledger request $ID --train: a train hangs on an op (ledger.sh op new --title …), and $ID is not an op"
  sc=$(train_scope "$RTRAIN" "$RTENV" "$RPRS") || exit 1
  scope_tmp "$sc"; request_action
}

# action step on any action whose commands wait for a step (after_step: merge, train): steps are recorded in order
# (Sketch 13), which is what makes after_step an ordering. A merge recorded out of order would skip step 1, the
# ledger's own state read (FR-023), a recipe out of order would run past its version check (FR-017); a pre-9.1 action
# (bare strings) and a one-step recipe keep any order.
step_order() { # $1 action JSON, $2 step → returns when the step may be recorded, or dies naming the missing one
  jq -e '[.scope.commands[]? | objects | .after_step | numbers] | length > 0' <<<"$1" >/dev/null || return 0
  local kind; kind=$(jq -r '.scope.kind // "action"' <<<"$1")
  local miss; miss=$(jq -r --argjson n "$2" '[.steps_done[]?.n] as $d | if $n < 1 or $n > (.scope.steps | length) then "range"
    else [range(1; $n) | select(. as $k | $d | index($k) | not)] | first // empty end' <<<"$1")
  [ "$miss" != range ] || die "ledger action step $AID $2: the $kind has steps 1..$(jq -r '.scope.steps | length' <<<"$1")"
  [ -z "$miss" ] || die "ledger action step $AID $2: a $kind records its steps in order — step $miss is not recorded yet"
}

# done (kind train, note 19): every head, in its own repo after a fetch, through pr_merge_evidence. No unverified path
# and no item phase moves: items reach released through `deployed`, a fact about a commit, not about the train.
train_heads() { # $1 action JSON → "<board repo>\t<n>\t<owner/repo>\t<pinned sha>" per merge command, in order
  jq -re '.scope as $s | [$s.commands[] | if type == "string" then {cmd: ., after_step: null} else . end | select(.cmd | startswith("gh pr merge "))
    | (.cmd | capture("^gh pr merge (?<n>[0-9]+) -R (?<r>[^ ]+) --merge --match-head-commit (?<s>[0-9a-f]{40})$")) as $m
    | ($s.steps[.after_step] | capture("^(?<nm>[a-z0-9_-]+): merge ").nm) as $nm | "\($nm)\t\($m.n)\t\($m.r)\t\($m.s)"] | if length == 0 then error("none") else .[] end' <<<"$1" 2>/dev/null
}
pr_merge_evidence() { # $1 board repo, $2 owner/repo, $3 PR n, $4 pinned sha → prints the proof, or dies naming what is missing
  local p fact st head base oid rc
  p=$(jq -r --arg n "$1" '.repos[$n] // empty' <<<"$BCTX"); [ -n "$p" ] || die "ledger action done $AID: repo $1 is not in the board's repos ($(repo_names))"
  fact=$("$GH" pr view "$3" -R "$2" --json state,mergeCommit,baseRefName,headRefOid -q '"\(.state) \(.headRefOid) \(.baseRefName) \(.mergeCommit.oid // "-")"' 2>/dev/null) \
    || die "ledger action done $AID: gh cannot read $2#$3 — a train's merge is never recorded unchecked; retry"
  read -r st head base oid <<<"$fact"
  [ "$st" = MERGED ] || die "ledger action done $AID: $2#$3 is $st, not merged — the action stays taken"
  [ "$head" = "$4" ] || die "ledger action done $AID: $2#$3 merged head $head, the approval pinned $4 — the action stays taken"
  [[ "$oid" =~ ^[0-9a-f]{7,40}$ ]] && [[ "$base" =~ ^[A-Za-z0-9._][A-Za-z0-9._/-]*$ ]] || die "ledger action done $AID: $2#$3 reports no merge commit or base ('$oid', '$base')"
  ( cd "$p" && hef_fetch_origin ) >/dev/null 2>&1 || die "ledger action done $AID: git fetch --prune origin failed in $1 ($p) — the evidence would be stale"
  rc=$(cd "$p" && { in_branch "$oid" "$base" >/dev/null; echo $?; })
  case "$rc" in
    0) echo "$2#$3 merged into $base at ${oid:0:12} (head ${4:0:12})" ;;
    1) die "ledger action done $AID: $2#$3's merge commit $oid is not in its base $base (nor origin/$base) — the action stays taken" ;;
    3) die "ledger action done $AID: $2#$3's merge commit $oid is not in $1's clone after a fetch" ;;
    *) die "ledger action done $AID: $2#$3's base $base resolves nowhere in $1 (no $base, no origin/$base)" ;;
  esac
}
train_done() { # $1 action JSON — returns when every head is merged into its PR's base; dies otherwise (the action stays taken)
  gh_present || die "ledger action done $AID: gh is not installed — a train's merges cannot be checked, so done is refused (no unverified path)"
  local hs nm n r sha
  hs=$(train_heads "$1") || die "ledger action done $AID: the train's scope names no pinned merge — not a train this ledger drafted"
  while IFS=$'\t' read -r nm n r sha; do pr_merge_evidence "$nm" "$r" "$n" "$sha" || exit 1; done <<<"$hs"
}
