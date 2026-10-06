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
  board                                                 the resolved board as JSON: mode (in-repo|external), board_top, config, ledger_dir, repos, repo
  init <id> --kind <tasks-repo|github-project> --ref <ref> [--url <u>] [--body-file <f>] [--item-kind feature|incident|vulnerability] [--repo <name>]   (--repo: required on an external board)
  claim <id> --session <name> --role <role>             exclusive; attempts > 2 → stall
  advance <id> <phase>                                  forward-only along the phase enum
  verdict <id> --gate <g> --verdict <PASS|FAIL|SKIPPED> --by <session> [--evidence <text>]
  block <id> --kind <kind> [--question <path>]
  unblock <id> [--reviewed-by-human --by <name>]        human:* kinds need artifact evidence (intake: a person's name, recorded)
  run <id> --role <role> --exit <n> --usd <x> [--session-id <s>]   records the run, releases owner
  record <id> [--worktree w] [--branch b] [--route r] [--pr url] [--spec-dir d] [--body-file f] [--item-kind k]   (--body-file re-hashes the item)
  show <id> | list [--phase p] [--blocked] [--active] [--today] | next [--stage plan|build|deploy]
  metrics [--since YYYY-MM-DD] [--json]                 delivery numbers from the entries (report 17 §7)
  handoff <id> --pr <url> [--branch <b>]                a hand-run item into the release queue (run, record, pr, human:merge)
  publish <id>                                          mirror the entry's state to the board (opt-in: orchestrate.publish)
  escalate [--record <id>]                              old human:* blocks as one-line pointers (opt-in: orchestrate.escalate_after_hours)
  branches                                              the resolved branch model as JSON (config .branches; defaults = trunk on main)
  where <id>                                            per environment: does it contain the entry's branch (local, then origin/)
EOF
  exit 2
}

command -v jq >/dev/null 2>&1 || die "ledger: jq not found — install jq: https://jqlang.org"
HERE="$(cd "$(dirname "$0")" && pwd)"

# The kind → pane map (stage-roles FR-010) — byte-identical to session-start-context.sh's copy; the smoke
# suite compares the two strings (ledger-surfaces FR-005). Config `orchestrate.panes` wins per pane.
PANES_DEFAULT='{"orchestrator":["human:intake"],"plan":["human:clarify","human:plan-review"],"build":["verdict","stall","budget","conflict"],"deploy":["ci","human:merge"]}'
# The publish state markers (ledger-surfaces FR-003) — byte-identical to status-board.sh's copy, which
# `--mark` uses to know which leading heading tokens are ITS markers (replace, never stack).
PUBLISH_MARKERS_DEFAULT='{"human_block":"⏸","block":"⛔","plan":"📐","build":"🔨","pr":"🔀","done":"✅"}'

# The board resolution (external-board FR-001) lives in board-lib.sh: project_config, repo_config, board_ctx
# and the helpers the arms below use (is_external, repo_names, cd_entry_repo). Sourced, never run.
[ -f "$HERE/board-lib.sh" ] || die "ledger: $HERE/board-lib.sh not found — the plugin install is incomplete (reinstall it, or copy board-lib.sh beside ledger.sh)"
# shellcheck source=hooks/board-lib.sh
. "$HERE/board-lib.sh"
cfgp() { # jq over the project config; empty output when there is no config (callers decide what absent means)
  local c; c=$(project_config) || return 0
  jq -r "$@" "$c" 2>/dev/null
}

# The branch model (branch-model FR-001): ONE place applies the defaults and validates; every consumer
# (session-launch, pr-watch, speckit-helper, merge-tree-probe, the commands) asks `ledger.sh branches`.
# `jq -n … input?`: an absent config must still run the program — jq never runs one over EMPTY input
# (plan review 2026-10-05: `jq -ce … /dev/null` printed nothing and exited 4).
branches_model() {
  local c out; c=$(repo_config) || c=""   # the CURRENT repo's model: ops integrates on dev, ui on trunk (external-board)
  # A config that does not PARSE is malformed, never "unconfigured": `input?` alone would swallow the
  # parse error and hand back the trunk defaults — dropping every protected branch on a typo (code review B1).
  [ -z "$c" ] || jq empty "$c" 2>/dev/null || die "ledger branches: $c is not valid JSON"
  out=$(jq -nce '
    def nm: type == "string" and test("^[A-Za-z0-9._][A-Za-z0-9._/-]*$") and (test("\\.\\.") | not);
    ((input? // null) | if type == "object" then .branches else null end) as $raw | ($raw // {}) as $b
    | if ($b | type) != "object" then error("branches must be an object like {\"integration\": \"dev\"}")
      else ($b.integration // "main") as $i | ($b.environments // [$i]) as $e | ($b.protected // []) as $p
      | if ($i | nm | not) then error("branches.integration must be a branch name (got \($i | tojson))")
        elif ($p | type) != "array" or ($p | any(type != "string" or length == 0 or test("[[:cntrl:]\\s]"))) then error("branches.protected must be a list of branch names or globs (got \($p | tojson))")
        elif ($e | type) != "array" or ($e | length) == 0 or ($e | any(nm | not)) or $e[0] != $i then error("branches.environments must be a list of branch names starting with the integration branch \($i | tojson) (got \($e | tojson))")
        else {integration: $i, protected: (["main", "master", $i] + $e + $p | unique), environments: $e, final: $e[-1]} end end' \
    ${c:+"$c"} 2>&1 </dev/null) || die "ledger branches: ${c:-<no config>}: ${out#jq: error*: }"
  echo "$out"
}
# in_branch <branch> <target> → prints the ref that contains it. Source and target are each tried
# local first, then origin/ (fxcube often has no local `dev`, only origin/dev). Exit 0 = contained;
# 1 = a target resolved and does not contain it ("not merged"); 3 = the branch resolves nowhere;
# 4 = the target resolves nowhere. 3 and 4 are never "not merged" (plan reviews 2026-10-05).
in_branch() {
  local src t found=0
  if git rev-parse --verify -q "$1^{commit}" >/dev/null 2>&1; then src="$1"
  elif git rev-parse --verify -q "origin/$1^{commit}" >/dev/null 2>&1; then src="origin/$1"
  else return 3; fi
  for t in "$2" "origin/$2"; do
    git rev-parse --verify -q "$t^{commit}" >/dev/null 2>&1 || continue
    found=1
    git merge-base --is-ancestor "$src" "$t" 2>/dev/null && { echo "$t"; return 0; }
  done
  [ "$found" = 1 ] && return 1
  return 4
}
is_protected() { # $1 branch, $2 model JSON — glob match over the effective protected set
  local p; while IFS= read -r p; do
    # shellcheck disable=SC2254  # the pattern IS a glob, on purpose (release/*)
    case "$1" in $p) return 0 ;; esac
  done < <(jq -r '.protected[]' <<<"$2"); return 1
}

# Sort ids by prefix then NUMERIC suffix: lexical order would dispatch HEF-10 before HEF-9 (review 2026-09-27).
ID_SORT='sort_by(.id | (capture("^(?<p>.*?)(?<n>[0-9]+)$") // {p: ., n: "0"}) | [.p, (.n | tonumber)])'
PHASES=(queued intake spec plan plan-review tasks implement verify quality security pr merged released)
KINDS="human:clarify human:plan-review human:merge human:intake ci conflict budget stall verdict"
GATES="verify review quality scan mutate incident vulnerability"   # the last two: item-kinds FR-002

ledger_dir() {
  if [ -n "${HEFESTO_LEDGER_DIR:-}" ]; then mkdir -p "$HEFESTO_LEDGER_DIR" || die "ledger: cannot create $HEFESTO_LEDGER_DIR"; echo "$HEFESTO_LEDGER_DIR"; return; fi
  # external-board: ONE central ledger in the board repo's git common dir, so ownership, list, metrics and
  # escalation see every repo the board feeds.
  if is_external; then
    local central; central=$(jq -r .ledger_dir <<<"$BCTX")
    mkdir -p "$central" || die "ledger: cannot create $central"; echo "$central"; return
  fi
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

# external-board FR-003: one worker per REPOSITORY. An entry is skipped while another entry of its repo is
# owned, so ops and ui run side by side. In-repo mode keeps today's `next` (no filter; /hef.orchestrate
# step 2 still stops on any owned entry) — the existing suite pins that. Uses SEL, ORDER, STAGE, FILES.
next_external() {
  local bad n busy
  bad=$(jq -rs "map(select($SEL) | select((.repo // \"\") == \"\") | .id) | join(\", \")" "${FILES[@]}") \
    || die "ledger next: an entry in $DIR is not valid JSON — repair or remove it"
  [ -z "$bad" ] || die "ledger next: the board is external and these entries record no repo: $bad — re-register each with ledger.sh init <id> … --repo <name> (the board feeds: $(repo_names))"
  n=$(jq -rs "[.[] | select(.owner != null) | (.repo // \"\")] as \$busy | map(select($SEL) | select((.repo // \"\") as \$r | \$busy | any(. == \$r) | not)) | $ORDER | .[0].id // empty" "${FILES[@]}") \
    || die "ledger next: an entry in $DIR is not valid JSON — repair or remove it"
  if [ -z "$n" ] && [ -n "$(jq -rs "map(select($SEL)) | .[0].id // empty" "${FILES[@]}")" ]; then
    busy=$(jq -rs '[.[] | select(.owner != null) | "\(.repo // "<none>") (owned by \(.owner.session_name) on \(.id))"] | join(", ")' "${FILES[@]}")
    die "ledger next: no dispatchable entry for stage $STAGE — every candidate's repo is busy (one worker per repository): $busy"
  fi
  [ -n "$n" ] || die "ledger next: no dispatchable entry for stage $STAGE in $DIR (plan: queued|intake; build: queued|tasks|implement, unowned, unblocked; deploy: pr with a PR)"
  echo "$n"
}

[ $# -ge 1 ] || usage
SUB="$1"; shift
# Read-only and ledger-free: answered before ledger_dir, which would create the directory (and needs a repo).
# `branches --configured` exits 0 when the config declares a `branches` block, 1 otherwise — so the
# consumers that keep the historical order for unconfigured repos ask here instead of re-reading.
if [ "$SUB" = branches ]; then
  if [ "${1:-}" = --configured ]; then   # 0 = declared, 1 = not, 2 = the config is not valid JSON (loud)
    c=$(repo_config) || exit 1   # the same file branches_model reads — never the board config (external-board)
    jq empty "$c" 2>/dev/null || { echo "ledger branches: $c is not valid JSON" >&2; exit 2; }
    jq -e '.branches != null' "$c" >/dev/null 2>&1; [ $? -eq 0 ] && exit 0; exit 1
  fi
  branches_model; exit $?
fi
# The board (external-board FR-001), resolved once per call. `board` is answered here, before ledger_dir:
# side-effect free, and in-repo it never dies where status-board does not (outside git, no config).
BCTX=$(board_ctx) || exit 1
if [ "$SUB" = board ]; then [ $# -eq 0 ] || usage; echo "$BCTX"; exit 0; fi
DIR=$(ledger_dir) || exit 1

case "$SUB" in
  dir) echo "$DIR" ;;

  init)
    ID="${1:-}"; [ -n "$ID" ] || usage; shift
    KIND=""; REF=""; URL=""; BODY=""; IKIND="feature"; RNAME=""; HAVE_REPO=0
    while [ $# -gt 0 ]; do case "$1" in
      --kind) KIND="${2:-}"; shift ;; --ref) REF="${2:-}"; shift ;; --url) URL="${2:-}"; shift ;; --body-file) BODY="${2:-}"; shift ;;
      --item-kind) IKIND="${2:-}"; shift ;; --repo) RNAME="${2:-}"; HAVE_REPO=1; shift ;;
      *) usage ;; esac; shift; done
    valid_id "$ID" || exit 1
    # external-board FR-003: the entry's repo, checked against the board's repos map. An EMPTY --repo is the
    # signature of a failed status-board.sh --item-repo swallowed by $(…) — never "no repo".
    if is_external; then
      [ "$HAVE_REPO" = 1 ] || die "ledger init $ID: the board is external — --repo <name> is required (the board feeds: $(repo_names))"
      [ -n "$RNAME" ] || die "ledger init $ID: --repo is empty — expected one of: $(repo_names) (status-board.sh --item-repo $ID names it)"
      jq -e --arg r "$RNAME" '.repos | has($r)' <<<"$BCTX" >/dev/null || die "ledger init $ID: --repo '$RNAME' is not a repo the board feeds ($(repo_names))"
    else
      [ "$HAVE_REPO" = 0 ] || die "ledger init $ID: --repo '$RNAME' given, but the board is in-repo (no repos map in $(project_config || echo .claude/project-status.json)) — drop --repo"
    fi
    # An EMPTY --item-kind is the signature of a failed detection swallowed by $(…) — never "feature".
    in_list "$IKIND" "feature incident vulnerability" || die "ledger init $ID: --item-kind must be feature, incident or vulnerability (got '${IKIND}')"
    if [ -f "$DIR/$ID.json" ]; then echo "$DIR/$ID.json"; exit 0; fi      # idempotent: unchanged, path printed
    in_list "$KIND" "tasks-repo github-project" || die "ledger init $ID: --kind must be tasks-repo or github-project (got '${KIND:-<none>}')"
    [ -n "$REF" ] || die "ledger init $ID: --ref is required (e.g. tasks/TODO.md#$ID)"
    SHA=null
    if [ -n "$BODY" ]; then [ -f "$BODY" ] || die "ledger init $ID: body file not found: $BODY"; SHA="\"$(sha256sum "$BODY" | cut -c1-64)\""; fi
    jq -n --arg id "$ID" --arg kind "$KIND" --arg ref "$REF" --arg url "$URL" --argjson sha "$SHA" --arg ik "$IKIND" --arg repo "$RNAME" '{
      id: $id, source: {kind: $kind, ref: $ref, url: (if $url == "" then null else $url end), body_sha256: $sha},
      item_kind: $ik, route: null, phase: "queued", owner: null, worktree: null, branch: null, spec_dir: null, pr: null,
      verdicts: [], blocked_on: null, budget: {usd_cap: null, usd_spent: 0}, runs: [], attempts: 0,
      created: (now | todate), updated: (now | todate) } + (if $repo == "" then {} else {repo: $repo} end)' | write_entry "$ID" || exit 1
    echo "$DIR/$ID.json" ;;

  claim)
    ID="${1:-}"; [ -n "$ID" ] || usage; shift; SESSION=""; ROLE=""
    while [ $# -gt 0 ]; do case "$1" in --session) SESSION="${2:-}"; shift ;; --role) ROLE="${2:-}"; shift ;; *) usage ;; esac; shift; done
    [ -n "$SESSION" ] && [ -n "$ROLE" ] || die "ledger claim $ID: --session <name> and --role <role> are required"
    E=$(entry "$ID") || exit 1
    OWNER=$(jq -r '.owner.session_name // empty' <<<"$E")
    [ -z "$OWNER" ] || die "ledger claim $ID: already owned by $OWNER (expected owner=null; wait for its run to finish)"
    # An intake-blocked entry is never worked on: claim → run → claim would reach the stall below and
    # overwrite the block (security re-review 2026-10-06). human:merge stays claimable — the deploy stage
    # babysits exactly that wait.
    [ "$(jq -r '.blocked_on.kind // empty' <<<"$E")" != human:intake ] \
      || die "ledger claim $ID: blocked on human:intake — a person reads the item and clears it (ledger.sh unblock $ID --reviewed-by-human --by <name>) before any session works on it"
    # attempts count IMPLEMENT claims only: a verify claim after each run would otherwise stall an
    # entry on its second implement attempt.
    INC=0; [ "$ROLE" = implement ] && INC=1
    N=$(jq --argjson i "$INC" '.attempts + $i' <<<"$E")
    if [ "$N" -gt 2 ]; then
      # never over a person's block — the stall only records when nothing a person must clear is pending
      jq 'if ((.blocked_on.kind // "") | startswith("human:")) then . else .blocked_on = {kind: "stall", since: (now | todate), question_path: null} end | .attempts += 1' <<<"$E" | write_entry "$ID" || exit 1
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
    if [ "$TO" = released ]; then   # branch-model FR-006 — the model is loaded only on this path
      cd_entry_repo "$E" || exit 1   # external-board: the entry's repo, its own model and its own branches
      BM=$(branches_model) || exit 1
      if [ "$(jq '.environments | length' <<<"$BM")" -gt 1 ]; then
        FIN=$(jq -r .final <<<"$BM"); BR=$(jq -r '.branch // empty' <<<"$E")
        [ -n "$BR" ] || die "ledger advance $ID released: no branch recorded — cannot check it reached $FIN"
        in_branch "$BR" "$FIN" >/dev/null; rc=$?
        [ "$rc" -ne 3 ] || die "ledger advance $ID released: branch '$BR' resolves to no commit (local or origin/) — git fetch first"
        [ "$rc" -ne 4 ] || die "ledger advance $ID released: the final branch '$FIN' resolves nowhere (no $FIN, no origin/$FIN) — git fetch first"
        [ "$rc" -eq 0 ] || die "ledger advance $ID released: '$BR' is in neither $FIN nor origin/$FIN — promote it first (git fetch if it was merged remotely)"
      fi
    fi
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
    # A launched worker never REPLACES a person's block: blocking a human:intake entry with `ci` and then
    # clearing `ci` freely was a path around the gate open to any worker, whose allowlist carries the hooks
    # directory (security review 2026-10-06, reproduced on 7.9.0). The launcher itself — the pane process,
    # never HEFESTO_WORKER — still re-blocks after a deploy pass, as it always has.
    CURK=$(jq -r '.blocked_on.kind // empty' <<<"$E")
    # human:intake is never replaced by ANY caller (user decision 2026-10-06): block-with-another-kind then
    # clear-that-kind was a route around the named clear, behind dialogs that never mention intake.
    [ "$CURK" != human:intake ] || [ "$KIND" = human:intake ] \
      || die "ledger block $ID: it is blocked on human:intake — nothing replaces it; a person clears it with ledger.sh unblock $ID --reviewed-by-human --by <name>"
    if [ -n "${HEFESTO_WORKER:-}" ] && [ "$HEFESTO_WORKER" != 0 ] && [[ "$CURK" == human:* ]] && [ "$KIND" != "$CURK" ]; then
      die "ledger block $ID: it is blocked on $CURK — a launched worker never replaces a person's block (only the person's own command clears it)"
    fi
    jq --arg k "$KIND" --arg q "$Q" '.blocked_on = {kind: $k, since: (now | todate), question_path: (if $q == "" then null else $q end)}' <<<"$E" | write_entry "$ID" || exit 1
    echo "$ID blocked_on $KIND" ;;

  unblock)
    ID="${1:-}"; [ -n "$ID" ] || usage; shift; REVIEWED=0; RBY=""
    while [ $# -gt 0 ]; do case "$1" in --reviewed-by-human) REVIEWED=1 ;; --by) RBY="${2:-}"; shift ;; *) usage ;; esac; shift; done
    E=$(entry "$ID") || exit 1
    KIND=$(jq -r '.blocked_on.kind // empty' <<<"$E"); [ -n "$KIND" ] || die "ledger unblock $ID: not blocked"
    [ "$KIND" = human:intake ] || { [ "$REVIEWED" = 0 ] && [ -z "$RBY" ]; } \
      || die "ledger unblock $ID: --reviewed-by-human / --by apply to human:intake only — this entry is blocked on $KIND (a reviewer would not be recorded)"
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
        cd_entry_repo "$E" || exit 1   # external-board: run from the board repo, the merge is checked in the entry's repo
        BM=$(branches_model) || exit 1; INT=$(jq -r .integration <<<"$BM")
        in_branch "$BRANCH" "$INT" >/dev/null; rc=$?
        [ "$rc" -ne 3 ] || die "ledger unblock $ID: $KIND — branch '$BRANCH' resolves to no commit (local or origin/) — git fetch origin first"
        [ "$rc" -ne 4 ] || die "ledger unblock $ID: $KIND — the integration branch '$INT' resolves nowhere (no $INT, no origin/$INT) — git fetch origin first"
        [ "$rc" -eq 0 ] || die "ledger unblock $ID: $KIND — '$BRANCH' is in neither $INT nor origin/$INT (git fetch origin first if it was merged remotely)" ;;
      human:intake)
        # The prompt-injection gate. It used to test `-t 0`, which the Bash tool never has, so a person
        # who had read the item in an interactive session still had to copy the line into a terminal
        # (fxcube, 2026-10-06). A terminal test proves nothing about who read the item, and anything a
        # session can run, the model that read the hostile text can run too — so the gate is the
        # PERMISSION PROMPT: this command must never be allowlisted (docs/install.md), every clear is a
        # dialog the person answers, and the name is recorded. A launched worker is refused outright.
        # That premise needs the pane in `default` permission mode: under auto, bypassPermissions or
        # dontAsk there is no dialog — session-start-context.sh warns when an intake block meets one.
        [ -z "${HEFESTO_WORKER:-}" ] || [ "$HEFESTO_WORKER" = 0 ] \
          || die "ledger unblock $ID: $KIND is never cleared from inside a launched worker — a person reads the item and runs it from their own session"
        # Compatibility: from a real terminal, --reviewed-by-human alone still works (as before 7.9.1), recording the login.
        [ -z "$RBY" ] && [ "$REVIEWED" = 1 ] && [ -t 0 ] && RBY="${USER:-$(id -un 2>/dev/null)}"
        [ "$REVIEWED" = 1 ] && [[ "$RBY" =~ ^[A-Za-z0-9]([A-Za-z0-9._@\ -]{0,62}[A-Za-z0-9._@-])?$ ]] \
          || die "ledger unblock $ID: $KIND needs --reviewed-by-human --by <your name> — a person read the item text (status-board.sh --item $ID) and answers the permission prompt for this command; never allowlist it" ;;
    esac
    if [ "$KIND" = human:intake ]; then
      jq --arg by "$RBY" '.blocked_on = null | .reviewed = ((.reviewed // []) + [{kind: "human:intake", by: $by, at: (now | todate)}])' <<<"$E" | write_entry "$ID" || exit 1
      echo "$ID unblocked ($KIND, reviewed by $RBY)"
    else
      jq '.blocked_on = null' <<<"$E" | write_entry "$ID" || exit 1; echo "$ID unblocked ($KIND)"
    fi ;;

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
      --item-kind) in_list "${2:-}" "feature incident vulnerability" || die "ledger record $ID: --item-kind must be feature, incident or vulnerability (got '${2:-}')"; setf '.item_kind = $v' "$2"; shift ;;
      *) usage ;; esac; shift; done
    write_entry "$ID" <<<"$E" || exit 1; echo "$ID recorded" ;;

  show) ID="${1:-}"; [ -n "$ID" ] || usage; entry "$ID" ;;
  where)   # branch-model FR-006 — computed from git, never stored
    ID="${1:-}"; [ -n "$ID" ] || usage
    E=$(entry "$ID") || exit 1; BR=$(jq -r '.branch // empty' <<<"$E")
    [ -n "$BR" ] || die "ledger where $ID: no branch recorded (ledger.sh record $ID --branch <b>)"
    cd_entry_repo "$E" || exit 1
    BM=$(branches_model) || exit 1
    UNK=0
    while IFS= read -r ENV; do
      REF=$(in_branch "$BR" "$ENV"); rc=$?
      [ "$rc" -ne 3 ] || die "ledger where $ID: branch '$BR' resolves to no commit (local or origin/) — git fetch first"
      case "$rc" in 0) echo "$ENV: yes ($REF)" ;; 4) echo "$ENV: unknown (no $ENV, no origin/$ENV)"; UNK=1 ;; *) echo "$ENV: no" ;; esac
    done < <(jq -r '.environments[]' <<<"$BM")
    [ "$UNK" = 0 ] || exit 1 ;;

  # --- ledger-surfaces (HEF-6, HEF-4, HEF-5) -------------------------------------------------------
  # handoff: the four calls a person makes for a hand-run item, through the same arms (their guards
  # apply). The temporary owner `hand` gives the run a session name, so the review guard (verdict --by ≠
  # an implement session) has something to compare. A blocked entry is refused: a handoff must never
  # clear a human:intake or stall block that only a person may clear.
  handoff)
    ID="${1:-}"; [ -n "$ID" ] || usage; shift; PR=""; BR=""
    while [ $# -gt 0 ]; do case "$1" in --pr) PR="${2:-}"; shift ;; --branch) BR="${2:-}"; shift ;; *) usage ;; esac; shift; done
    [[ "$PR" =~ /pull/[0-9]+$ ]] || die "ledger handoff $ID: --pr must be a pull-request URL ending in /pull/<n> (got '$PR')"
    E=$(entry "$ID") || exit 1
    OWNER=$(jq -r '.owner.session_name // empty' <<<"$E")
    [ -z "$OWNER" ] || die "ledger handoff $ID: owned by $OWNER — a session holds it; wait for its run to finish"
    K=$(jq -r '.blocked_on.kind // empty' <<<"$E")
    [ -z "$K" ] || die "ledger handoff $ID: blocked on $K — clear it with the command it names first (a handoff never clears a block)"
    CI=$(phase_index "$(jq -r .phase <<<"$E")") || exit 1; PI=$(phase_index pr) || exit 1
    [ "$CI" -le "$PI" ] || die "ledger handoff $ID: phase $(jq -r .phase <<<"$E") is already past pr"
    # external-board FR-006: the entry records the repo the handoff runs in, matched by its main worktree path
    HREPO=""
    if is_external; then
      HREPO=$(jq -r '.repo // empty' <<<"$BCTX")
      [ -n "$HREPO" ] || die "ledger handoff $ID: this repository ($(main_top || pwd)) is not one the board feeds ($(jq -r '.repos | to_entries | map("\(.key) = \(.value)") | join(", ")' <<<"$BCTX")) — hand off from the item's repo"
      ER=$(jq -r '.repo // empty' <<<"$E")
      [ -z "$ER" ] || [ "$ER" = "$HREPO" ] || die "ledger handoff $ID: the entry records repo '$ER', this is '$HREPO' — hand off from $ER's checkout"
    fi
    [ -n "$BR" ] || BR=$(git branch --show-current 2>/dev/null)
    [ -n "$BR" ] || die "ledger handoff $ID: no branch (detached HEAD) — hand off from the feature branch (or pass --branch)"
    BM=$(branches_model) || exit 1
    ! is_protected "$BR" "$BM" || die "ledger handoff $ID: '$BR' is a protected branch ($(jq -r '.protected | join(", ")' <<<"$BM")) — hand off from the feature branch (or pass --branch)"
    jq --arg r "$HREPO" '.owner = {session_name: "hand", role: "implement", pid: null, started: (now | todate)} | if $r == "" then . else .repo = $r end' <<<"$E" | write_entry "$ID" || exit 1
    # A failure after the owner write must not strand the entry under a session that does not exist.
    unhand() { local e; e=$(entry "$ID") && jq 'if .owner.session_name == "hand" then .owner = null else . end' <<<"$e" | write_entry "$ID"; die "ledger handoff $ID: $1 failed — the entry is released; fix the cause and run handoff again"; }
    bash "$0" run "$ID" --role implement --exit 0 --usd 0 >/dev/null || unhand run
    bash "$0" record "$ID" --pr "$PR" --branch "$BR" --worktree "$PWD" >/dev/null || unhand record
    if [ "$CI" -lt "$PI" ]; then bash "$0" advance "$ID" pr >/dev/null || unhand advance; fi
    bash "$0" block "$ID" --kind human:merge >/dev/null || unhand block
    entry "$ID" ;;

  # publish: the board shows where an item is. tasks-repo: verify the item's hash BEFORE writing (a
  # person's edit is still "changed since claim"), write the state marker through status-board.sh --mark
  # (the board's one write path), re-hash after (publish's own marker is not an edit). github-project:
  # one issue comment. Nothing is written when the state did not change.
  publish)
    ID="${1:-}"; [ -n "$ID" ] || usage
    [ "$(cfgp '.orchestrate.publish // false')" = true ] || die "ledger publish $ID: publish is off — set orchestrate.publish to true in .claude/project-status.json"
    E=$(entry "$ID") || exit 1
    MAP=$(jq -c --argjson d "$PUBLISH_MARKERS_DEFAULT" '$d + ((.orchestrate.publish_markers // {}) | if type == "object" then . else {} end)' "$(project_config)") || die "ledger publish: cannot read the publish markers"
    M=$(jq -r --argjson m "$MAP" '
      if .blocked_on != null then (if (.blocked_on.kind | startswith("human:")) then $m.human_block else $m.block end)
      else ({queued: null, intake: "plan", spec: "plan", plan: "plan", "plan-review": "plan", tasks: "plan",
             implement: "build", verify: "build", quality: "build", security: "build", pr: "pr", merged: "done", released: "done"}[.phase]) as $k
           | if $k == null then null else $m[$k] end end // empty' <<<"$E")
    PREV=$(jq -r 'if has("published") then (.published.state // "-") else "unset" end' <<<"$E")
    if [ "$PREV" = "${M:--}" ]; then echo "$ID publish: unchanged (${M:-no marker})"; exit 0; fi
    case "$(jq -r .source.kind <<<"$E")" in
      tasks-repo)
        SB="$HERE/status-board.sh"; T=$(mktemp) || die "ledger publish: mktemp failed"
        bash "$SB" --item-raw "$ID" > "$T" || { rm -f "$T"; die "ledger publish $ID: the board has no item $ID"; }
        STORED=$(jq -r '.source.body_sha256 // empty' <<<"$E"); NOW=$(sha256sum < "$T" | cut -c1-64)
        if [ -n "$STORED" ] && [ "$NOW" != "$STORED" ]; then rm -f "$T"; die "ledger publish $ID: item text changed since claim (board sha256 ${NOW:0:12}…, ledger ${STORED:0:12}…) — a person re-reads it and re-hashes with ledger.sh record $ID --body-file <raw>; the board is untouched"; fi
        PREVM=$(jq -r '.published.state // empty' <<<"$E")
        MARKED=$(bash "$SB" --mark "$ID" "${M:--}" ${PREVM:+--was "$PREVM"}) || { rm -f "$T"; exit 1; }
        bash "$SB" --item-raw "$ID" > "$T" || { rm -f "$T"; die "ledger publish $ID: cannot re-read the item after marking"; }
        "$0" record "$ID" --body-file "$T" >/dev/null || { rm -f "$T"; exit 1; }
        rm -f "$T"; WHERE="the board"; case "$MARKED" in *"not marked"*) WHERE="not marked — the item is in DONE" ;; esac ;;
      github-project)
        URL=$(jq -r '.source.url // empty' <<<"$E")
        [ -n "$URL" ] || die "ledger publish $ID: a github-project entry needs source.url (ledger.sh init … --url <issue-url>)"
        command -v gh >/dev/null 2>&1 || die "ledger publish $ID: gh not found — install GitHub CLI (https://cli.github.com)"
        GHERR=$(gh issue comment "$URL" --body "ledger: $ID phase $(jq -r .phase <<<"$E") blocked_on $(jq -r '.blocked_on.kind // "none"' <<<"$E")" 2>&1 >/dev/null) \
          || die "ledger publish $ID: gh issue comment $URL failed: $(tail -1 <<<"$GHERR")"
        WHERE="$URL" ;;
      *) die "ledger publish $ID: unknown source kind '$(jq -r .source.kind <<<"$E")'" ;;
    esac
    E=$(entry "$ID") || exit 1
    jq --arg s "$M" '.published = {state: (if $s == "" then null else $s end), at: (now | todate)}' <<<"$E" | write_entry "$ID" || exit 1
    echo "$ID published ${M:-no marker} ($WHERE)" ;;

  # escalate: report 17's single message type. Lists human:* blocks older than the threshold that were
  # not yet escalated for THIS block, one `<session>\t<pointer>` line each; the command sends the
  # pointer and then records it. Empty output at exit 0 is the answer "nothing to escalate".
  escalate)
    H=$(cfgp '.orchestrate.escalate_after_hours // empty')
    [ -n "$H" ] || die "ledger escalate: escalation is off — set orchestrate.escalate_after_hours in .claude/project-status.json"
    [[ "$H" =~ ^[0-9]+$ ]] || die "ledger escalate: orchestrate.escalate_after_hours must be a whole number of hours (got '$H')"
    if [ "${1:-}" = --record ]; then
      ID="${2:-}"; [ -n "$ID" ] || usage; E=$(entry "$ID") || exit 1
      [ -n "$(jq -r '.blocked_on.since // empty' <<<"$E")" ] || die "ledger escalate --record $ID: not blocked — nothing to record"
      jq '.escalated = {since: .blocked_on.since, at: (now | todate)}' <<<"$E" | write_entry "$ID" || exit 1
      echo "$ID escalation recorded"; exit 0
    fi
    [ $# -eq 0 ] || usage
    shopt -s nullglob; FILES=("$DIR"/*.json); shopt -u nullglob
    [ "${#FILES[@]}" -gt 0 ] || exit 0
    CFG_PANES=$(cfgp -c '(.orchestrate.panes // {}) | if type == "object" then . else {} end'); [ -n "$CFG_PANES" ] || CFG_PANES='{}'
    K2P=$(jq -nc --argjson d "$PANES_DEFAULT" --argjson c "$CFG_PANES" '[$d, $c] | map(to_entries[]) | map(.key as $p | .value[] | select(type == "string") | {key: ., value: $p}) | from_entries' 2>/dev/null)
    [ -n "$K2P" ] || K2P=$(jq -nc --argjson d "$PANES_DEFAULT" '$d | to_entries | map(.key as $p | .value[] | {key: ., value: $p}) | from_entries')
    PS=$(cfgp -c '(.orchestrate.pane_sessions // {}) | if type == "object" then . else {} end'); [ -n "$PS" ] || PS='{}'
    REPO=$(cfgp '.name // empty')
    if [ -z "$REPO" ] && is_external; then REPO=$(basename "$(jq -r .board_top <<<"$BCTX")"); fi   # one board, one set of sessions
    [ -n "$REPO" ] || REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
    jq -rs --argjson k "$K2P" --argjson ps "$PS" --arg repo "$REPO" --argjson h "$H" "
      map(select(.blocked_on != null and (.blocked_on.kind | startswith(\"human:\"))
                 and ((((.blocked_on.since // \"\") | try fromdate catch null) as \$t | \$t != null and ((now - \$t) / 3600) >= \$h))
                 and ((.escalated.since // \"\") != .blocked_on.since))) | $ID_SORT | .[]
      | (\$k[.blocked_on.kind] // \"orchestrator\") as \$p
      | (if .blocked_on.kind == \"human:merge\" then (.pr.url // \"-\")
         elif .blocked_on.kind == \"human:clarify\" or .blocked_on.kind == \"human:plan-review\" then (.blocked_on.question_path // .spec_dir // \"-\")
         elif .blocked_on.kind == \"human:intake\" then (.source.ref // \"-\")
         else \"-\" end) as \$path
      | (\"ledger \(.id) blocked_on \(.blocked_on.kind) \(\$path)\") as \$msg
      | \"\(\$ps[\$p] | if type == \"string\" then . else null end // \"\(\$repo)-\(\$p)\")\t\(if (\$msg | length) > 200 then \$msg[0:190] + \" …(cut)\" else \$msg end)\"" "${FILES[@]}" \
      || die "ledger escalate: an entry in $DIR is not valid JSON — repair or remove it" ;;

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
    # --stage (feature stage-roles FR-001): plan picks what has no spec yet (queued, or intake after a failed
    # or unblocked plan run); build picks queued (no plan stage), tasks (planned) or implement (a retry);
    # deploy picks a pr entry with a PR — even while blocked on human:merge, since that wait is what the
    # babysitter babysits — unblocked first, then the one babysat least recently, so a PR parked at the
    # gate never monopolises the stage.
    STAGE=build; while [ $# -gt 0 ]; do case "$1" in --stage) STAGE="${2:-}"; shift ;; *) usage ;; esac; shift; done
    case "$STAGE" in
      plan)   SEL='.owner == null and .blocked_on == null and (.phase == "queued" or .phase == "intake")'; ORDER="$ID_SORT" ;;
      build)  SEL='.owner == null and .blocked_on == null and (.phase == "queued" or .phase == "tasks" or .phase == "implement")'; ORDER="$ID_SORT" ;;
      deploy) SEL='.owner == null and .phase == "pr" and ((.pr.url // "") != "") and (.blocked_on == null or .blocked_on.kind == "human:merge")'
              ORDER='sort_by([(if .blocked_on == null then 0 else 1 end), (([.runs[]? | select(.role == "deploy") | .at] | max) // ""), (.id | (capture("^(?<p>.*?)(?<n>[0-9]+)$") // {p: ., n: "0"}) | [.p, (.n | tonumber)])])' ;;
      *) usage ;;
    esac
    shopt -s nullglob; FILES=("$DIR"/*.json); shopt -u nullglob
    [ "${#FILES[@]}" -gt 0 ] || die "ledger next: no entries in $DIR (run: ledger.sh init <id> …)"
    if is_external; then next_external; exit $?; fi
    N=$(jq -rs "map(select($SEL)) | $ORDER | .[0].id // empty" "${FILES[@]}") \
      || die "ledger next: an entry in $DIR is not valid JSON — repair or remove it"
    [ -n "$N" ] || die "ledger next: no dispatchable entry for stage $STAGE in $DIR (plan: queued|intake; build: queued|tasks|implement, unowned, unblocked; deploy: pr with a PR)"
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
