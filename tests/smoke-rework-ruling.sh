# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs and sed scripts are single-quoted on purpose
#
# verify-fix-loop (HEF-57) smoke checks, part 18b — a finding the builder disputes is a person's question: the dispute
# recorded on the rework row (`record --rework-asked`), the person's answer paired with it (`rework_pairs`), stamped as a
# ruling (`record --rework-consumed`), handed to the next rework run and every later verify, and a ruled verify never
# recording a verified head.
#
# SOURCED by tests/smoke.sh after part 18, never run on its own. Self-contained (smoke-rework.sh's model, no helper
# shared with it): a fixture repo with a bare origin and a worktree per entry, a named fake gh (FakeGh), a fake claude
# printing $rr_t/result.json, the real ledger.sh and session-launch.sh, and rr_mut: a scratch copy of the hooks folder
# with one file mutated by sed, cmp -s proving it applied. Blocks, asked[] records and answers are made by the real
# commands (rr_ask), so the pairing is tested on the state the launcher and the person leave, not on hand-written rows.

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ sld >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-rework-ruling.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_, sld)"
  else echo "tests/smoke-rework-ruling.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

head_ "Verify-fix loop: a disputed finding, the person's ruling, and the verify it reaches (verify-fix-loop FR-009..FR-012)"

# --- the fixture ---------------------------------------------------------------------------------------------------
rr_t="$(cd "$(mktemp -d)" && pwd -P)"; rr_w="$rr_t/w"; rr_url="https://github.com/acme/app/pull/9"
rr_g() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
git init -q --bare -b main "$rr_t/origin.git" && git init -q -b main "$rr_w" && rr_g "$rr_w" commit -q --allow-empty -m init \
  && git -C "$rr_w" remote add origin "$rr_t/origin.git" && git -C "$rr_w" push -q origin main 2>/dev/null
mkdir -p "$rr_t/bin" "$rr_t/cfg" "$rr_w/.claude"
cat > "$rr_t/bin/gh" <<'EOF'
#!/bin/bash
case "$1 $2" in "auth status") exit 0 ;; *) echo "FakeGh: unexpected gh $*" >&2; exit 1 ;; esac
EOF
cat > "$rr_t/bin/claude" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$rr_t/claude.log"
cat "$rr_t/result.json"
EOF
chmod +x "$rr_t/bin/gh" "$rr_t/bin/claude"
rr_ld="$(sld "$rr_w")"; mkdir -p "$rr_ld"; RR_GH="$rr_t/bin/gh"
rr_row='{"n":1,"pr_url":"https://github.com/acme/app/pull/9","head_sha":null,"sha256":"s","at":"2026-11-20T00:00:00Z","by":null,"consumed":false,"asked":[],"ruling":[]}'
rr_cfg() { printf '{"name":"app","orchestrate":%s}\n' "$1" > "$rr_w/.claude/project-status.json"; }   # rr_cfg <orchestrate JSON>
rr_entry() { # rr_entry <id> [jq filter] [jq args…] → a verify entry on PR #9, branch b-<id>, one review FAIL; the filter sees $ld
  jq -n --arg id "$1" --arg u "$rr_url" --arg wt "$rr_w/.claude/worktrees/$1" '{id: $id, item_kind: "feature", phase: "verify", owner: null,
    route: "full", pr: {url: $u, number: 9}, prs: [{url: $u, number: 9}], branch: "b-\($id)", worktree: $wt, runs: [], attempts: 0,
    blocked_on: null, updated: (now | todate), verdicts: [{gate: "review", verdict: "FAIL", by: "verify-\($id)", at: "2026-11-10T00:00:01Z", evidence: "EV-\($id)"}]}' \
    | jq --arg ld "$rr_ld" "${@:3}" "${2:-.}" > "$rr_ld/$1.json"
}
rr_wt() { # rr_wt <id> → a worktree at the launch path on a new branch b-<id> with one commit; prints its head
  local p="$rr_w/.claude/worktrees/$1"
  git -C "$rr_w" worktree add -q "$p" -b "b-$1" main >/dev/null 2>&1 && rr_g "$p" commit -q --allow-empty -m "work $1" >/dev/null 2>&1
  git -C "$p" rev-parse HEAD
}
rr() { (cd "$rr_w" && HEFESTO_GH_BIN="$RR_GH" bash "${RR_LG:-$REPO/hooks/ledger.sh}" "$@"); }   # the caller's own environment
rrl() { (cd "$rr_w" && launcher env HEFESTO_GH_BIN="$RR_GH" bash "${RR_LG:-$REPO/hooks/ledger.sh}" "$@"); }   # as the launcher
rrn() { (cd "$rr_w" && env -u CLAUDE_CODE_SESSION_ID -u HEFESTO_LAUNCHER HEFESTO_GH_BIN="$RR_GH" bash "${RR_LG:-$REPO/hooks/ledger.sh}" "$@"); }   # a person
rrw() { (cd "$rr_w" && launcher env HEFESTO_WORKER=1 HEFESTO_GH_BIN="$RR_GH" bash "${RR_LG:-$REPO/hooks/ledger.sh}" "$@"); }   # a worker, marker set
rrs() { (cd "$rr_w" && env CLAUDE_CODE_SESSION_ID=sid-rr-nobody-0001 HEFESTO_LAUNCHER=1 HEFESTO_GH_BIN="$RR_GH" bash "${RR_LG:-$REPO/hooks/ledger.sh}" "$@"); }   # a session
rr_sl() { (cd "$rr_w" && env -u CLAUDE_CODE_SESSION_ID PATH="$rr_t/bin:$PATH" HEFESTO_GH_BIN="$RR_GH" CLAUDE_CONFIG_DIR="$rr_t/cfg" bash "${RR_SL:-$REPO/hooks/session-launch.sh}" "$@"); }
rr_dry() { rr_sl "$1" "$2" --dry-run 2>&1; }   # rr_dry <role> <id> → the launch line (prompt and schema), nothing written
rr_j() { jq -e "${@:2}" "$rr_ld/$1.json" >/dev/null 2>&1; }   # rr_j <id> [--arg …] <jq test>
rr_put() { jq "$2" "$rr_ld/$1.json" > "$rr_t/e.tmp" && mv "$rr_t/e.tmp" "$rr_ld/$1.json"; }
rr_snap() { cksum < "$rr_ld/$1.json" > "$rr_t/snap.ck"; ls -a "$rr_ld" > "$rr_t/snap.ls"; }
rr_same() { [ "$(cksum < "$rr_ld/$1.json")" = "$(cat "$rr_t/snap.ck")" ] && [ "$(ls -a "$rr_ld")" = "$(cat "$rr_t/snap.ls")" ]; }   # entry AND folder
rr_calls() { touch "$rr_t/claude.log"; wc -l < "$rr_t/claude.log" | tr -d ' '; }
rr_sha() { sha256sum < "$1" | cut -c1-64; }
rr_res() { jq -nc --argjson so "$1" '{session_id: "rr", total_cost_usd: 0, structured_output: $so}' > "$rr_t/result.json"; }
rr_pass() { rr_res '{"summary":"VERIFIER","verdicts":[{"gate":"verify","verdict":"PASS"},{"gate":"review","verdict":"PASS"},{"gate":"quality","verdict":"PASS"},{"gate":"scan","verdict":"PASS"}]}'; }
rr_ires() { # rr_ires <outcome> <pr_url JSON> [blocked_on JSON] [question] → a builder's implement outcome
  rr_res "$(jq -nc --arg o "$1" --argjson u "$2" --argjson b "${3:-null}" --arg q "${4:-}" '{summary: "builder", route: "fix", outcome: $o, pr_url: $u, blocked_on: $b, spec_dir: null}
    + (if $q == "" then {} else {question: $q} end)')"
}
rr_moved() { rr_entry "$1" "${2:-.}"; rrl rework "$1" >/dev/null 2>&1 || { bad "fixture: rework $1 must move it — $(rrl rework "$1" 2>&1 | tail -c 300)"; x_fail=1; }; }
rr_qn=100
rr_ask() { # rr_ask <id> <dispute|other|none|plan-review> <question text> <answer text>: a human:clarify block with its question
  # file, the launcher's asked[] record (none: the record lost; plan-review: a dispute whose block is then replaced by
  # human:plan-review), then the person's answer — every step the real command
  local q="$rr_ld/$1.question-$rr_qn.md" r=0; rr_qn=$((rr_qn + 1)); printf '%s\n' "$3" > "$q"; printf '%s\n' "$4" > "$rr_t/ans.md"
  rrl block "$1" --kind human:clarify --question "$q" >/dev/null 2>&1 || r=1
  case "$2" in dispute|other) rrl record "$1" --rework-asked "$2" >/dev/null 2>&1 || r=1 ;;
    plan-review) { rrl record "$1" --rework-asked dispute && rrl block "$1" --kind human:plan-review; } >/dev/null 2>&1 || r=1 ;;
    swap) printf 'Q-SWAPPED\n' > "$q.swap.md"
      { rrl record "$1" --rework-asked dispute && rrl block "$1" --kind human:clarify --question "$q.swap.md"; } >/dev/null 2>&1 || r=1 ;; esac
  rrn answer "$1" --file "$rr_t/ans.md" --reviewed-by-human --by Ana </dev/null >/dev/null 2>&1 || r=1
  [ "$r" = 0 ] || { bad "fixture: rr_ask $1 $2 must block, record and answer (verify-fix-loop/FR-010) — got: $(jq -c '{blocked_on, reworks}' "$rr_ld/$1.json" | head -c 300)"; x_fail=1; }
}
rr_pl() { # rr_pl <id> → rework_pairs over the entry as the PROMPT's loader reads it (session-launch-rework.sh sourcing rework-pairs.sh)
  bash -c 'die() { echo "$*" >&2; exit 1; }; HERE="$1"; . "$HERE/session-launch-rework.sh"; jq -c "$REWORK_PAIRS_JQ rework_pairs" "$2"' _ "$REPO/hooks" "$rr_ld/$1.json"
}
rr_mut() { # rr_mut <hook file> <sed script> → RR_LG / RR_SL run a scratch hooks copy with that file mutated (0), or bad + 1
  rm -rf "$rr_t/mut"; mkdir -p "$rr_t/mut"; local f; for f in "$REPO"/hooks/*; do ln -s "$f" "$rr_t/mut/$(basename "$f")"; done
  RR_LG="$rr_t/mut/ledger.sh"; RR_SL="$rr_t/mut/session-launch.sh"
  rm -f "$rr_t/mut/$1"; sed "$2" "$REPO/hooks/$1" > "$rr_t/mut/$1"; chmod +x "$rr_t/mut/$1"
  cmp -s "$REPO/hooks/$1" "$rr_t/mut/$1" && { bad "verify-fix-loop mutation did not apply to $1: $2"; x_fail=1; return 1; }; return 0
}
rr_unmut() { unset RR_LG RR_SL; }
rr_survived() { bad "mutation survived: $1 (verify-fix-loop/FR-016)"; x_fail=1; }

# --- SC-003: a dispute, the person's answer, the rework run and the verify it reaches (FR-009..FR-012) ----------------
x_fail=0; rr_cfg '{}'; rr_wt RR-1 >/dev/null; rr_moved RR-1
rr_ires blocked null '"human:clarify"' 'DISPUTE-Q1: the review finding is wrong, tests/a.sh:12 already covers it'
rr_o="$(rr_sl implement RR-1 2>&1)" || { bad "a rework run reporting blocked human:clarify must pass (verify-fix-loop/FR-010) — got: $(tail -c 300 <<<"$rr_o")"; x_fail=1; }
rr_j RR-1 '.phase == "implement" and .blocked_on.kind == "human:clarify" and (.blocked_on.question_path | type) == "string" and (.reworks | length) == 1
  and ([.events[] | select(.kind == "rework")] | length) == 1 and (.reworks[0] | .consumed == false and (.asked | length) == 1
  and .asked[0].dispute == true and .asked[0].answers_before == 0) and .reworks[0].asked[0].path == .blocked_on.question_path' \
  || { bad "SC-003: the dispute → blocked human:clarify with its question, recorded on the open row as a dispute (answers_before 0), the round count unchanged (verify-fix-loop/FR-010 verify-fix-loop/FR-011) — got: $(jq -c '{phase, blocked_on, reworks}' "$rr_ld/RR-1.json" | head -c 400)"; x_fail=1; }
grep -qF DISPUTE-Q1 <<<"$(rr questions RR-1 2>&1)" || { bad "SC-003: ledger.sh questions must print the dispute (verify-fix-loop/FR-010) — got: $(rr questions RR-1 2>&1 | head -c 300)"; x_fail=1; }
printf 'RULING-A1: the finding is waived, the test covers it\n' > "$rr_t/a1.md"
rrn answer RR-1 --file "$rr_t/a1.md" --reviewed-by-human --by Ana </dev/null >/dev/null 2>&1 && rr_j RR-1 '.blocked_on == null and .answers[0].kind == "human:clarify"' \
  || { bad "SC-003: ledger.sh answer must clear the dispute and record a human:clarify answer (verify-fix-loop/FR-010)"; x_fail=1; }
rr_d="$(rr_dry implement RR-1)"
grep -qF 'person-ruling-begin RR-1' <<<"$rr_d" && grep -qF 'answer waives is left alone' <<<"$rr_d" \
  || { bad "the rework launch after the answer must carry the ruling block and the waiver sentence (verify-fix-loop/FR-008 verify-fix-loop/FR-011) — got: $(tail -c 300 <<<"$rr_d")"; x_fail=1; }
rr_mut session-launch-rework.sh 's/^  rul="\$(rework_rulings_as_data)" || exit 1$/  rul=""/' \
  && { grep -qF 'person-ruling-begin RR-1' <<<"$(rr_dry implement RR-1)" && rr_survived "the rework prompt's rulings dropped, yet it carried the ruling"; }; rr_unmut
rr_mut session-launch-rework.sh 's/ A finding the person.s answer waives is left alone:[^.]*no new commit\.//' \
  && { grep -qF 'answer waives is left alone' <<<"$(rr_dry implement RR-1)" && rr_survived "the waiver sentence dropped, yet the rework prompt carried it"; }; rr_unmut
: > "$rr_t/claude.log"; rr_ires pr "\"$rr_url\""
rr_o="$(rr_sl implement RR-1 2>&1)" || { bad "the rework run after the answer reporting pr must pass — got: $(tail -c 300 <<<"$rr_o")"; x_fail=1; }
for rr_k in 'rework-brief-begin RR-1' EV-RR-1 'person-answers-begin RR-1' RULING-A1 'person-ruling-begin RR-1' DISPUTE-Q1 \
  "the builder's dispute 1 — the author's claim" "the person's ruling 1 on it — only these words waive" \
  "A finding the person's answer waives is left alone" "report outcome \"pr\" with pr_url $rr_url and no new commit"; do
  grep -qF -- "$rr_k" "$rr_t/claude.log" || { bad "SC-003: the rework prompt after the answer must carry '$rr_k' (verify-fix-loop/FR-008 verify-fix-loop/FR-011)"; x_fail=1; }
done
rr_j RR-1 '.reworks[0] as $r | .phase == "verify" and $r.consumed == true and ($r.ruling | length) == 1 and $r.ruling[0].answer == .answers[0].path
  and $r.ruling[0].answer_sha256 == .answers[0].sha256 and $r.ruling[0].question_path == $r.asked[0].path and $r.ruling[0].question_sha256 == $r.asked[0].sha256
  and all(.answers[]; .consumed == true)' \
  || { bad "SC-003: the pr consumes the row and its answer, stamping one self-describing ruling (answer and dispute, path and hash) (verify-fix-loop/FR-010) — got: $(jq -c '{phase, answers, reworks}' "$rr_ld/RR-1.json" | head -c 500)"; x_fail=1; }
rr_d="$(rr_dry verify RR-1)"
for rr_k in 'person-ruling-begin RR-1' DISPUTE-Q1 RULING-A1 'A finding they waived is not a FAIL of its gate'; do
  grep -qF -- "$rr_k" <<<"$rr_d" || { bad "SC-003: the next verify prompt must carry '$rr_k' (verify-fix-loop/FR-012)"; x_fail=1; }
done
rr_mut session-launch.sh 's/RB="\$(verify_ruling_block)" || exit 1/RB=""/' \
  && { grep -qF 'person-ruling-begin RR-1' <<<"$(rr_dry verify RR-1)" && rr_survived "the verify ruling block dropped, yet the verify prompt carried it"; }; rr_unmut
rr_pass; rr_sl verify RR-1 >/dev/null 2>&1
rr_j RR-1 '.phase == "pr" and .blocked_on.kind == "human:merge" and (.pr.verified_head // null) == null' \
  || { bad "the ruled verify's all PASS → pr + human:merge, verified head none (verify-fix-loop/FR-012) — got: $(jq -c '{phase, blocked_on, pr}' "$rr_ld/RR-1.json")"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "SC-003 through the real launcher: a disputing builder → blocked human:clarify, the dispute recorded on the open row and served by ledger.sh questions, the round count unchanged; after ledger.sh answer the rework prompt carries the brief, the answer, the dispute beside its ruling and the waiver sentence; its pr stamps the ruling; the next verify prompt carries the ruling block and its PASS records no head; rulings, waiver and ruling-block mutations caught (verify-fix-loop/FR-008 verify-fix-loop/FR-009 verify-fix-loop/FR-010 verify-fix-loop/FR-011 verify-fix-loop/FR-012 verify-fix-loop/FR-016)"

# --- FR-009: the question field only on a rework run — a consumed row is no rework --------------------------------
head_ "Verify-fix loop: the implement schema gains question only with an open rework row (verify-fix-loop FR-009)"
x_fail=0
rr_wt RR-N >/dev/null; mkdir -p "$rr_w/.claude/worktrees/RR-N/.specify/specs/x"; printf '# Tasks\n- [ ] T001 x\n' > "$rr_w/.claude/worktrees/RR-N/.specify/specs/x/tasks.md"
printf 'OLD-BRIEF\n' > "$rr_ld/RR-N.rework-1.md"
rr_entry RR-N '.phase = "implement" | .verdicts = [] | .spec_dir = ".specify/specs/x" | .reworks = [$row | .consumed = true | .sha256 = $s]' \
  --argjson row "$rr_row" --arg s "$(rr_sha "$rr_ld/RR-N.rework-1.md")"
rr_o="$(rr_dry implement RR-N)"
grep -qF '/hefesto:hef.implement' <<<"$rr_o" && ! grep -qF '"question"' <<<"$rr_o" && ! grep -qF OLD-BRIEF <<<"$rr_o" \
  || { bad "an entry whose rework row is consumed builds the planned prompt with the 9.2.0 schema — no question, no brief (verify-fix-loop/FR-009) — got: $(tail -c 300 <<<"$rr_o")"; x_fail=1; }
rr_mut rework-pairs.sh 's/select(\.value\.consumed != true and/select(true and/' \
  && { grep -qF '"question"' <<<"$(rr_dry implement RR-N)" || rr_survived "a consumed row read as open, yet the launch had no question field"; }; rr_unmut
[ "$x_fail" -eq 0 ] && ok "an implement launch whose only rework row is consumed keeps the planned prompt and the schema without question; reading a consumed row as open is caught (verify-fix-loop/FR-009 verify-fix-loop/FR-016)"

# --- P13: record --rework-asked / --rework-consumed are the launcher's own records --------------------------------
head_ "Verify-fix loop: record --rework-asked and --rework-consumed refused from a session and a worker (verify-fix-loop FR-010 FR-016)"
x_fail=0
rr_gfix() { printf 'GATE-Q\n' > "$rr_ld/RR-G.question-1.md"
  rr_entry RR-G '.phase = "implement" | .verdicts = [] | .reworks = [$row] | .blocked_on = {kind: "human:clarify", since: "2026-11-20T00:00:00Z", question_path: ($ld + "/RR-G.question-1.md")}' \
    --argjson row "$rr_row"; rr_snap RR-G; }
rr_gcase() { # rr_gcase <rrs|rrw> <flag…>: refused naming the flag and the gate, entry and folder byte-identical
  local r="$1" tx="never from inside a launched worker" o; shift; [ "$r" = rrs ] && tx="only session-launch.sh writes it (HEFESTO_LAUNCHER=1, no session id)"
  rr_gfix; o="$("$r" record RR-G "$@" 2>&1)" && { bad "record $* from $r must be refused (verify-fix-loop/FR-010)"; x_fail=1; }
  grep -qF -- "$tx" <<<"$o" && grep -qF -- "$1" <<<"$o" && rr_same RR-G \
    || { bad "record $* from $r: refused naming '$tx', entry unchanged (verify-fix-loop/FR-010) — got: $(head -c 300 <<<"$o")"; x_fail=1; }
}
for rr_r in rrs rrw; do rr_gcase "$rr_r" --rework-consumed; rr_gcase "$rr_r" --rework-asked dispute; done
rr_gfix; rrl record RR-G --rework-asked dispute >/dev/null 2>&1 && rr_j RR-G '(.reworks[0].asked | length) == 1 and .reworks[0].asked[0].path == .blocked_on.question_path' \
  && rrl record RR-G --rework-consumed >/dev/null 2>&1 && rr_j RR-G '.reworks[0].consumed == true' \
  || { bad "the launcher's record --rework-asked (the block's own question) and --rework-consumed must be admitted (verify-fix-loop/FR-010)"; x_fail=1; }
rr_gmut() { # rr_gmut <sed on ledger-rework.sh> <runner> <label>: both flags through the mutant — a byte-identical entry = survived
  rr_mut ledger-rework.sh "$1" || return 0
  rr_gfix; "$2" record RR-G --rework-consumed >/dev/null 2>&1; rr_same RR-G && rr_survived "$3 (--rework-consumed)"
  rr_gfix; "$2" record RR-G --rework-asked dispute >/dev/null 2>&1; rr_same RR-G && rr_survived "$3 (--rework-asked)"; rr_unmut
}
rr_gmut '/only session-launch.sh writes it (HEFESTO_LAUNCHER=1/s/am_is_launcher || die/true || die/' rrs "the launcher-marker check dropped, yet a session's record was refused"
rr_gmut 's/^  am_not_worker "record \$ID \$1"$/  :/' rrw "the worker check dropped, yet a worker's record was refused"
[ "$x_fail" -eq 0 ] && ok "record --rework-consumed and --rework-asked dispute are refused from a session and from a worker, byte-identical, naming the gate; the launcher's are admitted; both gate removals caught (verify-fix-loop/FR-010 verify-fix-loop/FR-016)"

# --- P14: the pairing — two disputes, a worktree question, a plan-review answer, a lost record; both loaders ---------
head_ "Verify-fix loop: --rework-consumed pairs each answer with the dispute its block recorded, and the prompt's loader agrees (verify-fix-loop FR-010 FR-012)"
x_fail=0; rr_wt RR-M >/dev/null
rr_mfix() { # RR-M: an open row, then five blocks and answers: dispute A, worktree question, dispute C, a dispute re-blocked
  # human:plan-review, a block whose asked[] record was lost — rulings: A and C only
  rr_entry RR-M '.phase = "implement" | .verdicts = [] | .reworks = [$row]' --argjson row "$rr_row"
  rr_ask RR-M dispute Q-DISPUTE-A RULE-A; rr_ask RR-M other Q-WORKTREE ANS-WORKTREE; rr_ask RR-M dispute Q-DISPUTE-C RULE-C
  rr_ask RR-M plan-review Q-DISPUTE-D ANS-REPLAN; rr_ask RR-M none Q-LOST ANS-LOST
}
rr_mfix; rr_p="$(rr_pl RR-M)"
rr_o="$(rrl record RR-M --rework-consumed 2>&1)" || { bad "record --rework-consumed alone must pass — got: $(head -c 300 <<<"$rr_o")"; x_fail=1; }
rr_j RR-M '.reworks[0] as $r | $r.consumed == true and ($r.asked | length) == 4 and (.answers | length) == 5 and all(.answers[]; .consumed == true)
  and .answers[3].kind == "human:plan-review" and ($r.ruling | length) == 2 and $r.ruling[0].answer == .answers[0].path and $r.ruling[0].answer_sha256 == .answers[0].sha256
  and $r.ruling[0].question_path == $r.asked[0].path and $r.ruling[0].question_sha256 == $r.asked[0].sha256 and $r.ruling[1].answer == .answers[2].path
  and $r.ruling[1].question_path == $r.asked[2].path' \
  || { bad "--rework-consumed alone: two rulings (both disputes), not the worktree, plan-review or lost-record answers; the row and every answer consumed (verify-fix-loop/FR-010) — got: $(jq -c '.reworks[0] | {asked, ruling}' "$rr_ld/RR-M.json" | head -c 600)"; x_fail=1; }
[ -n "$rr_p" ] && [ "$rr_p" = "$(jq -c '.reworks[0].ruling' "$rr_ld/RR-M.json")" ] \
  || { bad "rework_pairs read by session-launch-rework.sh before the stamp must equal what ledger-rework.sh stamped (verify-fix-loop/FR-010 P14) — prompt: $(head -c 300 <<<"$rr_p")"; x_fail=1; }
rr_pmut() { # rr_pmut <hook> <sed> <label> <jq test the correct stamp passes>: RR-M rebuilt, stamped by the mutant
  rr_mfix; rr_mut "$1" "$2" || return 0
  rrl record RR-M --rework-consumed >/dev/null 2>&1; rr_j RR-M "$4" && rr_survived "$3"; rr_unmut
}
rr_two='(.reworks[0].ruling | length) == 2'
# the kind and ordinal tests each guard a case the question match also catches: each mutant drops the match too, so
# the test proves the older test alone holds the pre-match rule (HEF-57 verify)
rr_qx='s/ and (\$a\.question \/\/ "") == \$q\.path)/)/'
rr_pmut rework-pairs.sh "s/ and \\.value\\.kind == \"human:clarify\")/)/; $rr_qx" "the kind test (and the question match) dropped, yet the human:plan-review answer after a dispute was no ruling" "$rr_two"
rr_pmut rework-pairs.sh "s/select(\\.answers_before == \\\$i)/select(.answers_before <= \$i)/; $rr_qx" "answers_before <= i (and the question match dropped), yet the answer to the unrecorded block stayed unpaired" "$rr_two"
rr_pmut rework-pairs.sh 's/select(\$q != null and \$q\.dispute == true and /select($q != null and /' "the dispute test dropped, yet the worktree question's answer was no ruling" "$rr_two"
rr_pmut ledger-rework.sh 's/| \.reworks\[\$k\]\.ruling = ((\.reworks\[\$k\]\.ruling \/\/ \[\]) + \$p) |/|/' "the stamp dropped, yet the row carried two rulings" "$rr_two"
rr_pmut ledger-rework.sh 's/(if \.answers then \.answers |= map(\.consumed = true) else \. end) end/. end/' "the answers left open by --rework-consumed, yet they were consumed" 'all(.answers[]; .consumed == true)'
# HEF-57 verify (review): a dispute, then a same-kind question swapped in and answered — that answer is no ruling
rr_entry RR-S '.phase = "implement" | .verdicts = [] | .reworks = [$row]' --argjson row "$rr_row"; rr_ask RR-S swap Q-DISPUTE-S RULE-OTHER
rr_j RR-S '.answers[0].question != null and .answers[0].question != .reworks[0].asked[0].path' \
  || { bad "the answer must record the swapped-in question it cleared — got: $(jq -c '{answers, asked: .reworks[0].asked}' "$rr_ld/RR-S.json" | head -c 300)"; x_fail=1; }
[ "$(rr_pl RR-S)" = "[]" ] || { bad "an answer to a swapped-in question must not rule on the dispute (verify-fix-loop/FR-010) — got: $(rr_pl RR-S | head -c 300)"; x_fail=1; }
rr_mut rework-pairs.sh 's/ and (\$a\.question \/\/ "") == \$q\.path)/)/' && {
  [ "$(bash -c 'die() { echo "$*" >&2; exit 1; }; HERE="$1"; . "$HERE/session-launch-rework.sh"; jq -c "$REWORK_PAIRS_JQ rework_pairs" "$2"' _ "$rr_t/mut" "$rr_ld/RR-S.json")" = "[]" ] \
    && rr_survived "the question match dropped, yet the swapped-in answer was still no ruling"; }; rr_unmut
rr_mfix; rrl record RR-M --rework-consumed >/dev/null 2>&1; rr_put RR-M '.phase = "verify"'; cp "$rr_ld/RR-M.json" "$rr_t/m.json"
rr_d="$(rr_dry verify RR-M)"
for rr_k in 'person-ruling-begin RR-M' 'ruling 1 on it' 'ruling 2 on it' Q-DISPUTE-A RULE-A Q-DISPUTE-C RULE-C; do
  grep -qF -- "$rr_k" <<<"$rr_d" || { bad "two disputes in one row: the verify prompt must carry '$rr_k' (verify-fix-loop/FR-012)"; x_fail=1; }
done
for rr_k in 'ruling 3 on it' Q-WORKTREE ANS-WORKTREE ANS-REPLAN Q-LOST ANS-LOST; do
  grep -qF -- "$rr_k" <<<"$rr_d" && { bad "the verify prompt must not carry '$rr_k' — not a ruling (verify-fix-loop/FR-010 verify-fix-loop/FR-012)"; x_fail=1; }
done
[ "$x_fail" -eq 0 ] && ok "--rework-consumed alone stamps exactly the two disputes' answers (a worktree question's, a human:plan-review answer after a dispute and a lost record's answer stay out), consuming the row and every answer; the prompt's loader computes the same pairs; both rulings reach the verify prompt; kind, == i, dispute, stamp and consumption mutations caught (verify-fix-loop/FR-010 verify-fix-loop/FR-012 verify-fix-loop/FR-016)"

# --- FR-012: the ruling block — persistence, the reopen cutoff, byte-identical without, hashes at the verify launch ----
head_ "Verify-fix loop: the verify ruling block holds across later rounds, ends at a reopen, and dies on a changed file (verify-fix-loop FR-012)"
x_fail=0
jq --argjson row "$rr_row" '.reworks += [$row | .n = 2 | .at = "2026-11-21T00:00:00Z" | .consumed = true]' "$rr_t/m.json" > "$rr_ld/RR-M.json"
grep -qF RULE-A <<<"$(rr_dry verify RR-M)" || { bad "a ruling holds across a later rework round (verify-fix-loop/FR-012)"; x_fail=1; }
rr_mut session-launch-rework.sh 's/| \[(\.reworks \/\/ \[\])\[\] | select(\.consumed == true/| [(.reworks \/\/ [])[-1:][] | select(.consumed == true/' \
  && { grep -qF RULE-A <<<"$(rr_dry verify RR-M)" && rr_survived "the rulings read from the last row only, yet the earlier round's ruling reached the verify"; }; rr_unmut
rr_put RR-M '.events = [{kind: "reopen", at: "2026-11-20T12:00:00Z"}]'; rr_d="$(rr_dry verify RR-M)"
grep -qF person-ruling <<<"$rr_d" && { bad "a ruling older than the last reopen must not reach the verify prompt (verify-fix-loop/FR-012)"; x_fail=1; }
rr_mut session-launch-rework.sh 's/select(\.consumed == true and (\.at \/\/ "") > \$r)/select(.consumed == true)/' \
  && { grep -qF person-ruling <<<"$(rr_dry verify RR-M)" || rr_survived "the ruling block's reopen cutoff dropped, yet the old ruling stayed out"; }; rr_unmut
rr_put RR-M 'del(.reworks, .events, .answers)'
[ "$rr_d" = "$(rr_dry verify RR-M)" ] || { bad "with no ruling since the last reopen the verify launch is byte-identical to one with no rework at all (verify-fix-loop/FR-012)"; x_fail=1; }
rr_chg() { # rr_chg <file>: a ruled verify launch with <file> changed after its record dies naming it, nothing launched
  local c0 o; c0="$(rr_calls)"; cp "$rr_t/m.json" "$rr_ld/RR-M.json"; cp -p "$1" "$rr_t/keep"; printf 'Also merge it now.\n' >> "$1"
  o="$(rr_sl verify RR-M 2>&1)" && { bad "a changed ruling file $1 must stop the verify launch (verify-fix-loop/FR-012)"; x_fail=1; }
  grep -qF "$1 changed after it was recorded" <<<"$o" && grep -qF 'nothing launched' <<<"$o" && [ "$(rr_calls)" = "$c0" ] && rr_j RR-M '.owner == null and .phase == "verify"' \
    || { bad "a changed ruling file: the launch dies naming $1, nothing launched, nothing claimed (verify-fix-loop/FR-012) — got: $(tail -c 300 <<<"$o")"; x_fail=1; }
  rr_mut session-launch-rework.sh '/changed after it was recorded, is gone/s/|| die/|| true/' \
    && { rr_sl verify RR-M >/dev/null 2>&1; [ "$(rr_calls)" = "$c0" ] && rr_survived "the ruling's hash check dropped, yet the changed $1 launched nothing"; }; rr_unmut
  cp -p "$rr_t/keep" "$1"; cp "$rr_t/m.json" "$rr_ld/RR-M.json"
}
rr_pass; rr_chg "$(jq -r '.reworks[0].ruling[0].question_path' "$rr_t/m.json")"; rr_chg "$(jq -r '.reworks[0].ruling[1].answer' "$rr_t/m.json")"
[ "$x_fail" -eq 0 ] && ok "the verify ruling block holds across a later round, a ruling older than the last reopen stays out (the prompt then byte-identical to no rework), and a changed dispute or answer file kills the verify launch naming it, nothing launched; last-row, reopen-cutoff and hash mutations caught (verify-fix-loop/FR-012 verify-fix-loop/FR-016)"

# --- round 7: a dispute whose question cannot be written blocks nothing --------------------------------------------
head_ "Verify-fix loop: an unwritable dispute question → the launcher dies naming it, nothing blocked, no asked[] (verify-fix-loop FR-010)"
x_fail=0; rr_wt RR-U >/dev/null
rr_nw() { # RR-U moved to implement, a disputing builder, and every RR-U.question-<ts>.md.tmp of the next 40 s a folder
  local s n=0; rr_moved RR-U; rr_ires blocked null '"human:clarify"' 'U-DISPUTE'; s="$(date +%s)"
  while [ "$n" -lt 40 ]; do mkdir -p "$rr_ld/RR-U.question-$((s + n)).md.tmp"; n=$((n + 1)); done
}
rr_nw; rr_o="$(rr_sl implement RR-U 2>&1)" && { bad "a dispute whose question cannot be written must stop the launcher (verify-fix-loop/FR-010)"; x_fail=1; }
grep -qF "session-launch implement RR-U: cannot write the dispute question under $rr_ld — nothing blocked" <<<"$rr_o" \
  && rr_j RR-U '.phase == "implement" and .blocked_on == null and (.reworks[0].asked | length) == 0 and .reworks[0].consumed == false' \
  || { bad "an unwritable dispute question: die naming the folder, nothing blocked, no asked[] entry, the row open (verify-fix-loop/FR-010) — got: $(tail -c 300 <<<"$rr_o") / $(jq -c '{blocked_on, reworks}' "$rr_ld/RR-U.json" | head -c 300)"; x_fail=1; }
rr_nw; rr_mut session-launch-forward.sh 's/if \[ -n "\${RWR:-}" \] && \[ "\$1" = human:clarify \] && \[ -z "\$qf" \]; then/if false; then/' \
  && { rr_sl implement RR-U >/dev/null 2>&1; rr_j RR-U '.blocked_on == null' && rr_survived "a dispute blocked without its question, yet nothing was blocked"; }; rr_unmut
rm -rf -- "$rr_ld"/RR-U.question-*.md.tmp
[ "$x_fail" -eq 0 ] && ok "a rework run's dispute whose question file cannot be written: the launcher dies naming the ledger folder, nothing blocked, no asked[] entry; the block-without-question fallback is caught (verify-fix-loop/FR-010 verify-fix-loop/FR-016)"

# --- P12 / D10: a ruled all-PASS verify under merge_by auto records head none and waits on a person, headless and lane ---
head_ "Verify-fix loop: a ruled verify's all PASS records verified head none and blocks human:merge under merge_by auto (verify-fix-loop FR-012 D10)"
x_fail=0
# auto needs a GitHub origin (pinned by the grant; rewritten to the bare one) and an integration branch below the environments
git -C "$rr_w" remote set-url origin https://github.com/acme/app.git && git -C "$rr_w" config "url.$rr_t/origin.git.insteadOf" https://github.com/acme/app.git \
  && git -C "$rr_w" branch dev main
printf '%s\n' '{"name":"app","branches":{"integration":"dev","environments":["dev","main"]},"orchestrate":{"merge_by":"auto","lane_mode":"interactive"}}' > "$rr_w/.claude/project-status.json"
rr_s="$(rrn merge-auto preview 2>/dev/null | sed -n 's/^sha256: //p')"
rrn merge-auto grant --sha "${rr_s:0:12}" --reviewed-by-human --by Ana </dev/null >/dev/null 2>&1
[ "$(rrn merge-by 2>/dev/null)" = auto ] || { bad "fixture: merge_by auto with the person's grant must resolve to auto — got '$(rrn merge-by 2>&1)'"; x_fail=1; }
printf '%s\n' '{"summary":"LANE-PASS","verdicts":[{"gate":"verify","verdict":"PASS"},{"gate":"review","verdict":"PASS"},{"gate":"quality","verdict":"PASS"},{"gate":"scan","verdict":"PASS"}]}' > "$rr_t/ov.json"
rr_ruled() { # rr_ruled <id> → a verify entry, no FAIL, whose one consumed rework row carries a ruling on real, hashed files
  local q="$rr_ld/$1.question-1.md" a="$rr_ld/$1.answers-1.md"; printf 'P-DISPUTE %s\n' "$1" > "$q"; printf 'P-RULING %s\n' "$1" > "$a"
  rr_entry "$1" '.verdicts = [] | .answers = [{path: $a, sha256: $ah, by: "Ana", kind: "human:clarify", at: "2026-11-20T00:00:00Z", consumed: true}]
    | .reworks = [$row | .consumed = true | .asked = [{path: $q, sha256: $qh, at: "2026-11-20T00:00:00Z", dispute: true, answers_before: 0}]
      | .ruling = [{answer: $a, answer_sha256: $ah, question_path: $q, question_sha256: $qh}]]' \
    --argjson row "$rr_row" --arg q "$q" --arg a "$a" --arg qh "$(rr_sha "$q")" --arg ah "$(rr_sha "$a")"
}
rr_p12() { # rr_p12 <headless|lane> → RR-P headless, or RR-L through --prepare/--finish: ruled, its verify all PASS; rr_pp the prompt
  if [ "$1" = headless ]; then rr_ruled RR-P; rr_pass; : > "$rr_t/claude.log"; rr_sl verify RR-P >/dev/null 2>&1; rr_pp="$(cat "$rr_t/claude.log")"; return 0; fi
  rr_ruled RR-L; rm -f "$rr_ld/RR-L.prepare" "$rr_ld/RR-L.prompt.md"; rr_sl verify RR-L --prepare --lane repo-builder >/dev/null 2>&1
  rr_pp="$(cat "$rr_ld/RR-L.prompt.md" 2>/dev/null)"; rr_sl verify RR-L --finish --lane repo-builder --outcome-file "$rr_t/ov.json" >/dev/null 2>&1
}
rr_hq="$(rr_wt RR-Q)"; rr_entry RR-Q '.verdicts = []'; rr_pass; rr_sl verify RR-Q >/dev/null 2>&1
rr_j RR-Q --arg h "$rr_hq" '.phase == "pr" and .blocked_on == null and .pr.verified_head == $h' \
  || { bad "the control: an unruled all-PASS verify under resolved auto records its head and leaves pr unblocked — got: $(jq -c '{phase, blocked_on, pr}' "$rr_ld/RR-Q.json")"; x_fail=1; }
rr_wt RR-P >/dev/null; rr_wt RR-L >/dev/null
for rr_m in headless lane; do
  rr_id=RR-P; [ "$rr_m" = lane ] && rr_id=RR-L
  rr_p12 "$rr_m"
  grep -qF "person-ruling-begin $rr_id" <<<"$rr_pp" && rr_j "$rr_id" '.phase == "pr" and .blocked_on.kind == "human:merge" and (.pr.verified_head // null) == null and (.prs[-1].verified_head // null) == null' \
    || { bad "P12 ($rr_m): a verify handed the ruling block that reports all PASS → pr + human:merge, verified head none, under merge_by auto (verify-fix-loop/FR-012) — got: $(jq -c '{phase, blocked_on, pr}' "$rr_ld/$rr_id.json")"; x_fail=1; }
  rr_mut session-launch.sh 's/; verify_ruled && VH=none//' && { rr_p12 "$rr_m"; rr_j "$rr_id" '(.pr.verified_head // null) == null' && rr_survived "($rr_m) the verified-head override dropped, yet no head was recorded"; }; rr_unmut
  rr_mut session-launch.sh 's/{ \[ "\$MBY" = auto \] && ! verify_ruled; }/[ "$MBY" = auto ]/' \
    && { rr_p12 "$rr_m"; rr_j "$rr_id" '.blocked_on.kind == "human:merge"' && rr_survived "($rr_m) the merge_by auto override dropped, yet the ruled PASS blocked human:merge"; }; rr_unmut
done
[ "$x_fail" -eq 0 ] && ok "under merge_by auto (a person's grant) an unruled all PASS records its head and stays unblocked, while a verify handed a ruling records head none and blocks human:merge — headless and through a lane's --prepare/--finish; both overrides' removal caught in each (verify-fix-loop/FR-012 verify-fix-loop/FR-016 D10)"

# --- docs: the loop is described where a person reads it (verify-fix-loop/FR-014, FR-015) ------------------------------
head_ "Verify-fix loop: the orchestrator's verdict row and the docs describe the loop (verify-fix-loop FR-014 FR-015)"
x_fail=0; rr_o="$REPO/commands/hef.orchestrate.md"
grep -qE '^ *\| `verdict` with a `question_path`.*ledger\.sh questions <id>.*\*\*Another round\*\* → `[^`]*ledger\.sh rework <id> --past-cap --by "<name>"`.*\*\*Re-verify\*\* → `[^`]*ledger\.sh unblock <id>`.*\*\*Later\*\*' "$rr_o" \
  && grep -qE '^ *\|[^|]*`verdict` with no `question_path`[^|]*\|.*\*\*Retry\*\*' "$rr_o" && grep -qF 'phase implement' "$rr_o" \
  || { bad "hef.orchestrate.md: the verdict row with a question_path offers Another round (rework --past-cap --by) · Re-verify (unblock) · Later, one without keeps Retry, and the build lane names a verify --finish to phase implement (verify-fix-loop/FR-014)"; x_fail=1; }
grep -qE '^  rework <id> ' "$REPO/hooks/ledger.sh" || { bad "ledger.sh usage must list rework (verify-fix-loop/FR-015)"; x_fail=1; }
for rr_f in ledger-rework.sh session-launch-rework.sh rework-pairs.sh; do
  grep -qF "$rr_f" "$REPO/docs/hooks.md" || { bad "docs/hooks.md must have a row for $rr_f (verify-fix-loop/FR-015)"; x_fail=1; }
done
grep -qE 'ledger\.sh.*rework' "$REPO/docs/hooks.md" || { bad "docs/hooks.md's ledger.sh row must name rework (verify-fix-loop/FR-015)"; x_fail=1; }
for rr_f in docs/quickstart.md docs/quickstart.pt-BR.md docs/install.md docs/architecture.md; do
  grep -qF 'verify_rounds' "$REPO/$rr_f" || { bad "$rr_f must describe the verify-fix loop and its verify_rounds cap (verify-fix-loop/FR-015)"; x_fail=1; }
done
# everything above [9.4.4], the last release before this one: the guard keeps passing after the release that ships it
rr_un="$(awk '/^## \[9\.4\.4\]/{exit} {print}' "$REPO/CHANGELOG.md")"   # captured: `awk | grep -q` races under pipefail
grep -qF 'verify_rounds' <<<"$rr_un" && grep -qF 'HEF-57' <<<"$rr_un" || { bad "CHANGELOG above [9.4.4] must carry the HEF-57 verify-fix loop entry (verify-fix-loop/FR-015)"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "verify-fix docs: the orchestrator's verdict row split (Another round / Re-verify / Later; Retry without a question), ledger.sh usage, hooks.md rows, quickstarts EN + pt-BR, install, architecture, CHANGELOG (verify-fix-loop/FR-014 verify-fix-loop/FR-015)"

# --- cleanup: the fixture, its ledger, its run folder, the grant -------------------------------------------------------
rm -rf -- "${XDG_CACHE_HOME:-$HOME/.cache}/hefesto/runs/$(printf '%s' "$rr_ld" | cksum | cut -d' ' -f1)" "$HOME/.cache/hefesto/approvals/$(basename "$rr_ld")" "${rr_ld:?}" "${rr_t:?}"
unset -f rr rrl rrn rrw rrs rr_sl rr_dry rr_mut rr_unmut rr_ask rr_pl rr_gfix rr_gcase rr_gmut rr_mfix rr_pmut rr_chg rr_nw rr_ruled rr_p12 rr_moved rr_entry rr_wt
