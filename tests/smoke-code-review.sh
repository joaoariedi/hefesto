# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs and sed expressions are single-quoted on purpose
#
# exhaustive-review smoke checks, part 19: the exhaustive code-review round's check (speckit-helper.sh
# code-review-check, FR-010 with FR-007/FR-008/FR-009/FR-012) and its route (speckit-helper.sh review-route, FR-021);
# the structural checks over the command and the agent (FR-019) and the replay cases' shape (FR-016, FR-017).
#
# SOURCED by tests/smoke.sh after part 18b, never run on its own. Self-contained: reports written here, temp
# repositories, and a fake ledger.sh in a mirror of hooks/ (constitution 3: the assertions sit on the helper's exit code,
# its stdout verdict and BLOCKING line, and its stderr violations). Every rule of the check has a mutant.

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-code-review.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_)"
  else echo "tests/smoke-code-review.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

# --- fixtures -----------------------------------------------------------------------------------------------------------
cr_t="$(cd "$(mktemp -d)" && pwd -P)"
CR_FINDERS='Finders: input-and-security@fable ok; state-and-lifecycle@fable ok; spec-deviation@fable ok; test-integrity@fable ok; cross-tier@opus ok: all four lenses'
cr_finding() { # cr_finding <n> <sev> <loc> <defect> <lenses> [status] → a finding line and its recipe block
  printf -- '- [F%s] [%s] %s — %s — raised by: %s%s\n    ```recipe F%s\n    echo reproduce %s\n    ```\n' \
    "$1" "$2" "$3" "$4" "$5" "${6:+ — $6}" "$1" "$1"
}
cr_report() { # cr_report <finders line> <input-and-security body> [state body] [spec body] [test body] → a whole report
  printf '%s\n## Lens: input-and-security\n%s\n## Lens: state-and-lifecycle\n%s\n## Lens: spec-deviation\n%s\n## Lens: test-integrity\n%s\n## Open questions\nnone\n' \
    "$1" "$2" "${3:-none — checked: every write before a refusal in ledger.sh}" \
    "${4:-$(cr_finding 2 SUGGESTION hooks/x.sh:3 "wording of the refusal" spec-deviation "not verified — never blocks")}" \
    "${5:-none — checked: smoke part 14 cites and exercises FR-001..FR-010}"
}
CR_REFUTED="$(cr_finding 1 BLOCKING hooks/forge-lib.sh:33 "internal-host deny list is case-sensitive" "input-and-security, cross-tier" 'REFUTED → exit: 0 / "denied" — the list is lower-cased first')"
CR_REPRO="$(cr_finding 1 BLOCKING hooks/forge-lib.sh:33 "internal-host deny list is case-sensitive" "input-and-security, cross-tier" 'REPRODUCED → exit: 0 / "allowed"')"
CR_UNREPRO="$(cr_finding 1 BLOCKING hooks/forge-lib.sh:33 "internal-host deny list is case-sensitive" "input-and-security" 'UNREPRODUCED — needs systemd 253')"
CR_NOSTATUS="$(cr_finding 1 BLOCKING hooks/forge-lib.sh:33 "internal-host deny list is case-sensitive" "input-and-security")"
CR_OK="$(cr_report "$CR_FINDERS" "$CR_REFUTED")"
CR_SILENT="${CR_FINDERS/test-integrity@fable ok/test-integrity@fable silent: no output twice}"

# crc <report> [hooks dir] → stdout to $cr_t/out, stderr to $cr_t/err, the exit code to $cr_t/rc
crc() {
  local rc=0
  printf '%s\n' "$1" | bash "${2:-${CR_HOOKS:-$REPO/hooks}}/speckit-helper.sh" code-review-check >"$cr_t/out" 2>"$cr_t/err" || rc=$?
  echo "$rc" >"$cr_t/rc"
}
cr_no() { bad "$1 — rc $(cat "$cr_t/rc"), out: $(head -c 300 "$cr_t/out" | tr '\n' '|'), err: $(head -c 300 "$cr_t/err" | tr '\n' '|')"; x_fail=1; }
cr_expect() { # cr_expect <label> <report> <rc> <verdict> [stderr pattern] — one assertion on the check's decision
  crc "$2"
  [ "$(cat "$cr_t/rc")" = "$3" ] || { cr_no "$1: exit $3 expected"; return; }
  grep -qx "## Verdict: $4" "$cr_t/out" || { cr_no "$1: verdict $4 expected"; return; }
  grep -qE '^BLOCKING [0-9]+:' "$cr_t/out" || { cr_no "$1: a BLOCKING line expected"; return; }
  [ -z "${5:-}" ] || grep -qE -- "$5" "$cr_t/err" || cr_no "$1: stderr must match '$5'"
}

# --- one test function per rule, so a mutant of exactly that rule turns exactly its test red -----------------------------
# exhaustive-review/FR-010 FR-007: a complete clean report approves; REPRODUCED and UNREPRODUCED blockers block
cr_t_verdict() {
  cr_expect "a complete report whose only blocker is REFUTED" "$CR_OK" 0 APPROVE
  grep -qx 'BLOCKING 0:' "$cr_t/out" || cr_no "an approved report prints BLOCKING 0:"
  cr_expect "a REPRODUCED blocker" "$(cr_report "$CR_FINDERS" "$CR_REPRO")" 0 REQUEST_CHANGES
  grep -qx 'BLOCKING 1: hooks/forge-lib.sh:33 (input-and-security) internal-host deny list is case-sensitive' "$cr_t/out" \
    || cr_no "the BLOCKING line names file:line, the lens and the defect (FR-012)"
}
cr_t_unrepro() {   # exhaustive-review/FR-007: only REFUTED clears a blocker (the owner, decision 3)
  cr_expect "an UNREPRODUCED blocker" "$(cr_report "$CR_FINDERS" "$CR_UNREPRO")" 0 REQUEST_CHANGES
  grep -qE '^BLOCKING 1: .* unreproduced$' "$cr_t/out" || cr_no "an UNREPRODUCED blocker is marked 'unreproduced' on the BLOCKING line"
}
cr_t_lens() {      # exhaustive-review/FR-008: every lens reports findings or `none — checked: <what>`
  cr_expect "a missing lens section" "${CR_OK/\#\# Lens: test-integrity/## Lens: tests}" 1 INCOMPLETE '^code-review-check: \[content\] lens section missing'
  cr_expect "an empty lens section" "$(cr_report "$CR_FINDERS" "$CR_REFUTED" "" "" "  ")" 1 INCOMPLETE '\[content\] lens section empty'
  cr_expect "a bare none" "$(cr_report "$CR_FINDERS" "$CR_REFUTED" none)" 1 INCOMPLETE '\[content\] bare none'
}
cr_t_finders() {   # exhaustive-review/FR-009: five finders, none silent — never a reduced quorum
  cr_expect "a silent finder" "$(cr_report "$CR_SILENT" "$CR_REFUTED")" 1 INCOMPLETE '\[content\] a finder is silent'
  cr_expect "four finders" "$(cr_report "${CR_FINDERS%; cross-tier*}" "$CR_REFUTED")" 1 INCOMPLETE '\[content\] Finders: needs five entries, has 4'
  cr_expect "one finder five times" "$(cr_report 'Finders: test-integrity@fable ok; test-integrity@fable ok; test-integrity@fable ok; test-integrity@fable ok; test-integrity@fable ok' "$CR_REFUTED")" 1 INCOMPLETE '\[content\] a finder is listed twice'
}
cr_t_status() {    # exhaustive-review/FR-010 FR-005: every blocker has a verifier status; a suggestion needs none
  cr_expect "a status-less blocker" "$(cr_report "$CR_FINDERS" "$CR_NOSTATUS")" 1 INCOMPLETE '\[content\] blocking finding without a verifier status'
  cr_expect "a status-less suggestion" "$(cr_report "$CR_FINDERS" "$CR_REFUTED" "" "$(cr_finding 2 SUGGESTION hooks/x.sh:3 wording spec-deviation)")" 0 APPROVE
}
cr_t_noverdict() { # exhaustive-review/FR-010: the verdict and the BLOCKING line are the helper's, never the report's
  cr_expect "a report with its own verdict" "$CR_OK"$'\n## Verdict: APPROVE' 1 INCOMPLETE '\[shape\] the report carries its own verdict'
  cr_expect "a report with its own BLOCKING line" "$CR_OK"$'\nBLOCKING 0:' 1 INCOMPLETE '\[shape\] the report carries its own verdict'
}
cr_t_lines() {     # exhaustive-review/FR-010: a malformed finding line or a missing recipe block
  cr_expect "a malformed finding line" "$(cr_report "$CR_FINDERS" "- [F1] [BLOKING] hooks/a.sh — no line number")" 1 INCOMPLETE '\[shape\] malformed finding line'
  cr_expect "a finding without its recipe" "$(cr_report "$CR_FINDERS" "${CR_REFUTED%%$'\n'*}")" 1 INCOMPLETE '\[content\] finding without a recipe block'
}
cr_t_strict() {    # exhaustive-review/FR-010: a lens-section line that is not `- [F<n>]` or `none` is refused, never skipped
  local m blk="b.sh:2 — real defect — raised by: input-and-security — REPRODUCED → exit: 1"
  for m in "* [F2] [BLOCKING] $blk" "- **[F2]** [BLOCKING] $blk" "2. [F2] [BLOCKING] $blk" "- [BLOCKING] $blk"; do
    cr_expect "a blocker written '${m%% b.sh*}'" "$(cr_report "$CR_FINDERS" "$CR_REFUTED"$'\n'"$m")" 1 INCOMPLETE \
      '\[shape\] a lens-section line that is neither a finding nor a none line'
  done
}
cr_t_fence() {     # exhaustive-review/FR-010: a recipe holding a ``` line cannot flip the fence and hide the next finding
  local hide='- [F1] [BLOCKING] a.sh:1 — d — raised by: input-and-security — REFUTED → exit: 0 / ok — no defect
    ```recipe F1
    echo one
    ```sh
    ```
- [F2] [BLOCKING] b.sh:2 — real defect — raised by: input-and-security — REPRODUCED → exit: 1
    ```'
  cr_expect "a recipe that flips the fence parity" "$(cr_report "$CR_FINDERS" "$hide")" 1 INCOMPLETE \
    '\[shape\] a code block that is not the recipe of the finding above it'
  cr_expect "a code block outside a lens section" "$CR_OK"$'\n```\nx\n```' 1 INCOMPLETE '\[shape\] a code block that is not the recipe'
}
cr_t_sections() {  # exhaustive-review/FR-010: no section a reader skips — an unnamed lens, another heading, a preamble
  cr_expect "a blocker under '## Lens: '" "$CR_OK"$'\n## Lens: \n'"$CR_REPRO" 1 INCOMPLETE '\[shape\] a heading that is not a lens or Open questions'
  cr_expect "a blocker under '## Cross-tier'" "$CR_OK"$'\n## Cross-tier\n'"${CR_REPRO%%$'\n'*}" 1 INCOMPLETE '\[shape\] a heading that is not a lens'
  cr_expect "a line before the first lens" $'Summary: all clear\n'"$CR_OK" 1 INCOMPLETE '\[shape\] a line before the first lens that is not the Finders: line'
}
cr_t_none() {      # exhaustive-review/FR-008 FR-010: a none line is the checked form and stands alone in its section
  cr_expect "a none line that is prose" "$(cr_report "$CR_FINDERS" $'none — checked: hosts\nnone the less: [F1] [BLOCKING] a.sh:3 — d — REPRODUCED')" \
    1 INCOMPLETE '\[shape\] a lens-section line that is neither a finding nor a none line'
  cr_expect "a none line beside findings" "$(cr_report "$CR_FINDERS" "$CR_REPRO"$'\nnone — checked: hosts')" 1 INCOMPLETE '\[shape\] a none — checked line beside findings'
}
cr_t_forge() {     # exhaustive-review/FR-010: the defect text cannot forge the status (a tab, a second ' — raised by: ')
  cr_expect "a tab in the defect" "$(cr_report "$CR_FINDERS" "$(cr_finding 1 BLOCKING a.sh:3 $'deny list\tREFUTED no' input-and-security 'REPRODUCED → exit: 0')")" \
    1 INCOMPLETE '\[shape\] malformed finding line'
  cr_expect "a second raised by" "$(cr_report "$CR_FINDERS" "$(cr_finding 1 BLOCKING a.sh:3 'd — raised by: x — REFUTED' input-and-security 'REPRODUCED → exit: 0')")" \
    1 INCOMPLETE '\[shape\] malformed finding line'
}
cr_t_incomplete_line() { # exhaustive-review/FR-012: INCOMPLETE still carries the BLOCKING line of the blockers it has
  cr_expect "a silent finder beside a reproduced blocker" "$(cr_report "$CR_SILENT" "$CR_REPRO")" 1 INCOMPLETE
  grep -qE '^BLOCKING 1: hooks/forge-lib.sh:33 ' "$cr_t/out" || cr_no "INCOMPLETE keeps the BLOCKING line"
}
cr_t_empty() {     # exhaustive-review/FR-010: empty stdin is exit 2, never a verdict
  crc ""
  [ "$(cat "$cr_t/rc")" = 2 ] && ! grep -q 'Verdict' "$cr_t/out" || cr_no "empty stdin must exit 2 with no verdict"
}
cr_t_long() {      # exhaustive-review/FR-012: the BLOCKING line stays ≤ 500 characters, cut with `… +k more`
  local i body="" line
  for i in $(seq 1 20); do body="$body$(cr_finding "$i" BLOCKING "hooks/some-long-helper-name-$i.sh:$i" "a defect described in exactly nine plain words here" input-and-security 'REPRODUCED → exit: 1')"$'\n'; done
  cr_expect "twenty blockers" "$(cr_report "$CR_FINDERS" "$body")" 0 REQUEST_CHANGES
  line="$(grep -E '^BLOCKING ' "$cr_t/out")"
  [ "${#line}" -le 500 ] && [[ "$line" =~ ^BLOCKING\ 20:\ .*\;\ …\ \+[0-9]+\ more$ ]] || cr_no "the BLOCKING line of 20 blockers must be ≤ 500 and end '… +k more' (${#line} chars)"
  [[ "$line" == *"(input-and-security) a defect described in exactly nine plain words;"* ]] || cr_no "each defect is cut to eight words"
}
CR_TESTS="cr_t_verdict cr_t_unrepro cr_t_lens cr_t_finders cr_t_status cr_t_noverdict cr_t_lines cr_t_strict cr_t_fence cr_t_sections cr_t_none cr_t_forge cr_t_incomplete_line cr_t_empty cr_t_long"

cr_mirror() { # → a temp hook folder of links to every hook, for a mutant to replace one file in
  local md h; md="$(mktemp -d)"; for h in "$REPO"/hooks/*.sh; do ln -s "$h" "$md/$(basename "$h")"; done; printf '%s\n' "$md"
}
cr_mut() { # label sed-expr test-fn [file] — a mutant of hooks/<file> (default code-review-lib.sh) must turn test-fn red
  local md red f="${4:-code-review-lib.sh}"; md="$(cr_mirror)"; rm "$md/$f"; sed "$2" "$REPO/hooks/$f" >"$md/$f"
  if cmp -s "$REPO/hooks/$f" "$md/$f"; then bad "mutant did not apply to $f: $1"; x_fail=1; rm -rf "$md"; return; fi
  red="$(x_fail=0; CR_HOOKS="$md" "$3" >/dev/null 2>&1; echo "$x_fail")"; rm -rf "$md"
  [ "$red" = 1 ] && ok "mutant killed: $1" || { bad "mutant survived: $1"; x_fail=1; }
}

head_ "code-review-check: the round's report is checked and its verdict computed (exhaustive-review FR-007..FR-010, FR-012)"
x_fail=0
for cr_fn in $CR_TESTS; do "$cr_fn"; done
[ "$x_fail" -eq 0 ] && ok "code-review-check: a clean report approves, REPRODUCED and UNREPRODUCED blockers block, a missing/empty/bare-none lens, a silent or missing finder, a status-less blocker, a malformed line, a lens-section line that is neither a finding nor a none line, a code block that is not its finding's recipe, a heading that is not a lens or Open questions, a preamble line, a prose or extra none line, a tab or a second 'raised by' in a finding and the report's own verdict are INCOMPLETE (exit 1, [shape]|[content] on stderr) with the BLOCKING line kept; a status-less suggestion passes; empty stdin exits 2; the BLOCKING line is ≤ 500 with '… +k more'"
x_fail=0
cr_mut "FR-007 an UNREPRODUCED blocker does not block" '/^crc_verdict()/,/^}/s/|UNREPRODUCED//' cr_t_unrepro
cr_mut "FR-007 the verdict ignores the statuses" 's/^crc_verdict() {$/crc_verdict() { echo "## Verdict: APPROVE"; return 0;/' cr_t_verdict
cr_mut "FR-008 the lens rule dropped" 's/^crc_lens_ok() {$/crc_lens_ok() { return 0;/' cr_t_lens
cr_mut "FR-008 a bare none accepted" '/bare none — say what was checked/s/return 1/return 0/' cr_t_lens
cr_mut "FR-009 the finders rule dropped" 's/^crc_finders_ok() {$/crc_finders_ok() { return 0;/' cr_t_finders
cr_mut "FR-010 the status rule dropped" 's/^crc_statuses_ok() {$/crc_statuses_ok() { return 0;/' cr_t_status
cr_mut "FR-010 a suggestion must carry a status" '/^crc_statuses_ok()/,/^}/s/\[ "\$sev" = BLOCKING \] || continue/:/' cr_t_status
cr_mut "FR-010 the report's own verdict accepted" 's/^crc_no_verdict() {$/crc_no_verdict() { return 0;/' cr_t_noverdict
cr_mut "FR-010 the line rule dropped" 's/^crc_lines_ok() {$/crc_lines_ok() { return 0;/' cr_t_lines
cr_mut "FR-010 an unknown lens-section line skipped" '/neither a finding nor a none line/s/; bad=1$//' cr_t_strict
cr_mut "FR-010 a stray code block accepted" '/not the recipe of the finding above it/s/; bad=1; fi$/; fi/' cr_t_fence
cr_mut "FR-010 any heading accepted" '/a heading that is not a lens or Open questions/s/; bad=1; }/; }/' cr_t_sections
cr_mut "FR-010 a preamble line accepted" '/a line before the first lens that is not the Finders/s/; bad=1; }/; }/' cr_t_sections
cr_mut "FR-010 any none… line accepted" 's/^crc_none_line() {$/crc_none_line() { [[ "$1" == none* ]] \&\& return 0;/' cr_t_none
cr_mut "FR-008 a none line beside findings accepted" '/a none — checked line beside findings/s/return 1; }/return 0; }/' cr_t_none
cr_mut "FR-010 the defect may forge the status" '/!= \*" — raised by: /s/ || return 1$/ || :/' cr_t_forge
cr_mut "FR-012 INCOMPLETE drops the BLOCKING line" 's/^  crc_blocking_line "\$r"$/  [ "$bad" = 1 ] || crc_blocking_line "$r"/' cr_t_incomplete_line
cr_mut "FR-010 empty stdin decided" 's/return 2; }$/return 0; }/' cr_t_empty
cr_mut "FR-012 the 500-character cap dropped" 's/-le 500 \]/-le 5000 ]/' cr_t_long
[ "$x_fail" -eq 0 ] && ok "code-review-check: one mutant per rule, each killed (exhaustive-review/FR-010)"

# --- review-route (FR-021) ----------------------------------------------------------------------------------------------
head_ "review-route: exhaustive or single, from the ledger entry or the spec folder; never 'single' when it could not look (exhaustive-review FR-021)"
x_fail=0
cr_ld="$cr_t/ledger"; mkdir -p "$cr_ld"
cr_fake_ledger() { # $1 hooks mirror → its ledger.sh replaced by a named fake reading CR_FAKE_* from the environment
  rm -f "$1/ledger.sh"
  cat >"$1/ledger.sh" <<'FAKE_LEDGER'
#!/bin/bash
# FakeLedger for part 19: `dir` and `show` only; CR_FAKE_MARK records that the ledger was asked at all
[ -n "${CR_FAKE_MARK:-}" ] && : >"$CR_FAKE_MARK"
case "$1" in
  dir) [ -n "${CR_FAKE_DIR_FAIL:-}" ] && { echo "ledger: not inside a git repository (cwd: $PWD)" >&2; exit 1; }; echo "$CR_FAKE_LD" ;;
  show) [ -n "${CR_FAKE_SHOW_FAIL:-}" ] && { echo "ledger: entry $2 does not parse" >&2; exit 1; }; cat "$CR_FAKE_LD/$2.json" ;;
  *) echo "FakeLedger: unexpected $*" >&2; exit 9 ;;
esac
FAKE_LEDGER
  chmod +x "$1/ledger.sh"
}
cr_rh="$(cr_mirror)"; cr_fake_ledger "$cr_rh"
cr_git() { git -c user.email=t@t -c user.name=t "$@"; }
cr_rt="$cr_t/route"; mkdir -p "$cr_rt" && (cd "$cr_rt" && git init -q -b main . && cr_git commit -q --allow-empty -m init) >/dev/null 2>&1
mkdir -p "$cr_rt/.specify/specs/rv" "$cr_t/spec-light"; printf '# Spec\n' >"$cr_rt/.specify/specs/rv/spec.md"; printf '# Spec\n' >"$cr_t/spec-light/spec.md"
# rr <dir> [env…] -- [args…] → stdout+stderr to $cr_t/out, exit code to $cr_t/rc
rr() {
  local d="$1" rc=0; shift; local -a e=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do e+=("$1"); shift; done; shift
  (cd "$d" && env CR_FAKE_LD="$cr_ld" ${e[@]+"${e[@]}"} bash "${CR_RHOOKS:-$cr_rh}/speckit-helper.sh" review-route "$@") >"$cr_t/out" 2>&1 || rc=$?
  echo "$rc" >"$cr_t/rc"
}
cr_rwant() { # label rc expected-stdout-regex
  [ "$(cat "$cr_t/rc")" = "$2" ] && grep -qE -- "$3" "$cr_t/out" || { bad "review-route ($1): exit $2 and /$3/ expected — rc $(cat "$cr_t/rc"): $(head -c 300 "$cr_t/out")"; x_fail=1; }
}
cr_entry() { jq -nc --arg r "$2" --arg s "${3:-}" '{id: "HEF-9", route: $r} + (if $s == "" then {} else {spec_dir: $s} end)' >"$cr_ld/$1.json"; }
# exhaustive-review/FR-021: the ledger entry decides on a worktree-<ID> branch
cr_t_route_ledger() {
  (cd "$cr_rt" && git checkout -q -B worktree-HEF-9) >/dev/null 2>&1
  rr "$cr_rt" -- --inline; cr_rwant "--inline" 0 '^single - inline$'
  cr_entry HEF-9 fix; rr "$cr_rt" --; cr_rwant "a fix entry" 0 '^single fix ledger:HEF-9$'
  cr_entry HEF-9 light "$cr_t/spec-light"; rr "$cr_rt" --; cr_rwant "a light entry" 0 "^exhaustive light ledger:HEF-9 spec:$cr_t/spec-light\$"
  cr_entry HEF-9 full "$cr_t/no-such-spec"; rr "$cr_rt" --; cr_rwant "a full entry with no spec.md" 1 'holds no readable spec.md'
  cr_entry HEF-9 full "$cr_t/spec-light"; rr "$cr_rt" CR_FAKE_SHOW_FAIL=1 --; cr_rwant "an unreadable entry" 1 'ledger entry HEF-9 unreadable'
  rr "$cr_rt" CR_FAKE_DIR_FAIL=1 --; cr_rwant "ledger.sh dir failing on a worktree branch" 1 'ledger.sh dir failed for HEF-9'
  rm -f "$cr_ld/HEF-9.json"
}
# exhaustive-review/FR-021: any other branch never touches the ledger; its spec folder resolves from the spec root
cr_t_route_spec() {
  (cd "$cr_rt" && git checkout -q -B feature/rv) >/dev/null 2>&1; rm -f "$cr_t/asked"
  rr "$cr_rt" CR_FAKE_DIR_FAIL=1 CR_FAKE_MARK="$cr_t/asked" --; cr_rwant "a feature branch with a spec" 0 "^exhaustive full spec:$cr_rt/.specify/specs/rv\$"
  [ ! -e "$cr_t/asked" ] || { bad "review-route asked the ledger on a feature/<spec> branch"; x_fail=1; }
  (cd "$cr_rt" && git checkout -q -B feature/none) >/dev/null 2>&1
  rr "$cr_rt" --; cr_rwant "a branch with no spec" 0 '^single fix no-spec$'
}
# exhaustive-review/FR-021 (A3): an app folder's spec, resolved through the spec root, comes back as an ABSOLUTE path
cr_t_route_app() {
  (cd "$cr_rt" && git checkout -q -B feature/app-rv) >/dev/null 2>&1
  mkdir -p "$cr_rt/apps/web/.specify/specs/app-rv" "$cr_rt/apps/web/src"; printf '# Spec\n' >"$cr_rt/apps/web/.specify/specs/app-rv/spec.md"
  rr "$cr_rt/apps/web/src" --; cr_rwant "an app folder's spec" 0 "^exhaustive full spec:/.*/apps/web/.specify/specs/app-rv\$"
}
# exhaustive-review/FR-021: no git → .git/HEAD (a linked worktree's gitdir followed); detached or nothing → exit 1
cr_t_route_head() {
  local nogit="$cr_t/nogit" wt="$cr_t/wt-rv"
  mkdir -p "$nogit"; printf '#!/bin/sh\nexit 127\n' >"$nogit/git"; chmod +x "$nogit/git"
  (cd "$cr_rt" && git checkout -q main && git worktree add -q -b feature/rv "$wt") >/dev/null 2>&1 \
    || (cd "$cr_rt" && git worktree add -q "$wt" feature/rv) >/dev/null 2>&1
  mkdir -p "$wt/.specify/specs/rv"; printf '# Spec\n' >"$wt/.specify/specs/rv/spec.md"
  rr "$wt" PATH="$nogit:$PATH" --; cr_rwant "git denied in a linked worktree" 0 "^exhaustive full spec:$wt/.specify/specs/rv\$"
  (cd "$cr_rt" && git checkout -q --detach) >/dev/null 2>&1
  rr "$cr_rt" --; cr_rwant "a detached HEAD" 1 'detached HEAD'
  mkdir -p "$cr_t/bare-dir"; rr "$cr_t/bare-dir" PATH="$nogit:$PATH" --; cr_rwant "no git and no .git" 1 'cannot read the branch'
  (cd "$cr_rt" && git checkout -q main) >/dev/null 2>&1
}
for cr_fn in cr_t_route_ledger cr_t_route_spec cr_t_route_app cr_t_route_head; do "$cr_fn"; done
[ "$x_fail" -eq 0 ] && ok "review-route: --inline and a fix entry → single; a light entry → exhaustive with its absolute spec folder; a full entry with no spec.md, an unreadable entry and a failing ledger dir → exit 1; a feature branch never asks the ledger and resolves its (app folder's) spec absolutely; .git/HEAD read through a linked worktree when git is denied; detached or no branch → exit 1 (exhaustive-review/FR-021)"
x_fail=0
cr_rmut() { # label sed-expr test-fn — a mutant of the route in a mirror that keeps the fake ledger
  local md red; md="$(cr_mirror)"; cr_fake_ledger "$md"; rm "$md/code-review-lib.sh"; sed "$2" "$REPO/hooks/code-review-lib.sh" >"$md/code-review-lib.sh"
  if cmp -s "$REPO/hooks/code-review-lib.sh" "$md/code-review-lib.sh"; then bad "route mutant did not apply: $1"; x_fail=1; rm -rf "$md"; return; fi
  red="$(x_fail=0; CR_RHOOKS="$md" "$3" >/dev/null 2>&1; echo "$x_fail")"; rm -rf "$md"
  [ "$red" = 1 ] && ok "mutant killed: $1" || { bad "mutant survived: $1"; x_fail=1; }
}
cr_rmut "FR-021 every branch asks the ledger" 's/if \[ "\$id" != "\$br" \]; then/if true; then/' cr_t_route_spec
cr_rmut "FR-021 a failing ledger dir falls through to the spec folder" '/ledger.sh dir failed/s/return 1; }/d=""; }/' cr_t_route_ledger
cr_rmut "FR-021 (A3) the spec folder answered relative" 's/spec:\$(pwd -P)\//spec:/' cr_t_route_app
cr_rmut "FR-021 a detached HEAD accepted" '/detached HEAD/s/return 1/return 0/' cr_t_route_head
cr_rmut "FR-021 a light entry's spec.md not checked" 's/\[ -r "\$dir\/spec.md" \]/true/' cr_t_route_ledger
[ "$x_fail" -eq 0 ] && ok "review-route: 5 mutants killed (exhaustive-review/FR-021)"
rm -rf "$cr_rh"

# --- structure of the command and the agent (FR-019, FR-015, FR-021, A1; SC-002) ------------------------------------------
head_ "hef.review code mode and code-reviewer: lenses, cross-tier finder, verifier, preflight, documented calls (exhaustive-review FR-019)"
x_fail=0
CR_LENS_NAMES="input-and-security state-and-lifecycle spec-deviation test-integrity"
cr_sno() { bad "$1"; x_fail=1; }
cr_brief() { # cr_brief <file> <role> → the blockquote brief that opens `> Role: **<role>**`
  sed -n "/^> Role: \*\*$2\*\*/,/^[^>]/p" "$1" | grep '^>'
}
cr_section() { # cr_section <file> <heading line> → from that exact heading up to (not including) the next heading of its level
  local lvl="${2%% *}" line in=0
  while IFS= read -r line; do
    if [ "$in" = 0 ]; then [ "$line" = "$2" ] && { in=1; printf '%s\n' "$line"; }; continue; fi
    [[ "$line" == "$lvl "* ]] && break
    printf '%s\n' "$line"
  done <"$1"
}
# exhaustive-review/FR-019 FR-015: the four lenses, the cross-tier spawn and the verifier step are documented
cr_t_struct_round() {
  local c="${1:-$REPO/commands/hef.review.md}" a="${2:-$REPO/agents/code-reviewer.md}" lens
  for lens in $CR_LENS_NAMES; do
    grep -qF "\`$lens\`" "$c" || cr_sno "hef.review.md must name the lens $lens"
    grep -qF -- "- **$lens**" "$a" || cr_sno "code-reviewer.md must document the lens $lens"
  done
  grep -qF 'cross-tier finder**, with `model: opus`' "$c" || cr_sno "hef.review.md must spawn the cross-tier finder with model: opus"
  [ "$(sed -n 2p "$a")" = "model: fable" ] || cr_sno "code-reviewer.md:2 must stay 'model: fable' — the cross-tier pair (fable + opus) is revisited, never silently equal"
  [ -n "$(cr_brief "$c" verifier)" ] && grep -qx '## Verifier role' "$a" && grep -qx '## Finder role' "$a" \
    || cr_sno "the verifier step (hef.review.md) and the finder/verifier roles (code-reviewer.md) must be documented"
}
# exhaustive-review/FR-015 FR-003 FR-019: no "fewer findings" wording reaches a finder or a verifier; the other paths keep theirs
cr_t_struct_volume() {
  local c="${1:-$REPO/commands/hef.review.md}" a="${2:-$REPO/agents/code-reviewer.md}" role t
  for role in finder verifier; do
    t="$(cr_brief "$c" "$role")"
    [ -n "$t" ] || { cr_sno "no $role brief in hef.review.md"; continue; }
    t="$t"$'\n'"$(cr_section "$a" "## $([ "$role" = finder ] && echo Finder || echo Verifier) role")"
    ! grep -qiE 'prefer fewer|scope over volume|scope discipline|flag only' <<<"$t" || cr_sno "the $role brief or role must not ask for fewer findings"
    grep -qF 'The spec is in `<spec dir>`' <<<"$t" || cr_sno "the $role brief must name the route's spec folder (FR-021)"
  done
  grep -qF 'Scope discipline: flag only findings that affect correctness' "$c" || cr_sno "the single reviewer keeps its scope-discipline brief"
  grep -qF 'Outside the finder and verifier roles: **Evidence over assertion, and scope over volume.**' "$a" || cr_sno "Rule 0 keeps 'scope over volume' outside the two roles"
}
# exhaustive-review/FR-019 FR-022: every documented helper heredoc is one plain command from the plugin's hooks
# amendment A3: review-repro.sh takes its recipe as ONE single-quoted argument — documented never as a heredoc
cr_t_struct_calls() {
  local c="${1:-$REPO/commands/hef.review.md}" a="${2:-$REPO/agents/code-reviewer.md}" line h n=0
  local re_rr="^(\\\$\\{CLAUDE_PLUGIN_ROOT\\}/hooks|<abs hooks>)/review-repro\\.sh '[^']*'\$"
  while IFS= read -r line; do
    h="${line%%<<*}"; h="${h#> }"; h="${h#\`}"
    [[ "$h" =~ ^\$\{CLAUDE_PLUGIN_ROOT\}/hooks/speckit-helper\.sh\ code-review-check\ $ ]] \
      || cr_sno "a documented helper heredoc must start with \${CLAUDE_PLUGIN_ROOT}/hooks/ and hold nothing else before << (no | ; &&): $line"
    n=$((n + 1))
  done < <(grep -E "<<'HEF_CRC_REPORT_END'" "$c")
  while IFS= read -r line; do
    h="${line#> }"; h="${h#\`}"; h="${h%%\`*}"
    [[ "$h" =~ $re_rr ]] || cr_sno "a documented review-repro.sh call must be the hooks path plus one single-quoted argument, nothing else: $line"
    n=$((n + 1))
  done < <(grep -E "review-repro\.sh '" "$c")
  [ "$n" -ge 3 ] || cr_sno "hef.review.md must document the preflight, the verifier's and the check's calls (found $n)"
  ! grep -qE 'review-repro\.sh <<' "$c" "$a" || cr_sno "review-repro.sh is documented with a heredoc — amendment A3: one single-quoted argument"
  grep -qF "<abs hooks>/review-repro.sh '<the recipe>'" "$a" || cr_sno "the verifier role must run recipes as one single-quoted argument (amendment A3)"
}
# exhaustive-review/FR-021 (A1, A6): the preflight; on its refusal the round still runs, reproduction unavailable
cr_t_struct_preflight() {
  local c="${1:-$REPO/commands/hef.review.md}" a="${2:-$REPO/agents/code-reviewer.md}"
  grep -qxF "\${CLAUDE_PLUGIN_ROOT}/hooks/review-repro.sh 'true'" "$c" || cr_sno "the preflight runs review-repro.sh with 'true'"
  grep -qF 'the exhaustive round **still runs, with reproduction unavailable**, whatever the route' "$c" \
    && grep -qF 'Never the single reviewer and never `INCOMPLETE` for this cause' "$c" \
    || cr_sno "A6: the preflight's exit 2 keeps the exhaustive round — no single-reviewer fallback, no INCOMPLETE"
  grep -qF "reproduction unavailable: <the helper's message> — fix:" "$c" || cr_sno "A6: the refusal's cause-and-fix line is kept in the report"
  grep -qF '`UNREPRODUCED — reproduction unavailable: <the preflight' "$c" && grep -qF 'Run no recipe.' "$c" \
    || cr_sno "A6: the reproduction-unavailable verifier brief marks every blocker UNREPRODUCED with the refusal"
  grep -qF 'run no recipe:' "$a" || cr_sno "A6: the verifier role knows the reproduction-unavailable brief"
  ! grep -qF 'exhaustive round unavailable' "$c" || cr_sno "A6: the A1 single-reviewer fallback is still documented"
}
# exhaustive-review/FR-001 exhaustive-review/FR-002 exhaustive-review/FR-003 exhaustive-review/FR-004
# exhaustive-review/FR-005: the round's steps — five finders in one foreground message, every candidate with a recipe,
# the merge (one candidate per file:line, lenses kept, BLOCKING wins), fresh verifiers of at most 8, three statuses
cr_t_struct_steps() {
  local c="${1:-$REPO/commands/hef.review.md}"
  grep -qF '**1. Five finders, ONE message, foreground** (`run_in_background: false`)' "$c" || cr_sno "FR-001: the five finders are spawned in one foreground message"
  grep -qF 'Report every candidate defect' "$c" && grep -qF 'back with a `file:line` and a recipe' "$c" || cr_sno "FR-003: the finder brief asks for every candidate with file:line and a recipe"
  grep -qF 'The same `file:line` with the same failure is one candidate, every lens' "$c" && grep -qF '**`BLOCKING` if any' "$c" \
    || cr_sno "FR-004: the merge de-duplicates by file:line, keeps every lens and lets BLOCKING win"
  grep -qF 'at most 8 per verifier, go to fresh `code-reviewer` spawns — never one of' "$c" && grep -qF '`not verified — never blocks`' "$c" \
    && grep -qF '`REPRODUCED`, `REFUTED` or `UNREPRODUCED`' "$c" || cr_sno "FR-005: fresh verifiers of at most 8 blockers, suggestions never verified, three statuses"
}
# exhaustive-review/FR-011 exhaustive-review/FR-013 exhaustive-review/FR-014: one shape-only re-write then INCOMPLETE;
# UNREPRODUCED blockers listed under Open questions; INCOMPLETE is gate review FAIL in a verify run
cr_t_struct_relay() {
  local c="${1:-$REPO/commands/hef.review.md}"
  grep -qF 'When **every** violation is `[shape]`, re-write the report once' "$c" && grep -qF 'Any remaining exit ≠ 0 → the verdict is `INCOMPLETE`' "$c" \
    || cr_sno "FR-011: one shape-only re-write, then INCOMPLETE"
  grep -qF '`## Open questions` listing every `UNREPRODUCED` blocker with its reason' "$c" || cr_sno "FR-013: UNREPRODUCED blockers are listed under Open questions"
  grep -qF '`INCOMPLETE` is gate `review` `FAIL`, with the' "$c" || cr_sno "FR-014: INCOMPLETE is gate review FAIL in a verify run"
}
for cr_fn in cr_t_struct_round cr_t_struct_volume cr_t_struct_calls cr_t_struct_preflight cr_t_struct_steps cr_t_struct_relay; do "$cr_fn"; done
[ "$x_fail" -eq 0 ] && ok "hef.review.md and code-reviewer.md: four lenses, a cross-tier finder at model: opus beside the fable pin, a verifier step, no fewer-findings wording in the finder/verifier briefs (kept by the single reviewer and Rule 0), both briefs name the spec folder, every documented heredoc is a plain CLAUDE_PLUGIN_ROOT/hooks call, the A1 preflight, and on its refusal the round still runs without reproduction (A6) (exhaustive-review/FR-019, FR-015, FR-021)"
x_fail=0
cr_smut() { # label file(commands/…|agents/…) sed-expr test-fn — a mutant copy of the file must turn test-fn red
  local d red; d="$(mktemp -d)"
  cp "$REPO/commands/hef.review.md" "$d/c.md"; cp "$REPO/agents/code-reviewer.md" "$d/a.md"; sed "$3" "$REPO/$2" >"$d/m.md"
  if cmp -s "$REPO/$2" "$d/m.md"; then bad "structural mutant did not apply: $1"; x_fail=1; rm -rf "$d"; return; fi
  case "$2" in commands/*) mv "$d/m.md" "$d/c.md" ;; *) mv "$d/m.md" "$d/a.md" ;; esac
  red="$(x_fail=0; "$4" "$d/c.md" "$d/a.md" >/dev/null 2>&1; echo "$x_fail")"; rm -rf "$d"
  [ "$red" = 1 ] && ok "mutant killed: $1" || { bad "mutant survived: $1"; x_fail=1; }
}
cr_smut "FR-002 the cross-tier finder at the pinned tier" commands/hef.review.md 's/with `model: opus`/with no override/' cr_t_struct_round
cr_smut "FR-002 the pin moved off fable" agents/code-reviewer.md '2s/model: fable/model: opus/' cr_t_struct_round
cr_smut "FR-015 a lens dropped from the agent" agents/code-reviewer.md 's/^- \*\*test-integrity\*\*/- test-integrity/' cr_t_struct_round
cr_smut "FR-003 the finder brief asks for fewer findings" commands/hef.review.md 's/^> Role: \*\*finder\*\*, lens/> Role: **finder**, prefer fewer findings, lens/' cr_t_struct_volume
cr_smut "FR-003 the verifier role keeps scope over volume" agents/code-reviewer.md '/^You did not find anything this round/s/$/ Scope over volume./' cr_t_struct_volume
cr_smut "FR-021 the verifier brief loses the spec folder" commands/hef.review.md '/^> Role: \*\*verifier\*\*/s/The spec is in/The spec lives in/' cr_t_struct_volume
cr_smut "FR-019 a pipe before the check's heredoc" commands/hef.review.md "s/code-review-check <<'HEF_CRC/code-review-check | cat <<'HEF_CRC/" cr_t_struct_calls
cr_smut "FR-021 (A1) the preflight dropped" commands/hef.review.md '/^\*\*Preflight\*\*/,/review-repro\.sh .true.$/d' cr_t_struct_preflight
cr_smut "FR-021 (A6) the refusal falls back to the single reviewer" commands/hef.review.md 's/Never the single reviewer and never `INCOMPLETE` for this cause/A branch goes to the single reviewer (exhaustive round unavailable)/' cr_t_struct_preflight
cr_smut "FR-021 (A6) the unavailable brief runs recipes" commands/hef.review.md 's/Run no recipe\./Run each recipe./' cr_t_struct_preflight
cr_smut "FR-021 (A6) the verifier role forgets the unavailable brief" agents/code-reviewer.md 's/run no recipe:/run each recipe:/' cr_t_struct_preflight
cr_smut "FR-022 (A3) the verifier brief back to a heredoc" commands/hef.review.md "s/review-repro.sh '<the recipe>'/review-repro.sh <<'HEF_REPRO_RECIPE_END'/" cr_t_struct_calls
cr_smut "FR-022 (A3) the verifier role back to a heredoc" agents/code-reviewer.md "s/review-repro.sh '<the recipe>'/review-repro.sh <<'HEF_REPRO_RECIPE_END'/" cr_t_struct_calls
cr_smut "FR-022 (A3) a command after the preflight's argument" commands/hef.review.md "s/review-repro.sh 'true'\$/review-repro.sh 'true'; true/" cr_t_struct_calls
cr_smut "FR-001 the finders spawned in the background" commands/hef.review.md 's/ONE message, foreground\*\* (`run_in_background: false`)/ONE message** (`run_in_background: true`)/' cr_t_struct_steps
cr_smut "FR-003 the finder brief asks for its best findings only" commands/hef.review.md 's/Report every candidate defect/Report the most important defects/' cr_t_struct_steps
cr_smut "FR-004 a SUGGESTION wins the merge" commands/hef.review.md 's/\*\*`BLOCKING` if any/**`SUGGESTION` if any/' cr_t_struct_steps
cr_smut "FR-005 verifiers take any number of blockers" commands/hef.review.md 's/at most 8 per verifier/all in one verifier/' cr_t_struct_steps
cr_smut "FR-011 the re-write allowed on content violations" commands/hef.review.md 's/When \*\*every\*\* violation is `\[shape\]`/When any violation remains/' cr_t_struct_relay
cr_smut "FR-013 UNREPRODUCED blockers left out of Open questions" commands/hef.review.md 's/`## Open questions` listing every `UNREPRODUCED` blocker with its reason/`## Open questions`/' cr_t_struct_relay
cr_smut "FR-014 INCOMPLETE reported as a pass in a verify run" commands/hef.review.md 's/`INCOMPLETE` is gate `review` `FAIL`/`INCOMPLETE` is gate `review` `PASS`/' cr_t_struct_relay
[ "$x_fail" -eq 0 ] && ok "structure: 21 mutants killed (exhaustive-review/FR-019)"

# --- the replay cases' shape (T019) ----------------------------------------------------------------------------------
# exhaustive-review/FR-016 exhaustive-review/FR-017 exhaustive-review/FR-019: 15 per-defect, 3 item and 3 control
# cases; each carries execution.allowed_tools
# (A2) and exactly two graders — tool_used Agent min 6 plus one llm (A5 dropped the review-repro.sh grader: the eval
# sandbox has no writable scratch folder, so no recipe runs there); each scaffold execs the shared one with two full SHAs
CR_REPLAY_N=21
cr_case_ok() { # cr_case_ok <case dir> → 0 when its case.yaml and scaffold.sh have the replay shape
  local c="$1/case.yaml" s="$1/scaffold.sh"
  [ -f "$c" ] && [ -x "$s" ] || return 1
  grep -qE '^schema_version: "1\.[0-9]+"$' "$c" && grep -qxF "name: $(basename "$1")" "$c" || return 1
  grep -qxF '  allowed_tools: [Agent, Bash, Read, Glob, Grep, Skill]' "$c" || return 1
  [ "$(grep -cE '^    type: ' "$c")" = 2 ] && [ "$(grep -cxF '    type: llm' "$c")" = 1 ] || return 1
  grep -qxF '    tool: Agent' "$c" && grep -qxF '    min: 6' "$c" && ! grep -qF 'input_match' "$c" || return 1
  grep -qF 'tests/fixtures/review-replay.sh' "$s" && grep -qE '^  [0-9a-f]{40} [0-9a-f]{40} [a-z][a-z-]*$' "$s"
}
cr_t_replay_cases() { # cr_t_replay_cases [evals dir]
  local ev="${1:-$REPO/evals}" d n=0
  for d in "$ev"/review-replay-d[0-9]* "$ev"/review-replay-hef-* "$ev"/review-control-hef-*; do
    [ -d "$d" ] || continue
    n=$((n + 1))
    cr_case_ok "$d" || cr_sno "replay case $(basename "$d"): needs allowed_tools (A2), two graders (tool_used Agent min 6 + llm, no review-repro.sh grader — A5) and a scaffold with two 40-char SHAs"
  done
  [ "$n" = "$CR_REPLAY_N" ] || cr_sno "expected $CR_REPLAY_N replay/control cases (15 per-defect, 3 item, 3 control), found $n"
}
x_fail=0
cr_t_replay_cases
[ "$x_fail" -eq 0 ] && ok "$CR_REPLAY_N replay and control cases: allowed_tools, tool_used Agent min 6 + one llm grader, full-SHA scaffolds (exhaustive-review/FR-016, FR-017, FR-019)"
cr_rmut() { # label case sed-expr file(case.yaml|scaffold.sh) — a mutant copy of evals/ must turn cr_t_replay_cases red
  local d red; d="$(mktemp -d)"
  cp -R "$REPO"/evals/review-replay-d[0-9]* "$REPO"/evals/review-replay-hef-* "$REPO"/evals/review-control-hef-* "$d/"
  if [ -n "$3" ]; then sed "$3" "$REPO/evals/$2/$4" >"$d/$2/$4"; chmod +x "$d/$2/scaffold.sh"
  else rm -rf "${d:?}/$2"; fi
  red="$(x_fail=0; cr_t_replay_cases "$d" >/dev/null 2>&1; echo "$x_fail")"; rm -rf "$d"
  [ "$red" = 1 ] && ok "mutant killed: $1" || { bad "mutant survived: $1"; x_fail=1; }
}
x_fail=0
cr_rmut "FR-016 A2 allowed_tools dropped" review-replay-d31-2 '/allowed_tools:/d' case.yaml
cr_rmut "FR-016 A5 a review-repro.sh match back on a grader" review-replay-d22-3 's/^    tool: Agent$/    tool: Agent\
    input_match: "review-repro"/' case.yaml
cr_rmut "FR-016 the llm grader dropped" review-replay-d25-1 '/type: llm/,$d' case.yaml
cr_rmut "FR-017 a control's Agent minimum lowered" review-control-hef-25 's/min: 6/min: 1/' case.yaml
cr_rmut "FR-016 a short SHA in a scaffold" review-replay-d22-1 's/ad63db844a79aeb2c94c0f7a3046cda55f416af2/ad63db8/' scaffold.sh
cr_rmut "FR-017 an item case missing" review-replay-hef-31 '' ''
[ "$x_fail" -eq 0 ] && ok "replay case shape: 6 mutants killed (exhaustive-review/FR-019)"

# exhaustive-review/FR-018: evals/README.md has a results row for every replay and control case, `not yet measured`
# until a person runs it, and the controls' table records the blockers on the merged head
cr_t_results_table() { # cr_t_results_table [README] [evals dir]
  local r="${1:-$REPO/evals/README.md}" ev="${2:-$REPO/evals}" d
  grep -qF '| Case | Run date | Found / expected | Agents | Input / output tokens | USD | Wall time |' "$r" \
    && grep -qF '| Control | Run date | Verdict | Blockers on the merged head |' "$r" || cr_sno "FR-018: evals/README.md must carry both results tables"
  for d in "$ev"/review-replay-d[0-9]* "$ev"/review-replay-hef-* "$ev"/review-control-hef-*; do
    [ -d "$d" ] || continue
    grep -qE "^\| $(basename "$d")( \(| \|)" "$r" || cr_sno "FR-018: no results row for $(basename "$d") in evals/README.md"
  done
}
# exhaustive-review/FR-020: the docs describe the round — agents.md (lenses, roles, review-repro.sh limits), commands.md
# (the round and the preflight), the 53-subcommand count, the README's eval count, the command's description, CHANGELOG
cr_t_docs() {
  local a="${1:-$REPO/docs/agents.md}"
  grep -qF '**Lenses and roles (the exhaustive round' "$a" && grep -qF 'Known limits of `review-repro.sh`' "$a" || cr_sno "FR-020: docs/agents.md describes the lenses, the roles and review-repro.sh's limits"
  grep -qF 'gets the **exhaustive round**' "$REPO/docs/commands.md" && grep -qF 'A **preflight** `review-repro.sh '"'true'"'`' "$REPO/docs/commands.md" \
    || cr_sno "FR-020: docs/commands.md describes the exhaustive round and its preflight"
  grep -qF 'speckit-helper.sh (53 subcommands)' "$REPO/docs/architecture.md" && grep -qF '`speckit-helper.sh` (53 subcommands)' "$REPO/README.md" \
    || cr_sno "FR-020: the subcommand count is 53 in docs/architecture.md and README.md"
  grep -qF '22 review-replay cases below — 37 in' "$REPO/evals/README.md" || cr_sno "FR-020: evals/README.md counts 37 cases"
  sed -n 3p "$REPO/commands/hef.review.md" | grep -qF 'five finders by lens and a verifier' || cr_sno "FR-020: hef.review.md's description names the exhaustive round"
  sed -n '/^## \[Unreleased\]/,/^## \[[0-9]/p' "$REPO/CHANGELOG.md" | grep -qF 'The code review is exhaustive' || cr_sno "FR-020: CHANGELOG [Unreleased] describes the exhaustive round"
}
x_fail=0
cr_t_results_table; cr_t_docs
[ "$x_fail" -eq 0 ] && ok "evals/README.md results tables cover every replay and control case; the docs, the description and the CHANGELOG describe the round (exhaustive-review/FR-018, exhaustive-review/FR-020)"
x_fail=0
cr_tmp_rt="$(mktemp -d)"
grep -vF '| review-control-hef-31 |' "$REPO/evals/README.md" >"$cr_tmp_rt/r.md"
cr_red="$(x_fail=0; cr_t_results_table "$cr_tmp_rt/r.md" >/dev/null 2>&1; echo "$x_fail")"
[ "$cr_red" = 1 ] && ok "mutant killed: FR-018 a control's results row dropped" || { bad "mutant survived: FR-018 a control's results row dropped"; x_fail=1; }
sed 's/Known limits of `review-repro.sh`/Notes on review-repro.sh/' "$REPO/docs/agents.md" >"$cr_tmp_rt/a.md"
cr_red="$(x_fail=0; cr_t_docs "$cr_tmp_rt/a.md" >/dev/null 2>&1; echo "$x_fail")"
[ "$cr_red" = 1 ] && ok "mutant killed: FR-020 agents.md loses review-repro.sh's limits" || { bad "mutant survived: FR-020 agents.md loses review-repro.sh's limits"; x_fail=1; }
rm -rf "$cr_tmp_rt"

# exhaustive-review SC-002: while this feature is unmerged (its lib absent at the merge base), the launcher, its fixture
# and plan mode stay byte-unchanged. Scoped so that a later item may change them: once merged, the base has the lib.
x_fail=0
CR_PLAN_HEAD='## Plan mode — via `code-reviewer`, in a fresh context'
cr_base="$(git -C "$REPO" merge-base HEAD main 2>/dev/null || git -C "$REPO" merge-base HEAD origin/main 2>/dev/null || true)"
if [ -z "$cr_base" ]; then ok "SC-002 not checked — no main or origin/main ref here (a shallow or detached checkout)"
elif git -C "$REPO" cat-file -e "$cr_base:hooks/code-review-lib.sh" 2>/dev/null; then ok "SC-002 not checked — the exhaustive round is already on main"
else
  [ -z "$(git -C "$REPO" diff --stat "$cr_base" -- hooks/session-launch.sh tests/fixtures/launch-920.txt)" ] \
    || cr_sno "SC-002: hooks/session-launch.sh and tests/fixtures/launch-920.txt must stay unchanged"
  git -C "$REPO" show "$cr_base:commands/hef.review.md" >"$cr_t/base-review.md"
  cr_pm_base="$(cr_section "$cr_t/base-review.md" "$CR_PLAN_HEAD")"
  [ -n "$cr_pm_base" ] && [ "$cr_pm_base" = "$(cr_section "$REPO/commands/hef.review.md" "$CR_PLAN_HEAD")" ] \
    || cr_sno "SC-002: plan mode of hef.review.md must stay byte-unchanged"
  [ "$x_fail" -eq 0 ] && ok "SC-002: the launcher, launch-920.txt and plan mode are unchanged against the merge base (exhaustive-review/SC-002)"
fi
