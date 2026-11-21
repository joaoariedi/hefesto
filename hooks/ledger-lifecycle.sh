#!/bin/bash
# ledger-lifecycle.sh — an item's lifecycle past the happy path (lanes-parity, 9.1): the terminal phases
# (drop / fold --into / supersede --by), the PR list `.prs[]` (entry_prs, reopen), `deployed`, the owner release on
# done phases and the `.events` append. SOURCED by ledger.sh behind `[ -f ] || die`; never run on its own. Uses
# ledger.sh's globals and helpers (DIR, ID, E, die, entry, write_entry).
#
# ledger.sh is over the file limit, so the logic lives here and ledger.sh keeps only dispatch and call-site lines.

# --- Done phases and the owner release (FR-009, FR-010, FR-002; plan Sketch 4) -------------------------------------
# An owner on a done phase is stale: it blocks no claim and no `next` (#139.4 — a launched owner never released on a
# merged entry held its repository's one worker slot forever). The terminal phases are listed before they exist so
# every reader filters them from the day they do.
DONE_PHASES='["merged","released","dropped","folded","superseded"]'
# A jq def for the programs that count owners: prepend it ("$JQ_LIVE_OWNER …"); `live_owner` is false on a stale owner.
# shellcheck disable=SC2034  # used by ledger.sh, which sources this part
JQ_LIVE_OWNER="def live_owner: .owner != null and ((.phase // \"\") as \$p | $DONE_PHASES | any(. == \$p) | not);"
# list --active: each owner gains a computed `.owner.stale` (shown, never written). Needs JQ_LIVE_OWNER and list's $a.
# shellcheck disable=SC2034,SC2016  # used by ledger.sh; a jq program, single-quoted on purpose
JQ_LIST_STALE='if $a == 1 then map(if .owner != null then .owner.stale = (live_owner | not) else . end) else . end'

is_done_phase() { jq -e --arg p "$1" "$DONE_PHASES | any(. == \$p)" <<<'null' >/dev/null; }   # is_done_phase <phase>

# claim_refuse_done <id> <entry JSON>: a done or terminal entry is never claimed (note 5) — no stage has work there.
claim_refuse_done() {
  local ph; ph=$(jq -r '.phase // empty' <<<"$2")
  if is_done_phase "$ph" || [ "$(jq -r '.terminal != null' <<<"$2")" = true ]; then
    die "ledger claim $1: the entry is $ph — a done entry is never claimed (reopen it first if the work is not done)"
  fi
}

# owner_release_on <phase>: stdin entry → stdout. Reaching a done phase releases a LAUNCHED owner, recorded as a
# non-run release (exit 125, as the lease reaper's, note 12) plus an owner-released event. An interactive owner stays:
# its lane's `session-launch.sh --finish` checks it still holds the entry (:441-443) after the lane's own merge.
owner_release_on() {
  is_done_phase "$1" || { cat; return; }
  jq --arg p "$1" 'if .owner == null or .owner.mode == "interactive" then . else
    .runs = ((.runs // []) + [{role: .owner.role, session_name: .owner.session_name, exit: 125, usd: 0, note: "released-on-\($p)", at: (now | todate)}])
    | .events = ((.events // []) + [{kind: "owner-released", at: (now | todate), by: "ledger", note: $p}]) | .owner = null end'
}
# lease_drop_unowned <id>: the caller removes a released owner's lease, as `run` does.
lease_drop_unowned() { [ "$(jq -r '.owner == null' "$DIR/$1.json" 2>/dev/null)" = true ] && rm -f "$DIR/$1.lease"; return 0; }

# --- Terminal phases: drop / fold --into / supersede --by (FR-001, FR-002, FR-003; plan Sketch 1) -------------------
# Outside PHASES on purpose: `advance` can neither reach nor leave them, only these verbs do. Person-only through
# is_person_sub (lane-guard and caller_gate) and the ask rules setup writes — the dialog is the person's signature.
# shellcheck disable=SC2034  # read by ledger.sh's metrics
TERMINAL_PHASES='["dropped","folded","superseded"]'
# refuse_closed <verb> <id> <entry JSON>: a dropped/folded/superseded entry takes no new PR and no new block — drop
# cleared both, and metrics would count a block put back (code review 2026-10-27).
refuse_closed() { ! is_terminal_entry "$3" || die "ledger $1 $2: the entry is $(jq -r .phase <<<"$3") — a closed item takes no new $1"; }
is_terminal_entry() { jq -e "(.phase // \"\") as \$p | .terminal != null or ($TERMINAL_PHASES | index([\$p]) != null)" <<<"$1" >/dev/null; }   # <entry JSON>
terminal_phase() { case "$1" in drop) echo dropped ;; fold) echo folded ;; supersede) echo superseded ;; esac; }

# reason_ok <verb> <id> <file>: the reason is a file that exists, is not empty and is at most 8 KB (action stop's rule).
reason_ok() {
  [ -n "$3" ] || die "ledger $1 $2: pass the reason as a file (--reason-file <f>, written with the Write tool in your session scratchpad)"
  [ -f "$3" ] || die "ledger $1 $2: the reason file $3 does not exist"
  [ -s "$3" ] || die "ledger $1 $2: the reason file $3 is empty — say why the item ends here"
  [ "$(wc -c < "$3" | tr -d ' ')" -le 8192 ] || die "ledger $1 $2: the reason file $3 is over 8 KB — keep it to the reason"
}

# terminal_target <verb> <id> <other>: fold/supersede need another entry that exists and is not terminal (FR-003).
terminal_target() {
  [ "$3" != "$2" ] || die "ledger $1 $2: cannot $1 an entry into itself"
  local o; o=$(entry "$3") || exit 1
  [ "$(jq -r '.item_kind // empty' <<<"$o")" != op ] || die "ledger $1 $2: $3 is an op — an item is never $(terminal_phase "$1") into an op (code review 2026-10-27)"
  is_terminal_entry "$o" && die "ledger $1 $2: $3 is itself $(jq -r .phase <<<"$o") — $1 into an entry that is still open"
  return 0
}

# terminal_cmd <drop|fold|supersede> <id> [--into|--by <id2>] --reason-file <f>
terminal_cmd() {
  local verb="$1" id="${2:-}" flag="" other="" rfile="" e ph by
  case "$verb" in fold) flag=--into ;; supersede) flag=--by ;; esac
  [ -n "$id" ] || usage; shift 2
  while [ $# -gt 0 ]; do case "$1" in --reason-file) rfile="${2:-}"; shift ;;
    --into|--by) [ "$1" = "$flag" ] || die "ledger $verb $id: unexpected $1 (${flag:-drop takes no target}${flag:+ names the target})"; other="${2:-}"; shift ;;
    *) die "ledger $verb $id: unexpected '$1'" ;; esac; shift; done
  e=$(entry "$id") || exit 1; ph=$(jq -r '.phase // ""' <<<"$e")
  # An op has its own end, which refuses while an action is approved or taken (ledger-actions.sh op_end); ending it
  # here would step around that guard and strand a taken action (quality gate 2026-10-27).
  [ "$(jq -r '.item_kind // empty' <<<"$e")" != op ] || die "ledger $verb $id: $id is an op — it ends with ledger.sh op close $id --outcome-file <f> or op drop $id --reason-file <f>"
  { [ "$ph" = released ] || is_terminal_entry "$e"; } && die "ledger $verb $id: the entry is already $ph — a $ph entry is never $(terminal_phase "$verb")"
  if [ -n "$flag" ]; then [ -n "$other" ] || die "ledger $verb $id: $flag <id> names the entry it goes to"; terminal_target "$verb" "$id" "$other"; fi
  reason_ok "$verb" "$id" "$rfile"
  by="${USER:-$(id -un 2>/dev/null)}"; ph=$(terminal_phase "$verb")
  jq --arg p "$ph" --arg k "${flag#--}" --arg o "$other" --arg h "$(hef_sha256 < "$rfile")" --arg by "${by:-person}" '
    .phase = $p | .blocked_on = null
    | .terminal = ({kind: $p, reason_sha256: $h, by_person: $by, at: (now | todate)} + (if $k == "" then {} else {($k): $o} end))
    | .events = ((.events // []) + [{kind: "terminal", at: (now | todate), by: $by, note: $p}])' <<<"$e" \
    | owner_release_on "$ph" | write_entry "$id" || exit 1
  lease_drop_unowned "$id"; echo "$id $ph"
}

# --- Several PRs on one entry: .prs[] (FR-004, FR-006; plan Sketch 2, notes 2 and 23) ------------------------------
# `.prs[]` is the list and `.pr` stays the current PR (always prs[-1]), so 9.0's readers of `.pr.*` are untouched. A
# 9.0 entry (a single `.pr`, no `.prs`) reads as a one-element list (SC-007).
ENTRY_PRS='(.prs // ([.pr] | map(select(. != null))))'
entry_prs() { jq -c "$ENTRY_PRS" <<<"$1"; }   # entry_prs <entry JSON> → the PR list

# pr_append <url>: stdin entry → stdout (record --pr). A URL already listed is the same PR. Otherwise the current PR
# is REPLACED while unmerged (a split, a re-created PR) and APPENDED after when merged — a merged PR is never replaced.
# "Merged" is a stamp, or the 9.0 fields (note 2): a recorded `.pr.merge_sha`, or a phase at or past merged.
pr_append() {
  jq --arg u "$1" "$ENTRY_PRS as \$l | ((\$u | capture(\"/(?<n>[0-9]+)\$\").n | tonumber)? // null) as \$n
    | ((\$l[-1] // {}) as \$c | \$c.merged != null or \$c.merge_sha != null or (.pr.merge_sha // null) != null
       or ((.phase // \"\") as \$ph | [\"merged\", \"released\"] | index(\$ph) != null)) as \$m
    | (if (\$l | map(.url) | index(\$u)) != null then \$l elif \$m or (\$l | length) == 0 then \$l + [{url: \$u, number: \$n}]
       else \$l[0:-1] + [{url: \$u, number: \$n}] end) as \$l2
    | .prs = \$l2 | .pr = \$l2[-1]"
}

# pr_stamp_merged <via> [merge sha] [unverified true|false]: stdin entry → stdout. Stamps the current PR merged where
# the gate clears (unblock human:merge, a merge action's done). It never moves the phase (note 23): FR-006's check and
# the owner release stay in `advance`. `.pr` is the base, so a merge_sha written just before is kept in the stamp.
pr_stamp_merged() {
  jq --arg via "$1" --arg sha "${2:-}" --argjson unv "${3:-false}" "$ENTRY_PRS as \$l | if .pr == null then . else
    (\$l[0:-1] + [.pr + {merged: {via: \$via, merge_sha: (if \$sha == \"\" then null else \$sha end), unverified: \$unv, at: (now | todate)}}]) as \$n
    | .prs = \$n | .pr = \$n[-1] end"
}

# prs_unstamped <entry JSON>: prints the first earlier PR (prs[0:-1]) with no merged stamp; empty when every one has one.
# advance merged (FR-006) needs none, plus merge_evidence for the current PR.
prs_unstamped() { jq -r "$ENTRY_PRS | .[0:-1] | map(select(.merged == null)) | .[0].url // empty" <<<"$1"; }

# --- reopen: a merged item takes a follow-up PR (FR-005; plan Sketch 2, notes 1 and 18) ---------------------------
# The only way back from merged — a person's decision, taken in the orchestrator (person-only through is_person_sub
# and setup's ask rule). It stamps the closing PR from FRESH evidence first: earlier PRs carry no branch of their
# own (`record --branch` overwrites the entry's), so a stamp is the only proof that survives the reopen; it also
# covers a 9.0 entry that reached merged by the branch path with no stamp and no merge_sha. The recorded
# `.pr.merge_sha` is passed (note 18): a squash merge whose branch GitHub deleted is evidenced by it alone.
# Landing at implement, unowned, means the 9.0 build path runs unchanged; `record --pr` then appends.
reopen_cmd() {   # reopen <id> --reason-file <f>
  local id="${1:-}" rfile="" e ph via sha="" ver="" by
  [ -n "$id" ] || usage; shift
  while [ $# -gt 0 ]; do case "$1" in --reason-file) rfile="${2:-}"; shift ;; *) die "ledger reopen $id: unexpected '$1'" ;; esac; shift; done
  e=$(entry "$id") || exit 1; ph=$(jq -r '.phase // ""' <<<"$e")
  { [ "$ph" = merged ] && ! is_terminal_entry "$e"; } \
    || die "ledger reopen $id: only a merged item reopens (it is $ph) — a follow-up after released is a new item"
  reason_ok reopen "$id" "$rfile"
  # In a subshell: merge_evidence dies on a refusal, and its cd_entry_repo must not move this process.
  via=$(cd_entry_repo "$e" && { hef_fetch_origin >/dev/null 2>&1; merge_evidence "$e" "$(jq -r '.pr.merge_sha // empty' <<<"$e")" recorded; }) \
    || die "ledger reopen $id: no merge evidence for the current PR (see above) — it cannot be closed out, so it is not reopened"
  case "$via" in "commit "*) read -r _ sha ver _ <<<"$via" ;; esac
  by="${USER:-$(id -un 2>/dev/null)}"
  # The reason is the follow-up's only description: the board item and the spec still describe the merged PR, and a
  # directive reaches the build LANE, never the worker it launches (live check 2026-10-29: the worker re-checked the
  # merged PR and stopped). So it is copied beside the entry, hashed, and the implement launch hands it in as data.
  local n dst; n=$(( $(jq '.followups // [] | length' <<<"$e") + 1 )); dst="$DIR/$id.followup-$n.md"
  rm -f -- "$dst"; cp "$rfile" "$dst" || die "ledger reopen $id: cannot copy the reason to $dst"   # never through a link
  pr_stamp_merged "${via%% *}" "$sha" "$([ "$ver" = unverified ] && echo true || echo false)" <<<"$e" \
    | jq --arg by "${by:-person}" --arg h "$(hef_sha256 < "$dst")" '.phase = "implement" | .owner = null | .attempts = 0 | .blocked_on = null
      | .followups = ((.followups // []) + [{sha256: $h, by: $by, at: (now | todate)}])
      | .events = ((.events // []) + [{kind: "reopen", at: (now | todate), by: $by, note: "for a follow-up PR", reason_sha256: $h}])' \
    | write_entry "$id" || exit 1
  rm -f "$DIR/$id.lease"; echo "$id merged → implement (reopened; the closing PR is stamped ${via%% *})"
}

# handoff_refuse_merged <id> <entry JSON>: a hand-run follow-up on a merged item goes through reopen first (FR-005).
handoff_refuse_merged() {
  [ "$(jq -r '.phase // ""' <<<"$2")" != merged ] \
    || die "ledger handoff $1: merged — ask the orchestrator to reopen it first (ledger.sh reopen $1 --reason-file <f>)"
}

# --- forward: a PR behind or conflicting with its base goes back to the build stage (merge-forward, HEF-31) --------
# The second backward move beside reopen, and a mechanical one: git decides, not the caller (the `deployed` precedent)
# — pr-watch.sh state is read again here and only a live conflict/behind moves the entry, so no caller can pull a
# CLEAN PR off a person's human:merge gate. Every refusal comes before the first write (constitution 5). The two
# outcomes that are not a move — no usable worktree, the cap — are each one written conflict block whose reason
# `ledger.sh questions` serves (a question file, as `block` has no --reason), exit 0, so a routing caller never loops.
FORWARD_CAP=3
forward_cmd() {   # forward <id> --verdict conflict|behind [--past-cap --by <name>]
  local id="${1:-}" v="" past=0 by="" e st hb wt
  [ -n "$id" ] || usage; shift
  while [ $# -gt 0 ]; do case "$1" in --verdict) v="${2:-}"; shift ;; --past-cap) past=1 ;; --by) by="${2:-}"; shift ;;
    *) die "ledger forward $id: unexpected '$1'" ;; esac; shift; done
  case "$v" in conflict|behind) ;; *) die "ledger forward $id: --verdict must be conflict or behind (got '${v:-<none>}')" ;; esac
  [ -z "${HEFESTO_WORKER:-}" ] || [ "$HEFESTO_WORKER" = 0 ] \
    || die "ledger forward $id: never from inside a launched worker — the launcher forwards from the worker's structured output"
  forward_by_ok "$id" "$past" "$by"
  e=$(entry "$id") || exit 1; forward_guards "$id" "$e"
  st=$(forward_live_state "$id" "$e" "$v") || exit 1
  hb=$(jq -r .headRefName <<<"$st")
  # the implement launch's own path (session-launch.sh: <top>/.claude/worktrees/<id>), never .worktree, which a
  # handoff may record elsewhere — a launch there would make a fresh branch with `claude -w` (FR-005a)
  wt="$(entry_repo_top "$e")/.claude/worktrees/$id" || exit 1
  forward_worktree_ok "$wt" "$hb" || { forward_block_reason "$id" "$e" "no worktree on $hb to merge forward in: '$wt' — restore it (git worktree add $wt $hb), then merge forward again"; return 0; }
  if [ "$past" = 0 ] && forward_cap_reached "$e"; then
    forward_block_reason "$id" "$e" "merge forward cap $FORWARD_CAP reached for $(jq -r .pr.url <<<"$e") — a person decides (forward $id --verdict <v> --past-cap --by <name>)"; return 0
  fi
  forward_write "$id" "$e" "$st" "$by"
}

forward_by_ok() { # $1 id, $2 past-cap 0|1, $3 by — --past-cap is a person's decision and names them (FR-005)
  if [ "$2" = 0 ]; then [ -z "$3" ] || die "ledger forward $1: --by goes with --past-cap only (a routine forward records no person)"; return 0; fi
  [[ "$3" =~ ^[A-Za-z0-9]([A-Za-z0-9._@\ -]{0,62}[A-Za-z0-9._@-])?$ ]] \
    || die "ledger forward $1: --past-cap is a person's decision and needs --by <your name> (got '${3:-<none>}')"
}

forward_guards() { # $1 id, $2 entry JSON — the refusals the entry alone decides (FR-003); nothing is written
  local ph bk
  ! is_terminal_entry "$2" || die "ledger forward $1: the entry is $(jq -r .phase <<<"$2") — a closed item is never merged forward"
  ph=$(jq -r '.phase // ""' <<<"$2")
  [ "$ph" = pr ] || die "ledger forward $1: phase is '$ph', not pr — only an entry waiting on its PR is merged forward"
  [ -n "$(jq -r '.pr.url // empty' <<<"$2")" ] || die "ledger forward $1: no PR URL is recorded — nothing to merge forward"
  # D12: what a merge forward may clear — no block, the merge gate (re-earned through the verifier) or conflict
  bk=$(jq -r '.blocked_on.kind // empty' <<<"$2")
  case "$bk" in ""|human:merge|conflict) ;;
    *) die "ledger forward $1: blocked on $bk — a person or another gate clears that (a merge forward clears only none, human:merge or conflict)" ;; esac
  # a lane's interactive claim has no pid and is allowed: the lane babysit forwards while it holds the entry
  [ -z "$(jq -r '.owner.pid // empty' <<<"$2")" ] \
    || die "ledger forward $1: held by a live headless run ($(jq -r '.owner.session_name // "?"' <<<"$2"), pid $(jq -r .owner.pid <<<"$2")) — its launcher forwards from the run's output"
  forward_merge_action_refuse "$1"
}

forward_merge_action_refuse() { # $1 id — a merge action approved or taken for the entry is a person's open decision
  local id="$1" open
  set -- "$DIR"/actions/*.json; [ -f "${1:-}" ] || return 0
  open=$(jq -rs --arg id "$id" 'map(select(.entry == $id and .scope.kind == "merge" and (.status == "approved" or .status == "taken"))
    | "\(.aid) (\(.status))") | join(", ")' "$@") || die "ledger forward $id: an action in $DIR/actions is not valid JSON — repair or remove it"
  [ -z "$open" ] || die "ledger forward $id: the merge action $open is open on it — it is stopped first (ledger.sh action stop …)"
}

forward_live_state() { # $1 id, $2 entry JSON, $3 the caller's verdict → the pr-watch.sh state JSON (live conflict|behind)
  local url st live
  url=$(jq -r .pr.url <<<"$2")
  # In a subshell: cd_entry_repo must not move this process (an external board's entry is read in ITS repo)
  st=$(cd_entry_repo "$2" && bash "$HERE/pr-watch.sh" state "$url" 2>&1) \
    || die "ledger forward $1: pr-watch.sh state $url failed — nothing changed: $(tail -1 <<<"$st")"
  live=$(jq -r '.verdict // empty' <<<"$st" 2>/dev/null)
  # either live verdict is accepted and the live one recorded: a DIRTY↔BEHIND flip between two reads is no refusal (D3)
  case "$live" in conflict|behind) ;;
    *) die "ledger forward $1: $url is '${live:-unreadable}' now, not conflict or behind (the caller saw '$3') — nothing changed" ;; esac
  forward_refs_ok "$1" "$st"
  printf '%s\n' "$st"
}

forward_ref_ok() { # $1 a branch name → 0 when git takes it as a branch name unchanged (no leading -, no @{-n})
  case "$1" in ""|-*) return 1 ;; esac
  [ "$(git check-ref-format --branch "$1" 2>/dev/null)" = "$1" ]
}
forward_refs_ok() { # $1 id, $2 state JSON — the names go into the brief and into the worker's git push (FR-003)
  local h b o
  h=$(jq -r '.headRefName // empty' <<<"$2"); b=$(jq -r '.baseRefName // empty' <<<"$2"); o=$(jq -r '.headRefOid // empty' <<<"$2")
  forward_ref_ok "$h" || die "ledger forward $1: the PR's head branch '$h' is not a valid branch name — nothing changed"
  forward_ref_ok "$b" || die "ledger forward $1: the PR's base branch '$b' is not a valid branch name — nothing changed"
  [[ "$o" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || die "ledger forward $1: the PR's head commit '$o' is not a full sha — nothing changed"
}

forward_worktree_ok() { # $1 the launch's worktree path, $2 the PR's head branch → 0 when a worktree is checked out on it there
  local top
  [ -d "$1" ] || return 1
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ "$(cd -P "$top" && pwd -P)" = "$(cd -P "$1" && pwd -P)" ] || return 1   # a plain folder in the main checkout is none
  [ "$(git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "$2" ]
}

forward_cap_reached() { # $1 entry JSON → 0 when FORWARD_CAP forwards already went to its current PR URL (FR-005)
  [ "$(jq --argjson c "$FORWARD_CAP" '.pr.url as $u | [(.forwards // [])[] | select(.pr_url == $u)] | length >= $c' <<<"$1")" = true ]
}

forward_block_reason() { # $1 id, $2 entry JSON, $3 reason → one conflict block whose question file holds the reason
  local q; q="$DIR/$1.question-$(date +%s).md"
  rm -f -- "$q"; printf 'Merge forward of %s did not move it: %s\n' "$1" "$3" > "$q" || die "ledger forward $1: cannot write $q"
  jq --arg q "$q" --arg r "$3" '.blocked_on = {kind: "conflict", since: (now | todate), question_path: $q}
    | .events = ((.events // []) + [{kind: "forward-blocked", at: (now | todate), by: "ledger", note: $r}])' <<<"$2" \
    | write_entry "$1" || exit 1
  echo "$1 blocked_on conflict ($3)"
}

forward_brief() { # $1 id, $2 n, $3 entry JSON, $4 state JSON → the fixed template (FR-004): generated, never a person's text
  jq -r --arg id "$1" --argjson n "$2" --argjson st "$4" '"# Merge forward #\($n) — \($id)

- Pull request: #\($st.number // "?") \(.pr.url)
- Head branch: \($st.headRefName) at \($st.headRefOid)
- Base branch: \($st.baseRefName)
- Verdict: \($st.verdict) (\(if $st.verdict == "behind" then "the base moved on and the branch must be brought up to date" else "the branch conflicts with its base" end))

Merge origin/\($st.baseRefName) into \($st.headRefName) in this worktree — never a rebase — and push the same branch."' <<<"$3"
}

forward_write() { # $1 id, $2 entry JSON, $3 state JSON, $4 by → the brief, its hash and the move in one rewrite (FR-002)
  local n dst h
  n=$(( $(jq '.forwards // [] | length' <<<"$2") + 1 )); dst="$DIR/$1.forward-$n.md"
  rm -f -- "$dst"; forward_brief "$1" "$n" "$2" "$3" > "$dst" || die "ledger forward $1: cannot write the brief $dst"   # never through a link
  h=$(hef_sha256 < "$dst")
  # an answer to an earlier question never steers a merge forward: every recorded answer is consumed here
  jq --argjson st "$3" --argjson n "$n" --arg h "$h" --arg by "$4" '(if $by == "" then null else $by end) as $b
    | .phase = "implement" | .owner = null | .attempts = 0 | .blocked_on = null
    | (if .answers then .answers |= map(.consumed = true) else . end)
    | .forwards = ((.forwards // []) + [{n: $n, pr_url: .pr.url, head_sha: $st.headRefOid, head_branch: $st.headRefName,
        base: $st.baseRefName, verdict: $st.verdict, sha256: $h, at: (now | todate), by: $b, consumed: false}])
    | .events = ((.events // []) + [{kind: "forward", at: (now | todate), verdict: $st.verdict, pr_url: .pr.url, head_sha: $st.headRefOid, by: $b}])' <<<"$2" \
    | write_entry "$1" || exit 1
  rm -f "$DIR/$1.lease"; echo "$1 pr → implement (merge forward #$n, $(jq -r .verdict <<<"$3"))"
}

# --- deployed: a release proven by its own commit (FR-007, FR-008; plan Sketch 3, note 17) -------------------------
# A cherry-picked release carries the item's change as a NEW commit, so the item's branch is never an ancestor of
# the environment branch. The proof is the deployed commit itself inside that environment (in_branch, 0/1/3/4).
# Allow-listed for every lane: git decides, not the caller. It refuses an open human:* block because with the final
# environment it performs an advance (note 17), and the human gate is never stepped over.
deployed_check() {   # deployed_check <id> <env> <sha> → the full sha; needs cwd in the entry's repo
  local bm full rc
  bm=$(branches_model) || exit 1
  jq -e --arg e "$2" '.environments | index($e) != null' <<<"$bm" >/dev/null \
    || die "ledger deployed $1: --env $2 is not in the branch model ($(jq -r '.environments | join(", ")' <<<"$bm"))"
  [[ "$3" =~ ^[0-9a-fA-F]{4,40}$ ]] && full=$(git rev-parse --verify -q "$3^{commit}" 2>/dev/null) \
    || die "ledger deployed $1: $3 is not a commit here (git fetch origin first if it was pushed elsewhere)"
  in_branch "$full" "$2" >/dev/null; rc=$?
  case "$rc" in 0) ;; 1) die "ledger deployed $1: commit $full is in neither $2 nor origin/$2 — it is not deployed there" ;;
    *) die "ledger deployed $1: the environment branch '$2' resolves nowhere (no $2, no origin/$2) — git fetch first" ;; esac
  echo "$full"
}

deployed_cmd() {   # deployed <id> --env <env> --commit <sha>
  local id="${1:-}" env="" sha="" e bk full fin ph by to=""
  [ -n "$id" ] || usage; shift
  while [ $# -gt 0 ]; do case "$1" in --env) env="${2:-}"; shift ;; --commit) sha="${2:-}"; shift ;;
    *) die "ledger deployed $id: unexpected '$1'" ;; esac; shift; done
  [ -n "$env" ] && [ -n "$sha" ] || die "ledger deployed $id: both --env <env> and --commit <sha> are required"
  e=$(entry "$id") || exit 1
  [ "$(jq -r '.item_kind // empty' <<<"$e")" != op ] || die "ledger deployed $id: $id is an op — an op has no branch to deploy (code review 2026-10-27)"
  bk=$(jq -r '.blocked_on.kind // empty' <<<"$e")
  [[ "$bk" != human:* ]] || die "ledger deployed $id: blocked on $bk — a person clears it first (ledger.sh unblock $id)"
  is_terminal_entry "$e" && die "ledger deployed $id: the entry is $(jq -r .phase <<<"$e") — a closed item is never deployed"
  cd_entry_repo "$e" || exit 1   # external-board: the entry's repo, its own model and branches
  hef_fetch_origin >/dev/null 2>&1   # no origin (a local repo) is fine: the local branches still answer
  full=$(deployed_check "$id" "$env" "$sha") || exit 1
  fin=$(branches_model | jq -r .final) || exit 1; ph=$(jq -r '.phase // ""' <<<"$e")
  [ "$env" = "$fin" ] && [ "$ph" = merged ] && to=released
  by="${USER:-$(id -un 2>/dev/null)}"
  # A re-recorded env keeps the commit it replaces, in full, on its event (US3 Edge).
  jq --arg e "$env" --arg c "$full" --arg by "${by:-person}" --arg to "$to" '(.deployments[$e].commit // null) as $old
    | .deployments = ((.deployments // {}) + {($e): {commit: $c, at: (now | todate), by: $by}})
    | .events = ((.events // []) + [{kind: "deployed", at: (now | todate), by: $by, note: "\($e) \($c[0:12])", replaces: $old}])
    | if $to == "" then . else .phase = $to end' <<<"$e" | owner_release_on "${to:-none}" | write_entry "$id" || exit 1
  lease_drop_unowned "$id"; echo "$id deployed to $env at ${full:0:12}${to:+ (merged → released)}"
}

# released_by_record <entry JSON> <final env>: 0 when the final env's recorded deployment is still inside it — then
# `advance released` needs no branch ancestry (FR-008: a cherry-picked release carries the change as a new commit).
# Needs cwd in the entry's repo (advance has run cd_entry_repo).
released_by_record() {
  local c; c=$(jq -r --arg e "$2" '.deployments[$e].commit // empty' <<<"$1"); [ -n "$c" ] || return 1
  in_branch "$c" "$2" >/dev/null
}

# where_deployed <entry JSON> <env>: prints "<env>: yes (deployed <sha12>)" when the env's recorded deployment is
# still inside it; non-zero otherwise (the caller falls back to the branch ancestry check).
where_deployed() {
  local c; c=$(jq -r --arg e "$2" '.deployments[$e].commit // empty' <<<"$1"); [ -n "$c" ] || return 1
  in_branch "$c" "$2" >/dev/null || return 1
  echo "$2: yes (deployed ${c:0:12})"
}
