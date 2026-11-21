# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs and sed scripts are single-quoted on purpose
#
# merge-forward (HEF-31) smoke checks, part 17 — a PR behind or conflicting with its base goes back to the build
# stage: `ledger.sh forward` (the backward move pr → implement with a generated, hashed brief), its refusals, the cap,
# the person-only --past-cap, the readable conflict block, and `record --forward-consumed`.
#
# SOURCED by tests/smoke.sh after the other parts, never run on its own. Self-contained: a fixture repo with a bare
# origin and a worktree per entry at <top>/.claude/worktrees/<id> (the implement launch's own path), a named fake gh
# (FakeGh: `pr view` from $fw_t/pr.json — fw_gh switches it between DIRTY / BEHIND / CLEAN / UNKNOWN — and
# `pr checks` from $fw_t/checks.json), a fake claude reading $fw_t/result.json (for the launcher cases), the real
# ledger.sh, and fw_mut: a scratch copy of the hooks folder with ONE file mutated by sed, cmp -s proving it applied.

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ sld >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-forward.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_, sld)"
  else echo "tests/smoke-forward.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

# --- the fixture (T001): repo, origin, FakeGh, fake claude, entries, worktrees, mutation helper ---------------------
fw_t="$(cd "$(mktemp -d)" && pwd -P)"; fw_w="$fw_t/w"; fw_url="https://github.com/acme/app/pull/7"
fw_g() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
git init -q --bare -b main "$fw_t/origin.git" && git init -q -b main "$fw_w" && fw_g "$fw_w" commit -q --allow-empty -m init \
  && git -C "$fw_w" remote add origin "$fw_t/origin.git" && git -C "$fw_w" push -q origin main 2>/dev/null
mkdir -p "$fw_t/bin" "$fw_t/cfg" "$fw_w/.claude"; printf '{"name":"app"}\n' > "$fw_w/.claude/project-status.json"
printf '[]\n' > "$fw_t/checks.json"
# FakeGh: `pr view` answers from $fw_t/pr.json (through -q/--jq when given) — or fails like a 502 while
# $fw_t/gh.fail exists; `pr checks` answers $fw_t/checks.json; every call is logged.
cat > "$fw_t/bin/gh" <<EOF
#!/bin/bash
echo "\$*" >> "$fw_t/gh.log"
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "pr checks") cat "$fw_t/checks.json"; exit 0 ;;
  "pr view") [ ! -f "$fw_t/gh.fail" ] || { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
             q=""; while [ \$# -gt 0 ]; do case "\$1" in -q|--jq) q="\$2"; shift ;; esac; shift; done
             if [ -n "\$q" ]; then jq -r "\$q" "$fw_t/pr.json"; else cat "$fw_t/pr.json"; fi
             # a second read sees \$fw_t/pr.then.json when one waits (the DIRTY-then-UNKNOWN fixture, D14)
             [ ! -f "$fw_t/pr.then.json" ] || mv "$fw_t/pr.then.json" "$fw_t/pr.json" ;;
  *) echo "FakeGh: unexpected gh \$*" >&2; exit 1 ;;
esac
EOF
# The fake claude (the launcher cases, smoke.sh's sr pattern): logs its argv and prints $fw_t/result.json.
cat > "$fw_t/bin/claude" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$fw_t/claude.log"
cat "$fw_t/result.json"
EOF
chmod +x "$fw_t/bin/gh" "$fw_t/bin/claude"
fw_ld="$(sld "$fw_w")"; mkdir -p "$fw_ld"
fw_gh() { # fw_gh <mergeStateStatus> <head branch> [head sha] [base] [state] → the fake PR #7
  jq -n --arg ms "$1" --arg h "$2" --arg o "${3:-}" --arg b "${4:-main}" --arg st "${5:-OPEN}" --arg u "$fw_url" \
    '{number: 7, url: $u, state: $st, isDraft: false, mergeable: "MERGEABLE", mergeStateStatus: $ms, reviewDecision: "",
      headRefName: $h, baseRefName: $b, headRefOid: (if $o == "" then "0123456789abcdef0123456789abcdef01234567" else $o end)}' > "$fw_t/pr.json"
}
fw_entry() { # fw_entry <id> [blocked kind | none] [jq filter] → a pr entry on PR #7 (attempts 2, so the reset shows)
  jq -n --arg id "$1" --arg k "${2:-human:merge}" --arg u "$fw_url" '{id: $id, item_kind: "feature", phase: "pr", owner: null, route: "full",
    pr: {url: $u, number: 7}, prs: [{url: $u, number: 7}], runs: [], attempts: 2, verdicts: [], updated: (now | todate),
    blocked_on: (if $k == "none" then null else {kind: $k, since: "2026-11-01T00:00:00Z", question_path: null} end)}' \
    | jq "${3:-.}" > "$fw_ld/$1.json"
}
fw_wt() { # fw_wt <id> <branch> [path] → a worktree on a new branch with one commit; prints its head sha
  local p="${3:-$fw_w/.claude/worktrees/$1}"
  git -C "$fw_w" worktree add -q "$p" -b "$2" main >/dev/null 2>&1 && fw_g "$p" commit -q --allow-empty -m "work $1" >/dev/null 2>&1
  git -C "$p" rev-parse HEAD
}
fw() { (cd "$fw_w" && HEFESTO_GH_BIN="$fw_t/bin/gh" bash "${FW_LG:-$REPO/hooks/ledger.sh}" "$@"); }   # fw <ledger args…>
# The launcher with the fake claude on PATH (later tasks: deploy/implement through session-launch.sh).
fw_sl() { (cd "$fw_w" && PATH="$fw_t/bin:$PATH" HEFESTO_GH_BIN="$fw_t/bin/gh" CLAUDE_CONFIG_DIR="$fw_t/cfg" bash "${FW_SL:-$REPO/hooks/session-launch.sh}" "$@"); }
fw_j() { jq -e "$2" "$fw_ld/$1.json" >/dev/null 2>&1; }   # fw_j <id> <jq test>
fw_snap() { cp "$fw_ld/$1.json" "$fw_t/snap.json"; ls -a "$fw_ld" > "$fw_t/snap.ls"; }
fw_same() { cmp -s "$fw_ld/$1.json" "$fw_t/snap.json" && [ "$(ls -a "$fw_ld")" = "$(cat "$fw_t/snap.ls")" ]; }   # entry AND folder unchanged
fw_no() { # fw_no <label> <text the refusal names> <id> <forward args…>: exit non-zero, naming it, entry byte-identical
  local l="$1" need="$2" id="$3" o; shift 3; fw_snap "$id"
  o="$(fw forward "$id" "$@" 2>&1)" && { bad "$l must be refused — got: $(head -c 300 <<<"$o")"; x_fail=1; return; }
  grep -qF -- "$need" <<<"$o" || { bad "$l: the refusal must name '$need' — got: $(head -c 300 <<<"$o")"; x_fail=1; }
  fw_same "$id" || { bad "$l: a refusal must leave the entry and the ledger folder byte-identical"; x_fail=1; }
}
fw_mut() { # fw_mut <hook file> <sed script> → FW_LG runs a hooks copy with that one file mutated (0), or bad + 1
  rm -rf "$fw_t/mut"; mkdir -p "$fw_t/mut"
  local f; for f in "$REPO"/hooks/*; do [ "$(basename "$f")" = "$1" ] || ln -s "$f" "$fw_t/mut/$(basename "$f")"; done
  sed "$2" "$REPO/hooks/$1" > "$fw_t/mut/$1"
  cmp -s "$REPO/hooks/$1" "$fw_t/mut/$1" && { bad "merge-forward mutation did not apply to $1: $2"; x_fail=1; return 1; }
  FW_LG="$fw_t/mut/ledger.sh"
}
fw_survived() { bad "mutation survived: $1 (merge-forward/FR-017)"; x_fail=1; }

# --- T003: the move (merge-forward/FR-002, FR-004), the verdict flip and the build stage picking it up --------------
head_ "Merge forward: ledger.sh forward moves a behind/conflicting pr entry to implement with a hashed brief (merge-forward FR-002 FR-003 FR-004)"
x_fail=0
fw_h1="$(fw_wt HEF-1 feat1)"; fw_entry HEF-1; fw_gh BEHIND feat1 "$fw_h1"
fw_o="$(fw forward HEF-1 --verdict behind 2>&1)" || { bad "forward HEF-1 on a BEHIND PR must pass — got: $(head -c 300 <<<"$fw_o")"; x_fail=1; }
[ "$fw_o" = "HEF-1 pr → implement (merge forward #1, behind)" ] || { bad "forward must print one line naming the move (merge-forward/FR-002) — got: $fw_o"; x_fail=1; }
jq -e --arg h "$fw_h1" --arg u "$fw_url" '.phase == "implement" and .owner == null and .attempts == 0 and .blocked_on == null
  and (.forwards | length) == 1 and .forwards[0].n == 1 and .forwards[0].pr_url == $u and .forwards[0].head_sha == $h
  and .forwards[0].head_branch == "feat1" and .forwards[0].base == "main" and .forwards[0].verdict == "behind"
  and .forwards[0].consumed == false and .forwards[0].by == null and (.forwards[0].at | length) > 0
  and any(.events[]; .kind == "forward" and .verdict == "behind" and .pr_url == $u and .head_sha == $h)' "$fw_ld/HEF-1.json" >/dev/null 2>&1 \
  || { bad "forward must set implement, owner null, attempts 0, no block, one .forwards row {n, pr_url, head_sha, head_branch, base, verdict, sha256, at, by, consumed} and a forward event (merge-forward/FR-002) — got: $(jq -c '{phase, owner, attempts, blocked_on, forwards, events}' "$fw_ld/HEF-1.json" | head -c 600)"; x_fail=1; }
fw_b="$fw_ld/HEF-1.forward-1.md"
{ [ -f "$fw_b" ] && [ ! -L "$fw_b" ] && [ "$(jq -r '.forwards[0].sha256' "$fw_ld/HEF-1.json")" = "$(sha256sum < "$fw_b" | cut -c1-64)" ] \
  && grep -qF "$fw_url" "$fw_b" && grep -qF "$fw_h1" "$fw_b" && grep -qF 'Base branch: main' "$fw_b" && grep -qF 'Head branch: feat1' "$fw_b" \
  && grep -qF 'Verdict: behind' "$fw_b" && grep -qF 'never a rebase' "$fw_b"; } \
  || { bad "forward must write the generated brief <id>.forward-1.md (PR URL, head sha, head and base branch, verdict) with its sha256 in the row (merge-forward/FR-004) — got: $(head -c 400 "$fw_b" 2>&1)"; x_fail=1; }
[ "$(fw next --stage build 2>/dev/null)" = HEF-1 ] || { bad "a forwarded entry must be the build stage's: next --stage build returns it (US1) — got '$(fw next --stage build 2>&1)'"; x_fail=1; }
# D3: git decides — --verdict conflict while the PR reads BEHIND moves it, the LIVE verdict recorded
fw_h2="$(fw_wt HEF-2 feat2)"; fw_entry HEF-2; fw_gh BEHIND feat2 "$fw_h2"
fw_o="$(fw forward HEF-2 --verdict conflict 2>&1)" || { bad "forward --verdict conflict on a live BEHIND PR must move it (D3) — got: $(head -c 300 <<<"$fw_o")"; x_fail=1; }
fw_j HEF-2 '.phase == "implement" and .forwards[0].verdict == "behind"' || { bad "the live verdict (behind), not the caller's (conflict), is recorded (merge-forward/FR-002, D3) — got: $(jq -c .forwards "$fw_ld/HEF-2.json")"; x_fail=1; }
# a legacy conflict block (before this release) is one a forward may clear (D12); DIRTY reads conflict
fw_h3="$(fw_wt HEF-3 feat3)"; fw_entry HEF-3 conflict; fw_gh DIRTY feat3 "$fw_h3"
fw_o="$(fw forward HEF-3 --verdict conflict 2>&1)" || { bad "forward on a conflict-blocked entry whose PR is DIRTY must move it (D12) — got: $(head -c 300 <<<"$fw_o")"; x_fail=1; }
fw_j HEF-3 '.phase == "implement" and .blocked_on == null and .forwards[0].verdict == "conflict"' || { bad "a conflict block is cleared by the move (merge-forward/FR-002, D12) — got: $(jq -c '{phase, blocked_on}' "$fw_ld/HEF-3.json")"; x_fail=1; }
# answers to an earlier question never steer a merge forward: forward consumes them all
fw_h4="$(fw_wt HEF-4 feat4)"; fw_entry HEF-4 none '.answers = [{path: "/x/a1.md", sha256: "aa", by: "Ana", kind: "human:clarify", at: "2026-11-01T00:00:00Z"}, {path: "/x/a2.md", sha256: "bb", by: "Ana", kind: "human:clarify", at: "2026-11-02T00:00:00Z", consumed: true}]'
fw_gh BEHIND feat4 "$fw_h4"; fw forward HEF-4 --verdict behind >/dev/null 2>&1 || { bad "forward HEF-4 must pass"; x_fail=1; }
fw_j HEF-4 '.phase == "implement" and (.answers | length) == 2 and all(.answers[]; .consumed == true)' \
  || { bad "forward must mark every earlier answer consumed (merge-forward/FR-002) — got: $(jq -c .answers "$fw_ld/HEF-4.json")"; x_fail=1; }
# a lane's interactive claim (no pid) is no refusal: the lane babysit forwards while it holds the entry; owner released
fw_h5="$(fw_wt HEF-5 feat5)"; fw_entry HEF-5 human:merge '.owner = {session_name: "repo-deployer", role: "deploy", started: "2026-11-01T00:00:00Z", mode: "interactive"}'
fw_gh DIRTY feat5 "$fw_h5"; fw forward HEF-5 --verdict conflict >/dev/null 2>&1 || { bad "forward under a lane's interactive claim must pass (merge-forward/FR-003)"; x_fail=1; }
fw_j HEF-5 '.phase == "implement" and .owner == null' || { bad "forward under an interactive claim must release it (merge-forward/FR-002) — got: $(jq -c .owner "$fw_ld/HEF-5.json")"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "forward: a BEHIND/DIRTY pr entry → implement, unowned, unblocked, attempts 0, one .forwards row with the live verdict, a forward event, the generated brief hashed beside the entry, earlier answers consumed, a lane's interactive claim released; next --stage build returns it (merge-forward/FR-002 merge-forward/FR-004 merge-forward/FR-003 D3 D12)"

# --- T003: every refusal exits non-zero, names what it saw, and changes nothing (SC-003, merge-forward/FR-003) -------
head_ "Merge forward: refusals leave the entry byte-identical (merge-forward FR-003, SC-003)"
x_fail=0
fw_h6="$(fw_wt HEF-6 feat6)"; fw_gh BEHIND feat6 "$fw_h6"
fw_entry HEF-6 none '.phase = "verify"';            fw_no "forward on a verify entry" "not pr" HEF-6 --verdict behind
fw_entry HEF-6 none '.pr = null | .prs = []';      fw_no "forward with no PR URL" "no PR URL" HEF-6 --verdict behind
fw_entry HEF-6 none '.phase = "dropped" | .terminal = {kind: "dropped"}'; fw_no "forward on a dropped entry" "closed item" HEF-6 --verdict behind
fw_entry HEF-6;                                    fw_no "forward --verdict mergeable" "--verdict must be conflict or behind" HEF-6 --verdict mergeable
fw_no "forward without --verdict" "--verdict must be conflict or behind" HEF-6
fw_no "forward --by without --past-cap" "--by goes with --past-cap only" HEF-6 --verdict behind --by Ana
for fw_k in human:intake human:clarify human:plan-approval human:plan-review ci stall budget verdict; do
  fw_entry HEF-6 "$fw_k"; fw_no "forward on a $fw_k block (D12)" "blocked on $fw_k" HEF-6 --verdict behind
done
fw_entry HEF-6 human:merge '.owner = {session_name: "deploy-HEF-6", role: "deploy", started: "2026-11-01T00:00:00Z", pid: 4242}'
fw_no "forward while a headless run holds it" "live headless run" HEF-6 --verdict behind
fw_entry HEF-6; mkdir -p "$fw_ld/actions"
for fw_s in approved taken; do
  jq -n --arg s "$fw_s" '{aid: "HEF-6-A1", entry: "HEF-6", status: $s, scope: {kind: "merge"}}' > "$fw_ld/actions/HEF-6-A1.json"
  fw_no "forward while a merge action is $fw_s" "HEF-6-A1 ($fw_s)" HEF-6 --verdict behind
done; rm -f "$fw_ld/actions/HEF-6-A1.json"
fw_o="$(cd "$fw_w" && HEFESTO_WORKER=1 HEFESTO_GH_BIN="$fw_t/bin/gh" bash "$REPO/hooks/ledger.sh" forward HEF-6 --verdict behind 2>&1)" \
  && { bad "forward under HEFESTO_WORKER=1 must be refused (merge-forward/FR-003)"; x_fail=1; }
grep -qF 'never from inside a launched worker' <<<"$fw_o" || { bad "the worker refusal must say so — got: $(head -c 300 <<<"$fw_o")"; x_fail=1; }
fw_same HEF-6 || { bad "the worker refusal must leave the entry byte-identical (SC-003)"; x_fail=1; }
# the live verdict decides: a mergeable (CLEAN) or pending (UNKNOWN) PR stays on its gate; a failed read changes nothing
fw_gh CLEAN feat6 "$fw_h6";   fw_no "forward on a human:merge entry whose PR is CLEAN (SC-003)" "is 'mergeable' now" HEF-6 --verdict conflict
fw_gh UNKNOWN feat6 "$fw_h6"; fw_no "forward while GitHub recomputes (UNKNOWN)" "is 'pending' now" HEF-6 --verdict behind
fw_gh BEHIND feat6 "$fw_h6"; touch "$fw_t/gh.fail"; fw_no "forward when pr-watch.sh state fails" "pr-watch.sh state" HEF-6 --verdict behind; rm -f "$fw_t/gh.fail"
# the ref names go into the brief and the worker's push: an option-like or malformed name is refused, nothing written
fw_gh BEHIND -x "$fw_h6";   fw_no "a head branch named -x" "head branch '-x' is not a valid branch name" HEF-6 --verdict behind
fw_gh BEHIND a..b "$fw_h6"; fw_no "a head branch named a..b" "head branch 'a..b' is not a valid branch name" HEF-6 --verdict behind
fw_gh BEHIND feat6 "$fw_h6" 'ma in'; fw_no "a base branch with a space" "base branch 'ma in'" HEF-6 --verdict behind
fw_gh BEHIND feat6 nothex;  fw_no "a head commit that is not a sha" "head commit 'nothex'" HEF-6 --verdict behind
# a stopped merge action is no longer open: the merge path forwards right after merge_stop (T008)
jq -n '{aid: "HEF-6-A1", entry: "HEF-6", status: "stopped", scope: {kind: "merge"}}' > "$fw_ld/actions/HEF-6-A1.json"; fw_gh BEHIND feat6 "$fw_h6"
fw forward HEF-6 --verdict behind >/dev/null 2>&1 && fw_j HEF-6 '.phase == "implement"' || { bad "a stopped merge action must not refuse the forward (merge-forward/FR-003)"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "forward refuses, byte-identical, naming what it saw: not pr, no PR URL, closed, a bad --verdict, --by alone, every D12 block kind, a live headless owner, an approved/taken merge action, HEFESTO_WORKER, a live CLEAN/UNKNOWN PR, a failed state read, a bad head/base name or head sha (merge-forward/FR-003 SC-003)"

# --- T003 + T006: no usable worktree → a readable conflict block, phase pr (merge-forward/FR-005a, FR-015) ----------
head_ "Merge forward: no worktree on the head branch → a conflict block ledger.sh questions reads (merge-forward FR-005a FR-015)"
x_fail=0
fw_no_wt() { # fw_no_wt <label> <id> <branch>: forward exits 0, blocks conflict with the reason, never moves
  local o; o="$(fw forward "$2" --verdict behind 2>&1)" || { bad "$1: forward must exit 0 with a conflict block — got: $(head -c 300 <<<"$o")"; x_fail=1; return; }
  grep -qF "$2 blocked_on conflict (no worktree on $3 to merge forward in:" <<<"$o" || { bad "$1: forward must say it blocked conflict for the missing worktree — got: $o"; x_fail=1; }
  fw_j "$2" '.phase == "pr" and .blocked_on.kind == "conflict" and (.blocked_on.question_path | type) == "string" and (.forwards // []) == []' \
    || { bad "$1: the entry stays in pr, blocked conflict with a question_path, no forward row (merge-forward/FR-005a) — got: $(jq -c '{phase, blocked_on, forwards}' "$fw_ld/$2.json")"; x_fail=1; }
  o="$(fw questions "$2" 2>&1)"
  grep -qF "no worktree on $3" <<<"$o" && grep -qF "$fw_w/.claude/worktrees/$2" <<<"$o" && grep -qF 'untrusted-questions-begin' <<<"$o" \
    || { bad "$1: ledger.sh questions must serve the conflict block's reason (merge-forward/FR-005a merge-forward/FR-015) — got: $(head -c 300 <<<"$o")"; x_fail=1; }
}
fw_entry HEF-7; fw_gh BEHIND feat7; fw_no_wt "no directory at the launch path" HEF-7 feat7
fw_h8="$(fw_wt HEF-8 other8)"; fw_entry HEF-8; fw_gh BEHIND feat8 "$fw_h8"; fw_no_wt "the launch path on another branch" HEF-8 feat8
mkdir -p "$fw_w/.claude/worktrees/HEF-9"; fw_entry HEF-9; fw_gh BEHIND main; fw_no_wt "a plain folder (the main checkout's branch)" HEF-9 main
# handed off: .worktree records a real worktree elsewhere on the head branch, the launch path is absent — still no move
fw_h10="$(fw_wt HEF-10 feat10 "$fw_t/elsewhere10")"; fw_entry HEF-10
jq --arg p "$fw_t/elsewhere10" '.worktree = $p' "$fw_ld/HEF-10.json" > "$fw_t/e10" && mv "$fw_t/e10" "$fw_ld/HEF-10.json"
fw_gh BEHIND feat10 "$fw_h10"; fw_no_wt "a handed-off entry whose .worktree is elsewhere" HEF-10 feat10
# a legacy conflict block (no question_path) keeps the "waits on" refusal; human:merge is no question either
fw_entry HEF-11 conflict; fw_o="$(fw questions HEF-11 2>&1)" && { bad "questions on a legacy conflict block (no question_path) must be refused (merge-forward/FR-015)"; x_fail=1; }
grep -qF 'it waits on conflict' <<<"$fw_o" || { bad "a legacy conflict keeps the 'waits on' message — got: $(head -c 300 <<<"$fw_o")"; x_fail=1; }
fw_entry HEF-11 human:merge '.blocked_on.question_path = "/etc/hostname"'; fw questions HEF-11 >/dev/null 2>&1 && { bad "questions must stay refused on a human:merge block, question_path or not"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "forward with no usable worktree (absent, another branch, a plain folder, handed off elsewhere) blocks conflict with the reason in a question file, phase pr, exit 0; ledger.sh questions serves it, a legacy conflict keeps 'waits on' (merge-forward/FR-005a merge-forward/FR-015)"

# --- T004: the cap of 3 forwards per PR URL, and the person's --past-cap (merge-forward/FR-005) -----------------------
head_ "Merge forward: 3 forwards per PR, then a conflict block; --past-cap --by is a person's, orchestrator lane only (merge-forward FR-005)"
x_fail=0
fw_rows() { # fw_rows <url> <count> → a jq filter adding that many consumed forward rows on that URL
  printf '.forwards = [range(%s) | {n: (. + 1), pr_url: "%s", head_sha: "x", head_branch: "b", base: "main", verdict: "conflict", sha256: "s", at: "2026-11-01T00:00:00Z", by: null, consumed: true}]' "$2" "$1"
}
fw_h12="$(fw_wt HEF-12 feat12)"; fw_entry HEF-12 human:merge "$(fw_rows "$fw_url" 3)"; fw_gh DIRTY feat12 "$fw_h12"
fw_o="$(fw forward HEF-12 --verdict conflict 2>&1)" || { bad "the 4th forward must exit 0 with a conflict block — got: $(head -c 300 <<<"$fw_o")"; x_fail=1; }
grep -qF "HEF-12 blocked_on conflict (merge forward cap 3 reached for $fw_url" <<<"$fw_o" || { bad "the 4th forward must say the cap was reached (merge-forward/FR-005) — got: $fw_o"; x_fail=1; }
fw_j HEF-12 '.phase == "pr" and .blocked_on.kind == "conflict" and (.forwards | length) == 3' || { bad "at the cap the entry stays in pr, blocked conflict, 3 rows (merge-forward/FR-005) — got: $(jq -c '{phase, blocked_on}' "$fw_ld/HEF-12.json")"; x_fail=1; }
grep -qF 'cap 3 reached' <<<"$(fw questions HEF-12 2>&1)" || { bad "the cap block's reason must be readable through ledger.sh questions (merge-forward/FR-015)"; x_fail=1; }
fw_no "--past-cap without --by" "needs --by <your name>" HEF-12 --verdict conflict --past-cap
fw_o="$(fw forward HEF-12 --verdict conflict --past-cap --by p 2>&1)" || { bad "--past-cap --by p must forward past the cap — got: $(head -c 300 <<<"$fw_o")"; x_fail=1; }
fw_j HEF-12 '.phase == "implement" and (.forwards | length) == 4 and .forwards[3].by == "p" and .forwards[3].n == 4 and any(.events[]; .kind == "forward" and .by == "p")' \
  || { bad "--past-cap must record by in the row and the event (merge-forward/FR-005) — got: $(jq -c '.forwards[3]' "$fw_ld/HEF-12.json")"; x_fail=1; }
# --past-cap skips the count only: a live CLEAN PR is still refused
fw_entry HEF-13 human:merge "$(fw_rows "$fw_url" 3)"; fw_h13="$(fw_wt HEF-13 feat13)"; fw_gh CLEAN feat13 "$fw_h13"
fw_no "--past-cap on a live CLEAN PR" "is 'mergeable' now" HEF-13 --verdict conflict --past-cap --by p
# a new PR URL counts from zero
fw_entry HEF-13 human:merge "$(fw_rows "https://github.com/acme/app/pull/6" 3)"; fw_gh BEHIND feat13 "$fw_h13"
fw forward HEF-13 --verdict behind >/dev/null 2>&1 && fw_j HEF-13 '.phase == "implement" and (.forwards | length) == 4' \
  || { bad "a forward on a new PR URL counts from zero (merge-forward/FR-005) — got: $(jq -c '{phase, blocked_on}' "$fw_ld/HEF-13.json")"; x_fail=1; }
# lanes: --past-cap records a person's decision → the orchestrator lane only; a plain forward is any lane's
mkdir -p "$HOME/.cache/hefesto/sessions"
jq -nc --arg l "$fw_ld" '{title: "repo-deployer", role: "deploy", name: "repo-deployer", lanes: true, worker: false, ledger: $l}' > "$HOME/.cache/hefesto/sessions/sid-fw-deployer-0001.json"
jq -nc --arg l "$fw_ld" '{title: "repo-orchestrator", role: "orchestrator", name: "repo-orchestrator", lanes: true, worker: false, ledger: $l}' > "$HOME/.cache/hefesto/sessions/sid-fw-orch-0001.json"
fw_lane() { local s="$1"; shift; (cd "$fw_w" && CLAUDE_CODE_SESSION_ID="$s" HEFESTO_GH_BIN="$fw_t/bin/gh" bash "${FW_LG:-$REPO/hooks/ledger.sh}" "$@"); }
fw_h14="$(fw_wt HEF-14 feat14)"; fw_gh DIRTY feat14 "$fw_h14"; fw_entry HEF-14 conflict "$(fw_rows "$fw_url" 3)"; fw_snap HEF-14
fw_o="$(fw_lane sid-fw-deployer-0001 forward HEF-14 --verdict conflict --past-cap --by p 2>&1)" && { bad "--past-cap from the deployer lane must be refused (merge-forward/FR-005)"; x_fail=1; }
grep -qF "records a person's decision" <<<"$fw_o" && fw_same HEF-14 || { bad "--past-cap from a lane: refused as a person's decision, entry unchanged — got: $(head -c 300 <<<"$fw_o")"; x_fail=1; }
fw_lane sid-fw-orch-0001 forward HEF-14 --verdict conflict --past-cap --by p >/dev/null 2>&1 && fw_j HEF-14 '.phase == "implement" and .forwards[3].by == "p"' \
  || { bad "--past-cap from the orchestrator lane must be admitted (merge-forward/FR-005)"; x_fail=1; }
fw_h15="$(fw_wt HEF-15 feat15)"; fw_gh BEHIND feat15 "$fw_h15"; fw_entry HEF-15
fw_lane sid-fw-deployer-0001 forward HEF-15 --verdict behind >/dev/null 2>&1 && fw_j HEF-15 '.phase == "implement"' \
  || { bad "a plain forward from the deployer lane is mechanical routing and must be admitted (D3)"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "the 4th forward on a PR URL blocks conflict (readable reason), --past-cap --by forwards past it recording by, still refuses a CLEAN PR, a new URL counts from zero; --past-cap is refused from a non-orchestrator lane and admitted from the orchestrator lane (merge-forward/FR-005)"

# --- T005: record --forward-consumed (merge-forward/FR-010) ----------------------------------------------------------
head_ "Merge forward: record --forward-consumed marks every forward row consumed (merge-forward FR-010)"
x_fail=0
fw record HEF-1 --forward-consumed >/dev/null 2>&1 && fw_j HEF-1 '(.forwards | length) == 1 and all(.forwards[]; .consumed == true)' \
  || { bad "record --forward-consumed must mark every .forwards row consumed (merge-forward/FR-010) — got: $(jq -c .forwards "$fw_ld/HEF-1.json")"; x_fail=1; }
fw_entry HEF-16; jq -S 'del(.updated)' "$fw_ld/HEF-16.json" > "$fw_t/e16.before"
fw record HEF-16 --forward-consumed >/dev/null 2>&1 || { bad "record --forward-consumed on an entry with no forwards must pass"; x_fail=1; }
{ jq -S 'del(.updated)' "$fw_ld/HEF-16.json" | cmp -s - "$fw_t/e16.before" && ! fw_j HEF-16 'has("forwards")'; } \
  || { bad "record --forward-consumed must leave an entry with no .forwards unchanged — no empty array (merge-forward/FR-010) — got: $(jq -c .forwards "$fw_ld/HEF-16.json")"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "record --forward-consumed marks every .forwards row consumed and leaves an entry with none unchanged (merge-forward/FR-010)"

# --- FR-017: every guard above, reintroduced as a defect in a scratch copy, turns its assertion red ------------------
head_ "Merge forward mutations: each guard removed on a scratch copy is caught (merge-forward FR-017, SC-004)"
x_fail=0
fw_mut_moves() { # fw_mut_moves <label> <id> <forward args…>: under the mutant, an entry that must be refused moves
  local l="$1" id="$2"; shift 2
  fw forward "$id" "$@" >/dev/null 2>&1; fw_same "$id" && fw_survived "$l"
}
# the phase guard
fw_entry HEF-6 none '.phase = "verify"'; fw_gh BEHIND feat6 "$fw_h6"; rm -f "$fw_ld/actions/HEF-6-A1.json"; fw_snap HEF-6
fw_mut ledger-lifecycle.sh 's/\[ "\$ph" = pr \] ||/true ||/' && fw_mut_moves "the phase guard dropped, yet a verify entry was refused" HEF-6 --verdict behind
# the live-verdict check
fw_entry HEF-6; fw_gh CLEAN feat6 "$fw_h6"; fw_snap HEF-6
fw_mut ledger-lifecycle.sh 's/case "\$live" in conflict|behind) ;;/case "$live" in *) ;;/' && fw_mut_moves "any live verdict accepted, yet a CLEAN PR stayed on human:merge" HEF-6 --verdict conflict
# the D12 block kinds
fw_entry HEF-6 human:intake; fw_gh BEHIND feat6 "$fw_h6"; fw_snap HEF-6
fw_mut ledger-lifecycle.sh 's/case "\$bk" in ""|human:merge|conflict) ;;/case "$bk" in *) ;;/' && fw_mut_moves "the D12 block-kind refusal dropped, yet a human:intake entry was refused" HEF-6 --verdict behind
# the merge-action refusal
fw_entry HEF-6; jq -n '{aid: "HEF-6-A1", entry: "HEF-6", status: "approved", scope: {kind: "merge"}}' > "$fw_ld/actions/HEF-6-A1.json"; fw_snap HEF-6
fw_mut ledger-lifecycle.sh 's/^  forward_merge_action_refuse "\$1"$/  true/' && fw_mut_moves "the merge-action refusal dropped, yet an approved merge action blocked the forward" HEF-6 --verdict behind
rm -f "$fw_ld/actions/HEF-6-A1.json"
# the headless-owner refusal
fw_entry HEF-6 human:merge '.owner = {session_name: "deploy-HEF-6", role: "deploy", started: "2026-11-01T00:00:00Z", pid: 4242}'; fw_snap HEF-6
fw_mut ledger-lifecycle.sh "s/'.owner.pid \/\/ empty'/'.owner.pidX \/\/ empty'/" && fw_mut_moves "the pid guard dropped, yet a headless-held entry was refused" HEF-6 --verdict behind
# the worker refusal
fw_entry HEF-6; fw_snap HEF-6
if fw_mut ledger-lifecycle.sh '/never from inside a launched worker — the launcher forwards/s/|| die/|| true/'; then
  (cd "$fw_w" && HEFESTO_WORKER=1 HEFESTO_GH_BIN="$fw_t/bin/gh" bash "$FW_LG" forward HEF-6 --verdict behind) >/dev/null 2>&1
  fw_same HEF-6 && fw_survived "the worker refusal dropped, yet HEFESTO_WORKER=1 was refused"
fi
# the ref-name check
fw_entry HEF-6; fw_gh BEHIND -x "$fw_h6"; fw_snap HEF-6
fw_mut ledger-lifecycle.sh 's/^  forward_refs_ok "\$1" "\$st"$/  true/' && { fw forward HEF-6 --verdict behind >/dev/null 2>&1; fw_same HEF-6 && fw_survived "the ref-name check dropped, yet a head branch named -x wrote nothing"; }
# the worktree test, its branch comparison, and the launch path (not .worktree)
fw_entry HEF-7; fw_gh BEHIND feat7; fw_snap HEF-7
fw_mut ledger-lifecycle.sh 's/forward_worktree_ok "\$wt" "\$hb" ||/true ||/' && { fw forward HEF-7 --verdict behind >/dev/null 2>&1; fw_j HEF-7 '.phase == "implement"' || fw_survived "the worktree test dropped, yet an entry with no worktree did not move"; }
fw_entry HEF-8; fw_gh BEHIND feat8 "$fw_h8"
fw_mut ledger-lifecycle.sh '/^forward_worktree_ok()/,/^}/s/^  \[ "\$(git -C "\$1" rev-parse --abbrev-ref HEAD.*$/  true/' && { fw forward HEF-8 --verdict behind >/dev/null 2>&1; fw_j HEF-8 '.phase == "implement"' || fw_survived "the branch comparison dropped, yet a worktree on another branch did not move"; }
fw_entry HEF-10 human:merge; jq --arg p "$fw_t/elsewhere10" '.worktree = $p' "$fw_ld/HEF-10.json" > "$fw_t/e10" && mv "$fw_t/e10" "$fw_ld/HEF-10.json"; fw_gh BEHIND feat10 "$fw_h10"
fw_mut ledger-lifecycle.sh 's|wt="\$(entry_repo_top "\$e")/.claude/worktrees/\$id"|wt="$(jq -r .worktree <<<"$e")"|' && { fw forward HEF-10 --verdict behind >/dev/null 2>&1; fw_j HEF-10 '.phase == "implement"' || fw_survived "the test reads .worktree instead of the launch path, yet the handed-off entry did not move"; }
# forward consuming old answers
fw_entry HEF-4 none '.answers = [{path: "/x/a1.md", sha256: "aa", by: "Ana", kind: "human:clarify", at: "2026-11-01T00:00:00Z"}] | del(.forwards)'; fw_gh BEHIND feat4 "$fw_h4"
fw_mut ledger-lifecycle.sh 's/| (if .answers then .answers |= map(.consumed = true) else . end)$/| ./' && { fw forward HEF-4 --verdict behind >/dev/null 2>&1; fw_j HEF-4 'all(.answers[]; .consumed == true)' && fw_survived "the answers consumption dropped, yet the answers were consumed"; }
# the cap, and --past-cap's person-only gate (lane-lib.sh is_person_sub)
fw_entry HEF-12 human:merge "$(fw_rows "$fw_url" 3)"; fw_gh DIRTY feat12 "$fw_h12"
fw_mut ledger-lifecycle.sh 's/if \[ "\$past" = 0 \] && forward_cap_reached "\$e"; then/if false; then/' && { fw forward HEF-12 --verdict conflict >/dev/null 2>&1; fw_j HEF-12 '.phase == "implement"' || fw_survived "the cap dropped, yet a 4th forward was blocked"; }
fw_entry HEF-14 conflict "$(fw_rows "$fw_url" 3)"; fw_gh DIRTY feat14 "$fw_h14"; fw_snap HEF-14
fw_mut lane-lib.sh '/^    forward) shift; for a in/d' && { fw_lane sid-fw-deployer-0001 forward HEF-14 --verdict conflict --past-cap --by p >/dev/null 2>&1; fw_same HEF-14 && fw_survived "the forward case dropped from is_person_sub, yet --past-cap from the deployer lane was refused"; }
# questions_item admitting a conflict block that has a question_path (ledger-lanes.sh): HEF-12 blocked at the cap again
unset FW_LG; fw_entry HEF-12 human:merge "$(fw_rows "$fw_url" 3)"; fw_gh DIRTY feat12 "$fw_h12"; fw_o="$(fw forward HEF-12 --verdict conflict 2>&1)"
grep -qF 'cap 3 reached' <<<"$(fw questions HEF-12 2>&1)" || { bad "control: the real questions_item must serve HEF-12's cap reason before the mutation — forward said: $fw_o; questions said: $(fw questions HEF-12 2>&1 | head -c 300)"; x_fail=1; }
fw_mut ledger-lanes.sh 's/{ \[ "\$k" = conflict \] && \[ -n "\$qp" \]; } || //' && { grep -qF 'cap 3 reached' <<<"$(fw questions HEF-12 2>&1)" && fw_survived "the conflict admission dropped from questions_item, yet the cap reason was still served"; }
# record --forward-consumed (ledger.sh): the flag gone, and an empty array written where there were none
fw_entry HEF-17 none "$(fw_rows "$fw_url" 1) | .forwards[0].consumed = false"
fw_mut ledger.sh 's/      --forward-consumed)/      --forward-consumed-gone)/' && { fw record HEF-17 --forward-consumed >/dev/null 2>&1; fw_j HEF-17 '.forwards[0].consumed == true' && fw_survived "the --forward-consumed flag removed, yet the row was consumed"; }
fw_entry HEF-16
fw_mut ledger.sh 's/if .forwards then .forwards |= map(.consumed = true) else . end/.forwards = ((.forwards \/\/ []) | map(.consumed = true))/' && { fw record HEF-16 --forward-consumed >/dev/null 2>&1; fw_j HEF-16 'has("forwards") | not' && fw_survived "an empty .forwards written on an entry with none, yet none appeared"; }
unset FW_LG
[ "$x_fail" -eq 0 ] && ok "mutations caught: the phase guard, the live-verdict check, the D12 kinds, the merge-action refusal, the headless-owner and worker refusals, the ref-name check, the worktree test / its branch / the launch path, the answers consumption, the cap, --past-cap's person-only gate, questions_item's conflict admission, record --forward-consumed (merge-forward/FR-017 SC-004)"

# --- helpers for the launcher cases (T007–T012) ------------------------------------------------------------------------
fw_res() { jq -nc --argjson so "$1" '{session_id: "fw", total_cost_usd: 0, structured_output: $so}' > "$fw_t/result.json"; }   # the fake claude's result
fw_dep() { fw_res "{\"summary\":\"babysat\",\"verdict\":\"$1\",\"fixes\":0,\"questions\":0}"; }   # a babysitter's deploy outcome
fw_impl() { # fw_impl <outcome> <pr_url|null> [blocked_on|null] [question] → an implement worker's outcome (it claims route fix)
  fw_res "$(jq -nc --arg o "$1" --argjson u "$2" --argjson b "${3:-null}" --arg q "${4:-}" '{summary: "SUMMARY-AS-QUESTION merge forward", route: "fix", outcome: $o, pr_url: $u, blocked_on: $b, spec_dir: null, question: $q}')"
}
fw_pr_entry() { # fw_pr_entry <id> <branch> → a pr entry on human:merge with its worktree on <branch>; FakeGh DIRTY on it; fw_hh = its head
  fw_hh="$(fw_wt "$1" "$2")"
  fw_entry "$1" human:merge "$(printf '.worktree = "%s" | .branch = "%s"' "$fw_w/.claude/worktrees/$1" "$2")"; fw_gh DIRTY "$2" "$fw_hh"
}
fw_ready() { # fw_ready <id> <branch> → fw_pr_entry, then forwarded (phase implement, one open row)
  fw_pr_entry "$1" "$2"; fw forward "$1" --verdict conflict >/dev/null 2>&1 || { bad "fixture: forward $1 must pass"; x_fail=1; }
}
fw_calls() { touch "$fw_t/claude.log"; wc -l < "$fw_t/claude.log" | tr -d ' '; }   # how many times the fake claude ran
fw_mut_sl() { fw_mut "$@" && FW_SL="$fw_t/mut/session-launch.sh"; }   # the launcher from a hooks copy with one file mutated
fw_unmut() { unset FW_LG FW_SL; }
fw_put() { jq "$2" "$fw_ld/$1.json" > "$fw_t/e.tmp" && mv "$fw_t/e.tmp" "$fw_ld/$1.json"; }   # fw_put <id> <jq filter>: edit an entry in place

# --- T007: the headless deploy route forwards; a refusal never fails the run (merge-forward/FR-006, D14) -------------
head_ "Merge forward: deploy conflict/behind → ledger.sh forward; a refusal is a note on stderr, never an exit (merge-forward FR-006 D14)"
x_fail=0
# SC-001, first leg: the babysitter reports conflict on a DIRTY PR → the launcher forwards it to the build stage
fw_pr_entry HEF-20 feat20; fw_dep conflict
fw_o="$(fw_sl deploy HEF-20 2>&1)" || { bad "deploy reporting conflict must exit 0 — got: $(tail -c 400 <<<"$fw_o")"; x_fail=1; }
fw_j HEF-20 '.phase == "implement" and .blocked_on == null and .owner == null and (.forwards | length) == 1 and .forwards[0].verdict == "conflict"' \
  || { bad "deploy conflict must move the entry to implement with a forward row (merge-forward/FR-006 SC-001) — got: $(jq -c '{phase, blocked_on, owner, forwards}' "$fw_ld/HEF-20.json" | head -c 400)"; x_fail=1; }
grep -qF 'HEF-20 pr → implement (merge forward #1, conflict)' <<<"$fw_o" || { bad "the deploy run must say the entry was forwarded — got: $(tail -c 300 <<<"$fw_o")"; x_fail=1; }
fw_pr_entry HEF-21 feat21; fw_gh BEHIND feat21 "$fw_hh"; fw_dep behind
fw_sl deploy HEF-21 >/dev/null 2>&1 && fw_j HEF-21 '.phase == "implement" and .forwards[0].verdict == "behind"' \
  || { bad "deploy behind (the babysit schema's new verdict) must forward the entry too (merge-forward/FR-006) — got: $(jq -c '{phase, blocked_on}' "$fw_ld/HEF-21.json")"; x_fail=1; }
# D14: the babysitter reports conflict, but the PR reads CLEAN now — forward refuses, the run still exits 0
fw_pr_entry HEF-22 feat22; fw_gh CLEAN feat22 "$fw_hh"; fw_dep conflict
grep -qF '"conflict","behind","checks"' <<<"$(fw_sl deploy HEF-22 --dry-run 2>&1)" || { bad "the babysit schema's verdict enum must list behind (merge-forward/FR-006)"; x_fail=1; }
fw_o="$(fw_sl deploy HEF-22 2>&1)" || { bad "a refused forward must not fail the deploy run (D14) — got: $(tail -c 300 <<<"$fw_o")"; x_fail=1; }
grep -qF "forward refused: ledger forward HEF-22: $fw_url is 'mergeable' now" <<<"$fw_o" || { bad "the refusal must be on stderr as 'forward refused: …' (D14) — got: $(tail -c 300 <<<"$fw_o")"; x_fail=1; }
fw_j HEF-22 '.phase == "pr" and .blocked_on.kind == "human:merge" and (.forwards // []) == []' || { bad "a refused forward leaves the entry in pr on its gate (D14) — got: $(jq -c '{phase, blocked_on}' "$fw_ld/HEF-22.json")"; x_fail=1; }
# mutation: a refusal exits the run (forward_route's `|| exit 1` restored)
if fw_mut_sl session-launch-forward.sh '/^forward_route()/,/^}/s/^  else printf/  else exit 1; printf/'; then
  fw_o="$(fw_sl deploy HEF-22 2>&1)" && grep -qF 'forward refused' <<<"$fw_o" && fw_survived "forward_route exits on a refusal, yet the deploy run exited 0 saying so"
fi; fw_unmut
[ "$x_fail" -eq 0 ] && ok "deploy conflict/behind forwards the entry (phase implement, one row, the move printed); the babysit schema lists behind; a refused forward (PR CLEAN now) is 'forward refused: …' on stderr, exit 0, the entry on its gate; the exit-on-refusal mutation is caught (merge-forward/FR-006 SC-001 D14)"

# --- T007: a lane's forwarded deploy --finish (merge-forward/FR-006, D13) --------------------------------------------
head_ "Merge forward: the lane babysit forwards, then deploy --finish admits it — no run, no transcription (merge-forward FR-006 D13)"
x_fail=0
printf '{"name":"app","orchestrate":{"lane_mode":"interactive"}}\n' > "$fw_w/.claude/project-status.json"
printf '{"summary":"forwarded in step 4","verdict":"conflict","fixes":0,"questions":0}\n' > "$fw_t/out.json"
fw_d13() { # fw_d13 <id> <branch>: --prepare as the deployer lane, then the lane babysit's own forward (hef.babysit step 4)
  fw_pr_entry "$1" "$2"
  fw_sl deploy "$1" --prepare --lane repo-deployer >/dev/null 2>&1 || { bad "fixture: deploy $1 --prepare must pass — $(fw_sl deploy "$1" --prepare --lane repo-deployer 2>&1 | tail -c 300)"; x_fail=1; }
  fw forward "$1" --verdict conflict >/dev/null 2>&1 || { bad "fixture: the lane's forward of $1 must pass"; x_fail=1; }
}
fw_fin() { fw_sl deploy "$1" --finish --lane repo-deployer --outcome-file "$fw_t/out.json"; }
fw_d13 HEF-23 feat23; fw_o="$(fw_fin HEF-23 2>&1)" || { bad "--finish of a forwarded entry must exit 0 (D13) — got: $(tail -c 300 <<<"$fw_o")"; x_fail=1; }
fw_j HEF-23 '.phase == "implement" and (.forwards | length) == 1' || { bad "--finish must leave the forwarded entry in implement with one row (D13) — got: $(jq -c '{phase, forwards}' "$fw_ld/HEF-23.json" | head -c 300)"; x_fail=1; }
[ ! -e "$fw_ld/HEF-23.prepare" ] && [ ! -e "$fw_ld/HEF-23.prompt.md" ] || { bad "--finish must clean the prepare record and the prompt (D13)"; x_fail=1; }
grep -qF 'finished: HEF-23 deploy → phase implement, blocked_on none' <<<"$fw_o" || { bad "--finish must print the finished line with phase implement — got: $(head -c 300 <<<"$fw_o")"; x_fail=1; }
grep -qF 'forward refused' <<<"$fw_o" && { bad "--finish of a forwarded entry must not forward again (D13) — got: $(head -c 300 <<<"$fw_o")"; x_fail=1; }
# a builder claimed the entry between the lane's forward and its --finish: the claim survives, no run is recorded
fw_d13 HEF-24 feat24
(cd "$fw_w" && launcher bash "$REPO/hooks/ledger.sh" claim HEF-24 --session repo-builder --role implement --mode interactive) >/dev/null 2>&1 || { bad "fixture: the builder's claim of HEF-24"; x_fail=1; }
fw_n="$(jq '.runs | length' "$fw_ld/HEF-24.json")"
fw_fin HEF-24 >/dev/null 2>&1 && fw_j HEF-24 ".owner.session_name == \"repo-builder\" and (.runs | length) == $fw_n" \
  || { bad "--finish must keep a builder's claim and record no run (D13) — got: $(jq -c '{owner, runs: (.runs | length)}' "$fw_ld/HEF-24.json")"; x_fail=1; }
# a forward row older than the --prepare is not this lane's: --finish still refuses
fw_pr_entry HEF-25 feat25; fw_sl deploy HEF-25 --prepare --lane repo-deployer >/dev/null 2>&1
fw_put HEF-25 "$(fw_rows "$fw_url" 1) | .forwards[0].consumed = false | .forwards[0].at = \"2020-01-01T00:00:00Z\" | .phase = \"implement\" | .owner = null | .blocked_on = null"
fw_o="$(fw_fin HEF-25 2>&1)" && { bad "--finish with a forward row older than the prepare must be refused (D13)"; x_fail=1; }
grep -qF 'is not held by the lane repo-deployer' <<<"$fw_o" || { bad "the older-row refusal must say the entry is not held — got: $(head -c 300 <<<"$fw_o")"; x_fail=1; }
# mutations: transcribe on the forwarded path (a second forward, refused); a run recorded (the builder's claim released);
# forwarded_since_prepare dropped from the owner check
fw_d13 HEF-26 feat26
fw_mut_sl session-launch.sh 's/^    transcribe; }$/    transcribe; }; [ "$FWD" = 0 ] || transcribe/' \
  && { fw_o="$(fw_fin HEF-26 2>&1)"; grep -qF 'forward refused' <<<"$fw_o" || fw_survived "the forwarded --finish transcribes, yet no second forward was refused"; }; fw_unmut
fw_d13 HEF-27 feat27; (cd "$fw_w" && launcher bash "$REPO/hooks/ledger.sh" claim HEF-27 --session repo-builder --role implement --mode interactive) >/dev/null 2>&1
fw_mut_sl session-launch.sh 's/^  \[ "\$FWD" = 1 \] || { HEFESTO_LAUNCHER=1/  HEFESTO_LAUNCHER=1 "$LEDGER" run "$ID" --role "$ROLE" --exit 0 --usd 0 --session-id in-lane --note in-lane >\/dev\/null 2>\&1; [ "$FWD" = 1 ] || { HEFESTO_LAUNCHER=1/' \
  && { fw_fin HEF-27 >/dev/null 2>&1; fw_j HEF-27 '.owner.session_name == "repo-builder" and (.runs | length) == 0' && fw_survived "the forwarded --finish records a run, yet the builder kept its claim and no run appeared"; }; fw_unmut
fw_d13 HEF-28 feat28
fw_mut_sl session-launch.sh 's/ || { \[ "\$ROLE" = deploy \] && forwarded_since_prepare "\$E" "\$PF" && FWD=1; }//' \
  && { fw_fin HEF-28 >/dev/null 2>&1 && fw_survived "forwarded_since_prepare dropped from the owner check, yet --finish of a forwarded entry passed"; }; fw_unmut
printf '{"name":"app"}\n' > "$fw_w/.claude/project-status.json"
fw_put HEF-24 '.owner = null'; fw_put HEF-27 '.owner = null'   # the builder claims hold the repository's one implement slot
[ "$x_fail" -eq 0 ] && ok "a lane's --prepare → step-4 forward → --finish exits 0 with phase implement, one row, files cleaned, the finished line, no second forward; a builder's claim in between survives with no run; a row older than the prepare is refused; mutations caught: transcribe, run, forwarded_since_prepare dropped (merge-forward/FR-006 D13)"

# --- T008: the lane merge's state step and action stop --block conflict forward (merge-forward/FR-007, D14) ----------
head_ "Merge forward: a lane merge that finds conflict/behind sends the entry back to the build stage (merge-forward FR-007 D14)"
x_fail=0
printf '{"name":"app","orchestrate":{"merge_by":"lane"}}\n' > "$fw_w/.claude/project-status.json"; printf 'pr-watch.sh state: conflict\n' > "$fw_t/why.md"
fw_take() { # fw_take <id> <branch>: a pr entry on human:merge whose merge action <id>-A1 is approved and taken (PR CLEAN then)
  local h; fw_pr_entry "$1" "$2"; fw_gh CLEAN "$2" "$fw_hh"
  fw request "$1" --to repo-deployer --merge >/dev/null 2>&1 || { bad "fixture: request $1 --merge — $(fw request "$1" --to repo-deployer --merge 2>&1 | tail -c 300)"; x_fail=1; return 1; }
  h="$(jq -r .sha256 "$fw_ld/actions/$1-A1.json")"
  fw approve "$1-A1" --sha "${h:0:8}" --to repo-deployer --title "$(jq -r .scope.title "$fw_ld/actions/$1-A1.json")" --irreversible-confirmed --reviewed-by-human --by Ana </dev/null >/dev/null 2>&1 \
    && fw action take "$1-A1" >/dev/null 2>&1 || { bad "fixture: approve and take $1-A1"; x_fail=1; return 1; }
}
fw_unmoved() { fw_j "$1" '.phase == "pr" and (.forwards // []) == []'; }
# action stop --block conflict while GitHub recomputes (UNKNOWN), and once the PR reads CLEAN: exit 0, the refusal noted
for fw_c in "HEF-29 feat29 UNKNOWN pending" "HEF-30 feat30 CLEAN mergeable"; do
  read -r fw_i fw_br fw_ms fw_v <<<"$fw_c"
  fw_take "$fw_i" "$fw_br" || continue; fw_gh "$fw_ms" "$fw_br" "$fw_hh"
  fw_o="$(fw action stop "$fw_i-A1" --step 1 --block conflict --reason-file "$fw_t/why.md" 2>&1)" || { bad "action stop --block conflict on a $fw_ms PR must exit 0 (D14) — got: $(tail -c 300 <<<"$fw_o")"; x_fail=1; }
  grep -qF "forward refused: ledger forward $fw_i: $fw_url is '$fw_v' now" <<<"$fw_o" && grep -qF 'the orchestrator asks the person again' <<<"$fw_o" \
    || { bad "action stop on a $fw_ms PR: the closing line carries the refusal and 'the orchestrator asks the person again' — got: $(tail -c 300 <<<"$fw_o")"; x_fail=1; }
  { fw_unmoved "$fw_i" && fw_j "$fw_i" 'any(.events[]; .kind == "merge-stopped" and (.note | contains("forward refused")))'; } \
    || { bad "action stop on a $fw_ms PR: the entry stays in pr and the merge-stopped event carries the refusal (D14) — got: $(jq -c '{phase, events: [.events[]? | select(.kind == "merge-stopped")]}' "$fw_ld/$fw_i.json" | head -c 400)"; x_fail=1; }
done
# a stop on a DIRTY PR moves it, and says so
fw_take HEF-31 feat31 && { fw_gh DIRTY feat31 "$fw_hh"
  fw_o="$(fw action stop HEF-31-A1 --step 1 --block conflict --reason-file "$fw_t/why.md" 2>&1)" || { bad "action stop --block conflict on a DIRTY PR must pass"; x_fail=1; }
  grep -qF 'HEF-31 pr → implement (merge forward #1, conflict) — back to the build stage' <<<"$fw_o" && fw_j HEF-31 '.phase == "implement"' \
    || { bad "action stop --block conflict must forward and close with 'back to the build stage' (merge-forward/FR-007) — got: $(tail -c 300 <<<"$fw_o")"; x_fail=1; }; }
# merge_state_step: DIRTY on its own read, UNKNOWN on forward's — the step's stop message carries the refusal
fw_step_flip() { # fw_step_flip <id>: step 1 reads DIRTY, the forward inside it reads UNKNOWN → the step's output
  fw_gh UNKNOWN "$(jq -r .branch "$fw_ld/$1.json")" "$fw_hh"; mv "$fw_t/pr.json" "$fw_t/pr.then.json"; fw_gh DIRTY "$(jq -r .branch "$fw_ld/$1.json")" "$fw_hh"
  fw action step "$1-A1" 1 --evidence-file "$fw_t/why.md" 2>&1; rm -f "$fw_t/pr.then.json"
}
fw_take HEF-32 feat32 && { fw_o="$(fw_step_flip HEF-32)"
  grep -qF "the action is stopped before the merge; forward refused: ledger forward HEF-32: $fw_url is 'pending' now" <<<"$fw_o" \
    || { bad "merge_state_step: a forward refused on the second read is in the stop message (D14) — got: $(tail -c 400 <<<"$fw_o")"; x_fail=1; }
  jq -e '.status == "stopped"' "$fw_ld/actions/HEF-32-A1.json" >/dev/null 2>&1 && fw_unmoved HEF-32 || { bad "merge_state_step: the action stopped, the entry unchanged in pr (D14)"; x_fail=1; }; }
fw_take HEF-33 feat33 && { fw_gh DIRTY feat33 "$fw_hh"; fw_o="$(fw action step HEF-33-A1 1 --evidence-file "$fw_t/why.md" 2>&1)"
  grep -qF 'not mergeable — the action is stopped before the merge; HEF-33 pr → implement (merge forward #1, conflict)' <<<"$fw_o" && fw_j HEF-33 '.phase == "implement"' \
    || { bad "merge_state_step on a DIRTY PR must forward and say so (merge-forward/FR-007) — got: $(tail -c 300 <<<"$fw_o")"; x_fail=1; }; }
grep -qF 'goes back to the build stage' <<<"$(jq -r '.scope.steps[0]' "$fw_ld/actions/HEF-33-A1.json")" || { bad "the merge recipe's state step says a conflict goes back to the build stage (merge-forward/FR-007)"; x_fail=1; }
# mutations: each subshell dropped — the forward's die then ends the verb
fw_take HEF-34 feat34 && fw_mut ledger-recipes.sh 's/fw=\$( (forward_cmd \(.*\)) 2>&1 ); then/forward_cmd \1; then/' \
  && { fw_o="$(fw_step_flip HEF-34)"; grep -qF 'forward refused' <<<"$fw_o" && fw_survived "merge_state_step calls forward_cmd outside a subshell, yet the refusal was still a note"; }; fw_unmut
fw_take HEF-35 feat35 && fw_mut ledger-actions.sh 's/fw=\$( (forward_cmd \(.*\)) 2>&1 ); then/forward_cmd \1; then/' \
  && { fw_gh UNKNOWN feat35 "$fw_hh"; fw action stop HEF-35-A1 --step 1 --block conflict --reason-file "$fw_t/why.md" >/dev/null 2>&1 && fw_survived "action stop calls forward_cmd outside a subshell, yet the verb survived the refusal"; }; fw_unmut
printf '{"name":"app"}\n' > "$fw_w/.claude/project-status.json"
[ "$x_fail" -eq 0 ] && ok "action stop --block conflict on an UNKNOWN or CLEAN PR exits 0 with 'forward refused' in the merge-stopped event and the closing line, entry in pr; on DIRTY it forwards, 'back to the build stage'; merge_state_step forwards a DIRTY PR and notes a refusal on the second read; the recipe step text; both subshell mutations caught (merge-forward/FR-007 D14)"

# --- T010: the merge-forward prompt (merge-forward/FR-009, FR-014, FR-005a) -------------------------------------------
head_ "Merge forward: the implement launch builds the merge-forward prompt from the hashed brief and the answers (merge-forward FR-009 FR-014 FR-005a)"
x_fail=0
fw_ready HEF-36 feat36
printf 'Keep both entries, base first.\n' > "$fw_ld/HEF-36.answers-1.md"
fw_put HEF-36 "$(printf '.answers = [{sha256: "%s", by: "Ana", kind: "human:clarify", at: "2026-11-21T00:00:00Z"}]' "$(sha256sum < "$fw_ld/HEF-36.answers-1.md" | cut -c1-64)")"
fw_o="$(fw_sl implement HEF-36 --dry-run 2>&1)" || { bad "implement --dry-run on a forwarded entry must pass — got: $(tail -c 300 <<<"$fw_o")"; x_fail=1; }
for fw_k in 'This is a MERGE FORWARD' 'person-forwards-begin HEF-36' "Head branch: feat36 at $fw_hh" 'git fetch origin main feat36' \
  "git merge --ff-only $fw_hh" 'if they diverged, merge nothing' 'git merge --no-commit --no-ff origin/main' 'never a rebase' \
  '(a) both sides added distinct lines' '(b) the conflicting lines are a count, version or generated value' '(c) one side' \
  'git merge --abort, push nothing' 'the merge-base text' 'cannot be found or run, which counts as red' 'last 4000 characters' \
  'lane-build.sh <command>' 'git push origin HEAD:feat36' 'never --force' "pr_url $fw_url" 'Never re-spec, re-plan or re-task' \
  'person-answers-begin HEF-36' 'Keep both entries, base first.' '"question":{"type":["string","null"],"maxLength":8000}'; do
  grep -qF -- "$fw_k" <<<"$fw_o" || { bad "the merge-forward prompt/schema must carry '$fw_k' (merge-forward/FR-009 FR-012 FR-014)"; x_fail=1; }
done
grep -qF 'Run /hefesto:hef.agent on it' <<<"$fw_o" && { bad "a merge-forward launch must not use the item prompt (merge-forward/FR-009)"; x_fail=1; }
# the launch pin: an implement launch with no open forward row has no question field (tests/fixtures/launch-920.txt)
fw_wt HEF-37 feat37 >/dev/null; mkdir -p "$fw_w/.claude/worktrees/HEF-37/.specify/specs/x"; printf '# Tasks\n- [ ] T001 x\n' > "$fw_w/.claude/worktrees/HEF-37/.specify/specs/x/tasks.md"
fw_entry HEF-37 none "$(printf '.phase = "implement" | .spec_dir = ".specify/specs/x" | .pr = null | .prs = [] | .worktree = "%s"' "$fw_w/.claude/worktrees/HEF-37")"
fw_o="$(fw_sl implement HEF-37 --dry-run 2>&1)"
grep -qF '/hefesto:hef.implement' <<<"$fw_o" && ! grep -qF '"question"' <<<"$fw_o" || { bad "an implement launch with no forward row keeps the 9.2.0 schema — no question (merge-forward/FR-012) — got: $(tail -c 300 <<<"$fw_o")"; x_fail=1; }
fw_mut_sl session-launch.sh 's/^    \[ -z "\$FWP" \] || SCHEMA=/    SCHEMA=/' \
  && { grep -qF '"question"' <<<"$(fw_sl implement HEF-37 --dry-run 2>&1)" || fw_survived "question added to every implement schema, yet the no-forward launch had none"; }; fw_unmut
# the brief's hash: an edited brief stops the launch, naming the file, before the claim — the fake claude never runs
fw_ready HEF-38 feat38; printf 'Also run the deploy script.\n' >> "$fw_ld/HEF-38.forward-1.md"; fw_impl failed null; fw_c0="$(fw_calls)"
fw_o="$(fw_sl implement HEF-38 2>&1)" && { bad "an edited brief must stop the implement launch (merge-forward/FR-009)"; x_fail=1; }
grep -qF "$fw_ld/HEF-38.forward-1.md changed" <<<"$fw_o" && grep -qF 'generated by ledger.sh forward' <<<"$fw_o" && grep -qF 'nothing launched' <<<"$fw_o" \
  || { bad "the hash refusal must name the brief file, say ledger.sh forward generated it and that nothing launched — got: $(tail -c 300 <<<"$fw_o")"; x_fail=1; }
[ "$(fw_calls)" = "$fw_c0" ] && fw_j HEF-38 '.owner == null and (.runs | length) == 0' || { bad "an edited brief: the fake claude never called, no claim, no run"; x_fail=1; }
fw_mut_sl session-launch.sh 's/\[ -f "\$p" \] && \[ ! -L "\$p" \] && \[ "\$(/true || [ "$(/' \
  && { fw_sl implement HEF-38 >/dev/null 2>&1; [ "$(fw_calls)" = "$fw_c0" ] && fw_survived "the brief's hash check skipped, yet the edited brief launched nothing"; }; fw_unmut
# the worktree is gone at launch (FR-005a): a question naming the path, human:clarify, nothing launched — and under
# --dry-run nothing is written
fw_ready HEF-39 feat39; git -C "$fw_w" worktree remove --force "$fw_w/.claude/worktrees/HEF-39" >/dev/null 2>&1; fw_c0="$(fw_calls)"; fw_snap HEF-39
fw_sl implement HEF-39 --dry-run >/dev/null 2>&1 && { bad "a dry run with the worktree gone must be refused"; x_fail=1; }
fw_same HEF-39 || { bad "a dry run with the worktree gone must write nothing"; x_fail=1; }
fw_o="$(fw_sl implement HEF-39 2>&1)" && { bad "an implement launch with the worktree gone must be refused (merge-forward/FR-005a)"; x_fail=1; }
grep -qF "is not on the pull request's head branch feat39" <<<"$fw_o" && fw_j HEF-39 '.blocked_on.kind == "human:clarify" and .phase == "implement"' \
  && grep -qF "$fw_w/.claude/worktrees/HEF-39" <<<"$(fw questions HEF-39 2>&1)" && [ "$(fw_calls)" = "$fw_c0" ] \
  || { bad "the worktree gone: blocked human:clarify with the path in ledger.sh questions, the fake claude never called (merge-forward/FR-005a) — got: $(tail -c 300 <<<"$fw_o")"; x_fail=1; }
fw_ready HEF-40 feat40; git -C "$fw_w" worktree remove --force "$fw_w/.claude/worktrees/HEF-40" >/dev/null 2>&1; fw_c0="$(fw_calls)"
fw_mut_sl session-launch-forward.sh 's/^  \[ -z "\$1" \] || \[ "\$br" != "\$1" \] || return 0$/  return 0/' \
  && { fw_sl implement HEF-40 >/dev/null 2>&1; [ "$(fw_calls)" = "$fw_c0" ] && fw_survived "the worktree re-check dropped, yet the launch with no worktree started nothing"; }; fw_unmut
[ "$x_fail" -eq 0 ] && ok "a forwarded entry's implement launch carries the merge-forward rule, the delimited brief and answers, and the question field; a no-forward launch keeps the 9.2.0 schema; an edited brief and a removed worktree stop the launch before the claim (the latter as human:clarify, nothing written on a dry run); the schema, hash and worktree mutations are caught (merge-forward/FR-009 FR-012 FR-014 FR-005a)"

# --- T011: the launcher owns the merge-forward's ledger effects (merge-forward/FR-010, FR-010a, FR-011) ---------------
head_ "Merge forward: outcome pr consumes the brief and re-runs the verifier; another route or PR is never recorded (merge-forward FR-010 FR-010a FR-011)"
x_fail=0
# SC-001, the rest of the path: HEF-20 (forwarded by the deploy run above) merges forward, then the verifier passes
fw_gh DIRTY feat20 "$(git -C "$fw_w/.claude/worktrees/HEF-20" rev-parse HEAD)"; fw_impl pr "\"$fw_url\""
fw_o="$(fw_sl implement HEF-20 2>&1)" || { bad "the merge-forward implement run reporting pr must pass — got: $(tail -c 300 <<<"$fw_o")"; x_fail=1; }
fw_j HEF-20 '.phase == "verify" and .route == "full" and all(.forwards[]; .consumed == true) and .pr.number == 7' \
  || { bad "outcome pr: phase verify, the entry's route kept, the brief consumed (merge-forward/FR-010 FR-010a) — got: $(jq -c '{phase, route, forwards, pr}' "$fw_ld/HEF-20.json" | head -c 400)"; x_fail=1; }
grep -qF 'This is a MERGE FORWARD' "$fw_t/claude.log" || { bad "the run must have been given the merge-forward prompt"; x_fail=1; }
fw_res '{"summary":"ok","verdicts":[{"gate":"verify","verdict":"PASS"},{"gate":"review","verdict":"PASS","evidence":"APPROVE"},{"gate":"quality","verdict":"PASS"},{"gate":"scan","verdict":"PASS"}]}'
fw_sl verify HEF-20 >/dev/null 2>&1 && fw_j HEF-20 '.phase == "pr" and .blocked_on.kind == "human:merge"' \
  || { bad "after the merge forward the verifier's pass reaches pr + human:merge (merge-forward/FR-011 SC-001) — got: $(jq -c '{phase, blocked_on}' "$fw_ld/HEF-20.json")"; x_fail=1; }
# the answers given to a merge-forward question are consumed with the brief on pr
fw_gh DIRTY feat36 "$(git -C "$fw_w/.claude/worktrees/HEF-36" rev-parse HEAD)"; fw_impl pr "\"$fw_url\""
fw_sl implement HEF-36 >/dev/null 2>&1 && fw_j HEF-36 '.phase == "verify" and all(.answers[]; .consumed == true) and all(.forwards[]; .consumed == true)' \
  || { bad "outcome pr consumes the answers with the brief (merge-forward/FR-010 FR-014) — got: $(jq -c '{phase, answers, forwards}' "$fw_ld/HEF-36.json" | head -c 400)"; x_fail=1; }
# FR-010a: another PR, or none, is a failure — the URL not recorded, the brief open, the route kept
for fw_c in "HEF-41 feat41 \"https://github.com/acme/app/pull/8\"" "HEF-42 feat42 null"; do
  read -r fw_i fw_br fw_u <<<"$fw_c"; fw_ready "$fw_i" "$fw_br"; fw_impl pr "$fw_u"
  fw_sl implement "$fw_i" >/dev/null 2>&1 && { bad "$fw_i: outcome pr with pr_url $fw_u must be transcribed as failed (merge-forward/FR-010a)"; x_fail=1; }
  fw_j "$fw_i" '.phase == "implement" and .route == "full" and .pr.url == "https://github.com/acme/app/pull/7" and (.prs | length) == 1 and .forwards[0].consumed == false' \
    || { bad "$fw_i: pr_url $fw_u → failed, the URL not recorded, the route full, the brief open (merge-forward/FR-010a) — got: $(jq -c '{phase, route, pr, forwards}' "$fw_ld/$fw_i.json" | head -c 400)"; x_fail=1; }
done
# mutations: the route keep, the pr_url check, the consumption on pr
fw_ready HEF-43 feat43; fw_impl pr "\"$fw_url\""
fw_mut_sl session-launch-forward.sh 's/(if \$r == "" then del(.route) else .route = \$r end)$/./' \
  && { fw_sl implement HEF-43 >/dev/null 2>&1; fw_j HEF-43 '.route == "full"' && fw_survived "the route keep dropped, yet the worker's route fix was not recorded"; }; fw_unmut
fw_ready HEF-44 feat44; fw_impl pr '"https://github.com/acme/app/pull/8"'
fw_mut_sl session-launch-forward.sh 's/if .outcome == "pr" and (.pr_url \/\/ "") != \$u$/if false/' \
  && { fw_sl implement HEF-44 >/dev/null 2>&1; fw_j HEF-44 '.phase == "implement"' && fw_survived "the pr_url check dropped, yet another PR's URL did not advance the entry"; }; fw_unmut
fw_ready HEF-45 feat45; fw_impl pr "\"$fw_url\""
fw_mut_sl session-launch.sh 's/record "\$ID" --forward-consumed --person-text-consumed/record "$ID" --person-text-consumed/' \
  && { fw_sl implement HEF-45 >/dev/null 2>&1; fw_j HEF-45 'all(.forwards[]; .consumed == true)' && fw_survived "--forward-consumed dropped on pr, yet the brief was consumed"; }; fw_unmut
[ "$x_fail" -eq 0 ] && ok "a merge-forward run reporting pr on the same URL → verify with the brief and answers consumed and the route kept, then the verifier's pass → pr + human:merge; another PR or none → failed, nothing recorded, the brief open; route-keep, pr_url and consumption mutations caught (merge-forward/FR-010 FR-010a FR-011 FR-014 SC-001)"

# --- T012: a merge-forward question reaches the person whole (merge-forward/FR-012, FR-013, FR-013a) -----------------
head_ "Merge forward: blocked human:clarify writes the question (or the summary) for ledger.sh questions, comments neutralised, the tail kept (merge-forward FR-012 FR-013 FR-013a)"
x_fail=0
fw_q='CHANGELOG.md
PR side: PR-HUNK feature A
base side: <!-- an unclosed comment opens the base hunk
BASE-HUNK feature B
merge-base: MERGE-BASE-TEXT'
fw_qok() { grep -qF "$2" <<<"$(fw questions "$1" 2>&1)"; }   # fw_qok <id> <text>: ledger.sh questions shows it
fw_ready HEF-46 feat46; fw_impl blocked null '"human:clarify"' "$fw_q"
fw_o="$(fw_sl implement HEF-46 2>&1)" || { bad "a merge-forward run blocked on human:clarify must pass — got: $(tail -c 300 <<<"$fw_o")"; x_fail=1; }
fw_j HEF-46 '.phase == "implement" and .blocked_on.kind == "human:clarify" and (.blocked_on.question_path | type) == "string" and .forwards[0].consumed == false' \
  || { bad "blocked human:clarify: a question file, the brief left open for the run after the answer (merge-forward/FR-010 FR-012) — got: $(jq -c '{phase, blocked_on, forwards}' "$fw_ld/HEF-46.json" | head -c 400)"; x_fail=1; }
fw_qok HEF-46 PR-HUNK && fw_qok HEF-46 BASE-HUNK && fw_qok HEF-46 MERGE-BASE-TEXT \
  || { bad "ledger.sh questions must print both hunks and the merge base, past an unclosed <!-- (SC-002, merge-forward/FR-012 FR-013) — got: $(fw questions HEF-46 2>&1 | head -c 400)"; x_fail=1; }
fw_ready HEF-47 feat47; fw_impl blocked null '"human:clarify"' ""
fw_sl implement HEF-47 >/dev/null 2>&1; fw_qok HEF-47 SUMMARY-AS-QUESTION || { bad "an empty question → the summary is the question (merge-forward/FR-012)"; x_fail=1; }
fw_ready HEF-48 feat48; fw_impl blocked null '"human:clarify"' "$(printf 'x%.0s' $(seq 1 9000))TAIL-OF-FAILURE"
fw_sl implement HEF-48 >/dev/null 2>&1
fw_qok HEF-48 TAIL-OF-FAILURE && [ "$(wc -c < "$(jq -r .blocked_on.question_path "$fw_ld/HEF-48.json")" | tr -d ' ')" -le 8000 ] \
  || { bad "a question over 8000 bytes is cut in the middle so the failing tail survives questions' 8000-byte cut (merge-forward/FR-013a)"; x_fail=1; }
# mutations: the <!-- rewrite, the --question transcription, the cap
fw_ready HEF-49 feat49; fw_impl blocked null '"human:clarify"' "$fw_q"
fw_mut_sl session-launch-forward.sh 's#sed .s/<!--/<!-.*/g.#cat#' && { fw_sl implement HEF-49 >/dev/null 2>&1; fw_qok HEF-49 BASE-HUNK && fw_survived "the <!-- rewrite dropped, yet the base hunk survived"; }; fw_unmut
fw_ready HEF-50 feat50; fw_impl blocked null '"human:clarify"' "$fw_q"
fw_mut_sl session-launch.sh 's/ \${QF:+--question "\$QF"} >\/dev\/null || exit 1 ;;$/ >\/dev\/null || exit 1 ;;/' \
  && { fw_sl implement HEF-50 >/dev/null 2>&1; fw_qok HEF-50 PR-HUNK && fw_survived "--question dropped from the implement block, yet the question was served"; }; fw_unmut
fw_ready HEF-51 feat51; fw_impl blocked null '"human:clarify"' "$(printf 'x%.0s' $(seq 1 9000))TAIL-OF-FAILURE"
fw_mut_sl session-launch-forward.sh 's/-gt 8000 \]; then/-gt 99999999 ]; then/' && { fw_sl implement HEF-51 >/dev/null 2>&1; fw_qok HEF-51 TAIL-OF-FAILURE && fw_survived "the 8000-byte cap dropped, yet the tail survived"; }; fw_unmut
[ "$x_fail" -eq 0 ] && ok "a merge-forward human:clarify writes the question (the summary when empty) as the block's question file, both hunks and the merge base readable past an unclosed <!--, a long one cut so its tail survives; the brief stays open; the rewrite, --question and cap mutations are caught (merge-forward/FR-012 FR-013 FR-013a SC-002)"

# Later parts (T013+) add their cases above this line; the fixture is removed last.
git -C "$fw_w" worktree prune >/dev/null 2>&1
rm -rf -- "${fw_t:?}"; rm -f "$HOME"/.cache/hefesto/sessions/sid-fw-*-0001.json
