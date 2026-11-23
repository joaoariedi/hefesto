# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs and sed scripts are single-quoted on purpose
#
# verify-fix-loop (HEF-57) smoke checks, part 18 — a verify FAIL goes back to the build stage: `ledger.sh rework` (the
# launcher-only move verify → implement with a generated, hashed brief), its refusals, the verify_rounds cap and its
# findings question, the person-only --past-cap, and the launcher's FAIL → rework routing, headless and in a lane.
#
# SOURCED by tests/smoke.sh after part 17b, never run on its own. Self-contained (smoke-forward.sh's model): a fixture
# repo with a bare origin and a worktree per entry at <top>/.claude/worktrees/<id>, a named fake gh (FakeGh), a fake
# claude printing $rw_t/result.json, a fake ledger for rework_route's own cases (FakeLedger), lane session records, the
# real ledger.sh and session-launch.sh, and rw_mut: a scratch copy of the hooks folder with files mutated by sed, cmp -s
# proving each applied. Order-dependent cases carry explicit, distinct `at` stamps (plan, round 5 change 3).

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ sld >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-rework.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_, sld)"
  else echo "tests/smoke-rework.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

head_ "Verify-fix loop: a verify FAIL goes back to the build stage with its findings (verify-fix-loop FR-001..FR-008)"

# --- the fixture ---------------------------------------------------------------------------------------------------
rw_t="$(cd "$(mktemp -d)" && pwd -P)"; rw_w="$rw_t/w"; rw_url="https://github.com/acme/app/pull/9"; rw_hx="0123456789abcdef0123456789abcdef01234567"
rw_g() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
git init -q --bare -b main "$rw_t/origin.git" && git init -q -b main "$rw_w" && rw_g "$rw_w" commit -q --allow-empty -m init \
  && git -C "$rw_w" remote add origin "$rw_t/origin.git" && git -C "$rw_w" push -q origin main 2>/dev/null
mkdir -p "$rw_t/bin" "$rw_t/cfg" "$rw_t/fl" "$rw_w/.claude" "$HOME/.cache/hefesto/sessions"
cat > "$rw_t/bin/gh" <<'EOF'
#!/bin/bash
case "$1 $2" in "auth status") exit 0 ;; *) echo "FakeGh: unexpected gh $*" >&2; exit 1 ;; esac
EOF
cat > "$rw_t/bin/claude" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$rw_t/claude.log"
cat "$rw_t/result.json"
EOF
# FakeLedger, for rework_route alone: FL_MODE ok (the move lands; it keeps the summary it was handed) | block (rework
# refused, the fallback block lands) | fail (both refused) | nodir (no ledger folder: no summary file)
cat > "$rw_t/bin/fl" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$rw_t/fl.log"
case "\$FL_MODE:\$1" in
  nodir:dir) exit 1 ;;
  *:dir) echo "$rw_t/fl" ;;
  ok:rework) cat "\$6" > "$rw_t/fl.sum" ;;
  nodir:rework|block:block) ;;
  *) echo "FakeLedger: \$1 refused" >&2; exit 1 ;;
esac
EOF
chmod +x "$rw_t/bin/gh" "$rw_t/bin/claude" "$rw_t/bin/fl"
rw_ld="$(sld "$rw_w")"; mkdir -p "$rw_ld"
printf 'SUMMARY-TEXT\n' > "$rw_t/sum.md"; ln -s "$rw_t/sum.md" "$rw_t/sum.lnk"; head -c 33000 /dev/zero | tr '\0' x > "$rw_t/big.md"
for rw_r in orchestrator build; do   # lane session records, as the session start writes them (lane-lib.sh)
  jq -nc --arg r "$rw_r" --arg x "$REPO/hooks/ledger.sh *" --arg l "$rw_ld" '{title: "repo-\($r)", role: $r, name: "repo-\($r)", lanes: true, worker: false, excluded: [$x], ledger: $l}' \
    > "$HOME/.cache/hefesto/sessions/sid-rw-$rw_r-0001.json"
done
rw_cfg() { printf '{"name":"app","orchestrate":%s}\n' "$1" > "$rw_w/.claude/project-status.json"; }   # rw_cfg <orchestrate JSON>
rw_entry() { # rw_entry <id> [jq filter] → a verify entry on PR #9, branch b-<id>, one review FAIL (attempts 2: the reset shows)
  jq -n --arg id "$1" --arg u "$rw_url" --arg wt "$rw_w/.claude/worktrees/$1" '{id: $id, item_kind: "feature", phase: "verify", owner: null,
    route: "full", pr: {url: $u, number: 9}, prs: [{url: $u, number: 9}], branch: "b-\($id)", worktree: $wt, runs: [], attempts: 2,
    blocked_on: null, updated: (now | todate), verdicts: [{gate: "review", verdict: "FAIL", by: "verify-\($id)", at: "2026-11-10T00:00:01Z", evidence: "EV-REVIEW"}]}' \
    | jq "${2:-.}" > "$rw_ld/$1.json"
}
rw_wt() { # rw_wt <id> [branch] → a worktree at the launch path on a new branch (default b-<id>) with one commit; prints its head
  local p="$rw_w/.claude/worktrees/$1"
  git -C "$rw_w" worktree add -q "$p" -b "${2:-b-$1}" main >/dev/null 2>&1 && rw_g "$p" commit -q --allow-empty -m "work $1" >/dev/null 2>&1
  git -C "$p" rev-parse HEAD
}
RW_GH="$rw_t/bin/gh"
rw() { (cd "$rw_w" && HEFESTO_GH_BIN="$RW_GH" bash "${RW_LG:-$REPO/hooks/ledger.sh}" "$@"); }   # the caller's own environment
rwl() { (cd "$rw_w" && launcher env HEFESTO_GH_BIN="$RW_GH" bash "${RW_LG:-$REPO/hooks/ledger.sh}" "$@"); }   # as the verify launcher
rwn() { (cd "$rw_w" && env -u CLAUDE_CODE_SESSION_ID -u HEFESTO_LAUNCHER HEFESTO_GH_BIN="$RW_GH" bash "${RW_LG:-$REPO/hooks/ledger.sh}" "$@"); }   # a person, no lane
rww() { (cd "$rw_w" && launcher env HEFESTO_WORKER=1 HEFESTO_GH_BIN="$RW_GH" bash "${RW_LG:-$REPO/hooks/ledger.sh}" "$@"); }   # inside a worker
rws() { (cd "$rw_w" && env CLAUDE_CODE_SESSION_ID=sid-rw-nobody-0001 HEFESTO_LAUNCHER=1 HEFESTO_GH_BIN="$RW_GH" bash "${RW_LG:-$REPO/hooks/ledger.sh}" "$@"); }   # a session
rw_lane() { local s="$1"; shift; (cd "$rw_w" && env -u HEFESTO_LAUNCHER CLAUDE_CODE_SESSION_ID="sid-rw-$s-0001" HEFESTO_GH_BIN="$RW_GH" bash "${RW_LG:-$REPO/hooks/ledger.sh}" "$@"); }
rw_sl() { (cd "$rw_w" && env -u CLAUDE_CODE_SESSION_ID PATH="$rw_t/bin:$PATH" HEFESTO_GH_BIN="$RW_GH" CLAUDE_CONFIG_DIR="$rw_t/cfg" bash "${RW_SL:-$REPO/hooks/session-launch.sh}" "$@"); }
rw_j() { jq -e "${@:2}" "$rw_ld/$1.json" >/dev/null 2>&1; }   # rw_j <id> [--arg …] <jq test>
rw_put() { jq "$2" "$rw_ld/$1.json" > "$rw_t/e.tmp" && mv "$rw_t/e.tmp" "$rw_ld/$1.json"; }
rw_snap() { cksum < "$rw_ld/$1.json" > "$rw_t/snap.ck"; ls -a "$rw_ld" > "$rw_t/snap.ls"; }
rw_same() { [ "$(cksum < "$rw_ld/$1.json")" = "$(cat "$rw_t/snap.ck")" ] && [ "$(ls -a "$rw_ld")" = "$(cat "$rw_t/snap.ls")" ]; }   # entry AND folder
rw_calls() { touch "$rw_t/claude.log"; wc -l < "$rw_t/claude.log" | tr -d ' '; }
rw_res() { jq -nc --argjson so "$1" '{session_id: "rw", total_cost_usd: 0, structured_output: $so}' > "$rw_t/result.json"; }
rw_vres() { # rw_vres <review verdict> [evidence] → a verifier's outcome: review as given, verify/quality/scan PASS
  rw_res "$(jq -nc --arg v "$1" --arg e "${2:-}" '{summary: "VERIFIER-SUMMARY", verdicts: [{gate: "verify", verdict: "PASS"}, {gate: "review", verdict: $v, evidence: $e}, {gate: "quality", verdict: "PASS"}, {gate: "scan", verdict: "PASS"}]}')"
}
rw_ires() { rw_res "$(jq -nc --arg o "$1" --argjson u "$2" '{summary: "fixed", route: "fix", outcome: $o, pr_url: $u, blocked_on: null, spec_dir: null}')"; }   # an implement outcome
rw_mkmut() { rm -rf "$rw_t/mut"; mkdir -p "$rw_t/mut"; local f; for f in "$REPO"/hooks/*; do ln -s "$f" "$rw_t/mut/$(basename "$f")"; done
  RW_LG="$rw_t/mut/ledger.sh"; RW_SL="$rw_t/mut/session-launch.sh"; RW_HK="$rw_t/mut"; }
rw_mut_add() { # rw_mut_add <hook file> <sed script>: one more file of the scratch copy mutated (0), or bad + 1
  rm -f "$rw_t/mut/$1"; sed "$2" "$REPO/hooks/$1" > "$rw_t/mut/$1"; chmod +x "$rw_t/mut/$1"
  cmp -s "$REPO/hooks/$1" "$rw_t/mut/$1" && { bad "verify-fix-loop mutation did not apply to $1: $2"; x_fail=1; return 1; }; return 0
}
rw_mut() { rw_mkmut; rw_mut_add "$@"; }   # rw_mut <hook file> <sed script> → RW_LG / RW_SL / RW_HK run the mutant
rw_rm() { rw_mkmut; rm -f "$rw_t/mut/$1"; }   # rw_rm <hook file> → the scratch copy without it
rw_unmut() { unset RW_LG RW_SL RW_HK; }
rw_survived() { bad "mutation survived: $1 (verify-fix-loop/FR-016)"; x_fail=1; }

# --- SC-001: FAIL → fix → PASS through the real launcher, launcher calls only (verify-fix-loop/FR-001, FR-002, FR-004) --
x_fail=0
rw_cfg '{}'; rw_h1="$(rw_wt RW-1)"; rw_entry RW-1 '.verdicts = []'; rw_vres FAIL REVIEW-FINDING-1
rw_o="$(rw_sl verify RW-1 2>&1)" || { bad "verify RW-1 reporting a review FAIL must exit 0 — got: $(tail -c 400 <<<"$rw_o")"; x_fail=1; }
grep -qF 'RW-1 verify → implement (rework 1 of 3)' <<<"$rw_o" || { bad "the verify run must print the move, round 1 of the default cap 3 (verify-fix-loop/FR-002 verify-fix-loop/FR-005) — got: $(tail -c 400 <<<"$rw_o")"; x_fail=1; }
rw_j RW-1 --arg h "$rw_h1" --arg u "$rw_url" '.phase == "implement" and .blocked_on == null and .owner == null and .attempts == 0 and (.reworks | length) == 1
  and (.reworks[0] | .n == 1 and .consumed == false and .head_sha == $h and .pr_url == $u and .by == null and (.at | length) > 0)
  and any(.events[]; .kind == "rework" and .n == 1 and .head_sha == $h) and any(.verdicts[]; .gate == "review" and .verdict == "FAIL" and .evidence == "REVIEW-FINDING-1")' \
  || { bad "verify FAIL → implement, unowned, unblocked, attempts 0, one open .reworks row {n, pr_url, head_sha = the head verified, by null}, a rework event, the verdicts first (verify-fix-loop/FR-001 verify-fix-loop/FR-002 verify-fix-loop/FR-013a) — got: $(jq -c '{phase, blocked_on, owner, attempts, reworks}' "$rw_ld/RW-1.json" | head -c 500)"; x_fail=1; }
rw_b="$rw_ld/RW-1.rework-1.md"
{ [ -f "$rw_b" ] && [ "$(jq -r '.reworks[0].sha256' "$rw_ld/RW-1.json")" = "$(sha256sum < "$rw_b" | cut -c1-64)" ] && grep -qF 'Rework round 1 of 3 — RW-1' "$rw_b" \
  && grep -qF "Pull request: $rw_url" "$rw_b" && grep -qF "Head the verifier saw: $rw_h1" "$rw_b" && grep -qF '### review — FAIL (verifier session verify-RW-1)' "$rw_b" \
  && grep -qF REVIEW-FINDING-1 "$rw_b" && grep -qF VERIFIER-SUMMARY "$rw_b" && [ ! -e "$rw_ld/RW-1.verify-summary.md" ]; } \
  || { bad "the brief <id>.rework-1.md: hashed in the row, round, PR URL, head, the FAIL gate with its evidence, the verifier's summary; the summary file removed (verify-fix-loop/FR-004) — got: $(head -c 400 "$rw_b" 2>&1)"; x_fail=1; }
rw_ires pr "\"$rw_url\""; rw_o="$(rw_sl implement RW-1 2>&1)" || { bad "the rework run reporting pr must pass — got: $(tail -c 400 <<<"$rw_o")"; x_fail=1; }
rw_j RW-1 --arg u "$rw_url" '.phase == "verify" and .route == "full" and .reworks[0].consumed == true and .pr.url == $u and .blocked_on == null' \
  || { bad "the rework run's pr on the same URL → verify, the row consumed, the entry's route kept (verify-fix-loop/FR-008 verify-fix-loop/FR-010) — got: $(jq -c '{phase, route, reworks, pr}' "$rw_ld/RW-1.json" | head -c 400)"; x_fail=1; }
for rw_k in 'This is a REWORK' 'rework-brief-begin RW-1' REVIEW-FINDING-1 "git push origin HEAD:b-RW-1" "pr_url $rw_url" '"question":{"type":["string","null"],"maxLength":8000}'; do
  grep -qF -- "$rw_k" "$rw_t/claude.log" || { bad "the rework run's prompt/schema must carry '$rw_k' (verify-fix-loop/FR-008 verify-fix-loop/FR-009)"; x_fail=1; }
done
rw_vres PASS APPROVE; rw_sl verify RW-1 >/dev/null 2>&1 && rw_j RW-1 '.phase == "pr" and .blocked_on.kind == "human:merge" and (.reworks | length) == 1' \
  || { bad "the verifier's all-PASS after the rework → pr + human:merge (SC-001) — got: $(jq -c '{phase, blocked_on}' "$rw_ld/RW-1.json")"; x_fail=1; }
# mutations: the FAIL routed to today's verdict block; the row never consumed on pr; another PR's URL accepted; the route lost
rw_moved() { rw_entry "$1" "${2:-.}"; rwl rework "$1" >/dev/null 2>&1 || { bad "fixture: rework $1 must move it — $(rwl rework "$1" 2>&1 | tail -c 300)"; x_fail=1; }; }
rw_entry RW-1 '.verdicts = []'; rw_vres FAIL X
rw_mut session-launch.sh 's/then rework_route || exit 1/then "$LEDGER" block "$ID" --kind verdict >\/dev\/null || exit 1/' \
  && { rw_sl verify RW-1 >/dev/null 2>&1; rw_j RW-1 '.phase == "implement"' && rw_survived "the FAIL routed to block verdict, yet the entry reached implement"; }; rw_unmut
rw_moved RW-1; rw_ires pr "\"$rw_url\""
rw_mut session-launch-forward.sh 's/ --rework-consumed >/ --followups-consumed >/' && { rw_sl implement RW-1 >/dev/null 2>&1; rw_j RW-1 '.reworks[0].consumed == true' && rw_survived "--rework-consumed dropped on pr, yet the row was consumed"; }; rw_unmut
rw_moved RW-1; rw_ires pr '"https://github.com/acme/app/pull/8"'
rw_sl implement RW-1 >/dev/null 2>&1 && { bad "a rework run reporting another PR must be transcribed failed (verify-fix-loop/FR-010)"; x_fail=1; }
rw_j RW-1 --arg u "$rw_url" '.phase == "implement" and .pr.url == $u and .reworks[0].consumed == false' || { bad "another PR's URL: not recorded, phase implement, the row open (verify-fix-loop/FR-010) — got: $(jq -c '{phase, pr, reworks}' "$rw_ld/RW-1.json" | head -c 300)"; x_fail=1; }
rw_moved RW-1; rw_mut session-launch-rework.sh 's/if .outcome == "pr" and (.pr_url \/\/ "") != \$u$/if false/' \
  && { rw_sl implement RW-1 >/dev/null 2>&1; rw_j RW-1 '.phase == "implement"' && rw_survived "the pr_url check dropped, yet another PR's URL did not advance the entry"; }; rw_unmut
rw_moved RW-1; rw_ires pr "\"$rw_url\""; rw_mut session-launch-rework.sh 's/(if \$r == "" then del(.route) else .route = \$r end)$/./' \
  && { rw_sl implement RW-1 >/dev/null 2>&1; rw_j RW-1 '.route == "full"' && rw_survived "the route keep dropped, yet the worker's route fix was not recorded"; }; rw_unmut
[ "$x_fail" -eq 0 ] && ok "SC-001 through the real launcher: verify FAIL → implement with an open row (head, hashed brief with findings and summary, attempts 0, no block), the rework run (brief + question schema) reporting pr on the same URL → verify with the row consumed and the route kept, then all PASS → pr + human:merge; another PR → failed, nothing recorded; routing, consumption, pr_url and route mutations caught (verify-fix-loop/FR-001 verify-fix-loop/FR-002 verify-fix-loop/FR-004 verify-fix-loop/FR-008 verify-fix-loop/FR-010 verify-fix-loop/FR-016)"

# --- the move's details: round since reopen, cutoffs, resets, the brief (verify-fix-loop/FR-002, FR-004, FR-013, FR-013a) --
head_ "Verify-fix loop: the move — round since the reopen, the current round's latest FAILs, earlier rows and answers consumed, the brief (verify-fix-loop FR-004 FR-013 FR-013a)"
x_fail=0; rw_cfg '{"verify_rounds": 1}'
# one stale rework row and one stale forward row before a reopen (neither counts nor refuses); an implement run at :05
# splits the rounds — the :03 quality FAIL is the last round's, the :06 review FAIL (with an unclosed comment) this one's
rw_bf='.runs = [{role: "implement", session_name: "impl-RW-B", at: "2026-11-10T00:00:05Z"}]
  | .verdicts = [{gate: "quality", verdict: "FAIL", by: "verify-RW-B", at: "2026-11-10T00:00:03Z", evidence: "OLD-QUALITY"},
                 {gate: "review", verdict: "FAIL", by: "verify-RW-B", at: "2026-11-10T00:00:06Z", evidence: "NEW-REVIEW <!-- hidden"}]
  | .answers = [{path: "/x/a1.md", sha256: "aa", by: "Ana", kind: "human:plan-review", at: "2026-11-02T00:00:00Z"}]
  | .reworks = [{n: 1, pr_url: "u", head_sha: null, sha256: "s", at: "2026-11-01T00:00:00Z", by: null, consumed: false, asked: [], ruling: []}]
  | .forwards = [{n: 1, pr_url: "u", consumed: false, at: "2026-11-01T00:00:00Z"}] | .events = [{kind: "reopen", at: "2026-11-05T00:00:00Z"}]'
rw_bmove() { rw_entry RW-B "$rw_bf"; rw_o="$(rwl rework RW-B --summary-file "$rw_t/sum.md" --head "$rw_hx" 2>&1)"; rw_bb="$rw_ld/RW-B.rework-2.md"; }
rw_bmove
[ "$rw_o" = "RW-B verify → implement (rework 1 of 1)" ] || { bad "the move line names the round since the last reopen (1 of 1, not 2) and a stale forward row does not refuse (verify-fix-loop/FR-002 verify-fix-loop/FR-013) — got: $(head -c 300 <<<"$rw_o")"; x_fail=1; }
rw_j RW-B --arg h "$rw_hx" --arg u "$rw_url" --arg s "$(sha256sum < "$rw_bb" 2>/dev/null | cut -c1-64)" '.phase == "implement" and .owner == null and .attempts == 0 and .blocked_on == null
  and all(.answers[]; .consumed == true) and (.reworks | length) == 2 and .reworks[0].consumed == true and (.reworks[1] | .n == 2 and .consumed == false
  and .head_sha == $h and .pr_url == $u and .sha256 == $s) and any(.events[]; .kind == "rework" and .n == 2 and .head_sha == $h)' \
  || { bad "the move: attempts 0, every earlier answer and row consumed, row n 2 with --head and the brief's hash (verify-fix-loop/FR-002 verify-fix-loop/FR-013 verify-fix-loop/FR-013a) — got: $(jq -c '{attempts, answers, reworks}' "$rw_ld/RW-B.json" | head -c 500)"; x_fail=1; }
{ grep -qF 'Rework round 1 of 1 — RW-B' "$rw_bb" && grep -qF "Head the verifier saw: $rw_hx" "$rw_bb" && grep -qF 'NEW-REVIEW <!-\- hidden' "$rw_bb" \
  && grep -qF "## The verifier's run summary" "$rw_bb" && grep -qF SUMMARY-TEXT "$rw_bb" && ! grep -qF '<!--' "$rw_bb" && ! grep -qF OLD-QUALITY "$rw_bb"; } \
  || { bad "the brief: this round's latest FAIL only (not the last round's quality), every <!-- rewritten, the summary file appended (verify-fix-loop/FR-004) — got: $(head -c 500 "$rw_bb" 2>&1)"; x_fail=1; }
rw_bmut() { # rw_bmut <file> <sed> <label> <jq test | !grep text>: the move under the mutant; the assertion still holding = survived
  rw_mut "$1" "$2" || return 0; rw_bmove
  case "$4" in "!"*) grep -qF -- "${4#!}" "$rw_bb" 2>/dev/null || rw_survived "$3" ;; "="*) [ "$rw_o" = "${4#=}" ] && rw_survived "$3" ;; *) rw_j RW-B "$4" && rw_survived "$3" ;; esac; rw_unmut
}
rw_bmut ledger-rework.sh 's/round=\$(( \$(rework_rows_since_reopen "\$2") + 1 ))/round=$n/' "the round from n, yet the line said 1 of 1" "=RW-B verify → implement (rework 1 of 1)"
rw_bmut rework-pairs.sh 's/select(.kind == "reopen") | .at\]/select(false) | .at]/' "the reopen ignored, yet the stale rows neither counted nor refused" '.phase == "implement"'
rw_bmut ledger-rework.sh 's/select(.consumed != true and (.at \/\/ "") > \$r)\] | length/select(.consumed != true)] | length/' "the forward row's reopen cutoff dropped, yet the stale row did not refuse" '.phase == "implement"'
rw_bmut ledger-rework.sh 's/ | \.attempts = 0//' "the attempts reset dropped, yet attempts was 0" '.attempts == 0'
rw_bmut ledger-rework.sh 's/| (if .answers then .answers |= map(.consumed = true) else . end)$/| ./' "the answers consumption dropped, yet they were consumed" 'all(.answers[]; .consumed == true)'
rw_bmut ledger-rework.sh 's/((.reworks \/\/ \[\]) | map(.consumed = true))/(.reworks \/\/ [])/' "the earlier rows' consumption dropped, yet row 1 was consumed" '.reworks[0].consumed == true'
rw_bmut ledger-rework.sh 's/select((.at \/\/ "") >= \$t)/select(true)/' "the current-round filter dropped, yet the last round's FAIL stayed out" '!OLD-QUALITY'
rw_bmut ledger-rework.sh '/^  rework_brief "\$1"/s#sed .s/<!--/<!-.*/g.#cat#' "the brief's <!-- rewrite dropped, yet no <!-- reached it" '!<!--'
[ "$x_fail" -eq 0 ] && ok "the move counts the round since the last reopen, ignores a stale forward row, resets attempts, consumes every earlier answer and row, records --head and the brief's hash; the brief holds this round's latest FAILs only, the summary, every <!-- rewritten; 8 mutations caught (verify-fix-loop/FR-002 verify-fix-loop/FR-004 verify-fix-loop/FR-013 verify-fix-loop/FR-013a verify-fix-loop/FR-016)"

# --- FR-003: every refusal exits non-zero, names what it saw, changes nothing — and is the guard that refused ---------
head_ "Verify-fix loop: rework's refusals leave the entry byte-identical; each guard turned off is caught (verify-fix-loop FR-003 FR-007 FR-013a FR-016)"
x_fail=0; rw_cfg '{}'
rw_case() { # rw_case <text> <entry filter> <runner> [rework args…]: refused naming <text>, entry and folder byte-identical;
  # then that guard's `|| die` → `|| true` in ledger-rework.sh: the text must be gone (a later guard, or the move)
  local tx="$1" f="$2" r="$3" o; shift 3
  rw_entry RW-R "$f"; rw_snap RW-R
  o="$("$r" rework RW-R "$@" 2>&1)" && { bad "rework must refuse ('$tx') — got: $(head -c 300 <<<"$o") (verify-fix-loop/FR-003)"; x_fail=1; }
  grep -qF -- "$tx" <<<"$o" && rw_same RW-R || { bad "rework's refusal must name '$tx', entry and ledger folder byte-identical (verify-fix-loop/FR-003) — got: $(head -c 300 <<<"$o")"; x_fail=1; }
  rw_mut ledger-rework.sh "/$tx/s/|| die/|| true/" || return 0
  grep -qF -- "$tx" <<<"$("$r" rework RW-R "$@" 2>&1)" && rw_survived "the '$tx' refusal turned off, yet it still refused"; rw_unmut
}
rw_vb='.blocked_on = {kind: "verdict", since: "2026-11-01T00:00:00Z", question_path: null}'
rw_case "only a verified entry goes back" '.phase = "pr"' rwl
rw_case "a closed item is never reworked" '.terminal = {kind: "dropped"}' rwl
rw_case "no PR URL is recorded" '.pr = null | .prs = []' rwl
rw_case "the recorded PR URL" '.pr.url = "https://example.com/review/abc"' rwl
rw_case "is not a plain ref" '.branch = "-x"' rwl
rw_case "the verify run releases it" '.owner = {session_name: "repo-builder", role: "verify", mode: "interactive", started: "2026-11-01T00:00:00Z"}' rwl
rw_case "the command that block names clears it first" '.blocked_on = {kind: "ci", since: "2026-11-01T00:00:00Z"}' rwl
rw_case "the command that block names clears it first" "$rw_vb" rwl
rw_case "takes an entry blocked on verdict" . rwl --past-cap --by p
rw_case "nothing to fix" '.verdicts[0].verdict = "PASS"' rwl
rw_case "a merge-forward row is open" '.forwards = [{n: 1, pr_url: "u", consumed: false, at: "2026-11-20T00:00:00Z"}]' rwl
rw_case "never from inside a launched worker" . rww
rw_case "is a link" . rwl --summary-file "$rw_t/sum.lnk"
rw_case "does not exist" . rwl --summary-file "$rw_t/nope.md"
rw_case "is over 32 KB" . rwl --summary-file "$rw_t/big.md"
rw_case "must be the full 40- or 64-hex" . rwl --head abc123
rw_case "needs --by <your name>" "$rw_vb" rwl --summary-file "$rw_t/sum.md" --past-cap
rw_case "goes with --past-cap only" . rwl --by Ana
# the launcher marker: launcher_gate (ledger.sh) refuses first; rework_cmd's own check stands behind it — both must go
rw_entry RW-R; rw_snap RW-R
for rw_r in rwn rws; do
  rw_o="$("$rw_r" rework RW-R 2>&1)" && { bad "a plain rework ($rw_r) must be refused — the verify launcher's own move (verify-fix-loop/FR-003)"; x_fail=1; }
  grep -qF "ledger rework: the launcher's own record — only session-launch.sh calls it" <<<"$rw_o" && rw_same RW-R \
    || { bad "a plain rework without the marker or with a session id ($rw_r): the launcher's own record, entry unchanged (verify-fix-loop/FR-003) — got: $(head -c 300 <<<"$rw_o")"; x_fail=1; }
done
if rw_mut lane-lib.sh '/^    rework) shift; for a in/d'; then
  grep -qF "ledger rework RW-R: the verify launcher's own move" <<<"$(rwn rework RW-R 2>&1)" && rw_same RW-R || { bad "with is_launcher_sub blind to rework, rework_cmd's own marker check must still refuse (verify-fix-loop/FR-003)"; x_fail=1; }
  rw_mut_add ledger-rework.sh "/verify launcher.s own move/s/|| die/|| true/" && { rwn rework RW-R >/dev/null 2>&1; rw_same RW-R && rw_survived "both launcher-marker checks dropped, yet a plain rework without the marker was refused"; }
fi; rw_unmut
rw_o="$(rwl rework RW-R --x 2>&1)" && { bad "rework with an unknown option must be refused"; x_fail=1; }; grep -qF "unexpected '--x'" <<<"$rw_o" || { bad "rework names the unknown option — got: $(head -c 200 <<<"$rw_o")"; x_fail=1; }
# the latest verdict per gate decides: a review FAIL then PASS is nothing to fix (mutation: the first verdict per gate kept)
rw_entry RW-R '.verdicts += [{gate: "review", verdict: "PASS", by: "verify-RW-R", at: "2026-11-10T00:00:02Z", evidence: null}]'; rw_snap RW-R
rw_o="$(rwl rework RW-R 2>&1)"; grep -qF 'nothing to fix' <<<"$rw_o" && rw_same RW-R || { bad "a gate's latest PASS over its earlier FAIL is nothing to fix (verify-fix-loop/FR-003 D2) — got: $(head -c 300 <<<"$rw_o")"; x_fail=1; }
rw_mut ledger-rework.sh 's/\.\[\$v\.gate\] = \$v)/.[$v.gate] \/\/= $v)/' && { rwl rework RW-R >/dev/null 2>&1; rw_same RW-R && rw_survived "the first verdict per gate kept, yet the latest PASS refused"; }; rw_unmut
[ "$x_fail" -eq 0 ] && ok "rework refuses, byte-identical, naming what it saw: not verify, closed, no or non-forge PR URL, a non-plain branch, owned, blocked (ci, verdict without --past-cap), --past-cap on an unblocked entry, no FAIL, an open forward row, a worker, a linked/missing/>32 KB summary, a bad --head, --past-cap without --by, --by alone, an unknown option, no marker or a session id (both marker checks), a latest PASS; each guard turned off is caught (verify-fix-loop/FR-003 verify-fix-loop/FR-007 verify-fix-loop/FR-013a verify-fix-loop/FR-016)"

# --- SC-002: the cap, its findings question, the person's --past-cap in and out of lanes; verify_rounds (FR-005–FR-007) --
head_ "Verify-fix loop: at verify_rounds one verdict block with the findings question; --past-cap --by is a person's, orchestrator lane only (verify-fix-loop FR-005 FR-006 FR-007)"
x_fail=0; rw_cfg '{"verify_rounds": 2}'
rw_cap='.verdicts = [{gate: "review", verdict: "FAIL", by: "verify-RW-C", at: "2026-11-21T00:00:01Z", evidence: "REVIEW-EV <!-- opens a comment"},
  {gate: "quality", verdict: "FAIL", by: "verify-RW-C", at: "2026-11-21T00:00:02Z", evidence: "QUALITY-EV"}]
  | .reworks = [range(2) | {n: (. + 1), pr_url: "u", head_sha: null, sha256: "s", at: "2026-11-20T00:00:00Z", by: null, consumed: true, asked: [], ruling: []}]'
rw_entry RW-C "$rw_cap"; rw_o="$(rwl rework RW-C 2>&1)" || { bad "the third FAIL at verify_rounds 2 must exit 0 with the cap's block (verify-fix-loop/FR-006) — got: $(head -c 300 <<<"$rw_o")"; x_fail=1; }
grep -qF 'RW-C blocked_on verdict (verify_rounds 2 reached after 2 rework round(s) — a person decides: ledger.sh questions RW-C)' <<<"$rw_o" || { bad "the cap must say so — got: $rw_o"; x_fail=1; }
rw_j RW-C '.phase == "verify" and .blocked_on.kind == "verdict" and (.blocked_on.question_path | type) == "string" and (.reworks | length) == 2 and any(.events[]; .kind == "rework-blocked")' \
  || { bad "at the cap: phase verify, blocked verdict with a question_path, no new row, a rework-blocked event (SC-002, verify-fix-loop/FR-006) — got: $(jq -c '{phase, blocked_on}' "$rw_ld/RW-C.json")"; x_fail=1; }
rw_q="$(rw questions RW-C 2>&1)"
{ grep -qF 'review (verifier session verify-RW-C): REVIEW-EV' <<<"$rw_q" && grep -qF 'quality (verifier session verify-RW-C): QUALITY-EV' <<<"$rw_q" && grep -qF 'Rounds taken: 2' <<<"$rw_q" \
  && [ "$(wc -c < "$(jq -r .blocked_on.question_path "$rw_ld/RW-C.json")" | tr -d ' ')" -le 8000 ]; } \
  || { bad "ledger.sh questions must print every open finding's gate and evidence (past an unclosed <!--) and the rounds (SC-002, verify-fix-loop/FR-006) — got: $(head -c 400 <<<"$rw_q")"; x_fail=1; }
rw_snap RW-C
rw_o="$(rw_lane build rework RW-C --past-cap --by p 2>&1)" && { bad "--past-cap from a stage lane must be refused (verify-fix-loop/FR-007)"; x_fail=1; }
grep -qF "records a person's decision" <<<"$rw_o" && rw_same RW-C || { bad "--past-cap from the build lane: a person's decision, entry unchanged — got: $(head -c 300 <<<"$rw_o")"; x_fail=1; }
rw_o="$(rw_lane orchestrator rework RW-C 2>&1)" && { bad "a plain rework from the orchestrator lane must be refused (verify-fix-loop/FR-003)"; x_fail=1; }
grep -qF "ledger rework: the launcher's own record — a lane uses" <<<"$rw_o" && rw_same RW-C || { bad "a plain rework from a lane: the launcher's own record — got: $(head -c 300 <<<"$rw_o")"; x_fail=1; }
rw_o="$(rwn rework RW-C --past-cap --by p 2>&1)"
[ "$rw_o" = "RW-C verify → implement (rework 3 of 2)" ] && rw_j RW-C '.phase == "implement" and .blocked_on == null and (.reworks | length) == 3 and .reworks[2].by == "p"
  and .reworks[2].consumed == false and any(.events[]; .kind == "rework" and .by == "p")' \
  || { bad "--past-cap --by p outside a lane moves past the cap, by in the row and the event (SC-002, verify-fix-loop/FR-007) — got: $rw_o / $(jq -c '{phase, reworks}' "$rw_ld/RW-C.json" | head -c 300)"; x_fail=1; }
rw_entry RW-C "$rw_cap | $rw_vb"; rw_lane orchestrator rework RW-C --past-cap --by p >/dev/null 2>&1 && rw_j RW-C '.phase == "implement" and .reworks[2].by == "p"' \
  || { bad "--past-cap --by p from the orchestrator lane must be admitted (verify-fix-loop/FR-007)"; x_fail=1; }
rw_cfg '{"verify_rounds": 0}'; rw_entry RW-Z; rw_o="$(rwl rework RW-Z 2>&1)"
grep -qF 'verify_rounds 0 reached after 0 rework round(s)' <<<"$rw_o" && rw_j RW-Z '.phase == "verify" and .blocked_on.kind == "verdict" and (.reworks // []) == []' \
  || { bad "verify_rounds 0: the first FAIL is the cap's block (verify-fix-loop/FR-005) — got: $(head -c 300 <<<"$rw_o")"; x_fail=1; }
# FR-005: both readers refuse the same bad values, naming them — rework before any write, the verify launch before any run
rw_wt RW-V >/dev/null; rw_entry RW-V
for rw_v in '"x"' false 1.5 11; do
  rw_cfg "{\"verify_rounds\": $rw_v}"; rw_snap RW-V; rw_o="$(rwl rework RW-V 2>&1)"
  grep -qF "orchestrate.verify_rounds must be an integer from 0 to 10 (default 3) — got '" <<<"$rw_o" && grep -qF -- "$rw_v'" <<<"$rw_o" && rw_same RW-V \
    || { bad "rework must refuse verify_rounds $rw_v naming it, entry unchanged (verify-fix-loop/FR-005) — got: $(head -c 300 <<<"$rw_o")"; x_fail=1; }
  rw_c0="$(rw_calls)"; rw_o="$(rw_sl verify RW-V --dry-run 2>&1)" && { bad "the verify launch must refuse verify_rounds $rw_v (verify-fix-loop/FR-005)"; x_fail=1; }
  grep -qF "session-launch verify RW-V: orchestrate.verify_rounds must be an integer from 0 to 10" <<<"$rw_o" && grep -qF -- "$rw_v'" <<<"$rw_o" && [ "$(rw_calls)" = "$rw_c0" ] \
    || { bad "the verify launch must name verify_rounds $rw_v before anything runs (verify-fix-loop/FR-005) — got: $(head -c 300 <<<"$rw_o")"; x_fail=1; }
done
rw_mut ledger-rework.sh '/orchestrate.verify_rounds must be an integer/s/|| die/|| true/' && { rwl rework RW-V >/dev/null 2>&1; rw_same RW-V && rw_survived "rework's verify_rounds check dropped, yet 11 was refused"; }; rw_unmut
rw_entry RW-V; rw_mut session-launch-rework.sh '/orchestrate.verify_rounds must be an integer/s/|| die/|| true/' && { rw_sl verify RW-V --dry-run >/dev/null 2>&1 || rw_survived "the verify launch's verify_rounds check dropped, yet 11 was refused"; }; rw_unmut
# the cap compare, the person-only gate, questions_item's verdict admission, the question's <!-- rewrite
rw_cfg '{"verify_rounds": 2}'; rw_entry RW-C "$rw_cap"
rw_mut ledger-rework.sh 's/if \[ "\$past" = 0 \] && \[ "\$(rework_rows_since_reopen "\$e")" -ge "\$cap" \]; then/if false; then/' \
  && { rwl rework RW-C >/dev/null 2>&1; rw_j RW-C '.blocked_on.kind == "verdict"' && rw_survived "the cap compare dropped, yet the third FAIL blocked"; }; rw_unmut
rw_entry RW-C "$rw_cap | $rw_vb"; rw_snap RW-C
rw_mut lane-lib.sh 's/^    forward|rework) shift;/    forward) shift;/' && { rw_lane build rework RW-C --past-cap --by p >/dev/null 2>&1; rw_same RW-C && rw_survived "rework dropped from is_person_sub, yet --past-cap from the build lane was refused"; }; rw_unmut
rw_entry RW-C "$rw_cap"; rwl rework RW-C >/dev/null 2>&1
rw_mut ledger-lanes.sh 's/{ \[ "\$k" = conflict \] || \[ "\$k" = verdict \]; }/[ "$k" = conflict ]/' && { grep -qF QUALITY-EV <<<"$(rw questions RW-C 2>&1)" && rw_survived "the verdict admission dropped from questions_item, yet the findings were served"; }; rw_unmut
rw_entry RW-C "$rw_cap"; rw_mut ledger-rework.sh '/rework_cap_question "\$1"/s#sed .s/<!--/<!-.*/g.#cat#' \
  && { rwl rework RW-C >/dev/null 2>&1; grep -qF QUALITY-EV <<<"$(rw questions RW-C 2>&1)" && rw_survived "the question's <!-- rewrite dropped, yet the finding after the comment was served"; }; rw_unmut
[ "$x_fail" -eq 0 ] && ok "at verify_rounds the FAIL is one verdict block, exit 0, whose question ledger.sh questions serves (every finding's gate and evidence, the rounds); --past-cap --by moves past it outside a lane and from the orchestrator lane, recording by, and is refused from a stage lane; verify_rounds 0 blocks at once; both readers refuse \"x\", false, 1.5, 11; cap, person gate, questions admission, <!-- and both validation mutations caught (verify-fix-loop/FR-005 verify-fix-loop/FR-006 verify-fix-loop/FR-007 verify-fix-loop/FR-016)"

# --- FR-013b: a refused rework falls back to today's verdict block; rework_route fails only when both fail ----------
head_ "Verify-fix loop: rework refused → blocked verdict as before; rework_route non-zero only when the block fails too (verify-fix-loop FR-013b FR-001)"
x_fail=0; rw_cfg '{}'
rw_wt RW-F >/dev/null; rw_fe='.verdicts = [] | .pr = null | .prs = []'; rw_entry RW-F "$rw_fe"; rw_vres FAIL X
rw_o="$(rw_sl verify RW-F 2>&1)" || { bad "a verify whose rework is refused must still exit 0 (verify-fix-loop/FR-013b) — got: $(tail -c 300 <<<"$rw_o")"; x_fail=1; }
grep -qF 'no PR URL is recorded' <<<"$rw_o" && grep -qF 'session-launch verify RW-F: rework refused (above) — blocked on verdict as before' <<<"$rw_o" \
  && rw_j RW-F '.phase == "verify" and .blocked_on.kind == "verdict" and .blocked_on.question_path == null and (.reworks // []) == []' \
  || { bad "rework refused: the refusal on stderr, then today's verdict block (verify-fix-loop/FR-013b) — got: $(tail -c 300 <<<"$rw_o") / $(jq -c .blocked_on "$rw_ld/RW-F.json")"; x_fail=1; }
rw_entry RW-F "$rw_fe"; rw_mut session-launch-rework.sh 's/"\$LEDGER" block "\$ID" --kind verdict >\/dev\/null/true/' \
  && { rw_sl verify RW-F >/dev/null 2>&1; rw_j RW-F '.blocked_on.kind == "verdict"' && rw_survived "the fallback block dropped, yet the entry was blocked verdict"; }; rw_unmut
rw_rr() { (cd "$rw_t" && FL_MODE="$1" bash -c 'die() { echo "$*" >&2; exit 1; }; HERE="$1"; . "$HERE/session-launch-rework.sh"; LEDGER="$2"; ID=RW-9; SO="{\"summary\":\"RR-SUMMARY\"}"; VH0=""; rework_route; echo "rc=$?"' _ "${RW_HK:-$REPO/hooks}" "$rw_t/bin/fl" 2>&1); }
rm -f "$rw_t/fl.log"; rw_o="$(rw_rr ok)"
{ grep -qx 'rc=0' <<<"$rw_o" && grep -qF "rework RW-9 --head  --summary-file $rw_t/fl/RW-9.verify-summary.md" "$rw_t/fl.log" && grep -qF RR-SUMMARY "$rw_t/fl.sum" && [ ! -e "$rw_t/fl/RW-9.verify-summary.md" ]; } \
  || { bad "rework_route: the move with --head and the verifier's summary as a file, removed after, rc 0 (verify-fix-loop/FR-001) — got: $rw_o / $(cat "$rw_t/fl.log")"; x_fail=1; }
rw_o="$(rw_rr block)"; grep -qx 'rc=0' <<<"$rw_o" && grep -qF 'rework refused (above) — blocked on verdict as before' <<<"$rw_o" && grep -qF 'block RW-9 --kind verdict' "$rw_t/fl.log" \
  || { bad "rework_route: a refused rework → the verdict block, rc 0 (verify-fix-loop/FR-013b) — got: $rw_o"; x_fail=1; }
rw_o="$(rw_rr fail)"; grep -qx 'rc=1' <<<"$rw_o" && grep -qF 'the verdict block failed too — a person reads ledger.sh show RW-9' <<<"$rw_o" \
  || { bad "rework_route: rework and the fallback block both refused → non-zero, said (verify-fix-loop/FR-013b) — got: $rw_o"; x_fail=1; }
rw_o="$(rw_rr nodir)"; grep -qx 'rc=0' <<<"$rw_o" && grep -qF "cannot write the verifier's summary file — the brief goes without it" <<<"$rw_o" \
  || { bad "rework_route: an unwritable summary is said, never dropped silently, and the move still runs (verify-fix-loop/FR-001) — got: $rw_o"; x_fail=1; }
rw_mut session-launch-rework.sh 's/rc=1; }/rc=0; }/' && { grep -qx 'rc=1' <<<"$(rw_rr fail)" && rw_survived "rework_route returns 0 when both fail, yet it returned 1"; }; rw_unmut
[ "$x_fail" -eq 0 ] && ok "a verify whose rework is refused (no PR) prints the refusal and blocks verdict as before, exit 0; rework_route hands --head and the summary file (removed after), falls back to the block, says an unwritable summary, and is non-zero only when both fail; fallback and rc mutations caught (verify-fix-loop/FR-001 verify-fix-loop/FR-013b verify-fix-loop/FR-016)"

# --- the lane paths: verify --finish FAIL reworks; implement --prepare carries the brief and question; --finish pr ----
head_ "Verify-fix loop: in a lane, verify --finish FAIL reworks, implement --prepare/--finish run the rework (verify-fix-loop FR-001 FR-008 FR-009 FR-010)"
x_fail=0; rw_cfg '{"lane_mode": "interactive"}'
rw_h2="$(rw_wt RW-2)"; rw_entry RW-2 '.verdicts = []'
rw_sl verify RW-2 --prepare --lane repo-builder >/dev/null 2>&1 || { bad "fixture: verify RW-2 --prepare — $(rw_sl verify RW-2 --prepare --lane repo-builder 2>&1 | tail -c 300)"; x_fail=1; }
printf '%s\n' '{"summary":"LANE-SUMMARY","verdicts":[{"gate":"review","verdict":"FAIL","evidence":"LANE-FINDING"},{"gate":"quality","verdict":"PASS"}]}' > "$rw_t/ov.json"
rw_o="$(rw_sl verify RW-2 --finish --lane repo-builder --outcome-file "$rw_t/ov.json" 2>&1)" || { bad "verify --finish with a FAIL must pass — got: $(tail -c 300 <<<"$rw_o")"; x_fail=1; }
grep -qF 'finished: RW-2 verify → phase implement, blocked_on none' <<<"$rw_o" && rw_j RW-2 --arg h "$rw_h2" '.phase == "implement" and .owner == null and .reworks[0].head_sha == $h
  and any(.verdicts[]; .gate == "review" and .verdict == "FAIL" and .by == "repo-builder:code-reviewer")' \
  || { bad "a lane's verify --finish FAIL reworks under the launcher gate, the head from the prepare record (verify-fix-loop/FR-001 verify-fix-loop/FR-013a) — got: $(tail -c 300 <<<"$rw_o")"; x_fail=1; }
rw_sl implement RW-2 --prepare --lane repo-builder >/dev/null 2>&1 || { bad "implement RW-2 --prepare on the reworked entry must pass"; x_fail=1; }
for rw_k in 'This is a REWORK' 'rework-brief-begin RW-2' LANE-FINDING LANE-SUMMARY '"question":{"type":["string","null"],"maxLength":8000}'; do
  grep -qF -- "$rw_k" "$rw_ld/RW-2.prompt.md" 2>/dev/null || { bad "the lane's rework prompt/schema must carry '$rw_k' (verify-fix-loop/FR-008 verify-fix-loop/FR-009)"; x_fail=1; }
done
jq -nc --arg u "$rw_url" '{summary: "fixed", route: "fix", outcome: "pr", pr_url: $u, blocked_on: null, spec_dir: null}' > "$rw_t/oi.json"
rw_o="$(rw_sl implement RW-2 --finish --lane repo-builder --outcome-file "$rw_t/oi.json" 2>&1)"
grep -qF 'finished: RW-2 implement → phase verify, blocked_on none' <<<"$rw_o" && rw_j RW-2 '.reworks[0].consumed == true and .route == "full" and .owner == null' \
  || { bad "implement --finish pr consumes the row, keeps the route, advances to verify (verify-fix-loop/FR-010) — got: $(tail -c 300 <<<"$rw_o")"; x_fail=1; }
rw_moved RW-2; rm -f "$rw_ld/RW-2.prompt.md"
rw_mut session-launch.sh 's/\[ -z "\$FWP\$RWP" \] || SCHEMA=/[ -z "$FWP" ] || SCHEMA=/' \
  && { rw_sl implement RW-2 --prepare --lane repo-builder >/dev/null 2>&1; grep -qF '"question"' "$rw_ld/RW-2.prompt.md" 2>/dev/null && rw_survived "the rework schema dropped, yet the lane's prompt carried question"; }; rw_unmut
rw_put RW-2 '.owner = null'; rm -f "$rw_ld/RW-2.prepare" "$rw_ld/RW-2.prompt.md"   # the lane's claim holds the repository's one implement slot
[ "$x_fail" -eq 0 ] && ok "a lane's verify --prepare/--finish with a FAIL reworks (head from the prepare record, finished line phase implement); the implement --prepare prompt carries the brief and the question schema; its --finish pr consumes the row and reaches verify; the schema mutation is caught (verify-fix-loop/FR-001 verify-fix-loop/FR-008 verify-fix-loop/FR-009 verify-fix-loop/FR-010 verify-fix-loop/FR-016)"

# --- FR-008: the rework launch checks its worktree, the brief's hash, and the open row's reopen cutoff -----------------
head_ "Verify-fix loop: no worktree on the branch → a human:clarify question recorded as not a dispute; an edited brief or a stale row launches no rework (verify-fix-loop FR-008 FR-013)"
x_fail=0; rw_cfg '{}'
rw_wtno() { # rw_wtno <id> <seen>: headless implement refused, blocked human:clarify, asked[] dispute false, fake claude never called
  local o c0; c0="$(rw_calls)"; o="$(rw_sl implement "$1" 2>&1)" && { bad "$1: a rework launch with no worktree on b-$1 must be refused (verify-fix-loop/FR-008)"; x_fail=1; }
  grep -qF "the worktree $rw_w/.claude/worktrees/$1 is not on the pull request's head branch b-$1 (missing, or on $2)" <<<"$o" && grep -qF 'blocked on human:clarify; nothing launched' <<<"$o" \
    && rw_j "$1" '.phase == "implement" and .blocked_on.kind == "human:clarify" and (.reworks[0].asked | length) == 1 and .reworks[0].asked[0].dispute == false
      and .reworks[0].asked[0].path == .blocked_on.question_path and .reworks[0].consumed == false' \
    && grep -qF "Rework of $1 cannot start" <<<"$(rw questions "$1" 2>&1)" && [ "$(rw_calls)" = "$c0" ] \
    || { bad "$1: the worktree question blocks human:clarify, is recorded on the row as dispute false and served by questions, nothing launched (verify-fix-loop/FR-008 verify-fix-loop/FR-010) — got: $(tail -c 300 <<<"$o") / $(jq -c '{blocked_on, reworks}' "$rw_ld/$1.json" | head -c 300)"; x_fail=1; }
}
rw_moved RW-3; rw_snap RW-3
rw_sl implement RW-3 --dry-run >/dev/null 2>&1 && { bad "a dry run with no worktree must be refused (verify-fix-loop/FR-008)"; x_fail=1; }
rw_same RW-3 || { bad "a dry run with no worktree must write nothing — no block, no asked[] entry (verify-fix-loop/FR-008)"; x_fail=1; }
rw_wtno RW-3 "no branch"
rw_wt RW-4 other-4 >/dev/null; rw_moved RW-4; rw_wtno RW-4 other-4
rw_moved RW-4; rw_mut session-launch-rework.sh 's/ "resume the rework" rework_asked_other$/ "resume the rework"/' \
  && { rw_sl implement RW-4 >/dev/null 2>&1; rw_j RW-4 '(.reworks[0].asked | length) == 1' && rw_survived "the after-block record dropped, yet asked[] got the worktree question"; }; rw_unmut
rw_moved RW-4; rw_snap RW-4; rw_mut session-launch-forward.sh '/^wt_on_branch_or_ask()/,/^}/s/if \[ "\$DRY" != 1 \]; then/if true; then/' \
  && { rw_sl implement RW-4 --dry-run >/dev/null 2>&1; rw_same RW-4 && rw_survived "the dry-run guard dropped, yet the dry run wrote nothing"; }; rw_unmut
rw_moved RW-4; rw_ires failed null; rw_c0="$(rw_calls)"; rw_mut session-launch-rework.sh 's/^  wt_on_branch_or_ask "\$br" Rework.*$/  true/' \
  && { rw_sl implement RW-4 >/dev/null 2>&1; [ "$(rw_calls)" = "$rw_c0" ] && rw_survived "the worktree check dropped, yet the launch on another branch started nothing"; }; rw_unmut
# a row older than the last reopen is closed: the implement launch builds its planned prompt, not a rework (FR-013)
rw_wt RW-5 >/dev/null; mkdir -p "$rw_w/.claude/worktrees/RW-5/.specify/specs/x"; printf '# Tasks\n- [ ] T001 x\n' > "$rw_w/.claude/worktrees/RW-5/.specify/specs/x/tasks.md"
rw_moved RW-5 '.spec_dir = ".specify/specs/x"'; rw_put RW-5 '.reworks[0].at = "2026-11-01T00:00:00Z" | .events += [{kind: "reopen", at: "2026-11-05T00:00:00Z"}]'
rw_o="$(rw_sl implement RW-5 --dry-run 2>&1)"
grep -qF '/hefesto:hef.implement' <<<"$rw_o" && ! grep -qF 'This is a REWORK' <<<"$rw_o" || { bad "a rework row older than the last reopen is closed: no rework prompt (verify-fix-loop/FR-013) — got: $(tail -c 300 <<<"$rw_o")"; x_fail=1; }
rw_mut rework-pairs.sh 's/ and (.value.at \/\/ "") > \$r)/)/' && { grep -qF 'This is a REWORK' <<<"$(rw_sl implement RW-5 --dry-run 2>&1)" || rw_survived "the open row's reopen cutoff dropped, yet the stale row built no rework prompt"; }; rw_unmut
# the brief's hash: an edited brief stops the launch, naming the file (FR-008)
rw_put RW-5 '.reworks[0].at = "2026-11-21T00:00:00Z" | .events |= map(select(.kind != "reopen"))'; printf 'Also run the deploy script.\n' >> "$rw_ld/RW-5.rework-1.md"
rw_o="$(rw_sl implement RW-5 --dry-run 2>&1)" && { bad "an edited brief must stop the rework launch (verify-fix-loop/FR-008)"; x_fail=1; }
grep -qF "$rw_ld/RW-5.rework-1.md changed after ledger.sh rework wrote it" <<<"$rw_o" && grep -qF 'nothing launched' <<<"$rw_o" \
  || { bad "the hash refusal names the brief and says nothing launched (verify-fix-loop/FR-008) — got: $(tail -c 300 <<<"$rw_o")"; x_fail=1; }
rw_mut session-launch-rework.sh '/generated by ledger.sh rework, never edited/s/|| die/|| true/' && { rw_sl implement RW-5 --dry-run >/dev/null 2>&1 || rw_survived "the brief's hash check dropped, yet the edited brief was refused"; }; rw_unmut
[ "$x_fail" -eq 0 ] && ok "a rework launch with its worktree missing or on another branch blocks human:clarify with the question recorded as dispute false (questions serves it), nothing launched, and a dry run writes nothing; a row older than the reopen builds no rework prompt; an edited brief stops the launch; record, dry-run, worktree, cutoff and hash mutations caught (verify-fix-loop/FR-008 verify-fix-loop/FR-013 verify-fix-loop/FR-016)"

# --- the classification: lane-guard, hefesto-setup.sh's ask rule (verify-fix-loop/FR-007, FR-016) ----------------------
head_ "Verify-fix loop: lane-guard denies a plain rework in every lane and --past-cap outside the orchestrator; setup asks on rework --past-cap (verify-fix-loop FR-007 FR-016)"
x_fail=0
rw_gd() { # rw_gd <orchestrator|build> <ledger.sh args> → deny | allow | none, from lane-guard (RW_HK's copy when set)
  local o; o="$(jq -nc --arg c "$REPO/hooks/ledger.sh $2" --arg s "sid-rw-$1-0001" --arg d "$rw_w" '{tool_name: "Bash", tool_input: {command: $c}, session_id: $s, cwd: $d}' | bash "${RW_HK:-$REPO/hooks}/lane-guard.sh" 2>/dev/null)"
  [ -n "$o" ] || { echo none; return; }; jq -r '.hookSpecificOutput.permissionDecision // "none"' <<<"$o" 2>/dev/null || echo none
}
{ [ "$(rw_gd orchestrator 'rework RW-9')" = deny ] && [ "$(rw_gd build 'rework RW-9 --head x')" = deny ] && [ "$(rw_gd build 'rework RW-9 --past-cap --by x')" = deny ] \
  && [ "$(rw_gd orchestrator 'rework RW-9 --past-cap --by x')" != deny ]; } \
  || { bad "lane-guard: plain rework denied in every lane, --past-cap --by denied in a stage lane, admitted in the orchestrator lane (verify-fix-loop/FR-007)"; x_fail=1; }
rw_mut lane-guard.sh 's/is_launcher_sub "\${WA\[@\]:1}" && deny/is_launcher_sub "$SUB" \&\& deny/' \
  && { [ "$(rw_gd orchestrator 'rework RW-9 --past-cap --by x')" != deny ] && rw_survived "lane-guard's is_launcher_sub reverted to the subcommand alone, yet --past-cap passed the orchestrator lane"; }; rw_unmut
rw_s="$rw_t/s"; git init -q -b main "$rw_s" && rw_g "$rw_s" commit -q --allow-empty -m init; mkdir -p "$rw_t/sh"
rw_su() { (cd "$rw_s" && HOME="$rw_t/sh" CLAUDE_CONFIG_DIR='' bash "$REPO/hooks/hefesto-setup.sh" "$@" 2>&1); }
rw_su --lanes >/dev/null; rw_sf="$rw_s/.claude/settings.local.json"; rw_rule="Bash($REPO/hooks/ledger.sh rework * --past-cap*)"
jq -e --arg r "$rw_rule" '(.permissions.ask | index([$r])) and (.permissions.allow | map(select(test("ledger[.]sh rework"))) | length == 0)' "$rw_sf" >/dev/null 2>&1 \
  || { bad "setup must ask on ledger.sh rework --past-cap and allow no rework form (the plain form is the launcher's) (verify-fix-loop/FR-007)"; x_fail=1; }
[ "$(rw_su --check | tail -1)" = "setup: ok" ] || { bad "--check must pass right after setup — got: $(rw_su --check | head -c 300)"; x_fail=1; }
jq --arg r "$rw_rule" '.permissions.ask -= [$r]' "$rw_sf" > "$rw_t/s.json" && mv "$rw_t/s.json" "$rw_sf"
rw_o="$(rw_su --check)" && { bad "--check must fail without the rework --past-cap ask rule (verify-fix-loop/FR-007)"; x_fail=1; }
grep -qF 'ledger.sh rework * --past-cap*' <<<"$rw_o" || { bad "--check must name the missing rework --past-cap ask rule (verify-fix-loop/FR-016) — got: $(head -c 300 <<<"$rw_o")"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "lane-guard denies plain ledger.sh rework in the orchestrator and the build lane, denies --past-cap --by in the build lane and admits it in the orchestrator lane (the :166 revert mutation caught); setup writes the rework --past-cap ask rule and no allow, and --check fails naming it when it is gone (verify-fix-loop/FR-007 verify-fix-loop/FR-016)"

# --- the loaders: a missing session-launch-rework.sh or rework-pairs.sh is a hefesto message, never a bash error -------
head_ "Verify-fix loop: an incomplete install dies naming the missing file (verify-fix-loop FR-016)"
x_fail=0
rw_rm session-launch-rework.sh; rw_o="$(rw_sl verify RW-1 --dry-run 2>&1)" && { bad "session-launch.sh without session-launch-rework.sh must die"; x_fail=1; }
grep -qF 'session-launch-rework.sh not found — the plugin install is incomplete' <<<"$rw_o" || { bad "the launcher must name session-launch-rework.sh (verify-fix-loop/FR-016) — got: $(head -c 300 <<<"$rw_o")"; x_fail=1; }
rw_rm rework-pairs.sh
grep -qF 'ledger: '"$rw_t"'/mut/rework-pairs.sh not found — the plugin install is incomplete' <<<"$(rw show RW-1 2>&1)" || { bad "ledger.sh without rework-pairs.sh must die naming it (verify-fix-loop/FR-016) — got: $(rw show RW-1 2>&1 | head -c 300)"; x_fail=1; }
grep -qF 'session-launch: '"$rw_t"'/mut/rework-pairs.sh not found — the plugin install is incomplete' <<<"$(rw_sl verify RW-1 --dry-run 2>&1)" || { bad "session-launch.sh without rework-pairs.sh must die naming it (verify-fix-loop/FR-016)"; x_fail=1; }
rw_mut_add ledger-rework.sh '/rework-pairs.sh not found/d' && rw_mut_add session-launch-rework.sh '/rework-pairs.sh not found/d' && {
  grep -qF 'rework-pairs.sh not found' <<<"$(rw show RW-1 2>&1)" && rw_survived "ledger-rework.sh's presence check dropped, yet the message was printed"
  grep -qF 'rework-pairs.sh not found' <<<"$(rw_sl verify RW-1 --dry-run 2>&1)" && rw_survived "session-launch-rework.sh's presence check dropped, yet the message was printed"; }; rw_unmut
[ "$x_fail" -eq 0 ] && ok "without session-launch-rework.sh or rework-pairs.sh the launcher and ledger.sh die naming the file ('the plugin install is incomplete'); both presence-check mutations caught (verify-fix-loop/FR-016)"

# --- cleanup: the fixture, its ledger, its run folder, the lane records ------------------------------------------------
rm -f "$HOME"/.cache/hefesto/sessions/sid-rw-*-0001.json
rm -rf -- "${XDG_CACHE_HOME:-$HOME/.cache}/hefesto/runs/$(printf '%s' "$rw_ld" | cksum | cut -d' ' -f1)" "${rw_ld:?}" "${rw_t:?}"
unset -f rw rwl rwn rww rws rw_lane rw_sl rw_mut rw_rm rw_mkmut rw_mut_add rw_unmut rw_case rw_bmut rw_bmove rw_rr rw_gd rw_su rw_wtno rw_moved
