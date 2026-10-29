# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
#
# lanes-parity (9.1) smoke checks, part 2 — ops (US5), branch models from the board (US6) and the docs (T014).
#
# SOURCED by tests/smoke.sh right after tests/smoke-lifecycle.sh, never run on its own: it uses that part's section
# helpers (lc, lc_git, lc_entry, lc_put, lc_jq) and its 9.0 fixture builder (lc_entry_90). Split off because one file
# of these checks went over the 500-code-line limit (quality gate 2026-10-27); the conventions are part 1's.

# Fail loudly when part 1 did not run first: a part that silently defines nothing would report "0 failed".
if ! declare -F lc lc_git lc_entry lc_put lc_jq lc_entry_90 lc_refuse >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-lifecycle-ops.sh: source it from tests/smoke.sh after tests/smoke-lifecycle.sh"
  else echo "tests/smoke-lifecycle-ops.sh: source it from tests/smoke.sh after tests/smoke-lifecycle.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

# --- op close / op drop end an op; ops are listed and counted apart (US5, FR-011) -----------------------------------
# An op holds approved actions, so it never closes while one of them is approved or taken (the refusal names it).
# `list` puts ops after the items; `metrics` leaves ops out of every item count and counts them in `.ops`.
head_ "Lifecycle: op close / op drop (US5)"
x_fail=0
lc_t="$(cd "$(mktemp -d)" && pwd -P)"; git -C "$lc_t" init -q -b main . && lc_git "$lc_t" commit -q --allow-empty -m init
lc_entry_90 HEF-1 queued "" "" null | lc_put "$lc_t" HEF-1
lc_entry_90 WEB-1 implement "web-1" "" null | lc_put "$lc_t" WEB-1
for lc_i in 1 2 3; do [ "$(lc "$lc_t" op new --title "op number $lc_i" 2>&1)" = "OP-$lc_i" ] || { bad "op new must create OP-$lc_i"; x_fail=1; }; done
lc_act() { # lc_act <aid> <status>: a raw action record, as request/approve/take leave it
  mkdir -p "$(sld "$lc_t")/actions"
  jq -n --arg a "$1" --arg s "$2" '{aid: $a, entry: ($a | sub("-A[0-9]+$"; "")), to: "repo-deployer", status: $s, at: "2026-10-21T00:00:00Z",
    sha256: "0000", scope: {title: "a step", steps: ["do it"]}}' > "$(sld "$lc_t")/actions/$1.json"
}
lc_op_refused() { # lc_op_refused <id> <text the refusal must name> <ledger args…>
  local id="$1" need="$2" before o; shift 2; before="$(sha256sum < "$(lc_entry "$lc_t" "$id")")"
  o="$(lc "$lc_t" "$@" 2>&1)" && { bad "ledger $* must be refused (FR-011)"; x_fail=1; }
  grep -qF -- "$need" <<<"$o" || { bad "the refusal of ledger $* must name '$need' — got: $(head -c 200 <<<"$o")"; x_fail=1; }
  [ "$(sha256sum < "$(lc_entry "$lc_t" "$id")")" = "$before" ] || { bad "a refused ledger $* must leave $id unchanged"; x_fail=1; }
}
printf 'the stg volumes are gone\n' > "$lc_t/out.md"; : > "$lc_t/empty.md"
lc_act OP-1-A1 "done"; lc_act OP-1-A2 approved
lc_op_refused OP-1 'OP-1-A2' op close OP-1 --outcome-file "$lc_t/out.md"
lc_op_refused OP-1 'OP-1-A2' op drop OP-1 --reason-file "$lc_t/out.md"
lc_act OP-1-A2 taken
lc_op_refused OP-1 'OP-1-A2' op close OP-1 --outcome-file "$lc_t/out.md"
lc_act OP-1-A2 stopped
lc_op_refused OP-1 'outcome' op close OP-1
lc_op_refused OP-1 'empty' op close OP-1 --outcome-file "$lc_t/empty.md"
lc_op_refused OP-1 '--outcome-file' op close OP-1 --reason-file "$lc_t/out.md"
lc_op_refused OP-1 '--reason-file' op drop OP-1 --outcome-file "$lc_t/out.md"
lc_op_refused HEF-1 'not an op' op close HEF-1 --outcome-file "$lc_t/out.md"
lc "$lc_t" op close OP-1 --outcome-file "$lc_t/out.md" >/dev/null 2>&1 \
  && jq -e --arg h "$(sha256sum < "$lc_t/out.md" | cut -c1-64)" '.phase == "done" and .outcome_sha256 == $h' "$(lc_entry "$lc_t" OP-1)" >/dev/null 2>&1 \
  && lc_jq "$lc_t" OP-1 '.outcome.kind == "done" and (.outcome.text | contains("stg volumes are gone")) and (.events[-1].kind == "op-closed")' \
  || { bad "op close must set phase done and keep the outcome (text and sha256) — got: $(jq -c '{phase, outcome, outcome_sha256}' "$(lc_entry "$lc_t" OP-1)")"; x_fail=1; }
lc_op_refused OP-1 'already done' op close OP-1 --outcome-file "$lc_t/out.md"
lc_op_refused OP-1 'already done' op drop OP-1 --reason-file "$lc_t/out.md"
lc "$lc_t" op drop OP-2 --reason-file "$lc_t/out.md" >/dev/null 2>&1 \
  && lc_jq "$lc_t" OP-2 '.phase == "dropped" and .outcome.kind == "dropped" and .outcome_sha256 != null' \
  || { bad "op drop must set phase dropped and keep the reason — got: $(jq -c '{phase, outcome}' "$(lc_entry "$lc_t" OP-2)")"; x_fail=1; }
# list: the items first, then the ops (WEB-1 sorts after OP-* by id, so the order is the grouping, not the id sort)
lc_o="$(lc "$lc_t" list 2>&1)"
jq -e 'map(.id) == ["HEF-1", "WEB-1", "OP-1", "OP-2", "OP-3"]' <<<"$lc_o" >/dev/null 2>&1 \
  || { bad "list must show the items, then the ops apart — got: $(jq -c 'map(.id)' <<<"$lc_o" 2>&1 | head -c 200)"; x_fail=1; }
# metrics: ops are not items
lc_o="$(lc "$lc_t" metrics --json 2>&1)"
jq -e '.entries == 2 and .by_phase == {implement: 1, queued: 1} and .ops == {open: 1, done: 1, dropped: 1}' <<<"$lc_o" >/dev/null 2>&1 \
  || { bad "metrics must exclude ops from the item counts and count them in .ops — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
grep -qF 'ops       open 1 · done 1 · dropped 1' <<<"$(lc "$lc_t" metrics 2>&1)" || { bad "metrics' text must print the op counts apart — got: $(lc "$lc_t" metrics 2>&1 | tail -3)"; x_fail=1; }
# metrics --since filters the op counts too: OP-2 (dropped) created before the date is not counted.
jq '.created = "2020-01-01T00:00:00Z"' "$(lc_entry "$lc_t" OP-2)" > "$lc_t/e.json" && mv "$lc_t/e.json" "$(lc_entry "$lc_t" OP-2)"
lc_o="$(lc "$lc_t" metrics --since 2026-01-01 --json 2>&1)"
jq -e '.entries == 2 and .ops == {open: 1, done: 1, dropped: 0}' <<<"$lc_o" >/dev/null 2>&1 \
  || { bad "metrics --since must filter the op counts by created too (FR-011) — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
# Closing an op WITHDRAWS its pending actions (a pending action has no other way out — only a taken one is stopped),
# names them, and leaves a done one alone. Then the closed op takes nothing more: request, approve, take all refuse.
[ "$(lc "$lc_t" op new --title "op number 4" 2>&1)" = OP-4 ] || { bad "op new must create OP-4"; x_fail=1; }
lc_act OP-4-A1 pending; lc_act OP-4-A2 "done"
lc_o="$(lc "$lc_t" op close OP-4 --outcome-file "$lc_t/out.md" 2>&1)" || { bad "op close must pass with only pending and done actions — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
grep -qF 'OP-4-A1' <<<"$lc_o" || { bad "op close must name the pending action it withdrew — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
jq -e '.status == "withdrawn" and (.withdrawn.reason | contains("OP-4")) and (.withdrawn.at | type) == "string"' "$(sld "$lc_t")/actions/OP-4-A1.json" >/dev/null 2>&1 \
  || { bad "op close must mark a pending action withdrawn with the reason (US5) — got: $(jq -c . "$(sld "$lc_t")/actions/OP-4-A1.json" | head -c 300)"; x_fail=1; }
jq -e '.status == "done"' "$(sld "$lc_t")/actions/OP-4-A2.json" >/dev/null 2>&1 || { bad "op close must leave a done action as it is"; x_fail=1; }
lc_act OP-2-A1 pending; lc_act OP-2-A2 approved   # left on the dropped op OP-2, as a 9.0 ledger might hold them
lc_cr() { # lc_cr <aid file to keep unchanged> <ledger args…> — refused because the op is closed, the action unchanged
  local f b o; f="$(sld "$lc_t")/actions/$1.json"; shift; b="$(sha256sum < "$f")"
  o="$(lc "$lc_t" "$@" 2>&1)" && { bad "ledger $* on a closed op must be refused (US5)"; x_fail=1; }
  grep -qF 'a closed op takes no more actions' <<<"$o" || { bad "ledger $*: the refusal must say the op is closed — got: $(head -c 300 <<<"$o")"; x_fail=1; }
  [ "$(sha256sum < "$f")" = "$b" ] || { bad "a refused ledger $* must leave $f unchanged"; x_fail=1; }
}
printf '{"title": "late", "steps": ["x"]}\n' > "$lc_t/scope.json"
lc_cr OP-2-A1 request OP-2 --to repo-deployer --scope-file "$lc_t/scope.json"
[ ! -f "$(sld "$lc_t")/actions/OP-2-A3.json" ] || { bad "a refused request on a closed op must write no action"; x_fail=1; }
lc_cr OP-2-A1 approve OP-2-A1 --sha 00000000 --to repo-deployer --title "a step" --reviewed-by-human --by Ana
lc_cr OP-2-A2 action take OP-2-A2
# An op ends only through op close / op drop: drop, fold and supersede would step around their open-action guard,
# and op_closed_refuse would then strand a taken action (quality gate 2026-10-27).
lc_act OP-3-A1 taken
for lc_v in "drop OP-3" "fold OP-3 --into HEF-1" "supersede OP-3 --by HEF-1"; do
  # shellcheck disable=SC2086  # the verb and its target are split on purpose
  lc_op_refused OP-3 'op close' $lc_v --reason-file "$lc_t/out.md"
done
rm -f "$(sld "$lc_t")/actions/OP-3-A1.json"
# An op is never the target of fold/supersede, nor deployed: it has no branch, repo or release (code review 2026-10-27).
lc_op_refused HEF-1 'is an op' fold HEF-1 --into OP-1 --reason-file "$lc_t/out.md"
lc_op_refused HEF-1 'is an op' supersede HEF-1 --by OP-3 --reason-file "$lc_t/out.md"
lc_op_refused OP-3 'is an op' deployed OP-3 --env main --commit "$(git -C "$lc_t" rev-parse HEAD)"
# metrics on a ledger that holds only ops shows their counts instead of "no entries".
lc_t2="$(cd "$(mktemp -d)" && pwd -P)"; git -C "$lc_t2" init -q -b main . && lc_git "$lc_t2" commit -q --allow-empty -m init
lc "$lc_t2" op new --title "only an op" >/dev/null 2>&1
lc_o="$(lc "$lc_t2" metrics --json 2>&1)"
jq -e '.entries == 0 and .ops == {open: 1, done: 0, dropped: 0}' <<<"$lc_o" >/dev/null 2>&1 \
  || { bad "metrics on an ops-only ledger must show the op counts (FR-011) — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
grep -qF 'ops       open 1 · done 0 · dropped 0' <<<"$(lc "$lc_t2" metrics 2>&1)" || { bad "metrics' text on an ops-only ledger must print the op counts — got: $(lc "$lc_t2" metrics 2>&1 | tail -3)"; x_fail=1; }
rm -rf -- "${lc_t2:?}"
rm -rf -- "${lc_t:?}"
[ "$x_fail" -eq 0 ] && ok "op close / op drop end an op with its outcome kept, refused while an action is approved or taken (named), with a missing/empty/wrong file, on a non-op or a closed op; a pending action is withdrawn (named); a closed op refuses request, approve and take; list shows ops after the items; metrics counts ops apart, with --since and on an ops-only ledger (US5 FR-011)"

# --- Branch models declared on the board (US6: FR-012, FR-013, NR-005; plan Sketch 5, notes 15 and 21) ------------
# A board `repos.<name>` value is "<path>" or {path, branches}. `ledger.sh branches` (and --configured) resolve the
# repo file's block first, then the board's, then the default, and print `.source`. The fixture keeps the 9.0
# pointer file (`{"board": "../kanban"}`, no branches) in the code repo (note 15). Every error is loud (NR-005).
head_ "Lifecycle: branch models from the board"
x_fail=0
lc_t="$(cd "$(mktemp -d)" && pwd -P)"; lc_k="$lc_t/kanban"; lc_a="$lc_t/api"; lc_w="$lc_t/web"; lc_l="$lc_t/lone"
for lc_r in kanban api web lone; do git init -q --bare -b main "$lc_t/o-$lc_r.git" && git init -q -b main "$lc_t/$lc_r" \
  && git -C "$lc_t/$lc_r" remote add origin "$lc_t/o-$lc_r.git" && lc_git "$lc_t/$lc_r" commit -q --allow-empty -m init \
  && mkdir -p "$lc_t/$lc_r/.claude" && printf '.claude/\n' >> "$lc_t/$lc_r/.git/info/exclude"; done
mkdir -p "$lc_k/tasks" && printf '# TODO\n\n## HEF-1 — api one\nrepo: api\n\n## HEF-2 — api two\nrepo: api\n' > "$lc_k/tasks/TODO.md"
for lc_c in DOING DONE BACKLOG; do printf '# %s\n' "$lc_c" > "$lc_k/tasks/$lc_c.md"; done
lc_git "$lc_k" add tasks && lc_git "$lc_k" commit -q -m board
# api: dev leads main by one commit; hef-1 (off dev) is merged into dev only, and dev-only files mark the diff base.
{ lc_git "$lc_a" switch -q -c dev && printf 'd\n' > "$lc_a/dev-lead.txt" && lc_git "$lc_a" add dev-lead.txt && lc_git "$lc_a" commit -q -m 'dev lead' \
  && lc_git "$lc_a" switch -q -c hef-1 && printf '1\n' > "$lc_a/f1.txt" && lc_git "$lc_a" add f1.txt && lc_git "$lc_a" commit -q -m one \
  && lc_git "$lc_a" switch -q dev && lc_git "$lc_a" merge -q --no-ff -m 'Merge hef-1' hef-1 \
  && lc_git "$lc_a" push -q origin main dev hef-1 && lc_git "$lc_a" switch -q -c hef-2 && printf '2\n' > "$lc_a/f2.txt" \
  && lc_git "$lc_a" add f2.txt && lc_git "$lc_a" commit -q -m two; } >/dev/null 2>&1 || { bad "fixture: the api repository could not be built"; x_fail=1; }
LC_BOARD_OK='{"source":"tasks-repo","root":"tasks","repos":{"api":{"path":"../api","branches":{"integration":"dev","environments":["dev","main"]}},"web":"../web"}}'
lc_board() { printf '%s\n' "$1" > "$lc_k/.claude/project-status.json"; }
lc_board "$LC_BOARD_OK"
for lc_r in api web; do printf '{"board":"../kanban"}\n' > "$lc_t/$lc_r/.claude/project-status.json"; done   # the 9.0 pointer, no branches
rmdir "$lc_l/.claude"   # lone: no pointer, no config at all
lc_rc() { (cd "$1" && bash "$LC_LG" "${@:2}" >/dev/null 2>&1); echo $?; }   # lc_rc <repo> <args…> → the exit code
# FR-012: the board's block, from the code repo itself; --configured answers 0 exactly as for a repo-file block.
lc_o="$(lc "$lc_a" branches 2>&1)"
jq -e '.integration == "dev" and .environments == ["dev","main"] and .final == "main" and .source == "board" and (.protected | index("dev"))' <<<"$lc_o" >/dev/null 2>&1 \
  || { bad "branches in a board-declared repo must print the board's block with source board (FR-012) — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
[ "$(lc_rc "$lc_a" branches --configured)" = 0 ] || { bad "branches --configured must exit 0 for a board-only block (FR-012) — got rc $(lc_rc "$lc_a" branches --configured)"; x_fail=1; }
# FR-013: --repo <name> from the board repo, and each source named.
jq -e '.integration == "dev" and .source == "board"' <<<"$(lc "$lc_k" branches --repo api 2>&1)" >/dev/null 2>&1 \
  || { bad "branches --repo api from the board repo must print the board block (FR-013) — got: $(lc "$lc_k" branches --repo api 2>&1 | head -c 300)"; x_fail=1; }
jq -e '.integration == "main" and .source == "default"' <<<"$(lc "$lc_k" branches --repo web 2>&1)" >/dev/null 2>&1 \
  || { bad "branches --repo web (a plain path, no file block) must print the default (FR-013) — got: $(lc "$lc_k" branches --repo web 2>&1 | head -c 300)"; x_fail=1; }
jq -e '.integration == "main" and .source == "default"' <<<"$(lc "$lc_k" branches --repo nope 2>&1)" >/dev/null 2>&1 \
  || { bad "branches --repo for a repo missing from the map must print default — got: $(lc "$lc_k" branches --repo nope 2>&1 | head -c 300)"; x_fail=1; }
jq -e '.integration == "main" and .source == "default"' <<<"$(lc "$lc_l" branches 2>&1)" >/dev/null 2>&1 \
  || { bad "a pointer-less repo must print the default with source default — got: $(lc "$lc_l" branches 2>&1 | head -c 300)"; x_fail=1; }
[ "$(lc_rc "$lc_l" branches --configured)" = 1 ] || { bad "a pointer-less repo: branches --configured must exit 1 — got rc $(lc_rc "$lc_l" branches --configured)"; x_fail=1; }
# `"branches": null` on the board means "not declared", exactly as in a repo file: default model, --configured 1.
lc_board '{"source":"tasks-repo","root":"tasks","repos":{"api":{"path":"../api","branches":null},"web":"../web"}}'
jq -e '.source == "default"' <<<"$(lc "$lc_a" branches 2>&1)" >/dev/null 2>&1 \
  || { bad "a board branches: null must read as undeclared (source default) — got: $(lc "$lc_a" branches 2>&1 | head -c 300)"; x_fail=1; }
[ "$(lc_rc "$lc_a" branches --configured)" = 1 ] || { bad "a board branches: null: --configured must exit 1, as a repo file's null does — got rc $(lc_rc "$lc_a" branches --configured)"; x_fail=1; }
lc_board "$LC_BOARD_OK"
# The repo's own file overrides the board.
printf '{"board":"../kanban","branches":{"integration":"stg","environments":["stg","main"]}}\n' > "$lc_a/.claude/project-status.json"
jq -e '.integration == "stg" and .source == "repo file"' <<<"$(lc "$lc_k" branches --repo api 2>&1)" >/dev/null 2>&1 \
  || { bad "the repo's own branches block must override the board's, source repo file — got: $(lc "$lc_k" branches --repo api 2>&1 | head -c 300)"; x_fail=1; }
printf '{"board":"../kanban"}\n' > "$lc_a/.claude/project-status.json"
# From the board repo, where / unblock / deployed on an api entry use the board's block (dev, then main).
lc_entry_90 HEF-1 pr hef-1 9 null | jq '.repo = "api" | .blocked_on = {kind: "human:merge", since: "2026-10-21T00:00:00Z"}' | lc_put "$lc_k" HEF-1
lc_o="$(lc "$lc_k" where HEF-1 2>&1)"
{ grep -q '^dev: yes' <<<"$lc_o" && grep -qx 'main: no' <<<"$lc_o"; } || { bad "where from the board repo must walk the board's environments (dev: yes, main: no) — got: $(tr '\n' '|' <<<"$lc_o")"; x_fail=1; }
lc_o="$(lc "$lc_k" unblock HEF-1 2>&1)" || { bad "unblock human:merge from the board repo must take dev as the integration branch (hef-1 is in dev only) — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
lc_o="$(lc "$lc_k" deployed HEF-1 --env dev --commit "$(lc_git "$lc_a" rev-parse dev)" 2>&1)" \
  || { bad "deployed --env dev from the board repo must accept dev (an env of the board's model) — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
# The consumers: the PR base rule (session-launch), integration_base (speckit-helper), merge-tree-probe.
(cd "$lc_k" && bash "$LC_LG" init HEF-2 --kind tasks-repo --ref 'tasks/TODO.md#HEF-2' --repo api) >/dev/null 2>&1
mkdir -p "$lc_t/cfg"; lc_o="$(cd "$lc_k" && CLAUDE_CONFIG_DIR="$lc_t/cfg" bash "$REPO/hooks/session-launch.sh" implement HEF-2 --dry-run 2>&1)"
grep -qF 'gh pr create --base dev' <<<"$lc_o" || { bad "session-launch's PR base rule must honour the board block (--base dev) — got: $(head -c 400 <<<"$lc_o")"; x_fail=1; }
lc_o="$(cd "$lc_a" && bash "$REPO/hooks/speckit-helper.sh" pr-files 2>&1)"
{ grep -q 'f2.txt' <<<"$lc_o" && ! grep -q 'dev-lead.txt' <<<"$lc_o"; } || { bad "speckit-helper integration_base must diff against the board's dev (f2 only, not dev's lead) — got: $(tr '\n' '|' <<<"$lc_o")"; x_fail=1; }
lc_mtp() { rm -f "${TMPDIR:-/tmp}/.hefesto-merge-probe-$(printf '%s' "$lc_a" | { md5sum 2>/dev/null || md5 -r; } | cut -d' ' -f1)"
  printf '{"cwd":"%s"}' "$lc_a" | bash "$REPO/hooks/merge-tree-probe.sh" 2>&1; }
lc_git "$lc_a" switch -q -c hef-3 main && for lc_n in 1 2 3 4 5 6 7 8 9 10 11; do lc_git "$lc_a" commit -q --allow-empty -m "m$lc_n"; done   # never on dev
lc_git "$lc_a" switch -q dev && for lc_n in 1 2 3 4 5 6 7 8 9 10 11; do lc_git "$lc_a" commit -q --allow-empty -m "d$lc_n"; done
lc_git "$lc_a" push -q origin dev >/dev/null 2>&1; lc_git "$lc_a" switch -q hef-3   # the probe tries origin/dev first
lc_o="$(lc_mtp)"
grep -qF 'origin/dev has' <<<"$lc_o" || { bad "merge-tree-probe must take the board's dev as its base — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
# NR-005: a malformed board is loud — rc 2 for --configured, a named refusal for branches, integration_base fails.
lc_board '{"source":"tasks-repo","root":"tasks","repos":{"api":{"path":"../api","extra":1},"web":"../web"}}'
lc_o="$(lc "$lc_a" branches 2>&1)" && { bad "an unknown key in repos.api must be refused (NR-005) — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
{ grep -qF 'repos.api' <<<"$lc_o" && grep -qF "$lc_k/.claude/project-status.json" <<<"$lc_o"; } || { bad "the refusal must name repos.api and the board file — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
[ "$(lc_rc "$lc_a" branches --configured)" = 2 ] || { bad "an unresolvable board: branches --configured must exit 2, never 1 (NR-005) — got rc $(lc_rc "$lc_a" branches --configured)"; x_fail=1; }
lc_board '{"source":"tasks-repo","root":"tasks","repos":{"api":{"branches":{}},"web":"../web"}}'
grep -qF 'repos.api' <<<"$(lc "$lc_a" branches 2>&1)" || { bad "an object without path must be refused naming repos.api — got: $(lc "$lc_a" branches 2>&1 | head -c 300)"; x_fail=1; }
lc_board '{"source":"tasks-repo","root":"tasks","repos":{"api":{"path":"../api","branches":{"integration":""}},"web":"../web"}}'
lc_o="$(lc "$lc_a" branches 2>&1)" && { bad "an invalid board branches block must be refused — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
{ grep -qF 'repos.api' <<<"$lc_o" && grep -qF "$lc_k/.claude/project-status.json" <<<"$lc_o" && grep -qF 'branches.integration' <<<"$lc_o"; } \
  || { bad "the invalid-block refusal must name repos.api, the board file and the field — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
[ "$(lc_rc "$lc_a" branches --configured)" = 2 ] || { bad "an invalid board block: branches --configured must exit 2 (NR-005) — got rc $(lc_rc "$lc_a" branches --configured)"; x_fail=1; }
lc_git "$lc_a" switch -q hef-2
lc_o="$(cd "$lc_a" && bash "$REPO/hooks/speckit-helper.sh" pr-files 2>&1)" && { bad "integration_base must fail loudly on rc 2, never fall back to today's chain (NR-005) — got: $(tr '\n' '|' <<<"$lc_o")"; x_fail=1; }
# merge-tree-probe is a hook: rc 2 is "unconfigured" there BY DESIGN (it fails open, merge-tree-probe.sh:40), so it
# exits 0 on the historical order — never read as NR-005's silent fallback.
lc_git "$lc_a" switch -q hef-3; lc_o="$(lc_mtp)"; lc_n=$?
{ [ "$lc_n" = 0 ] && ! grep -qF 'dev has' <<<"$lc_o"; } || { bad "merge-tree-probe must fail open on a malformed board (exit 0, historical base) — got rc $lc_n: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
printf '{"board":"../missing"}\n' > "$lc_a/.claude/project-status.json"
[ "$(lc_rc "$lc_a" branches --configured)" = 2 ] || { bad "a pointer to a missing board: branches --configured must exit 2 — got rc $(lc_rc "$lc_a" branches --configured)"; x_fail=1; }
rm -rf -- "${lc_t:?}"
[ "$x_fail" -eq 0 ] && ok "branch models from the board: repos.<name> as {path, branches}, the repo file first, then the board, then default (named by .source, --repo); --configured 0/1/2; where/unblock/deployed from the board repo, session-launch's PR base, integration_base and merge-tree-probe honour it; malformed blocks are loud (US6 FR-012 FR-013 NR-005)"

# --- Docs: the lifecycle commands and the board branch model are documented (T014; US1, US6, plan note 14) --------
head_ "Lifecycle: docs"
x_fail=0
for lc_w in '`drop <id> --reason-file <f>`' '`fold <id> --into <id2> --reason-file <f>`' '`supersede <id> --by <id2> --reason-file <f>`' \
  '`reopen <id> --reason-file <f>`' '`deployed <id> --env <env> --commit <sha>`' '`op close <OP-n> --outcome-file <f>`' \
  'each call runs `board_ctx` once'; do
  grep -qF -- "$lc_w" "$REPO/docs/hooks.md" || { bad "docs/hooks.md must document $lc_w (US1, US6)"; x_fail=1; }
done
for lc_w in 'ledger.sh deployed <id> --env <env> --commit <sha>' '"branches": { "integration": "dev"' 'branches --configured'; do
  grep -qF -- "$lc_w" "$REPO/docs/install.md" || { bad "docs/install.md must document $lc_w (US3, US6)"; x_fail=1; }
done
[ "$x_fail" -eq 0 ] && ok "docs: hooks.md names drop/fold/supersede/reopen/deployed/op close and branches' per-call cost; install.md shows deployed and the board {path, branches} form (US1 US3 US6)"

# --- scope_check: the 9.1 scope shape and the merge-command rule (FR-018, FR-022, NR-004; Sketches 8b and 14) ------
# kind/repo/pr/expects are kept (scope_check drops unknown keys); commands normalise to [{cmd, after_step}], a bare
# string being after_step null, an after_step outside 1..len(steps) refused. Any `gh pr merge` must be a merge commit
# pinned to a head: refusing `done` after a squash undoes nothing, so a --squash scope is refused at REQUEST.
head_ "Lifecycle: scope_check (FR-018 NR-004)"
x_fail=0
lc_t="$(cd "$(mktemp -d)" && pwd -P)"; git -C "$lc_t" init -q -b main . && lc_git "$lc_t" commit -q --allow-empty -m init
lc_entry_90 HEF-1 implement "hef-1" "7" null | lc_put "$lc_t" HEF-1
lc_sh="0123456789abcdef0123456789abcdef01234567"
lc_sc_refused() { # lc_sc_refused <text the refusal must name> <scope json>: request refused, no action written
  local o; printf '%s\n' "$2" > "$lc_t/scope.json"
  o="$(lc "$lc_t" request HEF-1 --to repo-deployer --scope-file "$lc_t/scope.json" 2>&1)" && { bad "request must refuse the scope $2 (FR-018 NR-004)"; x_fail=1; }
  grep -qF -- "$1" <<<"$o" || { bad "the refusal of $2 must name '$1' — got: $(head -c 300 <<<"$o")"; x_fail=1; }
  [ -z "$(find "$(sld "$lc_t")/actions" -name 'HEF-1-A*.json' 2>/dev/null)" ] || { bad "a refused request ($2) must write no action"; x_fail=1; }
}
lc_mrule='gh pr merge: --merge and --match-head-commit <40-hex sha> only'
for lc_f in "--squash" "-s" "--rebase" "-r" "--auto" "--admin"; do
  lc_sc_refused "$lc_mrule" "{\"title\": \"merge it\", \"steps\": [\"merge\"], \"commands\": [\"gh pr merge 7 --merge --match-head-commit $lc_sh $lc_f\"]}"
done
lc_sc_refused "$lc_mrule" '{"title": "merge it", "steps": ["merge"], "commands": ["gh pr merge 7 --squash"]}'
lc_sc_refused "$lc_mrule" "{\"title\": \"merge it\", \"steps\": [\"merge\"], \"commands\": [{\"cmd\": \"gh pr merge 7 --squash --match-head-commit $lc_sh\", \"after_step\": 1}]}"
lc_sc_refused "$lc_mrule" '{"title": "merge it", "steps": ["merge"], "commands": ["gh pr merge 7 --merge"]}'
lc_sc_refused "$lc_mrule" '{"title": "merge it", "steps": ["merge"], "commands": ["gh pr merge 7 --merge --match-head-commit 0123abcd"]}'
lc_sc_refused "$lc_mrule" "{\"title\": \"merge it\", \"steps\": [\"merge\"], \"commands\": [\"gh pr merge 7 --match-head-commit $lc_sh\"]}"
# The T017 verifier's bypasses (2026-10-27): a deny list missed each of these; the allowlist refuses them all.
for lc_c in "gh pr merge 7 --merge --match-head-commit $lc_sh *" "gh pr merge 7 --merge --match-head-commit $lc_sh --squash=true" \
  "gh pr merge 7 --merge --match-head-commit $lc_sh --auto=true" "gh pr merge 7 --merge --match-head-commit $lc_sh -sd" \
  "gh pr -R o/r merge 7 --squash" "/usr/bin/gh pr merge 7 --squash" "gh pr merge 7 --merge --match-head-commit=$lc_sh -s" \
  "gh api -X PUT repos/o/r/pulls/7/merge -f merge_method=squash" "gh api graphql -f query=mutation{mergePullRequest}" \
  "gh pr merge 7 --merge --match-head-commit $lc_sh --body x" "gh pr merge 7 --merge --match-head-commit ${lc_sh:0:39}?"; do
  lc_sc_refused "$lc_mrule" "{\"title\": \"merge it\", \"steps\": [\"merge\"], \"commands\": [\"$lc_c\"]}"
done
lc_sc_refused 'no * in the program name' '{"title": "merge it", "steps": ["merge"], "commands": ["/usr/bin/g* pr merge 7 --squash"]}'
lc_sc_refused 'after_step' '{"title": "two steps", "steps": ["a", "b"], "commands": [{"cmd": "make check", "after_step": 3}]}'
lc_sc_refused 'after_step' '{"title": "two steps", "steps": ["a", "b"], "commands": [{"cmd": "make check", "after_step": 0}]}'
lc_sc_refused 'after_step' '{"title": "two steps", "steps": ["a", "b"], "commands": [{"cmd": "make check", "after_step": "1"}]}'
lc_sc_refused 'commands' '{"title": "two steps", "steps": ["a", "b"], "commands": [{"cmd": "bash -c x", "after_step": 1}]}'
lc_sc_refused 'kind' '{"title": "two steps", "steps": ["a", "b"], "kind": "deploy"}'
lc_sc_refused 'pr' '{"title": "two steps", "steps": ["a", "b"], "pr": "7"}'
lc_sc_refused 'expects' '{"title": "two steps", "steps": ["a", "b"], "expects": [null, "ok", "extra"]}'
# Accepted: the shape is kept and normalised, and the action hash covers it (after_step cannot move after approval).
printf '%s\n' "{\"title\": \"merge HEF-1\", \"steps\": [\"state\", \"merge\"], \"kind\": \"merge\", \"repo\": \"app\", \"pr\": 7,
  \"expects\": [\"mergeable\", null], \"heads\": {\"example/app#7\": \"$lc_sh\"}, \"unknown\": 1,
  \"commands\": [\"pr-watch.sh state 7\", {\"cmd\": \"gh pr merge 7 -R example/app --merge --match-head-commit $lc_sh\", \"after_step\": 1},
  \"gh pr view 7 --json mergeable,mergeStateStatus\", \"gh pr merge https://github.com/example/app/pull/7 --repo=example/app --merge -d --match-head-commit=$lc_sh\"]}" > "$lc_t/scope.json"
lc_o="$(lc "$lc_t" request HEF-1 --to repo-deployer --scope-file "$lc_t/scope.json" 2>&1)" || { bad "a valid 9.1 merge scope must be accepted — got: $(head -c 300 <<<"$lc_o")"; x_fail=1; }
jq -e --arg s "$lc_sh" '.scope | .kind == "merge" and .repo == "app" and .pr == 7 and .expects == ["mergeable", null] and (has("unknown") | not)
  and .commands == [{cmd: "pr-watch.sh state 7", after_step: null}, {cmd: "gh pr merge 7 -R example/app --merge --match-head-commit \($s)", after_step: 1},
    {cmd: "gh pr view 7 --json mergeable,mergeStateStatus", after_step: null},
    {cmd: "gh pr merge https://github.com/example/app/pull/7 --repo=example/app --merge -d --match-head-commit=\($s)", after_step: null}]' \
  "$(sld "$lc_t")/actions/HEF-1-A1.json" >/dev/null 2>&1 \
  || { bad "scope_check must keep kind/repo/pr/expects and normalise commands to {cmd, after_step} — got: $(jq -c .scope "$(sld "$lc_t")/actions/HEF-1-A1.json" 2>&1 | head -c 400)"; x_fail=1; }
printf '{"title": "a 9.0 scope", "steps": ["x"]}\n' > "$lc_t/scope.json"
lc "$lc_t" request HEF-1 --to repo-deployer --scope-file "$lc_t/scope.json" >/dev/null 2>&1 \
  && jq -e '.scope | .kind == null and .repo == null and .pr == null and .expects == [] and .commands == []' "$(sld "$lc_t")/actions/HEF-1-A2.json" >/dev/null 2>&1 \
  || { bad "a 9.0-shaped scope must still be accepted, with kind/repo/pr null — got: $(jq -c .scope "$(sld "$lc_t")/actions/HEF-1-A2.json" 2>&1 | head -c 300)"; x_fail=1; }
rm -rf -- "${lc_t:?}"
[ "$x_fail" -eq 0 ] && ok "scope_check keeps kind/repo/pr/expects, normalises commands to {cmd, after_step} (1..len(steps)), and refuses any gh pr merge that is not --merge --match-head-commit <40-hex> or carries any other token (=value, bundled flags, -R before merge, a gh path, gh api merges, a glob), at request (FR-018 FR-022 NR-004)"

# --- hand-run claims are never reaped; a reap is not a failed run (US4, FR-044, #152) --------------------------------
# A claim made by hand (no --pid) has no launcher to renew a lease, so it is interactive: the reaper never takes it.
# A launched claim whose lease ran out is still released, recorded as {kind: "reaped", note} — not exit 125 — so
# metrics never counts it as a run (a reaped verify run would have been "verified" and diluted the FAIL rate).
head_ "Lifecycle: hand claims are never reaped; a reap is not a failed run (FR-044)"
x_fail=0
lc_t="$(cd "$(mktemp -d)" && pwd -P)"; git -C "$lc_t" init -q -b main . && lc_git "$lc_t" commit -q --allow-empty -m init
for lc_i in 1 2 4; do lc_entry_90 "HEF-$lc_i" queued "" "" null | lc_put "$lc_t" "HEF-$lc_i"; done
lc_entry_90 HEF-3 verify hef-3 "" '{"session_name":"hef-verify-HEF-3","role":"verify","pid":1,"started":"2026-01-01T00:00:00Z"}' | lc_put "$lc_t" HEF-3
: > "$(sld "$lc_t")/HEF-3.lease"   # alive for the first claim; its lease dies before the second
lc_entry_90 HEF-5 merged hef-5 "" null | jq '.runs = [{role: "verify", session_name: "v", exit: 0, usd: 0, at: "2026-10-21T00:00:00Z"}]
  | .verdicts = [{gate: "verify", verdict: "FAIL", by: "v", at: "2026-10-21T00:00:00Z"}]' | lc_put "$lc_t" HEF-5
lc_o="$(lc "$lc_t" claim HEF-1 --session hand-1 --role plan 2>&1)" || { bad "a bare hand claim must succeed — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
lc_jq "$lc_t" HEF-1 '.owner.session_name == "hand-1" and .owner.mode == "interactive" and (.owner | has("pid") | not)' \
  || { bad "a claim with no --pid must be interactive (FR-044) — got: $(jq -c .owner "$(lc_entry "$lc_t" HEF-1)")"; x_fail=1; }
# five minutes on, with no lease: another claim must leave it alone (and reap HEF-3, whose lease is now dead)
jq '.owner.started = "2026-01-01T00:00:00Z"' "$(lc_entry "$lc_t" HEF-1)" > "$lc_t/h1.json" && lc_put "$lc_t" HEF-1 < "$lc_t/h1.json"
touch -t 202601010000 "$(sld "$lc_t")/HEF-3.lease"
lc_o="$(lc "$lc_t" claim HEF-2 --session s2 --role implement --pid $$ 2>&1)" || { bad "the second claim must succeed — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
lc_jq "$lc_t" HEF-1 '.owner.session_name == "hand-1" and .runs == []' \
  || { bad "a hand claim must survive another claim after five minutes (FR-044, #152) — got: $(jq -c '{owner, runs}' "$(lc_entry "$lc_t" HEF-1)")"; x_fail=1; }
lc_jq "$lc_t" HEF-3 '.owner == null and (.runs[-1] | .kind == "reaped" and (.note | length > 0) and (has("exit") | not) and .role == "verify")' \
  || { bad "a launched claim with a dead lease must be reaped and recorded as kind reaped, with no exit (FR-044) — got: $(jq -c '{owner, runs}' "$(lc_entry "$lc_t" HEF-3)")"; x_fail=1; }
grep -qF 'released HEF-3' <<<"$lc_o" || { bad "the reap must still be announced — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
grep -qF 'exit 125' <<<"$lc_o" && { bad "the reap must no longer be announced as a failed run (exit 125) — got: $(head -c 200 <<<"$lc_o")"; x_fail=1; }
# the --pid + --mode interactive refusal stays
lc_o="$(lc "$lc_t" claim HEF-4 --session s4 --role deploy --pid $$ --mode interactive 2>&1)" && { bad "--pid with --mode interactive must still be refused"; x_fail=1; }
lc_jq "$lc_t" HEF-4 '.owner == null' || { bad "a refused claim must write no owner"; x_fail=1; }
# metrics: the reaped verify run is not a verify run — HEF-5 is the only one verified, and it FAILed
lc_o="$(lc "$lc_t" metrics --json 2>&1)"
jq -e '.verified == 1 and .verify_fail_rate == 1' <<<"$lc_o" >/dev/null 2>&1 \
  || { bad "metrics must ignore a reaped run: verified 1, FAIL rate 100% (FR-044) — got: $(jq -c '{verified, verify_fail_rate}' <<<"$lc_o" 2>&1 | head -c 200)"; x_fail=1; }
rm -rf -- "${lc_t:?}"
[ "$x_fail" -eq 0 ] && ok "a claim with no --pid is interactive and survives the reaper; a launched claim with a dead lease is reaped as kind reaped (no exit 125); metrics' verified count and FAIL rate ignore the reap (FR-044)"
