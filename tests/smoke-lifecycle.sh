# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
#
# lanes-parity (9.1) smoke checks — the item lifecycle, recipes, branch models from the board.
#
# SOURCED by tests/smoke.sh (`. "$REPO/tests/smoke-lifecycle.sh"`), never run on its own: smoke.sh is over the
# 500-line limit, so every FR/NR test of this plan lives here, with its FR ids in comments.
#
# Section conventions (the same as smoke.sh's, research.md "Tests"):
#   * each section resets its own flag, `x_fail=0`; a check is `cond || { bad "…"; x_fail=1; }`; the section ends
#     with ONE summary, `[ "$x_fail" -eq 0 ] && ok "… (FR-…)"`. `ok`/`bad`/`head_` count into smoke.sh's PASS/FAIL.
#   * fixtures run in smoke.sh's throwaway HOME (the ledger lives under $HOME/.cache/hefesto) and find a repo's
#     ledger folder with smoke.sh's `sld`, which recomputes the key independently of board-lib.
#   * gh is never the real one: smoke.sh exports HEFESTO_GH_BIN at a missing path; a test that needs gh passes its
#     own named fake.
#
# PR A mutation pass (T015, SC-002), 2026-10-27: each mutant applied to a copy, this part run, restored. Every one
# went red, and the restored tree is 0 failed. A guard whose mutant stays green has no test — add one before a fix.
#   guard                         mutant                                                  went red
#   terminal person gate          is_person_sub loses drop|fold|supersede|reopen          caller_gate must refuse drop from a stage lane
#                                 caller_gate's is_person_sub test → false                (the same, and the entry left unchanged)
#                                 setup's ask-rule loop loses drop…"op drop"              setup must write an ask rule … (all six)
#   BUSY / next done filter       live_owner = .owner != null (both readers)              a stale owner … must not block claim HEF-3; .owner.stale
#                                 next_external's $busy: select(.owner != null)           next --stage build … must not count a merged entry's stale owner
#                                 claim BUSY: .owner != null for live_owner               a stale owner on a merged 9.0 entry must not block claim HEF-3
#   the claim refusal             claim_refuse_done → return 0                            claim must refuse a merged entry (FR-002)
#   replace-vs-append             pr_append always appends                                record --pr must REPLACE an unmerged current PR
#                                 pr_append never appends after merged                    record --pr after a merged stamp must APPEND; ledger-id PR 1
#   the reopen evidence           merge_evidence → echo branch                            ledger reopen HEF-6 … must be refused (FR-005)
#   deployed's in_branch          in_branch … rc=$? → rc=0                                deployed HEF-1 --env stg … must be refused
#   --configured rc 2             BCTX=$(board_ctx) || return 1                           an unresolvable board: branches --configured must exit 2
#   the loud EVAL_GH_BIN          not executable → echo gh; return 0                      a non-executable EVAL_GH_BIN=… must fail (FR-027), all three
#   board object validation       `[ -z "$bad" ] || die` → `true || die`                  an unknown key in repos.api must be refused (NR-005)
#
# PR B mutation pass (T027, SC-002), 2026-10-28: the same method, against parts 1–7, on a copy of the tree. 29 mutants,
# 29 red. The five marked * stayed GREEN on the first run — no part tested them — and the T027 section at the end of
# this file is what sends them red now.
#   guard                         mutant                                                  went red
#   merge_ok                      scope_check's merge_ok call → `elif false`               a 9.0-shaped scope …; request --merge must draft …
#                                 the --match-head-commit requirement removed              (the same; a pinless merge in a scope is refused)
#                                 the --merge requirement → true                           (the same)
#                                 m_rest's last arm `else false` → `else true`             (the same)
#   after_step in try_grant       granted_cmds' after_step select → select(true)           a check must not be granted before step 1 is recorded
#   the excluded-command deny     `if [ -n "$EXCL_HIT" ] … ; then` → `if false; then`      a stopped recipe action must grant nothing more
#   the basename helper match     */ledger.sh|… → "$HERE"/ledger.sh|… (the hook's dir)     lane-guard (deployer): '<clone>/hooks/pr-watch.sh state 7' must be none
#                                 is_hefesto_helper → return 1                             (the same)
#   exclusivity at approve        merge_exclusive at approve → :                           approving a second merge action on acme/app must be refused
#                                 merge_exclusive at request → :                           a merge action on a repo an approved train holds …
#                                 merge_exclusive keyed on kind merge only (not train)     (the same)
#   the expects stop              recipe_expect_check's match → return 0                   a stopped recipe action must grant nothing more
#   the done evidence             `done) merge_done "$a"` → `done) true`                   a merge action's done must stamp the PR's merge commit …
#                                 `[ "$st" = MERGED ] && [ "$oid" != - ] ||` → `true ||`   done before the PR is merged: the refusal must name 'OPEN'
#                               * `|| die "… no merge evidence …"` → `|| true`             a refused done must leave HEF-1-A1 taken and HEF-1 unchanged
#   train base check              in_branch rc 1 → echo, not die                           done while ui's merge commit is only in main …
#                               * rc 2 (base resolves nowhere) → echo, not die             action done OP-1-A1 must be refused (base qa resolves nowhere)
#                                 the pinned-head compare → true                           done when a PR merged another head than the pinned one …
#                               * the MERGED compare → true                                … must name 'acme/api#5 is OPEN, not merged'
#   train fail-closed             gh_present → true                                        the no-gh refusal must name gh
#                               * `|| die "… gh cannot read …"` → `|| true`                … must name 'gh cannot read acme/api#5'
#                                 the git fetch in each repo → skipped                     done once both merge commits are in stg must pass
#   placement: new section        new_sections' `has … && continue` → `continue`           a new ## [1.1.0-rc1] section and --cut 1.2.0: want exit 1
#              kept sections      compare_kept skips every key                             a stacked-train auto-merge edits ## [1.0.0]: want exit 1
#              link refs          the `/^\[[^]]+\]: / { next }` line removed               (new section): output must name '## [1.2.0]'
#              exit 2             cannot() exits 0                                         a base with no CHANGELOG.md: want exit 2, got 0
#                                 the base-has-no-CHANGELOG arm → return 0                 (the same)
#   placeholder refusal           recipe_validate's unknown-placeholder die → true          an edit to the recipe must not change the approved action
#                               * merge_checks_get's unknown-placeholder die → true         a merge check with {branch} must be refused

# Fail loudly when the part is run on its own, or after smoke.sh stopped providing what it relies on: a part that
# silently defines nothing would report "0 failed" for every test in it. Inside smoke.sh the refusal is a counted
# FAIL (a bare `return` would let the suite go on to "N passed, 0 failed"); on its own it exits non-zero.
lc_refuse() {
  if declare -F bad >/dev/null; then bad "tests/smoke-lifecycle.sh: $1"; else echo "tests/smoke-lifecycle.sh: $1" >&2; fi
}
if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || ! declare -F ok bad head_ sld >/dev/null; then
  lc_refuse "source it from tests/smoke.sh (needs REPO, SMOKE_HOME, ok, bad, head_, sld)"
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi
# The throwaway HOME is the only thing standing between these fixtures and the person's own ledger.
if [ "$HOME" != "$SMOKE_HOME" ]; then
  lc_refuse "HOME is '$HOME', not smoke.sh's throwaway '$SMOKE_HOME' — refusing to write a ledger"
  return 0
fi

LC_LG="$REPO/hooks/ledger.sh"

# --- Section helpers -----------------------------------------------------------------------------------------------
lc() { local r="$1"; shift; (cd "$r" && bash "$LC_LG" "$@"); }            # lc <repo> <ledger args…>
lc_git() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }      # lc_git <repo> <git args…>
lc_entry() { printf '%s/%s.json\n' "$(sld "$1")" "$2"; }                  # lc_entry <repo> <id> → its file
lc_put() { mkdir -p "$(sld "$1")" && cat > "$(lc_entry "$1" "$2")"; }    # lc_put <repo> <id> < json (a raw write)
lc_jq() { jq -e "$3" "$(lc_entry "$1" "$2")" >/dev/null 2>&1; }          # lc_jq <repo> <id> <predicate>

# --- 9.0-shaped ledger fixture (SC-007) ----------------------------------------------------------------------------
# lc_fixture_90 → prints a fresh repo path whose ledger is written in the 9.0 shape, by hand, so 9.1's own writers
# never touch it: a single `.pr` (no `.prs`), no `.deployments`, no `.events`, no `.terminal`. Frozen on purpose —
# a 9.1 test that needs a different entry builds its own, it does not edit these.
#   HEF-1  merged by the BRANCH path: `hef-1` is inside main through a merge commit, and no `.pr.merge_sha` is
#          recorded (ledger.sh:583-586 — a 9.0 entry that reached merged with no stamp and no sha).
#   HEF-2  merged with a STALE OWNER: a launched implement claim never released (#139.4). It has no lease file and
#          started long ago, so a `claim` (which reaps under its lock, ledger-lanes.sh:138) releases it; `next` and
#          `list` are read-only and still see it. A claim test that needs the owner alive touches <ledger>/HEF-2.lease.
#   HEF-3  queued, unowned: the work a build pass should still find past HEF-2's owner.
lc_entry_90() {   # lc_entry_90 <id> <phase> <branch|""> <pr number|""> <owner json|null> → a 9.0 entry on stdout
  jq -n --arg id "$1" --arg ph "$2" --arg br "$3" --arg n "$4" --argjson own "$5" '{
    id: $id, source: {kind: "tasks-repo", ref: "tasks/TODO.md#\($id)", url: null, body_sha256: null},
    item_kind: "feature", route: "light", phase: $ph, owner: $own, worktree: null,
    branch: (if $br == "" then null else $br end), spec_dir: null,
    pr: (if $n == "" then null else {url: "https://github.com/example/app/pull/\($n)", number: ($n | tonumber)} end),
    verdicts: [], blocked_on: null, budget: {usd_cap: null, usd_spent: 0}, runs: [], attempts: (if $n == "" then 0 else 1 end),
    created: "2026-10-20T00:00:00Z", updated: "2026-10-21T00:00:00Z" }'
}
lc_fixture_90() {
  local r b; r="$(cd "$(mktemp -d)" && pwd -P)"   # pwd -P: on macOS /var is a link to /private/var
  git -C "$r" init -q -b main . && lc_git "$r" commit -q --allow-empty -m init || return 1
  for b in hef-1 hef-2; do   # each branch merged into main through a merge commit, as GitHub's merge button does
    lc_git "$r" switch -q -c "$b" && lc_git "$r" commit -q --allow-empty -m "$b" && lc_git "$r" switch -q main \
      && lc_git "$r" merge -q --no-ff -m "Merge $b" "$b" || return 1
  done
  lc_entry_90 HEF-1 merged hef-1 1 null | lc_put "$r" HEF-1 || return 1
  lc_entry_90 HEF-2 merged hef-2 2 '{"session_name":"hef-build-HEF-2","role":"implement","started":"2026-10-21T00:00:00Z"}' \
    | lc_put "$r" HEF-2 || return 1
  lc_entry_90 HEF-3 queued "" "" null | lc_put "$r" HEF-3 || return 1
  printf '%s\n' "$r"
}

# --- Tier 1: the 9.0-shaped fixture reads unmodified (SC-007) -------------------------------------------------------
head_ "Lifecycle: 9.0 ledger fixture"
x_fail=0
lc_t="$(lc_fixture_90)" || { bad "lc_fixture_90 could not build the 9.0 fixture"; x_fail=1; }
lc_sum0="$(cat "$(sld "$lc_t")"/*.json 2>/dev/null | sha256sum)"
# The shape: one .pr each, none of 9.1's fields.
for lc_id in HEF-1 HEF-2 HEF-3; do
  lc_jq "$lc_t" "$lc_id" 'has("prs") or has("deployments") or has("events") or has("terminal") | not' \
    || { bad "9.0 fixture $lc_id must carry no prs/deployments/events/terminal"; x_fail=1; }
done
lc_jq "$lc_t" HEF-1 '.phase == "merged" and .owner == null and (.pr | type == "object" and .number == 1 and (.url | endswith("/pull/1")))
  and (.pr | has("merge_sha") | not) and .branch == "hef-1"' || { bad "9.0 fixture HEF-1 must be merged by branch, with a single .pr and no merge_sha"; x_fail=1; }
lc_jq "$lc_t" HEF-2 '.phase == "merged" and .owner.role == "implement" and (.owner | has("mode") | not) and .pr.number == 2' \
  || { bad "9.0 fixture HEF-2 must be merged with a launched (non-interactive) owner left on it"; x_fail=1; }
lc_jq "$lc_t" HEF-3 '.phase == "queued" and .owner == null and .pr == null' || { bad "9.0 fixture HEF-3 must be queued and unowned"; x_fail=1; }
# Today's ledger reads it: the branch path proves HEF-1's merge, list --active still sees HEF-2's owner.
[ "$(lc "$lc_t" where HEF-1 2>&1)" = "main: yes (main)" ] || { bad "ledger where HEF-1 must prove the branch-path merge — got: $(lc "$lc_t" where HEF-1 2>&1 | head -c 200)"; x_fail=1; }
[ "$(lc "$lc_t" list --active 2>/dev/null | jq -r 'map(.id) | join(",")')" = HEF-2 ] || { bad "ledger list --active must read the fixture and list HEF-2 (its stale owner)"; x_fail=1; }
lc "$lc_t" show HEF-1 >/dev/null 2>&1 || { bad "ledger show HEF-1 must read the 9.0 entry"; x_fail=1; }
[ "$(cat "$(sld "$lc_t")"/*.json 2>/dev/null | sha256sum)" = "$lc_sum0" ] || { bad "reading the 9.0 fixture must leave it byte-identical"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "a 9.0-shaped ledger (single .pr, branch-path merge, stale owner on merged) builds and reads unmodified (SC-007)"

# --- The two new sourced parts (FR-001, plan note 8) ---------------------------------------------------------------
# ledger.sh sources ledger-lifecycle.sh and ledger-recipes.sh behind `[ -f ] || die`: an install that lost one must
# stop every call naming the file — never run on with the part's functions silently undefined.
head_ "Lifecycle: the sourced parts die loudly when missing"
x_fail=0
lc_t="$(cd "$(mktemp -d)" && pwd -P)"; git -C "$lc_t" init -q -b main . >/dev/null 2>&1
lc_pd="$(mktemp -d)"
for lc_f in "$REPO"/hooks/*.sh; do ln -s "$lc_f" "$lc_pd/${lc_f##*/}"; done
for lc_p in ledger-lifecycle.sh ledger-recipes.sh; do
  [ -f "$REPO/hooks/$lc_p" ] || { bad "hooks/$lc_p must exist (FR-001)"; x_fail=1; }
  grep -qF "[ -f \"\$HERE/$lc_p\" ] || die" "$LC_LG" || { bad "ledger.sh must source $lc_p behind [ -f ] || die (FR-001)"; x_fail=1; }
done
(cd "$lc_t" && bash "$lc_pd/ledger.sh" list >/dev/null 2>&1) || { bad "with every part present, ledger.sh list must succeed (the control)"; x_fail=1; }
for lc_p in ledger-lifecycle.sh ledger-recipes.sh; do
  rm -f "$lc_pd/$lc_p"
  lc_o="$(cd "$lc_t" && bash "$lc_pd/ledger.sh" list 2>&1)" && { bad "ledger.sh must stop when $lc_p is missing (FR-001)"; x_fail=1; }
  grep -qF "$lc_pd/$lc_p not found" <<<"$lc_o" || { bad "the stop for a missing $lc_p must name the file — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
  ln -s "$REPO/hooks/$lc_p" "$lc_pd/$lc_p" 2>/dev/null
done
rm -rf -- "${lc_pd:?}" "${lc_t:?}"
[ "$x_fail" -eq 0 ] && ok "ledger.sh sources ledger-lifecycle.sh and ledger-recipes.sh behind [ -f ] || die; a missing part stops every call naming the file (FR-001)"

# --- One gh resolution: gh_bin (FR-027, NR-007, plan Sketch 10, notes 3 and 13) ------------------------------------
# HEFESTO_GH_BIN keeps its 9.0 meaning (a missing path = "gh absent", the merge gate's unverified path), then
# EVAL_GH_BIN (the eval seam: relative = against the workspace top captured when lane-lib.sh is sourced; set but not
# executable = a loud stop, never the real gh), then gh. Each helper resolves it once at entry: `GH=$(gh_bin) || exit 1`.
head_ "Lifecycle: gh_bin resolves HEFESTO_GH_BIN, then EVAL_GH_BIN, then gh"
x_fail=0
lc_t="$(cd "$(mktemp -d)" && pwd -P)"; git -C "$lc_t" init -q -b main . >/dev/null 2>&1; mkdir -p "$lc_t/bin" "$lc_t/sub"
printf '#!/bin/bash\necho "$*" >> "%s/gh.log"\necho fake\n' "$lc_t" > "$lc_t/bin/gh"; chmod +x "$lc_t/bin/gh"
: > "$lc_t/bin/noexec"
lc_gb() { # lc_gb <dir to source from> <env assignments…> → gh_bin's stdout, stderr on stderr, its rc (resolved after a cd away)
  local d="$1"; shift
  (cd "$d" && env -u HEFESTO_GH_BIN -u EVAL_GH_BIN -u HEFESTO_EVAL_ROOT "$@" bash -c '. "$1"; cd /; gh_bin' _ "$REPO/hooks/lane-lib.sh")
}
[ "$(lc_gb "$lc_t" HEFESTO_GH_BIN=/h/gh EVAL_GH_BIN="$lc_t/bin/gh" 2>&1)" = /h/gh ] || { bad "HEFESTO_GH_BIN must win over EVAL_GH_BIN (FR-027)"; x_fail=1; }
[ "$(lc_gb "$lc_t" HEFESTO_GH_BIN=/nonexistent/gh 2>&1)" = /nonexistent/gh ] || { bad "a HEFESTO_GH_BIN at a missing path must pass through unchanged (9.0: gh absent)"; x_fail=1; }
[ "$(lc_gb "$lc_t" EVAL_GH_BIN="$lc_t/bin/gh" 2>&1)" = "$lc_t/bin/gh" ] || { bad "an executable absolute EVAL_GH_BIN must be used when HEFESTO_GH_BIN is unset (FR-027)"; x_fail=1; }
[ "$(lc_gb "$lc_t" 2>&1)" = gh ] || { bad "with neither set gh_bin must answer gh"; x_fail=1; }
[ "$(lc_gb "$lc_t/sub" EVAL_GH_BIN=bin/gh 2>&1)" = "$lc_t/bin/gh" ] || { bad "a relative EVAL_GH_BIN must resolve against the workspace top captured at source time, not the later cwd — got: $(lc_gb "$lc_t/sub" EVAL_GH_BIN=bin/gh 2>&1 | head -c 200)"; x_fail=1; }
for lc_v in "$lc_t/bin/noexec" /nonexistent/eval-gh bin/noexec; do
  lc_o="$(lc_gb "$lc_t" EVAL_GH_BIN="$lc_v" 2>&1)" && { bad "a non-executable EVAL_GH_BIN=$lc_v must fail (FR-027)"; x_fail=1; }
  grep -qF "EVAL_GH_BIN=$lc_v" <<<"$lc_o" || { bad "the EVAL_GH_BIN failure must name the value $lc_v — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
done
# The loud failure reaches every helper — through gh_present it is never "absent" (note 3: resolved at entry).
lc_o="$(cd "$lc_t" && env -u HEFESTO_GH_BIN EVAL_GH_BIN=/nonexistent/eval-gh bash "$LC_LG" list 2>&1)" && { bad "ledger.sh must stop on a non-executable EVAL_GH_BIN, never read gh as absent (FR-027)"; x_fail=1; }
grep -qF 'EVAL_GH_BIN=/nonexistent/eval-gh' <<<"$lc_o" || { bad "ledger.sh's EVAL_GH_BIN stop must name it — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
for lc_h in pr-watch.sh status-board.sh; do
  lc_o="$(cd "$lc_t" && env -u HEFESTO_GH_BIN EVAL_GH_BIN=/nonexistent/eval-gh bash "$REPO/hooks/$lc_h" --check 2>&1)" && { bad "$lc_h must stop on a non-executable EVAL_GH_BIN (FR-027)"; x_fail=1; }
  grep -qF 'EVAL_GH_BIN=/nonexistent/eval-gh' <<<"$lc_o" || { bad "$lc_h's EVAL_GH_BIN stop must name it — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
done
# An executable EVAL_GH_BIN reaches the helper's gh calls (pr-watch --check runs gh auth status).
rm -f "$lc_t/gh.log"; (cd "$lc_t" && env -u HEFESTO_GH_BIN EVAL_GH_BIN=bin/gh bash "$REPO/hooks/pr-watch.sh" --check >/dev/null 2>&1)
grep -qF 'auth status' "$lc_t/gh.log" 2>/dev/null || { bad "pr-watch.sh must call the EVAL_GH_BIN fake (FR-027)"; x_fail=1; }
# Structural: one resolution per helper, no inline fallbacks left, no bare gh calls in status-board or publish.
for lc_h in ledger.sh ledger-actions.sh pr-watch.sh status-board.sh; do
  # the one allowed form is pr-watch/status-board's lane-lib-less fallback, taken only while EVAL_GH_BIN is unset
  grep -F 'HEFESTO_GH_BIN:-gh' "$REPO/hooks/$lc_h" | grep -vqF 'elif [ -z "${EVAL_GH_BIN:-}" ]; then GH=' && { bad "hooks/$lc_h still resolves gh inline (\${HEFESTO_GH_BIN:-gh}) — use gh_bin (FR-027)"; x_fail=1; }
done
for lc_h in ledger.sh pr-watch.sh status-board.sh; do
  grep -qE '(^|then )GH=\$\(gh_bin\) \|\| exit 1' "$REPO/hooks/$lc_h" || { bad "hooks/$lc_h must resolve GH=\$(gh_bin) || exit 1 at entry (note 3)"; x_fail=1; }
done
grep -nE '(\$\(|^[[:space:]]*|if |! |&& |\|\| )gh (auth|project|repo|api|issue|pr) ' "$REPO/hooks/status-board.sh" "$REPO/hooks/ledger.sh" >/dev/null \
  && { bad "status-board.sh/ledger.sh still call a bare gh (FR-027): $(grep -nE '(\$\(|^[[:space:]]*|if |! |&& |\|\| )gh (auth|project|repo|api|issue|pr) ' "$REPO/hooks/status-board.sh" "$REPO/hooks/ledger.sh" | head -3)"; x_fail=1; }
grep -qE 'command -v gh\b' "$REPO/hooks/status-board.sh" "$REPO/hooks/ledger.sh" && { bad "status-board.sh/ledger.sh still probe a bare gh with command -v (FR-027)"; x_fail=1; }
# NR-007 (note 13): gh_bin reads no file — no redirection, no reader, no settings path in its body.
lc_body="$(bash -c '. "$1"; declare -f gh_bin' _ "$REPO/hooks/lane-lib.sh" 2>/dev/null)"
[ -n "$lc_body" ] || { bad "lane-lib.sh must define gh_bin (FR-027)"; x_fail=1; }
grep -qE '<|\b(cat|jq|read|source|sed|awk|head|grep|mapfile)\b|settings|\.json|\.claude' <<<"$lc_body" && { bad "gh_bin must read no file (NR-007): $(head -c 300 <<<"$lc_body")"; x_fail=1; }
rm -rf -- "${lc_t:?}"
[ "$x_fail" -eq 0 ] && ok "gh_bin: HEFESTO_GH_BIN (9.0, missing = absent) > EVAL_GH_BIN (relative = workspace top at source time; non-executable = loud) > gh; every helper resolves it once at entry; it reads no file (FR-027 NR-007)"

# --- Stale owners and the automatic release (FR-009, FR-010, FR-002; plan Sketch 4, notes 5, 9, 12) ---------------
# An owner on a done phase (merged, released, dropped, folded, superseded) never blocks a claim or `next`'s
# external busy set; reaching a done phase releases a LAUNCHED owner (exit 125, a released-on-<phase> note, an
# owner-released event, its lease gone); an INTERACTIVE owner stays, because its lane's --finish checks it holds
# the entry (session-launch.sh:441-443); `claim` refuses a done entry outright.
head_ "Lifecycle: stale owners block nothing; a done phase releases a launched owner"
x_fail=0
lc_t="$(lc_fixture_90)" || { bad "lc_fixture_90 could not build the 9.0 fixture"; x_fail=1; }
# FR-009: HEF-2's owner is alive (a fresh lease, so the claim's reaper leaves it) — and still blocks nothing.
: > "$(sld "$lc_t")/HEF-2.lease"
lc_o="$(lc "$lc_t" claim HEF-3 --session hef-build-HEF-3 --role implement 2>&1)" \
  || { bad "a stale owner on a merged 9.0 entry must not block claim HEF-3 (FR-009) — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
lc_jq "$lc_t" HEF-2 '.owner.session_name == "hef-build-HEF-2"' || { bad "the control: HEF-2's owner must still be on record (the filter, not the reaper, let the claim through)"; x_fail=1; }
# FR-002 (note 5): a done entry is refused outright, naming its phase.
lc_o="$(lc "$lc_t" claim HEF-1 --session s1 --role deploy 2>&1)" && { bad "claim must refuse a merged entry (FR-002)"; x_fail=1; }
grep -qF 'HEF-1' <<<"$lc_o" && grep -qF 'merged' <<<"$lc_o" || { bad "the done-entry refusal must name the entry and its phase — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
lc_jq "$lc_t" HEF-1 '.owner == null' || { bad "a refused claim must write no owner"; x_fail=1; }
# list --active marks the owner: stale on the done phase, live on the active one (computed, never written).
lc_o="$(lc "$lc_t" list --active 2>/dev/null)"
jq -e 'map({(.id): .owner.stale}) | add == {"HEF-2": true, "HEF-3": false}' <<<"$lc_o" >/dev/null 2>&1 \
  || { bad "list --active must carry .owner.stale (true on merged HEF-2, false on HEF-3) — got: $(jq -c 'map({id, owner})' <<<"$lc_o" 2>&1 | head -c 300)"; x_fail=1; }
lc_jq "$lc_t" HEF-2 '.owner | has("stale") | not' || { bad ".owner.stale must be computed by list, never written to the entry"; x_fail=1; }
# FR-010 (note 12): advance into merged releases a launched owner, with exit 125, a run note and an event.
lc_entry_90 HEF-4 pr hef-1 4 '{"session_name":"hef-deploy-HEF-4","role":"deploy","started":"2026-10-21T00:00:00Z"}' | lc_put "$lc_t" HEF-4
: > "$(sld "$lc_t")/HEF-4.lease"
lc_o="$(lc "$lc_t" advance HEF-4 merged 2>&1)" || { bad "advance HEF-4 merged must pass on the branch path — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
lc_jq "$lc_t" HEF-4 '.phase == "merged" and .owner == null
  and (.runs[-1] | .exit == 125 and .usd == 0 and .role == "deploy" and .session_name == "hef-deploy-HEF-4" and .note == "released-on-merged")
  and (.events[-1] | .kind == "owner-released" and .note == "merged")' \
  || { bad "reaching merged must release a launched owner (exit 125, released-on-merged, an owner-released event) (FR-010) — got: $(jq -c '{phase, owner, run: .runs[-1], ev: .events}' "$(lc_entry "$lc_t" HEF-4)")"; x_fail=1; }
[ -e "$(sld "$lc_t")/HEF-4.lease" ] && { bad "the released owner's lease must be removed"; x_fail=1; }
# An advance that stays short of a done phase leaves the owner alone.
lc_entry_90 HEF-6 implement hef-1 "" '{"session_name":"hef-build-HEF-6","role":"implement","started":"2026-10-21T00:00:00Z"}' | lc_put "$lc_t" HEF-6
lc "$lc_t" advance HEF-6 verify >/dev/null 2>&1 && lc_jq "$lc_t" HEF-6 '.owner.session_name == "hef-build-HEF-6" and (has("events") | not) and .runs == []' \
  || { bad "advance to a phase that is not done must keep the owner and write no release"; x_fail=1; }
# FR-010: an interactive deployer keeps its claim through the merge, so its lane's --finish still holds it.
lc_entry_90 HEF-5 pr hef-2 5 '{"session_name":"repo-deployer","role":"deploy","started":"2026-10-21T00:00:00Z","mode":"interactive"}' | lc_put "$lc_t" HEF-5
lc "$lc_t" advance HEF-5 merged >/dev/null 2>&1 || { bad "advance HEF-5 merged must pass on the branch path"; x_fail=1; }
lc_jq "$lc_t" HEF-5 '.phase == "merged" and .owner.session_name == "repo-deployer" and .owner.mode == "interactive" and .owner.role == "deploy" and .runs == []' \
  || { bad "an interactive owner must stay through the merge — session-launch --finish checks it holds the entry (FR-010) — got: $(jq -c '{phase, owner, runs}' "$(lc_entry "$lc_t" HEF-5)")"; x_fail=1; }
lc "$lc_t" run HEF-5 --role deploy --exit 0 --usd 0 --session-id in-lane --note in-lane >/dev/null 2>&1 && lc_jq "$lc_t" HEF-5 '.owner == null and .runs[-1].session_name == "repo-deployer"' \
  || { bad "the lane's --finish run (session-launch.sh's ledger run) must still record and release after the merge"; x_fail=1; }
rm -rf -- "${lc_t:?}"
# FR-009 (note 9): on an external board, next --stage build skips the merged entry's stale owner in the busy set.
lc_t="$(cd "$(mktemp -d)" && pwd -P)"; lc_k="$lc_t/kanban"; lc_a="$lc_t/app"
for lc_r in kanban app; do git init -q -b main "$lc_t/$lc_r" && lc_git "$lc_t/$lc_r" commit -q --allow-empty -m init && mkdir -p "$lc_t/$lc_r/.claude" \
  && printf '.claude/\n' >> "$lc_t/$lc_r/.git/info/exclude"; done
mkdir -p "$lc_k/tasks" && printf '# TODO\n' > "$lc_k/tasks/TODO.md"
printf '{"source":"tasks-repo","root":"tasks","repos":{"app":"../app"}}\n' > "$lc_k/.claude/project-status.json"
printf '{"board":"../kanban"}\n' > "$lc_a/.claude/project-status.json"
[ "$(lc "$lc_a" board 2>/dev/null | jq -r .mode)" = external ] || { bad "fixture: the app repo must resolve an external board — got: $(lc "$lc_a" board 2>&1 | head -c 200)"; x_fail=1; }
lc_entry_90 HEF-2 merged hef-2 2 '{"session_name":"hef-build-HEF-2","role":"implement","started":"2026-10-21T00:00:00Z"}' | jq '.repo = "app"' | lc_put "$lc_k" HEF-2
lc_entry_90 HEF-3 queued "" "" null | jq '.repo = "app"' | lc_put "$lc_k" HEF-3
lc_o="$(lc "$lc_a" next --stage build 2>&1)"
[ "$lc_o" = HEF-3 ] || { bad "next --stage build on an external board must not count a merged entry's stale owner as busy (FR-009) — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
# the control: a LIVE owner in the same repo still makes it busy
lc_entry_90 HEF-7 implement hef-7 "" '{"session_name":"hef-build-HEF-7","role":"implement","started":"2026-10-21T00:00:00Z"}' | jq '.repo = "app"' | lc_put "$lc_k" HEF-7
lc_o="$(lc "$lc_a" next --stage build 2>&1)" && { bad "the control: a live owner in the repo must still make next refuse — got: $lc_o"; x_fail=1; }
grep -qF 'owned by hef-build-HEF-7 on HEF-7' <<<"$lc_o" && ! grep -qF 'HEF-2' <<<"$lc_o" \
  || { bad "the busy refusal must name the live owner only, never the stale one — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
rm -rf -- "${lc_t:?}"
[ "$x_fail" -eq 0 ] && ok "an owner on a done phase blocks neither claim nor next's external busy set and is marked stale by list --active; claim refuses a done entry; reaching merged releases a launched owner (exit 125, note, event, lease) and keeps an interactive one for --finish (FR-009 FR-010 FR-002)"

# --- Terminal phases: drop / fold --into / supersede --by (US1: FR-001, FR-002, FR-003, NR-001; plan Sketch 1) ---
# Each moves an entry to dropped / folded / superseded with a reason file (exists, non-empty, ≤ 8 KB), keeping its
# history (runs, verdicts, PR) and clearing its blocks; a launched owner is released as on any done phase. Refused:
# a released or already-terminal entry, a fold/supersede into itself or into a terminal entry (naming it), a missing
# reason. Person-only through BOTH gates: lane-guard (the hook) and ledger.sh's caller_gate (the hook fails open).
head_ "Lifecycle: drop / fold --into / supersede --by"
x_fail=0
lc_t="$(cd "$(mktemp -d)" && pwd -P)"; git -C "$lc_t" init -q -b main . && lc_git "$lc_t" commit -q --allow-empty -m init
printf 'out of scope: the vendor API went away\n' > "$lc_t/why.md"; : > "$lc_t/empty.md"; head -c 9000 /dev/zero | tr '\0' x > "$lc_t/big.md"
lc_entry_90 HEF-1 implement hef-1 "" '{"session_name":"hef-build-HEF-1","role":"implement","started":"2026-10-21T00:00:00Z"}' \
  | jq '.blocked_on = {kind: "stall", since: "2026-10-21T00:00:00Z"} | .runs = [{role: "plan", exit: 0, usd: 1, at: "2026-10-20T00:00:00Z"}]
        | .verdicts = [{gate: "verify", verdict: "FAIL", by: "v"}] | .pr = {url: "https://github.com/example/app/pull/9", number: 9}' | lc_put "$lc_t" HEF-1
: > "$(sld "$lc_t")/HEF-1.lease"
for lc_id in HEF-2 HEF-3 HEF-6 HEF-7; do lc_entry_90 "$lc_id" queued "" "" null | lc_put "$lc_t" "$lc_id"; done
lc_entry_90 HEF-4 released hef-4 4 null | lc_put "$lc_t" HEF-4
lc_sum() { sha256sum < "$(lc_entry "$lc_t" "$1")"; }
lc_refused() { # lc_refused <id that must stay unchanged> <text the refusal must name> <ledger args…>
  local id="$1" want="$2" s o; shift 2; s="$(lc_sum "$id")"
  o="$(lc "$lc_t" "$@" 2>&1)" && { bad "ledger $* must be refused (FR-003)"; x_fail=1; }
  grep -qF -- "$want" <<<"$o" || { bad "the refusal of ledger $* must name '$want' — got: $(head -c 200 <<<"$o")"; x_fail=1; }
  [ "$(lc_sum "$id")" = "$s" ] || { bad "a refused ledger $* must leave $id unchanged"; x_fail=1; }
}
# A missing, empty or oversized reason is refused before anything is written.
lc_refused HEF-1 'reason' drop HEF-1
lc_refused HEF-1 "$lc_t/nope.md" drop HEF-1 --reason-file "$lc_t/nope.md"
lc_refused HEF-1 'empty' drop HEF-1 --reason-file "$lc_t/empty.md"
lc_refused HEF-1 '8 KB' drop HEF-1 --reason-file "$lc_t/big.md"
# FR-001: drop keeps the history, clears owner (launched: released, lease gone) and block, records why and who.
lc_o="$(lc "$lc_t" drop HEF-1 --reason-file "$lc_t/why.md" 2>&1)" || { bad "drop HEF-1 must pass — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
jq -e --arg h "$(sha256sum < "$lc_t/why.md" | cut -c1-64)" '.phase == "dropped" and .owner == null and .blocked_on == null
  and .terminal.kind == "dropped" and .terminal.reason_sha256 == $h and (.terminal.by_person | type == "string" and length > 0) and (.terminal.at | type == "string")
  and .runs[0].role == "plan" and .runs[-1].exit == 125 and .verdicts[0].verdict == "FAIL" and .pr.number == 9
  and any(.events[]; .kind == "terminal" and .note == "dropped")' "$(lc_entry "$lc_t" HEF-1)" >/dev/null 2>&1 \
  || { bad "drop must set phase dropped with .terminal {kind, reason_sha256, by_person, at}, clear owner and block, keep runs/verdicts/PR and log a terminal event (FR-001) — got: $(jq -c '{phase, owner, blocked_on, terminal, events}' "$(lc_entry "$lc_t" HEF-1)" | head -c 400)"; x_fail=1; }
[ -e "$(sld "$lc_t")/HEF-1.lease" ] && { bad "drop must remove a released owner's lease"; x_fail=1; }
# FR-003: the refusals, each naming what is wrong.
lc_refused HEF-1 'dropped' drop HEF-1 --reason-file "$lc_t/why.md"
lc_refused HEF-4 'released' drop HEF-4 --reason-file "$lc_t/why.md"
lc_refused HEF-2 'itself' fold HEF-2 --into HEF-2 --reason-file "$lc_t/why.md"
lc_refused HEF-2 'HEF-1' fold HEF-2 --into HEF-1 --reason-file "$lc_t/why.md"
lc_refused HEF-2 'HEF-99' fold HEF-2 --into HEF-99 --reason-file "$lc_t/why.md"
lc_refused HEF-2 '--into' fold HEF-2 --reason-file "$lc_t/why.md"
lc_refused HEF-3 '--by' supersede HEF-3 --into HEF-6 --reason-file "$lc_t/why.md"
lc_refused HEF-3 'reason' fold HEF-3 --into HEF-6
lc "$lc_t" fold HEF-2 --into HEF-3 --reason-file "$lc_t/why.md" >/dev/null 2>&1 \
  && lc_jq "$lc_t" HEF-2 '.phase == "folded" and .terminal.kind == "folded" and .terminal.into == "HEF-3" and any(.events[]; .kind == "terminal" and .note == "folded")' \
  || { bad "fold --into must set phase folded with .terminal.into (FR-001) — got: $(jq -c '{phase, terminal}' "$(lc_entry "$lc_t" HEF-2)")"; x_fail=1; }
lc_refused HEF-3 'HEF-2' supersede HEF-3 --by HEF-2 --reason-file "$lc_t/why.md"
lc "$lc_t" supersede HEF-3 --by HEF-6 --reason-file "$lc_t/why.md" >/dev/null 2>&1 \
  && lc_jq "$lc_t" HEF-3 '.phase == "superseded" and .terminal.kind == "superseded" and .terminal.by == "HEF-6"' \
  || { bad "supersede --by must set phase superseded with .terminal.by (FR-001) — got: $(jq -c '{phase, terminal}' "$(lc_entry "$lc_t" HEF-3)")"; x_fail=1; }
# FR-002: terminal entries leave next and claim; advance never reaches or leaves them; metrics counts each phase.
[ "$(lc "$lc_t" next --stage build 2>&1)" = HEF-6 ] || { bad "next --stage build must skip terminal entries — got: $(lc "$lc_t" next --stage build 2>&1 | head -c 200)"; x_fail=1; }
lc_refused HEF-2 'folded' claim HEF-2 --session s1 --role implement
lc "$lc_t" advance HEF-6 dropped >/dev/null 2>&1 && { bad "advance must never reach a terminal phase (FR-002)"; x_fail=1; }
lc "$lc_t" advance HEF-1 implement >/dev/null 2>&1 && { bad "advance must never move a terminal entry (FR-002)"; x_fail=1; }
lc_o="$(lc "$lc_t" metrics --json 2>&1)"
jq -e '.terminal == {dropped: 1, folded: 1, superseded: 1} and .prs_opened == 1' <<<"$lc_o" >/dev/null 2>&1 \
  || { bad "metrics must count each terminal phase and leave terminal entries out of the PR count (FR-002) — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
grep -qF 'dropped 1 · folded 1 · superseded 1' <<<"$(lc "$lc_t" metrics 2>&1)" || { bad "metrics' text must print the terminal counts — got: $(lc "$lc_t" metrics 2>&1 | head -c 400)"; x_fail=1; }
# NR-001: one person-only list, read by both gates.
for lc_v in drop fold supersede reopen; do
  bash -c '. "$1"; is_person_sub "$2" HEF-1' _ "$REPO/hooks/lane-lib.sh" "$lc_v" || { bad "is_person_sub must list $lc_v (NR-001)"; x_fail=1; }
done
# NR-001, gate 1 — lane-guard: hand-written session records, as the session start writes them (lane-lib.sh:1-8).
mkdir -p "$HOME/.cache/hefesto/sessions"
for lc_r in orchestrator build; do
  jq -nc --arg r "$lc_r" --arg x "$LC_LG *" --arg l "$(sld "$lc_t")" '{title: "repo-\($r)", role: $r, name: "repo-\($r)", lanes: true, worker: false, excluded: [$x], ledger: $l}' \
    > "$HOME/.cache/hefesto/sessions/sid-lc-$lc_r-0001.json"
done
lc_gd() { # lc_gd <role> <command> → deny | allow | none
  local o; o="$(jq -nc --arg c "$2" --arg s "sid-lc-$1-0001" --arg d "$lc_t" '{tool_name: "Bash", tool_input: {command: $c}, session_id: $s, cwd: $d}' | bash "$REPO/hooks/lane-guard.sh" 2>/dev/null)"
  [ -n "$o" ] || { echo none; return; }; jq -r '.hookSpecificOutput.permissionDecision // "none"' <<<"$o" 2>/dev/null || echo none
}
for lc_c in "drop HEF-6 --reason-file $lc_t/why.md" "fold HEF-6 --into HEF-7 --reason-file $lc_t/why.md" "supersede HEF-6 --by HEF-7 --reason-file $lc_t/why.md" \
            "reopen HEF-6 --reason-file $lc_t/why.md" "op close OP-1 --outcome-file $lc_t/why.md" "op drop OP-1 --reason-file $lc_t/why.md"; do
  [ "$(lc_gd build "$LC_LG $lc_c")" = deny ] || { bad "lane-guard must deny 'ledger.sh $lc_c' in a stage lane (NR-001)"; x_fail=1; }
  [ "$(lc_gd orchestrator "$LC_LG $lc_c")" = none ] || { bad "lane-guard must let the orchestrator run 'ledger.sh $lc_c'"; x_fail=1; }
done
# NR-001, gate 2 — caller_gate, with lane-guard out of the way (ledger.sh called directly with the lane's session id).
lc_s="$(lc_sum HEF-6)"
lc_o="$(cd "$lc_t" && CLAUDE_CODE_SESSION_ID=sid-lc-build-0001 bash "$LC_LG" drop HEF-6 --reason-file "$lc_t/why.md" 2>&1)" && { bad "caller_gate must refuse drop from a stage lane (NR-001)"; x_fail=1; }
grep -qF 'only in the orchestrator lane' <<<"$lc_o" || { bad "caller_gate's refusal must say why — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
for lc_c in "fold HEF-6 --into HEF-7" "supersede HEF-6 --by HEF-7"; do
  # shellcheck disable=SC2086  # the words on purpose
  (cd "$lc_t" && CLAUDE_CODE_SESSION_ID=sid-lc-build-0001 bash "$LC_LG" $lc_c --reason-file "$lc_t/why.md") >/dev/null 2>&1 && { bad "caller_gate must refuse '$lc_c' from a stage lane (NR-001)"; x_fail=1; }
done
[ "$(lc_sum HEF-6)" = "$lc_s" ] || { bad "a lane's refused terminal call must leave the entry unchanged"; x_fail=1; }
(cd "$lc_t" && CLAUDE_CODE_SESSION_ID=sid-lc-orchestrator-0001 bash "$LC_LG" drop HEF-6 --reason-file "$lc_t/why.md") >/dev/null 2>&1 \
  && lc_jq "$lc_t" HEF-6 '.phase == "dropped"' || { bad "the orchestrator lane must be able to drop (the control)"; x_fail=1; }
rm -f "$HOME"/.cache/hefesto/sessions/sid-lc-*-0001.json
# A terminal entry takes no new PR and no new block: drop cleared both, and nothing should put them back
# (code review 2026-10-27; metrics would count the block).
lc_s="$(lc_sum HEF-6)"
lc_o="$(lc "$lc_t" record HEF-6 --pr https://github.com/example/app/pull/66 2>&1)" && { bad "record on a dropped entry must be refused"; x_fail=1; }
grep -qF 'dropped' <<<"$lc_o" || { bad "the record refusal must name the phase — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
lc_o="$(lc "$lc_t" block HEF-6 --kind ci 2>&1)" && { bad "block on a dropped entry must be refused"; x_fail=1; }
grep -qF 'dropped' <<<"$lc_o" || { bad "the block refusal must name the phase — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
[ "$(lc_sum HEF-6)" = "$lc_s" ] || { bad "a refused record/block must leave the dropped entry unchanged"; x_fail=1; }
# Setup: the ask rules (both spellings) for every person-only lifecycle verb, and --check names a missing one.
lc_sh="$(mktemp -d)"; lc_su() { (cd "$lc_t" && HOME="$lc_sh" CLAUDE_CONFIG_DIR='' bash "$REPO/hooks/hefesto-setup.sh" "$@" 2>&1); }
lc_su --lanes >/dev/null; lc_sf="$lc_t/.claude/settings.local.json"
for lc_v in drop fold supersede reopen "op close" "op drop"; do
  jq -e --arg h "$REPO/hooks" --arg v "$lc_v" '(.permissions.ask | index(["Bash(\($h)/ledger.sh \($v):*)"])) and (.permissions.ask | index(["Bash(bash \($h)/ledger.sh \($v):*)"]))
    and (.permissions.allow | map(select(contains("ledger.sh \($v)"))) | length == 0)' "$lc_sf" >/dev/null 2>&1 \
    || { bad "setup must write an ask rule (both spellings) for ledger.sh $lc_v, never an allow (NR-001)"; x_fail=1; }
done
[ "$(lc_su --check | tail -1)" = "setup: ok" ] || { bad "--check must pass right after setup — got: $(lc_su --check | head -c 300)"; x_fail=1; }
jq --arg r "Bash($REPO/hooks/ledger.sh fold:*)" '.permissions.ask -= [$r]' "$lc_sf" > "$lc_t/s.json" && mv "$lc_t/s.json" "$lc_sf"
lc_o="$(lc_su --check)" && { bad "--check must fail when the fold ask rule is missing"; x_fail=1; }
grep -qF 'ledger.sh fold' <<<"$lc_o" || { bad "--check must name the missing fold ask rule — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
rm -rf -- "${lc_t:?}" "${lc_sh:?}"
[ "$x_fail" -eq 0 ] && ok "drop / fold --into / supersede --by reach a terminal phase with the reason's hash, keep history, clear owner and block; every refusal names its cause; terminal entries leave next/claim/advance and metrics counts each; person-only through lane-guard, caller_gate and setup's ask rules (FR-001 FR-002 FR-003 NR-001)"

# --- Several PRs on one entry: .prs[] (US2: FR-004, FR-006; plan Sketch 2, notes 2 and 23) -------------------------
head_ "Lifecycle: .prs[] — one PR list per entry"
x_fail=0
lc_t="$(lc_fixture_90)" || { bad "lc_fixture_90 could not build the 9.0 fixture"; x_fail=1; }
lc_u="https://github.com/example/app/pull"
# FR-004: a 9.0 entry (a single .pr, no .prs) reads as a one-element list.
lc_o="$(bash -c '. "$1"; entry_prs "$(cat "$2")"' _ "$REPO/hooks/ledger-lifecycle.sh" "$(lc_entry "$lc_t" HEF-1)" 2>&1)"
jq -e --arg u "$lc_u/1" 'length == 1 and .[0].url == $u and .[0].number == 1' <<<"$lc_o" >/dev/null 2>&1 \
  || { bad "entry_prs must read a 9.0 .pr as a one-element list (FR-004, SC-007) — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
lc_o="$(bash -c '. "$1"; entry_prs "$(cat "$2")"' _ "$REPO/hooks/ledger-lifecycle.sh" "$(lc_entry "$lc_t" HEF-3)" 2>&1)"
[ "$lc_o" = '[]' ] || { bad "entry_prs must read an entry with no PR as [] — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
# An unmerged current PR: the same URL twice is one PR; a split (a new URL) REPLACES it; .pr is always prs[-1].
lc_entry_90 HEF-7 implement hef-7 "" null | lc_put "$lc_t" HEF-7
lc "$lc_t" record HEF-7 --pr "$lc_u/7" >/dev/null 2>&1; lc "$lc_t" record HEF-7 --pr "$lc_u/7" >/dev/null 2>&1
lc_jq "$lc_t" HEF-7 '(.prs | length) == 1 and .prs[0].url == "'"$lc_u/7"'" and .prs[0].number == 7 and .pr == .prs[-1]' \
  || { bad "the same URL recorded twice must be one PR (FR-004) — got: $(jq -c '{pr, prs}' "$(lc_entry "$lc_t" HEF-7)")"; x_fail=1; }
lc "$lc_t" record HEF-7 --pr "$lc_u/8" >/dev/null 2>&1
lc_jq "$lc_t" HEF-7 '(.prs | map(.url)) == ["'"$lc_u/8"'"] and .pr == .prs[-1] and .pr.number == 8' \
  || { bad "record --pr must REPLACE an unmerged current PR (a split, FR-004) — got: $(jq -c '{pr, prs}' "$(lc_entry "$lc_t" HEF-7)")"; x_fail=1; }
lc "$lc_t" record HEF-7 --pr "https://example.com/review/abc" >/dev/null 2>&1
lc_jq "$lc_t" HEF-7 '.pr.url == "https://example.com/review/abc" and .pr.number == null and (.prs | length) == 1' \
  || { bad "a URL that does not end in digits must record number null — got: $(jq -c '{pr, prs}' "$(lc_entry "$lc_t" HEF-7)")"; x_fail=1; }
# Note 2: "unmerged" honours the 9.0 fields — a phase >= merged (HEF-1) or a recorded .pr.merge_sha APPENDS.
lc "$lc_t" record HEF-1 --pr "$lc_u/11" >/dev/null 2>&1
lc_jq "$lc_t" HEF-1 '(.prs | map(.url)) == ["'"$lc_u/1"'", "'"$lc_u/11"'"] and .pr == .prs[-1]' \
  || { bad "record --pr on a merged 9.0 entry must APPEND, never replace the merged PR (note 2) — got: $(jq -c '{pr, prs}' "$(lc_entry "$lc_t" HEF-1)")"; x_fail=1; }
lc_entry_90 HEF-8 pr hef-1 8 null | jq '.pr.merge_sha = "abc1234"' | lc_put "$lc_t" HEF-8
lc "$lc_t" record HEF-8 --pr "$lc_u/18" >/dev/null 2>&1
lc_jq "$lc_t" HEF-8 '(.prs | map(.url)) == ["'"$lc_u/8"'", "'"$lc_u/18"'"] and .prs[0].merge_sha == "abc1234"' \
  || { bad "record --pr must APPEND after a 9.0 .pr.merge_sha (note 2) — got: $(jq -c '{pr, prs}' "$(lc_entry "$lc_t" HEF-8)")"; x_fail=1; }
# unblock human:merge stamps the current PR and never moves the phase (note 23); then a new PR appends.
lc_entry_90 HEF-9 pr hef-1 9 null | jq '.blocked_on = {kind: "human:merge", at: "2026-10-21T00:00:00Z"}' | lc_put "$lc_t" HEF-9
lc_o="$(lc "$lc_t" unblock HEF-9 2>&1)" || { bad "unblock HEF-9 (branch merged) must pass — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
lc_jq "$lc_t" HEF-9 '.phase == "pr" and .blocked_on == null and (.prs | length) == 1 and .prs[0].merged.via == "branch" and (.prs[0].merged.at | type) == "string" and .pr == .prs[-1]' \
  || { bad "unblock human:merge must stamp the current PR merged and leave the phase at pr (note 23) — got: $(jq -c '{phase, pr, prs}' "$(lc_entry "$lc_t" HEF-9)")"; x_fail=1; }
lc "$lc_t" record HEF-9 --pr "$lc_u/19" >/dev/null 2>&1
lc_jq "$lc_t" HEF-9 '(.prs | map(.url)) == ["'"$lc_u/9"'", "'"$lc_u/19"'"] and (.prs[0].merged | type) == "object" and (.prs[1] | has("merged") | not)' \
  || { bad "record --pr after a merged stamp must APPEND and keep the stamp (FR-004) — got: $(jq -c '.prs' "$(lc_entry "$lc_t" HEF-9)")"; x_fail=1; }
# The merge-commit path of unblock human:merge (ledger.sh, MERGED_VIA): a squash merge whose branch is gone, proven by
# --merge-sha. gh is absent here (smoke.sh's missing HEFESTO_GH_BIN), so the stamp is unverified; .pr.merge_sha written
# just before the stamp is kept in it, and the phase stays at pr (note 23). Then a new PR appends, never replaces.
lc_ms="$(git -C "$lc_t" rev-parse main)"
lc_entry_90 HEF-13 pr gone-13 13 null | jq '.blocked_on = {kind: "human:merge", at: "2026-10-21T00:00:00Z"}' | lc_put "$lc_t" HEF-13
lc_o="$(lc "$lc_t" unblock HEF-13 --merge-sha "$lc_ms" 2>&1)" || { bad "unblock HEF-13 --merge-sha (a merge commit on main) must pass — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
lc_jq "$lc_t" HEF-13 '.phase == "pr" and .blocked_on == null and (.prs | length) == 1 and .pr == .prs[-1]
  and .prs[-1].merged.via == "commit" and .prs[-1].merged.merge_sha == "'"$lc_ms"'" and .prs[-1].merged.unverified == true
  and .pr.merge_sha == "'"$lc_ms"'" and (.prs[-1].merged.at | type) == "string"' \
  || { bad "unblock human:merge by merge commit must stamp via commit with the sha and unverified, keep .pr.merge_sha, leave the phase (FR-004) — got: $(jq -c '{phase, pr, prs}' "$(lc_entry "$lc_t" HEF-13)")"; x_fail=1; }
lc "$lc_t" record HEF-13 --pr "$lc_u/23" >/dev/null 2>&1
lc_jq "$lc_t" HEF-13 '(.prs | map(.url)) == ["'"$lc_u/13"'", "'"$lc_u/23"'"] and .prs[0].merged.via == "commit"' \
  || { bad "record --pr after a commit-path stamp must APPEND (FR-004) — got: $(jq -c '.prs' "$(lc_entry "$lc_t" HEF-13)")"; x_fail=1; }
# FR-006: advance merged needs every earlier PR stamped, plus merge_evidence for the current one.
jq -n --arg u "$lc_u" '[{url: "\($u)/20", number: 20}, {url: "\($u)/21", number: 21}]' > "$lc_t/prs.json"
lc_entry_90 HEF-10 pr hef-1 21 null | jq --slurpfile p "$lc_t/prs.json" '.prs = $p[0] | .pr = $p[0][-1]' | lc_put "$lc_t" HEF-10
lc_o="$(lc "$lc_t" advance HEF-10 merged 2>&1)" && { bad "advance merged must refuse while an earlier PR carries no merged stamp (FR-006)"; x_fail=1; }
grep -qF "$lc_u/20" <<<"$lc_o" || { bad "the FR-006 refusal must name the unstamped PR — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
lc_jq "$lc_t" HEF-10 '.phase == "pr"' || { bad "a refused advance must leave the phase"; x_fail=1; }
jq '.prs[0].merged = {via: "branch", at: "2026-10-21T00:00:00Z"}' "$(lc_entry "$lc_t" HEF-10)" > "$lc_t/e.json" && mv "$lc_t/e.json" "$(lc_entry "$lc_t" HEF-10)"
lc_o="$(lc "$lc_t" advance HEF-10 merged 2>&1)" || { bad "advance merged must pass once earlier PRs are stamped and the current one is merged — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
lc_entry_90 HEF-12 pr hef-12 22 null | jq --slurpfile p "$lc_t/prs.json" '.prs = [$p[0][0] + {merged: {via: "branch", at: "x"}}, $p[0][1]] | .pr = .prs[-1]' | lc_put "$lc_t" HEF-12
lc "$lc_t" advance HEF-12 merged >/dev/null 2>&1 && { bad "advance merged must still need merge_evidence for the current PR (FR-006)"; x_fail=1; }
rm -rf -- "${lc_t:?}"
[ "$x_fail" -eq 0 ] && ok ".prs[]: a 9.0 .pr reads as one PR, the same URL twice is one PR, a split replaces an unmerged PR, a merged one (stamp, .pr.merge_sha or phase merged) is appended after; unblock human:merge stamps without moving the phase; advance merged needs every earlier PR stamped plus the current one's evidence (FR-004 FR-006)"

# --- reopen: a merged item takes a follow-up PR (US2: FR-005, FR-006, SC-007; plan Sketch 2, notes 1 and 18) ------
# Person-only, only from merged: it stamps the closing PR from a fresh merge_evidence (passing the recorded
# .pr.merge_sha — note 18), then phase implement, owner none, attempts 0 (note 1: claim stalls at > 2), a reopen event.
# The 9.0 build path then runs unchanged through session-launch.sh --prepare/--finish and appends the second PR.
head_ "Lifecycle: reopen a merged item for a follow-up PR"
x_fail=0
lc_t="$(lc_fixture_90)" || { bad "lc_fixture_90 could not build the 9.0 fixture"; x_fail=1; }
lc_u="https://github.com/example/app/pull"; lc_w="$(mktemp -d)"; printf 'a follow-up: the export misses a column\n' > "$lc_w/why.md"
lc_ro() { # lc_ro <id> <text the refusal must name> <ledger args…> — refused, naming it, the entry unchanged
  local id="$1" want="$2" s o; shift 2; s="$(sha256sum < "$(lc_entry "$lc_t" "$id")")"
  o="$(lc "$lc_t" "$@" 2>&1)" && { bad "ledger $* must be refused (FR-005)"; x_fail=1; }
  grep -qF -- "$want" <<<"$o" || { bad "the refusal of ledger $* must name '$want' — got: $(head -c 200 <<<"$o")"; x_fail=1; }
  [ "$(sha256sum < "$(lc_entry "$lc_t" "$id")")" = "$s" ] || { bad "a refused ledger $* must leave $id unchanged"; x_fail=1; }
}
lc_entry_90 HEF-4 released hef-1 4 null | lc_put "$lc_t" HEF-4
lc_entry_90 HEF-5 merged hef-1 5 null | jq '.phase = "dropped" | .terminal = {kind: "dropped"}' | lc_put "$lc_t" HEF-5
lc_ro HEF-3 'queued' reopen HEF-3 --reason-file "$lc_w/why.md"
lc_ro HEF-4 'released' reopen HEF-4 --reason-file "$lc_w/why.md"
lc_ro HEF-5 'dropped' reopen HEF-5 --reason-file "$lc_w/why.md"
lc_ro HEF-1 'reason' reopen HEF-1
# handoff on merged answers "reopen first" — before the stale owner on HEF-2 is even looked at.
lc_ro HEF-2 'reopen' handoff HEF-2 --pr "$lc_u/12" --branch hef-2b
# No merge evidence for the current PR → refused: a branch that is gone, no sha, gh absent.
lc_entry_90 HEF-6 merged gone-6 6 null | lc_put "$lc_t" HEF-6
lc_ro HEF-6 'merge' reopen HEF-6 --reason-file "$lc_w/why.md"
# Note 18: the recorded .pr.merge_sha is passed to merge_evidence (a squash merge whose branch was deleted).
lc_sha="$(git -C "$lc_t" rev-parse 'main^{commit}')"
lc_entry_90 HEF-7 merged gone-7 7 '{"session_name":"hef-build-HEF-7","role":"implement","started":"2026-10-21T00:00:00Z"}' \
  | jq --arg s "$lc_sha" '.pr.merge_sha = $s | .attempts = 3' | lc_put "$lc_t" HEF-7
lc_o="$(lc "$lc_t" reopen HEF-7 --reason-file "$lc_w/why.md" 2>&1)" || { bad "reopen must pass the recorded .pr.merge_sha to merge_evidence (note 18) — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
lc_jq "$lc_t" HEF-7 '.phase == "implement" and .owner == null and .attempts == 0 and .blocked_on == null
  and (.prs | length) == 1 and .prs[0].merged.merge_sha == "'"$lc_sha"'" and .pr == .prs[-1]
  and (.events[-1] | .kind == "reopen" and (.by | type == "string" and length > 0))' \
  || { bad "reopen must stamp the PR with the recorded sha, land at implement with no owner and attempts 0, and log a reopen event (FR-005, note 1) — got: $(jq -c '{phase, owner, attempts, prs, events}' "$(lc_entry "$lc_t" HEF-7)" | head -c 400)"; x_fail=1; }
# live check 2026-10-29: the reason is the follow-up's only description, so reopen keeps a hashed copy for the worker
lc_fu="$(sld "$lc_t")/HEF-7.followup-1.md"
{ cmp -s "$lc_fu" "$lc_w/why.md" && lc_jq "$lc_t" HEF-7 '(.followups | length) == 1 and .followups[0].sha256 == "'"$(sha256sum < "$lc_w/why.md" | cut -c1-64)"'" and (.followups[0].consumed // false) == false'; } \
  || { bad "reopen must copy the reason to HEF-7.followup-1.md and record its hash, unconsumed (FR-005) — got: $(jq -c .followups "$(lc_entry "$lc_t" HEF-7)")"; x_fail=1; }
# A reopened entry is claimable again (attempts 0: the claim is attempt 1, never a stall).
lc_o="$(lc "$lc_t" claim HEF-7 --session s7 --role implement 2>&1)" && grep -qF 'attempt 1' <<<"$lc_o" \
  || { bad "a reopened entry must be claimable as attempt 1 (note 1) — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
lc "$lc_t" run HEF-7 --role implement --exit 0 --usd 0 >/dev/null 2>&1   # free the repo's one builder slot for HEF-1
# SC-007: the branch-via 9.0 entry HEF-1 reopens and goes round the lane route through the launcher.
lc_o="$(lc "$lc_t" reopen HEF-1 --reason-file "$lc_w/why.md" 2>&1)" || { bad "reopen HEF-1 (merged by branch, 9.0) must pass — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
lc_jq "$lc_t" HEF-1 '.phase == "implement" and .attempts == 0 and (.prs | length) == 1 and .prs[0].merged.via == "branch" and .prs[0].url == "'"$lc_u/1"'"' \
  || { bad "reopen HEF-1 must stamp its 9.0 PR via the branch (SC-007) — got: $(jq -c '{phase, attempts, prs}' "$(lc_entry "$lc_t" HEF-1)")"; x_fail=1; }
lc_ro HEF-1 'implement' reopen HEF-1 --reason-file "$lc_w/why.md"
mkdir -p "$lc_t/.claude" "$lc_t/tasks" && printf '.claude/\n' >> "$lc_t/.git/info/exclude"
printf '# TODO\n\n## HEF-1 — export orders\nadd the missing column\n' > "$lc_t/tasks/TODO.md"
for lc_c in DOING DONE BACKLOG; do printf '# %s\n' "$lc_c" > "$lc_t/tasks/$lc_c.md"; done
lc_git "$lc_t" add tasks && lc_git "$lc_t" commit -q -m board
printf '{"source":"tasks-repo","root":"tasks","orchestrate":{"lane_mode":"interactive"}}\n' > "$lc_t/.claude/project-status.json"
lc_sl() { (cd "$lc_t" && env -u CLAUDE_CODE_SESSION_ID -u HEFESTO_TRUSTED_TOP -u HEFESTO_LANE_MAP bash "$REPO/hooks/session-launch.sh" "$@"); }
lc_o="$(lc_sl implement HEF-1 --prepare --lane repo-builder 2>&1)" || { bad "implement --prepare on the reopened HEF-1 must pass — got: $(head -c 400 <<<"$lc_o")"; x_fail=1; }
lc_wt="$lc_t/.claude/worktrees/HEF-1"
lc_git "$lc_wt" commit -q --allow-empty -m "the follow-up" 2>/dev/null
printf '{"summary":"the column","route":"light","outcome":"pr","pr_url":"%s/31"}\n' "$lc_u" > "$lc_w/impl.json"
lc_o="$(lc_sl implement HEF-1 --finish --lane repo-builder --outcome-file "$lc_w/impl.json" 2>&1)" || { bad "implement --finish must pass — got: $(head -c 400 <<<"$lc_o")"; x_fail=1; }
lc_o="$(lc_sl verify HEF-1 --prepare --lane repo-builder 2>&1)" || { bad "verify --prepare must pass — got: $(head -c 400 <<<"$lc_o")"; x_fail=1; }
printf '{"summary":"fine","verdicts":[{"gate":"review","verdict":"PASS","evidence":"ok"}]}\n' > "$lc_w/ver.json"
lc_o="$(lc_sl verify HEF-1 --finish --lane repo-builder --outcome-file "$lc_w/ver.json" 2>&1)" || { bad "verify --finish must pass — got: $(head -c 400 <<<"$lc_o")"; x_fail=1; }
lc_jq "$lc_t" HEF-1 '.phase == "pr" and .blocked_on.kind == "human:merge" and (.prs | map(.url)) == ["'"$lc_u/1"'", "'"$lc_u/31"'"]
  and (.prs[0].merged | type) == "object" and (.prs[1] | has("merged") | not) and .pr.url == "'"$lc_u/31"'"' \
  || { bad "the lane route must end at pr + human:merge with 2 PRs and the first stamped (US2) — got: $(jq -c '{phase, blocked_on, prs}' "$(lc_entry "$lc_t" HEF-1)" | head -c 400)"; x_fail=1; }
# pr-watch.sh ledger-id searches every PR: the earlier one still resolves to the entry (a named fake gh, a remote).
lc_git "$lc_t" remote add origin "$lc_w/no-remote.git"
printf '#!/bin/bash\n[ "$1" = auth ] && exit 0\nexit 1\n' > "$lc_w/FakeGhAuthOnly"; chmod +x "$lc_w/FakeGhAuthOnly"
for lc_n in 1 31; do
  lc_o="$(cd "$lc_t" && HEFESTO_GH_BIN="$lc_w/FakeGhAuthOnly" bash "$REPO/hooks/pr-watch.sh" ledger-id "$lc_u/$lc_n" 2>&1)"
  [ "$lc_o" = HEF-1 ] || { bad "pr-watch.sh ledger-id must resolve PR $lc_n to HEF-1 through entry_prs — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
done
# ...and merges again: the follow-up branch into main, the gate cleared, merged reached with both PRs stamped.
lc_br="$(jq -r .branch "$(lc_entry "$lc_t" HEF-1)")"
lc_git "$lc_t" merge -q --no-ff -m "Merge $lc_br" "$lc_br" >/dev/null 2>&1
lc "$lc_t" unblock HEF-1 >/dev/null 2>&1 && lc "$lc_t" advance HEF-1 merged >/dev/null 2>&1 \
  && lc_jq "$lc_t" HEF-1 '.phase == "merged" and (.prs | length) == 2 and all(.prs[]; .merged != null) and any(.events[]; .kind == "reopen")' \
  || { bad "the reopened 9.0 entry must merge again with both PRs stamped (SC-007) — got: $(jq -c '{phase, blocked_on, branch, prs}' "$(lc_entry "$lc_t" HEF-1)" | head -c 400)"; x_fail=1; }
rm -rf -- "${lc_t:?}" "${lc_w:?}"
[ "$x_fail" -eq 0 ] && ok "reopen: only a merged entry, with a reason; stamps the closing PR from fresh evidence (the recorded merge_sha too), lands at implement with no owner and attempts 0, logs a reopen event; handoff on merged says reopen first; the lane route ends at pr + human:merge with 2 PRs, ledger-id finds both, and the 9.0 entry merges again (FR-005 FR-006 SC-007)"

# --- deployed: a release proven by its own commit in the environment (US3: FR-007, FR-008; plan Sketch 3, note 17) -
# The fixture is a cherry-pick release: hef-1 merged into main, its commit cherry-picked onto stg (cut from main
# before the merge), prod = stg. hef-1 is NOT an ancestor of stg, so ancestry alone could never release it.
head_ "Lifecycle: deployed — a cherry-picked release"
x_fail=0
lc_t="$(cd "$(mktemp -d)" && pwd -P)"; lc_w="$(mktemp -d)"
git -C "$lc_t" init -q -b main . && lc_git "$lc_t" commit -q --allow-empty -m init && lc_git "$lc_t" branch stg \
  && lc_git "$lc_t" switch -q -c hef-1 && echo a > "$lc_t/a" && lc_git "$lc_t" add a && lc_git "$lc_t" commit -q -m hef-1 \
  && lc_git "$lc_t" switch -q main && lc_git "$lc_t" merge -q --no-ff -m "Merge hef-1" hef-1 \
  && lc_git "$lc_t" switch -q stg && lc_git "$lc_t" cherry-pick -x hef-1 >/dev/null && lc_git "$lc_t" branch prod && lc_git "$lc_t" switch -q main \
  || { bad "the cherry-pick fixture could not be built"; x_fail=1; }
mkdir -p "$lc_t/.claude"; echo '{"branches": {"integration": "main", "environments": ["main", "stg", "prod"]}}' > "$lc_t/.claude/project-status.json"
lc_orig="$(git -C "$lc_t" rev-parse hef-1)"; lc_cp="$(git -C "$lc_t" rev-parse stg)"
lc_entry_90 HEF-1 merged hef-1 1 '{"session_name":"hef-deploy-HEF-1","role":"deploy","started":"2026-10-21T00:00:00Z"}' | lc_put "$lc_t" HEF-1
lc_entry_90 HEF-2 pr hef-1 2 null | jq '.blocked_on = {kind: "human:merge", since: "2026-10-21T00:00:00Z"}' | lc_put "$lc_t" HEF-2
lc_dr() { # lc_dr <id> <text the refusal must name…> -- <deployed args…> — refused, naming each text, the entry unchanged
  local id="$1" s o t; shift; s="$(sha256sum < "$(lc_entry "$lc_t" "$id")")"; local want=()
  while [ "$1" != -- ]; do want+=("$1"); shift; done; shift
  o="$(lc "$lc_t" deployed "$id" "$@" 2>&1)" && { bad "deployed $id $* must be refused"; x_fail=1; }
  for t in "${want[@]}"; do grep -qF -- "$t" <<<"$o" || { bad "deployed $id $*: the refusal must name '$t' — got: $(head -c 300 <<<"$o")"; x_fail=1; }; done
  [ "$(sha256sum < "$(lc_entry "$lc_t" "$id")")" = "$s" ] || { bad "a refused deployed $id $* must leave the entry unchanged"; x_fail=1; }
}
lc_dr HEF-1 "$lc_orig" stg -- --env stg --commit "$lc_orig"            # the item's own commit is not in stg: both refs named
lc_dr HEF-1 qa 'main, stg, prod' -- --env qa --commit "$lc_cp"         # an env outside the model lists the valid ones
lc_dr HEF-2 'human:merge' -- --env stg --commit "$lc_cp"               # an open human:* block (note 17)
lc_dr HEF-1 'deadbee' -- --env stg --commit deadbee                    # not a commit here
lc_o="$(lc "$lc_t" deployed HEF-1 --env stg --commit "${lc_cp:0:8}" 2>&1)" || { bad "deployed with the cherry-picked commit must pass — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
jq -e --arg c "$lc_cp" '.phase == "merged" and .deployments.stg.commit == $c and (.deployments.stg.at | type == "string")
  and (.events[-1] | .kind == "deployed" and (.note | contains($c[0:12])))' "$(lc_entry "$lc_t" HEF-1)" >/dev/null 2>&1 \
  || { bad "deployed stg must store the FULL sha and an event, and a non-final env leaves the phase — got: $(jq -c '{phase, deployments, events}' "$(lc_entry "$lc_t" HEF-1)" | head -c 400)"; x_fail=1; }
grep -qxF "stg: yes (deployed ${lc_cp:0:12})" <<<"$(lc "$lc_t" where HEF-1 2>&1)" || { bad "where must print 'stg: yes (deployed <sha12>)' — got: $(lc "$lc_t" where HEF-1 2>&1 | head -c 300)"; x_fail=1; }
lc_o="$(lc "$lc_t" deployed HEF-1 --env prod --commit "$lc_cp" 2>&1)" || { bad "deployed prod (the final env) must pass — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
jq -e '.phase == "released" and .owner == null and (.deployments | keys == ["prod", "stg"]) and any(.events[]; .kind == "owner-released")' "$(lc_entry "$lc_t" HEF-1)" >/dev/null 2>&1 \
  || { bad "deployed on the final env must advance a merged item to released and release its owner — got: $(jq -c '{phase, owner, deployments}' "$(lc_entry "$lc_t" HEF-1)" | head -c 400)"; x_fail=1; }
# FR-008's other half: `advance released` accepts the final env's release record in place of branch ancestry. HEF-3 is
# deployed to prod while still at pr (no auto-advance), then advanced by hand: hef-1 is not in prod, the record is.
# HEF-4, the control, has no record — ancestry alone still refuses it.
lc_entry_90 HEF-3 pr hef-1 3 null | lc_put "$lc_t" HEF-3
lc_entry_90 HEF-4 pr hef-1 4 null | lc_put "$lc_t" HEF-4
lc "$lc_t" deployed HEF-3 --env prod --commit "$lc_cp" >/dev/null 2>&1 && lc_jq "$lc_t" HEF-3 '.phase == "pr"' \
  || { bad "deployed prod on an unmerged item must record it and leave the phase — got: $(jq -c '{phase, deployments}' "$(lc_entry "$lc_t" HEF-3)")"; x_fail=1; }
lc_o="$(lc "$lc_t" advance HEF-3 released 2>&1)" && lc_jq "$lc_t" HEF-3 '.phase == "released"' \
  || { bad "advance released must accept the final env's release record in place of ancestry (FR-008) — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
lc_o="$(lc "$lc_t" advance HEF-4 released 2>&1)" && { bad "advance released with no release record must still need ancestry (FR-008 control)"; x_fail=1; }
grep -qF 'promote it first' <<<"$lc_o" || { bad "the ancestry refusal must stay as it was — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
# US3 Edge: a re-recorded env keeps the commit it replaces, in full, in the event history.
lc_git "$lc_t" switch -q stg && lc_git "$lc_t" commit -q --allow-empty -m later && lc_git "$lc_t" switch -q main
lc_later="$(git -C "$lc_t" rev-parse stg)"
lc "$lc_t" deployed HEF-4 --env stg --commit "$lc_cp" >/dev/null 2>&1 && lc "$lc_t" deployed HEF-4 --env stg --commit "$lc_later" >/dev/null 2>&1 \
  && jq -e --arg a "$lc_cp" --arg b "$lc_later" '.deployments.stg.commit == $b and .events[-1].replaces == $a and .events[-2].replaces == null' \
       "$(lc_entry "$lc_t" HEF-4)" >/dev/null 2>&1 \
  || { bad "re-recording an env must keep the replaced commit in full in its event (US3 Edge) — got: $(jq -c '{deployments, events}' "$(lc_entry "$lc_t" HEF-4)" | head -c 400)"; x_fail=1; }
# Setup allow-lists deployed (git decides, any lane) — never an ask rule.
lc_sh="$(mktemp -d)"; (cd "$lc_t" && HOME="$lc_sh" CLAUDE_CONFIG_DIR='' bash "$REPO/hooks/hefesto-setup.sh" --lanes >/dev/null 2>&1)
jq -e --arg r "Bash($REPO/hooks/ledger.sh deployed:*)" '(.permissions.allow | index([$r])) and ((.permissions.ask // []) | map(select(contains("ledger.sh deployed"))) | length == 0)' \
  "$lc_t/.claude/settings.local.json" >/dev/null 2>&1 || { bad "setup must allow-list ledger.sh deployed (plan Revision 2 #6)"; x_fail=1; }
rm -rf -- "${lc_t:?}" "${lc_w:?}" "${lc_sh:?}"
[ "$x_fail" -eq 0 ] && ok "deployed: a cherry-picked commit in the env records the full sha and an event; where says yes (deployed <sha12>); a commit not in the env, an env outside the model, a human:* block and a non-commit are refused unchanged; the final env releases a merged item and its owner; advance released accepts the final env's record in place of ancestry; a re-recorded env keeps the replaced commit; setup allow-lists it (FR-007 FR-008)"

# --- list --active marks stale owners on every done phase (US4, FR-009) --------------------------------------------
# `.owner.stale` is computed from the phase alone: true on each of the five done phases, false on an active one, and
# shown only by `list --active` (plain `list` prints the entry as written; nothing is ever written back).
head_ "Lifecycle: list --active marks owners stale on done phases (US4)"
x_fail=0
lc_t="$(cd "$(mktemp -d)" && pwd -P)"; git -C "$lc_t" init -q -b main . && lc_git "$lc_t" commit -q --allow-empty -m init
lc_n=0
for lc_ph in merged released dropped folded superseded implement verify; do
  lc_n=$((lc_n + 1))
  lc_entry_90 "HEF-$lc_n" "$lc_ph" "hef-$lc_n" "" "{\"session_name\":\"hef-s-$lc_n\",\"role\":\"implement\",\"started\":\"2026-10-21T00:00:00Z\"}" \
    | lc_put "$lc_t" "HEF-$lc_n"
done
lc_entry_90 HEF-8 queued "" "" null | lc_put "$lc_t" HEF-8
lc_sum0="$(cat "$(sld "$lc_t")"/*.json | sha256sum)"
lc_o="$(lc "$lc_t" list --active 2>/dev/null)"
jq -e 'map({(.phase): .owner.stale}) | add == {merged: true, released: true, dropped: true, folded: true, superseded: true, implement: false, verify: false}' \
  <<<"$lc_o" >/dev/null 2>&1 \
  || { bad "list --active must set .owner.stale true on every done phase and false on implement/verify — got: $(jq -c 'map({phase, stale: .owner.stale})' <<<"$lc_o" 2>&1 | head -c 400)"; x_fail=1; }
jq -e 'all(.[]; .owner.stale | type == "boolean") and (map(.id) | index("HEF-8") | not)' <<<"$lc_o" >/dev/null 2>&1 \
  || { bad "list --active must carry a boolean .owner.stale on each owned entry and leave the unowned HEF-8 out"; x_fail=1; }
lc_o="$(lc "$lc_t" list 2>/dev/null)"
jq -e 'length == 8 and all(.[]; .owner == null or (.owner | has("stale") | not))' <<<"$lc_o" >/dev/null 2>&1 \
  || { bad "plain list must not add .owner.stale — got: $(jq -c 'map(.owner)' <<<"$lc_o" 2>&1 | head -c 300)"; x_fail=1; }
[ "$(cat "$(sld "$lc_t")"/*.json | sha256sum)" = "$lc_sum0" ] || { bad "list must never write .owner.stale back to an entry"; x_fail=1; }
rm -rf -- "${lc_t:?}"
[ "$x_fail" -eq 0 ] && ok "list --active marks .owner.stale true on merged/released/dropped/folded/superseded and false on implement/verify, computed and never written (US4 FR-009)"

# --- PR B mutation pass: the done and placeholder refusals no other part sent red (T027, SC-002) --------------------
# Five PR B mutants stayed green against parts 3–7 (the table at the top of this file): the merge done's evidence
# refusal, a train done's not-merged / unreadable-gh / unresolvable-base refusals, and the merge checks' placeholder
# refusal. Each case below is the one that sends its mutant red: a refusal naming its cause, the action left taken
# and the entry unchanged. The actions are hand-written as `take` leaves them: `done` reads only the status.
head_ "Lifecycle: merge and train done refuse without evidence; merge checks refuse an unknown placeholder (T027)"
x_fail=0
lc_t="$(cd "$(mktemp -d)" && pwd -P)"; lc_a="$lc_t/api"; git init -q --bare -b main "$lc_t/api.git" && git init -q -b main "$lc_a"
lc_git "$lc_a" commit -q --allow-empty -m init && git -C "$lc_a" remote add origin "$lc_t/api.git" && git -C "$lc_a" checkout -q -b feat \
  && lc_git "$lc_a" commit -q --allow-empty -m feat && git -C "$lc_a" push -q origin main feat 2>/dev/null && git -C "$lc_a" checkout -q main
lc_head="$(git -C "$lc_a" rev-parse feat)"; mkdir -p "$lc_t/bin" "$lc_a/.claude"; printf 'merged\n' > "$lc_t/ev.md"
# FakeGhDone: `pr view` answers from $lc_t/pr.json through -q/--jq; with no file there, gh cannot read the PR.
cat > "$lc_t/bin/gh" <<EOF
#!/bin/bash
[ "\$1 \$2" = "pr view" ] && [ -f "$lc_t/pr.json" ] || exit 1
q=""; while [ \$# -gt 0 ]; do case "\$1" in -q|--jq) q="\$2"; shift ;; esac; shift; done
if [ -n "\$q" ]; then jq -r "\$q" "$lc_t/pr.json"; else cat "$lc_t/pr.json"; fi
EOF
chmod +x "$lc_t/bin/gh"
# lc_pr <state> <base> <merge commit|"">: the fake PR acme/api#5, its head the feat commit
lc_pr() { jq -n --arg st "$1" --arg b "$2" --arg mc "$3" --arg h "$lc_head" '{number: 5, url: "https://github.com/acme/api/pull/5", state: $st,
  headRefName: "feat", baseRefName: $b, headRefOid: $h, mergeCommit: (if $mc == "" then null else {oid: $mc} end)}' > "$lc_t/pr.json"; }
lcd() { local d="$1"; shift; (cd "$d" && env -u CLAUDE_CODE_SESSION_ID HEFESTO_GH_BIN="$lc_t/bin/gh" bash "$LC_LG" "$@"); }
# lc_taken <repo dir> <aid> <entry> <scope JSON>: a taken action, as take leaves it
lc_taken() { mkdir -p "$(sld "$1")/actions" && jq -n --arg a "$2" --arg e "$3" --argjson sc "$4" '{aid: $a, entry: $e, to: "repo-deployer",
  status: "taken", at: "2026-10-28T00:00:00Z", sha256: "0000", scope: $sc, steps_done: [], taken_at: "2026-10-28T00:00:00Z"}' > "$(sld "$1")/actions/$2.json"; }
lc_done_no() { # lc_done_no <repo dir> <aid> <entry> <text the refusal must name>: refused, the action taken, the entry unchanged
  local f o before; f="$(sld "$1")/$3.json"; before="$(sha256sum < "$f")"
  o="$(lcd "$1" action "done" "$2" --evidence-file "$lc_t/ev.md" 2>&1)" && { bad "action done $2 must be refused ($4)"; x_fail=1; }
  grep -qF -- "$4" <<<"$o" || { bad "the refusal of action done $2 must name '$4' — got: $(head -c 300 <<<"$o")"; x_fail=1; }
  jq -e '.status == "taken"' "$(sld "$1")/actions/$2.json" >/dev/null 2>&1 && [ "$(sha256sum < "$f")" = "$before" ] \
    || { bad "a refused done must leave $2 taken and $3 unchanged"; x_fail=1; }
}
# lc_scope <kind> <pr|null> <steps JSON>: the scope request drafts, pinned to the feat head
lc_scope() { jq -nc --arg h "$lc_head" --arg k "$1" --argjson pr "$2" --argjson st "$3" '{title: "\($k) acme/api#5", kind: $k, repo: null, pr: $pr, steps: $st,
  heads: {"acme/api#5": $h}, commands: [{cmd: "gh pr merge 5 -R acme/api --merge --match-head-commit \($h)", after_step: 1}], expects: []}'; }
lc_entry_90 HEF-1 pr feat 5 null | jq '.pr.url = "https://github.com/acme/api/pull/5" | .blocked_on = {kind: "human:merge", since: "2026-10-27T00:00:00Z"}' | lc_put "$lc_a" HEF-1
# FR-020, note 16: a merge check's placeholder outside {repo_path} and {base} is refused at request, and no action written
jq -n '{name: "api", orchestrate: {merge_by: "lane", merge: {checks: ["changelog-check.sh -C {repo_path} placement --base origin/{branch}"]}}}' > "$lc_a/.claude/project-status.json"
lc_pr OPEN main ""; lc_o="$(lcd "$lc_a" request HEF-1 --to repo-deployer --merge 2>&1)" && { bad "a merge check with {branch} must be refused"; x_fail=1; }
grep -qF 'unknown placeholder {branch}' <<<"$lc_o" || { bad "the merge-check refusal must name {branch} — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
[ ! -e "$(sld "$lc_a")/actions/HEF-1-A1.json" ] || { bad "a refused request --merge must write no action"; x_fail=1; }
# FR-021, note 4: gh says MERGED, but the merge commit is not in the integration branch — done records nothing
lc_taken "$lc_a" HEF-1-A1 HEF-1 "$(lc_scope merge 5 '["state", "merge"]')"; lc_pr MERGED main "$lc_head"; lc_done_no "$lc_a" HEF-1-A1 HEF-1 "no merge evidence"
# FR-019, note 19: a train's done checks every head through gh and its base, and fails closed on each missing fact
lc_bd="$lc_t/board"; git init -q -b main "$lc_bd" && lc_git "$lc_bd" commit -q --allow-empty -m init; mkdir -p "$lc_bd/.claude"
jq -n '{name: "board", repos: {api: {path: "../api", branches: {integration: "main", environments: ["stg", "main"]}}}}' > "$lc_bd/.claude/project-status.json"
[ "$(lcd "$lc_bd" op new --title "promote api to stg" 2>&1)" = OP-1 ] || { bad "op new must create OP-1 on the board"; x_fail=1; }
lc_taken "$lc_bd" OP-1-A1 OP-1 "$(lc_scope train null '["api: state of acme/api#5", "api: merge acme/api#5"]')"
lc_pr OPEN stg ""; lc_done_no "$lc_bd" OP-1-A1 OP-1 "acme/api#5 is OPEN, not merged"
rm -f "$lc_t/pr.json"; lc_done_no "$lc_bd" OP-1-A1 OP-1 "gh cannot read acme/api#5"
lc_pr MERGED qa "$lc_head"; lc_done_no "$lc_bd" OP-1-A1 OP-1 "base qa resolves nowhere"
rm -rf -- "${lc_t:?}"
[ "$x_fail" -eq 0 ] && ok "a merge check's unknown placeholder is refused at request; a merge done with no merge evidence and a train done on an unmerged PR, an unreadable PR or a base that resolves nowhere are refused, the action taken and the entry unchanged (T027 SC-002 FR-019 FR-020 FR-021)"
