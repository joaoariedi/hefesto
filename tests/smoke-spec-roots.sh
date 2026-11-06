# shellcheck shell=bash
#
# monorepo-spec-roots smoke checks, part 10: a .specify/ per app folder in one git repository (#172;
# FR-001..FR-019, SC-001..SC-004).
#
# SOURCED by tests/smoke.sh, never run on its own. Self-contained: temp repositories with apps in subfolders, the
# hooks run with JSON on stdin, the ledger and the launcher's --dry-run run against them.

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ sld >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-spec-roots.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_, sld)"
  else echo "tests/smoke-spec-roots.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

sr_git() { git -c user.email=t@t -c user.name=t "$@"; }
sr_mirror() { # → a temp hook folder of links to every hook, for a mutant to replace one file in
  local md h; md="$(mktemp -d)"; for h in "$REPO"/hooks/*.sh; do ln -s "$h" "$md/$(basename "$h")"; done; printf '%s\n' "$md"
}
sr_mutant() { # hooks-dir file sed-expr → replaces the link with the edited copy; refuses a no-op edit
  rm "$1/$2"; sed "$3" "$REPO/hooks/$2" > "$1/$2"
  ! cmp -s "$REPO/hooks/$2" "$1/$2" || { bad "mutant did not apply to $2: $3"; return 1; }
}

# --- SC-003 / FR-011: with no spec_roots, the launcher's lines are 9.2.0's --------------------------------------------
# The fixture is the one tests/fixtures/launch-920.txt was captured from: a tasks-repo board with one item, the
# plan and implement dry runs. sr_launch_lines prints them normalised (temp paths, the hooks folder, the nonce).
sr_launch_repo() { # → a fresh fixture repository; prints its path
  local t; t="$(cd "$(mktemp -d)" && pwd -P)"
  ( cd "$t" && git init -q -b main . && sr_git commit -q --allow-empty -m init && mkdir -p tasks .claude \
    && printf '# TODO\n\n## HEF-1 — first\nbody one\n' > tasks/TODO.md && printf '# D\n' > tasks/DOING.md \
    && printf '# D\n' > tasks/DONE.md && printf '# B\n' > tasks/BACKLOG.md \
    && printf '{"source":"tasks-repo","root":"tasks","orchestrate":{"usd_cap":5,"daily_usd_cap":25}}\n' > .claude/project-status.json \
    && bash "${2:-$REPO/hooks}/ledger.sh" init HEF-1 --kind tasks-repo --ref tasks/TODO.md#HEF-1 >/dev/null ) >/dev/null 2>&1
  printf '%s\n' "$t"
}
# The launcher's own line carries `env -u GIT_CONFIG_KEY_<n>…` built from the caller's GIT_CONFIG_COUNT (a sandboxed
# shell sets one, CI does not): the comparison runs with none, so the fixture is the same on every machine.
sr_noenv() { local v; for v in $(env | sed -n 's/^\(GIT_CONFIG_[A-Z_0-9]*\)=.*/\1/p'); do unset "$v"; done; }
sr_launch_lines() { # hooks-dir → the normalised plan + implement dry runs of a fresh fixture
  local hd="$1" t cfg out
  t="$(sr_launch_repo "" "$hd")"; cfg="$(mktemp -d)"
  out="$(for r in plan implement; do echo "== $r"; (cd "$t" && unset XDG_CACHE_HOME && sr_noenv && CLAUDE_CONFIG_DIR="$cfg" bash "$hd/session-launch.sh" "$r" HEF-1 --dry-run 2>&1); done)"
  # macOS /bin/bash 3.2 renders the dry run's quoted apostrophe ('\'' under bash 5) as \'\\'\' — the launcher's display
  # helper q(), unchanged since 9.2.0; the fixture is the bash 5 rendering, so the 3.2 form is mapped onto it
  local b32="\\'\\\\'\\'" b5="'\\''"; out="${out//"$b32"/$b5}"
  # 9.3.0 spells every command the way Claude Code resolves a plugin component (/hefesto:hef.<name>); the fixture is
  # 9.2.0's, so the spelling is mapped back: everything else must still be byte-identical
  local ns_full="/hefesto:hef." ns_bare="/hef."; out="${out//"$ns_full"/$ns_bare}"   # no backslash: bash 3.2 keeps it in the replacement
  sed -e "s#$t#<TOP>#g" -e "s#$cfg#<CFG>#g" -e "s#$hd#<HOOKS>#g" -e "s#$HOME#<HOME>#g" -e 's#worker-cache/[^/ "]*#worker-cache/<KEY>#g' \
      -e 's/\(untrusted-[a-z]*-\{0,1\}[a-z]* HEF-1\) [0-9a-f]\{8\}/\1 <N>/g' -e 's/untrusted-end [0-9a-f]\{8\}/untrusted-end <N>/g' <<<"$out"
  rm -rf "$t" "$cfg"
}

head_ "No spec_roots: the launcher's plan and implement lines are 9.2.0's, byte for byte (FR-011, SC-003)"
# FR-011 SC-003: tests/fixtures/launch-920.txt was captured from the v9.2.0 tree's hooks (git archive v9.2.0 hooks)
sr_now="$(sr_launch_lines "$REPO/hooks")"
if [ "$sr_now" = "$(cat "$REPO/tests/fixtures/launch-920.txt")" ]; then ok "no spec_roots: the launcher's dry runs equal the 9.2.0 fixture (FR-011)"
else bad "no spec_roots: the launcher's dry runs differ from tests/fixtures/launch-920.txt (FR-011), word by word: $(diff <(printf '%s\n' "$sr_now" | tr ' ' '\n') <(tr ' ' '\n' < "$REPO/tests/fixtures/launch-920.txt") | head -c 1500)"; fi

# --- the app fixture ----------------------------------------------------------------------------------------------
# outer/.specify/ sits ABOVE the repository (a home-folder one); the repository has a top constitution, apps backend/,
# frontend/, apps/web/, a nested backend/api/, and backend/linked/.specify → a folder outside the repository.
sr_t="$(cd "$(mktemp -d)" && pwd -P)"; sr_r="$sr_t/outer/repo"
mkdir -p "$sr_t/outer/.specify" "$sr_t/elsewhere/specs" "$sr_r"
( cd "$sr_r" && git init -q -b main . && sr_git commit -q --allow-empty -m init && git checkout -q -b feature/audit-log \
  && mkdir -p .specify/memory backend/.specify/memory backend/.specify/specs/audit-log backend/internal/store \
       frontend/.specify/specs/audit-log frontend/src apps/web/.specify/specs backend/api/.specify/specs backend/api/handlers \
       backend/linked .claude tasks \
  && printf '# Repo constitution\nroot rule\n' > .specify/memory/constitution.md \
  && printf '# Backend constitution\nbackend rule\n' > backend/.specify/memory/constitution.md \
  && printf '# Spec\nFR-001 backend\n' > backend/.specify/specs/audit-log/spec.md \
  && ln -s "$sr_t/elsewhere" backend/linked/.specify ) >/dev/null 2>&1

head_ "spec_root_find: the nearest .specify/, never above the top, never through a link out (FR-001, FR-017–FR-019)"
x_fail=0
sr_lib_case() { # path expected label — runs spec_root_find in a fresh shell with the lib (or $SR_LIB)
  local got; got="$(bash -c '. "$1"; spec_root_find "$2"' _ "${SR_LIB:-$REPO/hooks/spec-root-lib.sh}" "$1" 2>&1)"
  [ "$got" = "$2" ] || { bad "$3: spec_root_find $1 → '$got', expected $2"; x_fail=1; }
}
sr_lib_tests() {
  sr_lib_case "$sr_r/backend/internal/store" "$sr_r/backend" "FR-001 from a subfolder of an app"
  sr_lib_case "$sr_r/backend/internal/store/new_test.go" "$sr_r/backend" "FR-001 from a file that does not exist yet"
  sr_lib_case "$sr_r/backend" "$sr_r/backend" "FR-001 from the app folder itself"
  sr_lib_case "$sr_r/frontend/src" "$sr_r/frontend" "FR-001 another app"
  sr_lib_case "$sr_r/backend/api/handlers" "$sr_r/backend/api" "FR-018 a nested spec root wins over its parent"
  sr_lib_case "$sr_r/backend/linked" "$sr_r/backend" "FR-019 a .specify that links out of the repository is skipped"
  sr_lib_case "$sr_r/tasks" "$sr_r" "FR-001 a folder with no app of its own finds the top"
  sr_lib_case "$sr_r/backend/.specify/specs/audit-log/plan.md" "$sr_r/backend" "FR-001 a file inside .specify/ belongs to its root"
  rm -rf "$sr_r/.specify.off"; mv "$sr_r/.specify" "$sr_r/.specify.off"
  sr_lib_case "$sr_r/tasks" "$sr_r/tasks" "FR-017 no .specify/ up to the top: the start folder, never outer/.specify above the top"
  mv "$sr_r/.specify.off" "$sr_r/.specify"
  sr_lib_case "$sr_t/elsewhere/specs" "$sr_t/elsewhere/specs" "FR-001 outside any repository: the start folder is its own top"
}
sr_lib_tests
[ "$x_fail" = 0 ] && ok "spec_root_find: nearest root, nested wins, bounded by the top, links out skipped (FR-001, FR-017, FR-018, FR-019)"
sr_lib_mut() { # label sed-expr test-fn — a mutant of spec-root-lib.sh must turn the test red
  local m red; m="$(mktemp)"; sed "$2" "$REPO/hooks/spec-root-lib.sh" > "$m"
  if cmp -s "$REPO/hooks/spec-root-lib.sh" "$m"; then bad "mutant did not apply: $1"; rm -f "$m"; return; fi
  red="$(x_fail=0; SR_LIB="$m" "$3" >/dev/null 2>&1; echo "$x_fail")"; rm -f "$m"
  [ "$red" = 1 ] && ok "mutant killed: $1" || bad "mutant survived: $1"
}
# FR-017 has no mutant of its own: the link-out check (FR-019) refuses any .specify outside the top, so removing
# the walk's top bound changes no answer, only how far the walk goes. The FR-019 mutant below covers both.
sr_lib_mut "FR-019 the link-out check removed" 's/\[ "\${real#"\$top\/"}" = "\$real" \] ||/false ||/' sr_lib_tests

head_ "spec_roots: validated, read from the code repository, with the owner of a recorded spec_dir (FR-006, FR-007, FR-010)"
x_fail=0
sr_lib() { bash -c '. "$1"; shift; "$@"' _ "${SR_LIB:-$REPO/hooks/spec-root-lib.sh}" "$@"; }
sr_cfg() { printf '%s\n' "$1" > "$sr_r/.claude/project-status.json"; }
sr_cfg_tests() {
  sr_cfg '{"source":"tasks-repo","spec_roots":{"backend":"backend","frontend":"frontend","web":"apps/web","api":"backend/api"}}'
  [ "$(sr_lib spec_roots_json "$sr_r" 2>&1)" = '{"backend":"backend","frontend":"frontend","web":"apps/web","api":"backend/api"}' ] \
    || { bad "FR-006 a valid spec_roots is printed as compact JSON"; x_fail=1; }
  [ "$(sr_lib spec_root_folder "$sr_r" web 2>&1)" = apps/web ] || { bad "FR-006 spec_root_folder web → apps/web"; x_fail=1; }
  sr_lib spec_root_folder "$sr_r" payments >/dev/null 2>&1 && { bad "FR-007 an undeclared app must be refused"; x_fail=1; }
  grep -qF 'declared: api, backend, frontend, web' <<<"$(sr_lib spec_root_folder "$sr_r" payments 2>&1)" || { bad "FR-007 the refusal names the declared apps"; x_fail=1; }
  [ "$(sr_lib spec_root_owner "$sr_r" apps/web/.specify/specs/x)" = web ] || { bad "FR-010 a two-segment folder owns its spec_dir (apps/web)"; x_fail=1; }
  [ "$(sr_lib spec_root_owner "$sr_r" backend/api/.specify/specs/x)" = api ] || { bad "FR-018 the nested app owns its spec_dir (longest folder wins)"; x_fail=1; }
  [ "$(sr_lib spec_root_owner "$sr_r" backend/.specify/specs/x)" = backend ] || { bad "FR-010 backend owns backend/.specify/specs/x"; x_fail=1; }
  [ "$(sr_lib spec_root_owner "$sr_r" .specify/specs/x)" = . ] || { bad "FR-010 a top spec_dir belongs to ."; x_fail=1; }
  [ "$(sr_lib spec_root_owner "$sr_r" /abs/.claude/worktrees/X/.specify/specs/x)" = . ] || { bad "FR-010 an absolute 9.2.0 spec_dir belongs to ."; x_fail=1; }
  [ "$(sr_lib spec_root_label "$sr_r/apps/web")" = web ] || { bad "FR-004 the label of a declared folder is its app name"; x_fail=1; }
  [ "$(sr_lib spec_root_label "$sr_r/backend/linked")" = linked ] || { bad "FR-004 an undeclared folder's label is its basename"; x_fail=1; }
  local b
  for b in '{"spec_roots":{"x":"../up"}}' '{"spec_roots":{"x":".claude"}}' '{"spec_roots":{"x":".claude/worktrees"}}' \
           '{"spec_roots":{"Bad_Name":"backend"}}' '{"spec_roots":{"x":"/abs"}}' '{"spec_roots":{"x":"a/./b"}}' '{"spec_roots":{"x":"."}}' '{"spec_roots":["backend"]}'; do
    sr_cfg "$b"
    if sr_lib spec_roots_json "$sr_r" >/dev/null 2>&1; then bad "FR-006 spec_roots must refuse $b"; x_fail=1; fi
  done
  sr_cfg '{"spec_roots":{"x":"../up"}}'
  grep -qF "bad entry 'x=../up'" <<<"$(sr_lib spec_roots_json "$sr_r" 2>&1)" || { bad "FR-006 the refusal names the bad entry"; x_fail=1; }
  sr_cfg '{"source":"tasks-repo"}'
  [ "$(sr_lib spec_roots_json "$sr_r")" = '{}' ] || { bad "FR-006 no spec_roots key → {}"; x_fail=1; }
  # the main worktree's config when a linked worktree has none (.claude/ ignored, #160)
  sr_cfg '{"spec_roots":{"backend":"backend"}}'
  rm -rf "$sr_t/wt"; git -C "$sr_r" worktree add -q --detach "$sr_t/wt" >/dev/null 2>&1
  [ "$(sr_lib spec_roots_json "$sr_t/wt")" = '{"backend":"backend"}' ] || { bad "FR-006 a linked worktree with no config reads the main worktree's"; x_fail=1; }
  git -C "$sr_r" worktree remove --force "$sr_t/wt" >/dev/null 2>&1
}
sr_cfg_tests
[ "$x_fail" = 0 ] && ok "spec_roots: validated, names and folders, the longest-folder owner, the main worktree's fallback (FR-006, FR-007, FR-010)"
sr_lib_mut "FR-006 the '..' and '.claude' checks removed" '/split("\/") | any(. == "." or . == "..")/d; /startswith(".claude\/")))/s/or (.value | . == ".claude" or startswith(".claude\/")))/)/' sr_cfg_tests
sr_lib_mut "FR-010 the owner takes the first folder, not the longest" 's/sort_by(.value | length) | last/first/' sr_cfg_tests

head_ "spec_dir relative to the worktree, absolute passed through; the app: line shape (FR-008, FR-010)"
x_fail=0
sr_abs_tests() {
  [ "$(sr_lib spec_dir_abs '{"worktree":"/w","spec_dir":"backend/.specify/specs/x"}')" = /w/backend/.specify/specs/x ] || { bad "FR-010 relative spec_dir joined to the worktree"; x_fail=1; }
  [ "$(sr_lib spec_dir_abs '{"worktree":"/w","spec_dir":"/old/abs"}')" = /old/abs ] || { bad "FR-010 an absolute spec_dir is used as is"; x_fail=1; }
  [ -z "$(sr_lib spec_dir_abs '{"worktree":null,"spec_dir":"backend/x"}')" ] || { bad "FR-010 a relative spec_dir with no worktree and no top resolves to nothing, never /…"; x_fail=1; }
  [ "$(sr_lib spec_dir_abs '{"worktree":null,"spec_dir":"backend/x"}' /top)" = /top/backend/x ] || { bad "FR-010 a hand-recorded relative spec_dir with no worktree is the repository top's (as 9.2.0)"; x_fail=1; }
  [ "$(sr_lib item_app_shape HEF-1 $'body\n- app: backend\n')" = backend ] || { bad "FR-008 an app: line (list form) gives its name"; x_fail=1; }
  [ -z "$(sr_lib item_app_shape HEF-1 $'body only\n')" ] || { bad "FR-008 no app: line gives nothing"; x_fail=1; }
  sr_lib item_app_shape HEF-1 $'app: backend\napp: web\n' >/dev/null 2>&1 && { bad "FR-008 two app: lines are refused"; x_fail=1; }
  sr_lib item_app_shape HEF-1 $'app: ../../etc\n' >/dev/null 2>&1 && { bad "FR-008 a path in the app: line is refused"; x_fail=1; }
  sr_lib item_app_shape HEF-1 $'APP: Backend\n' >/dev/null 2>&1 && { bad "FR-008 an upper-case name is refused"; x_fail=1; }
  return 0
}
sr_abs_tests
[ "$x_fail" = 0 ] && ok "spec_dir_abs and the app: line: relative join, absolute passthrough, one strict name (FR-008, FR-010)"
sr_lib_mut "FR-010 the no-worktree guard removed" 's/elif \$top != "" then \$top + "\/" + .spec_dir else empty end/else "\/" + .spec_dir end/' sr_abs_tests
sr_lib_mut "FR-008 the name shape check removed" 's/\[\[ "\$a" =~ \^\[a-z0-9\]\[a-z0-9-\]{0,31}\$ \]\]/true/' sr_abs_tests

head_ "speckit-helper.sh works from the spec root: artifacts, markers, the inherited constitution (FR-002, FR-003, FR-004)"
x_fail=0
sr_cfg '{"source":"tasks-repo","spec_roots":{"backend":"backend","frontend":"frontend"}}'
printf '# Spec\nFR-001 frontend\n' > "$sr_r/frontend/.specify/specs/audit-log/spec.md"
sr_h() { (cd "$1" && shift && bash "${SR_HOOKS:-$REPO/hooks}/speckit-helper.sh" "$@"); }
sr_helper_tests() {
  grep -qF 'FR-001 backend' <<<"$(sr_h "$sr_r/backend/internal/store" spec 2>&1)" || { bad "FR-002 spec from backend/internal/store reads backend/.specify/specs/audit-log/spec.md"; x_fail=1; }
  sr_h "$sr_r/backend/internal" plan-phase-start >/dev/null 2>&1
  { [ -f "$sr_r/backend/.specify/.plan-in-progress" ] && [ ! -e "$sr_r/backend/internal/.specify" ]; } \
    || { bad "FR-002 plan-phase-start from backend/internal marks backend/.specify/, never a new backend/internal/.specify/"; x_fail=1; }
  sr_h "$sr_r/backend/internal" plan-phase-end >/dev/null 2>&1
  [ ! -e "$sr_r/backend/.specify/.plan-in-progress" ] || { bad "FR-002 plan-phase-end clears the same marker"; x_fail=1; }
  local c; c="$(sr_h "$sr_r/backend" constitution 2>&1)"
  [ "$c" = "$(printf '## Repository constitution (inherited)\n# Repo constitution\nroot rule\n\n## backend constitution\n# Backend constitution\nbackend rule')" ] \
    || { bad "FR-004 backend's constitution is the top one, marked inherited, then its own — got: $(head -c 300 <<<"$c")"; x_fail=1; }
  c="$(sr_h "$sr_r/frontend" constitution 2>&1)"
  [ "$c" = "$(printf '## Repository constitution (inherited)\n# Repo constitution\nroot rule')" ] \
    || { bad "FR-004 an app with no constitution prints the top one alone, marked inherited — got: $(head -c 300 <<<"$c")"; x_fail=1; }
  [ "$(sr_h "$sr_r" constitution 2>&1)" = "$(cat "$sr_r/.specify/memory/constitution.md")" ] || { bad "FR-004 at the top the constitution is printed as before"; x_fail=1; }
  c="$(sr_h "$sr_r" plan 2>&1)"
  grep -qF 'backend/.specify/specs/audit-log' <<<"$c" && grep -qF 'frontend/.specify/specs/audit-log' <<<"$c" \
    || { bad "FR-003 a missing artifact names the declared apps that hold the feature — got: $(head -c 400 <<<"$c")"; x_fail=1; }
  [ "$(sr_h "$sr_r/frontend/src" check-specify-dir 2>&1)" = NOT_FOUND ] || { bad "FR-002 check-specify-dir stays literal to the cwd (/hefesto:hef.init in an app folder)"; x_fail=1; }
  rm -rf "$sr_r/backend/internal/.specify" "$sr_r/backend/.specify/.plan-in-progress"   # a mutant's stray marker must not reach the next test
  return 0
}
sr_helper_tests
# FR-002: req-coverage --all re-enters the helper; invoked by a relative path from a subfolder it must still find itself
ln -s "$REPO/hooks" "$sr_r/backend/tools"
grep -qF 'shipped spec(s) checked' <<<"$(cd "$sr_r/backend/internal" && bash ../tools/speckit-helper.sh req-coverage --all 2>&1)" \
  || { bad "FR-002 req-coverage --all from a subfolder, helper called by a relative path, re-enters itself"; x_fail=1; }
[ "$x_fail" = 0 ] && ok "the helper runs from the spec root: artifacts, markers, the inherited constitution, the hint, check-specify-dir literal (FR-002, FR-003, FR-004)"
sr_helper_mut() { # label sed-expr — a mutant of speckit-helper.sh must turn sr_helper_tests red
  local md red; md="$(sr_mirror)"; sr_mutant "$md" speckit-helper.sh "$2" || { rm -rf "$md"; return; }
  red="$(x_fail=0; SR_HOOKS="$md" sr_helper_tests >/dev/null 2>&1; echo "$x_fail")"; rm -rf "$md"
  [ "$red" = 1 ] && ok "mutant killed: $1" || bad "mutant survived: $1"
}
sr_helper_mut "FR-002 the cd into the spec root removed" 's/SPEC_ROOT="\$(spec_root_find "\$PWD")" \&\& cd "\$SPEC_ROOT"/SPEC_ROOT="$PWD"/'
sr_helper_mut "FR-004 the inherited constitution removed" 's/echo "## Repository constitution (inherited)"/false/'

head_ "The guards follow the spec root: the marker of the cwd's root or the edited file's arms them (FR-005)"
x_fail=0
mkdir -p "$sr_r/backend/tests" "$sr_r/frontend/tests" "$sr_r/backend/src"
printf 'assert_eq 1 1\n' > "$sr_r/backend/tests/store_test.sh"
printf '# FR-001\nassert_eq 2 2\n' > "$sr_r/frontend/tests/a_test.sh"
sr_hook() { # hook cwd tool file → the hook's exit code (stderr to the file $sr_t/herr: a $(…) caller loses variables)
  local rc=0
  jq -nc --arg c "$2" --arg t "$3" --arg f "$4" '{cwd: $c, tool_name: $t, tool_input: {file_path: $f, content: "x"}}' \
    | bash "${SR_HOOKS:-$REPO/hooks}/$1" >/dev/null 2>"$sr_t/herr" || rc=$?
  echo "$rc"
}
sr_guard_case() { # hook expected-rc cwd tool file label
  local got; got="$(sr_hook "$1" "$3" "$4" "$5")"
  [ "$got" = "$2" ] || { bad "$6: $1 cwd=${3#"$sr_r"/} file=${5#"$sr_r"/} → exit $got, expected $2 ($(head -c 160 "$sr_t/herr"))"; x_fail=1; }
}
sr_guard_tests() {
  local ig=implement-phase-test-guard.sh pb=plan-phase-write-block.sh
  : > "$sr_r/backend/.specify/.implement-in-progress"
  sr_guard_case $ig 2 "$sr_r" Write "$sr_r/backend/tests/store_test.sh" "FR-005 the file's root arms the test guard from a top cwd"
  sr_guard_case $ig 2 "$sr_r/backend" Write "$sr_r/backend/tests/store_test.sh" "FR-005 the cwd's root arms the test guard"
  sr_guard_case $ig 2 "$sr_r/frontend" Write "$sr_r/backend/tests/store_test.sh" "FR-005 the file's root arms it from another app's cwd"
  sr_guard_case $ig 2 "$sr_r" Write "backend/tests/store_test.sh" "FR-005 a relative file_path is the session's (joined to cwd)"
  sr_guard_case $ig 2 "$sr_r/backend" Write "$sr_r/frontend/tests/a_test.sh" "FR-005 the cwd's root arms it for a file in another app"
  rm -f "$sr_r/backend/.specify/.implement-in-progress"
  sr_guard_case $ig 0 "$sr_r/backend" Write "$sr_r/backend/tests/store_test.sh" "FR-005 no marker in either root: nothing blocked"
  : > "$sr_r/backend/.specify/.plan-in-progress"
  sr_guard_case $pb 2 "$sr_r/backend" Write "$sr_r/frontend/src/app.tsx" "FR-005 the plan marker of the cwd's root blocks another app's source"
  sr_guard_case $pb 0 "$sr_r/backend" Write "$sr_r/backend/.specify/specs/x/plan.md" "FR-005 a plan artifact is allowed"
  sr_guard_case $pb 2 "$sr_r" Write "$sr_r/backend/src/x.go" "FR-005 the file's root blocks from a top cwd"
  sr_guard_case $pb 2 "$sr_r" Write "backend/src/x.go" "FR-005 a relative path is joined to the cwd (plan block)"
  sr_guard_case $pb 0 "$sr_r" Write "$sr_r/frontend/src/app.tsx" "FR-005 from the top, frontend/ holds no marker: not blocked (US3 edge)"
  rm -f "$sr_r/backend/.specify/.plan-in-progress"
  # spec-cite-probe: a test edited from a top cwd is checked against ITS app's specs (no marker anywhere)
  rm -f "${TMPDIR:-/tmp}"/.hefesto-spec-cite-* 2>/dev/null   # the probe speaks once a minute per file
  sr_guard_case spec-cite-probe.sh 0 "$sr_r" Edit "$sr_r/frontend/tests/a_test.sh" "FR-005 spec-cite-probe runs"
  grep -qF "declared by spec 'audit-log'" "$sr_t/herr" || { bad "FR-005 spec-cite-probe checks a frontend test against frontend's specs from a top cwd — got: $(head -c 200 "$sr_t/herr")"; x_fail=1; }
  rm -f "${TMPDIR:-/tmp}"/.hefesto-spec-cite-* 2>/dev/null
  return 0
}
sr_guard_tests
# precompact-progress: the spec artifacts of the cwd's spec root
printf -- '- [ ] T001 open backend task\n' > "$sr_r/backend/.specify/specs/audit-log/tasks.md"
jq -nc --arg c "$sr_r/backend/internal" '{cwd: $c, trigger: "manual"}' | XDG_CACHE_HOME="$sr_t/xdg" bash "$REPO/hooks/precompact-progress.sh" >/dev/null 2>&1
grep -qF 'T001 open backend task' "$sr_t"/xdg/hefesto/progress/*.md 2>/dev/null || { bad "FR-005 precompact-progress lists the open tasks of the cwd's spec root"; x_fail=1; }
[ "$x_fail" = 0 ] && ok "guards: armed by either root, relative paths joined, the probe and the progress file read the app's specs (FR-005)"
sr_guard_mut() { # label file sed-expr
  local md red; md="$(sr_mirror)"; sr_mutant "$md" "$2" "$3" || { rm -rf "$md"; return; }
  red="$(x_fail=0; SR_HOOKS="$md" sr_guard_tests >/dev/null 2>&1; echo "$x_fail")"; rm -rf "$md"
  [ "$red" = 1 ] && ok "mutant killed: $1" || bad "mutant survived: $1"
}
sr_guard_mut "FR-005 the file side of spec_armed removed" spec-root-lib.sh 's/for r in "\$(spec_root_find "\$1")" \${f:+"\$(spec_root_find "\$f")"}; do/for r in "$(spec_root_find "$1")"; do/'
sr_guard_mut "FR-005 the cwd side of spec_armed removed" spec-root-lib.sh 's/for r in "\$(spec_root_find "\$1")" \${f:+/for r in ${f:+/'
sr_guard_mut "FR-005 the relative-path join removed" spec-root-lib.sh 's/|| f="\$1\/\$f"$/|| :/'
sr_guard_mut "FR-005 spec-cite-probe scans only the cwd's root" spec-cite-probe.sh 's/done < <(spec_roots_of "\$CWD" "\$FILE")/done < <(spec_root_find "$CWD")/'

head_ "The ledger: an item's owning app, a worktree-relative spec_dir, the form's inputs (FR-007, FR-008, FR-010)"
x_fail=0
sr_cfg '{"source":"tasks-repo","root":"tasks","spec_roots":{"backend":"backend","frontend":"frontend"}}'
printf '# TODO\n\n## HEF-1 — owned\nbody\napp: backend\n\n## HEF-2 — no app\nbody\n\n## HEF-3 — bad app\napp: payments\n\n## HEF-4 — old\nbody\n' > "$sr_r/tasks/TODO.md"
for c in DOING DONE BACKLOG; do printf '# %s\n' "$c" > "$sr_r/tasks/$c.md"; done
sr_lg() { (cd "$sr_r" && bash "${SR_HOOKS:-$REPO/hooks}/ledger.sh" "$@"); }
sr_ent() { jq -r "$2" "$(sld "$sr_r")/$1.json" 2>/dev/null; }
sr_lgf() { (cd "$sr_r/frontend/src" && bash "${SR_HOOKS:-$REPO/hooks}/ledger.sh" "$@"); }   # from a subfolder: a raw relative spec_dir would not resolve here
sr_ledger_tests() {
  rm -rf "$(sld "$sr_r")"
  sr_lg register HEF-1 --ref tasks/TODO.md#HEF-1 >/dev/null 2>&1
  [ "$(sr_ent HEF-1 .spec_root)" = backend ] || { bad "FR-008 register records the app: line's declared name (got '$(sr_ent HEF-1 .spec_root)')"; x_fail=1; }
  sr_lg register HEF-3 --ref tasks/TODO.md#HEF-3 >/dev/null 2>&1 && { bad "FR-008 register refuses an undeclared app: name"; x_fail=1; }
  [ ! -e "$(sld "$sr_r")/HEF-3.json" ] || { bad "FR-008 a refused app: name leaves no entry (never a form)"; x_fail=1; }
  sr_lg register HEF-2 --ref tasks/TODO.md#HEF-2 >/dev/null 2>&1
  [ "$(sr_ent HEF-2 .spec_root)" = null ] || { bad "FR-008 an item with no app: line is undecided (spec_root null)"; x_fail=1; }
  [ "$(sr_lg list --undecided-app 2>&1 | jq -r '[.[].id] | join(",")' 2>&1)" = HEF-2 ] || { bad "FR-008 list --undecided-app lists exactly HEF-2 — got: $(sr_lg list --undecided-app 2>&1 | head -c 200)"; x_fail=1; }
  [ "$(sr_lg spec-roots HEF-2 2>&1 | jq -c . 2>&1)" = '{"declared":["backend","frontend"],"spec_root":null}' ] || { bad "FR-008 spec-roots HEF-2 prints the declared apps and the entry's value — got: $(sr_lg spec-roots HEF-2 2>&1 | head -c 200)"; x_fail=1; }
  sr_lg record HEF-2 --spec-root payments >/dev/null 2>&1 && { bad "FR-007 record --spec-root refuses an undeclared app"; x_fail=1; }
  sr_lg record HEF-2 --spec-root . >/dev/null 2>&1 && [ "$(sr_ent HEF-2 .spec_root)" = . ] || { bad "FR-007 record --spec-root . sets the repository top"; x_fail=1; }
  [ "$(sr_lg list --undecided-app 2>&1 | jq -r 'length')" = 0 ] || { bad "FR-008 a decided entry leaves list --undecided-app"; x_fail=1; }
  sr_lg record HEF-2 --spec-root backend >/dev/null 2>&1 && [ "$(sr_ent HEF-2 .spec_root)" = backend ] || { bad "FR-007 the owner can change while no spec_dir is recorded"; x_fail=1; }
  sr_lg record HEF-2 --worktree "$sr_r" --spec-dir ../escape/.specify >/dev/null 2>&1 && { bad "FR-010 a spec_dir with '..' is refused"; x_fail=1; }
  sr_lg record HEF-2 --worktree "$sr_r" --spec-dir backend/.specify/specs/audit-log >/dev/null 2>&1 \
    && [ "$(sr_ent HEF-2 .spec_dir)" = backend/.specify/specs/audit-log ] || { bad "FR-010 a relative spec_dir is stored relative to the worktree"; x_fail=1; }
  sr_lg record HEF-2 --spec-root frontend >/dev/null 2>&1 && { bad "FR-007 the owner cannot move once spec_dir is recorded (it would orphan the spec)"; x_fail=1; }
  sr_lgf block HEF-2 --kind human:plan-approval >/dev/null 2>&1 || { bad "FR-010 block human:plan-approval resolves a relative spec_dir against the worktree (tasks.md found)"; x_fail=1; }
  # FR-010: an entry from 9.2.0 with an absolute spec_dir, and the migration (spec_dir set, spec_root null) is not undecided
  sr_lg register HEF-4 --ref tasks/TODO.md#HEF-4 >/dev/null 2>&1
  sr_lg record HEF-4 --spec-dir "$sr_r/backend/.specify/specs/audit-log" >/dev/null 2>&1
  sr_lgf block HEF-4 --kind human:plan-approval >/dev/null 2>&1 || { bad "FR-010 an absolute 9.2.0 spec_dir still resolves"; x_fail=1; }
  [ "$(sr_lg list --undecided-app 2>&1 | jq -r 'length')" = 0 ] || { bad "FR-007 an entry with spec_dir recorded is never undecided (the migration rule)"; x_fail=1; }
  return 0
}
sr_ledger_tests
[ "$x_fail" = 0 ] && ok "ledger: app recorded at registration, undeclared refused with no entry, --spec-root, relative spec_dir, the readers (FR-007, FR-008, FR-010)"
sr_ledger_mut() { # label file sed-expr
  local md red; md="$(sr_mirror)"; sr_mutant "$md" "$2" "$3" || { rm -rf "$md"; return; }
  red="$(x_fail=0; SR_HOOKS="$md" sr_ledger_tests >/dev/null 2>&1; echo "$x_fail")"; rm -rf "$md"
  [ "$red" = 1 ] && ok "mutant killed: $1" || bad "mutant survived: $1"
}
sr_ledger_mut "FR-007 record --spec-root accepts an undeclared name" ledger-lanes.sh 's/spec_root_folder "\$rt" "\$1" >\/dev\/null || exit 1/:/'
sr_ledger_mut "FR-010 record --spec-dir accepts '..'" ledger-lanes.sh 's/\*\/..\/\*|..\/\*|\*\/..|..) die/__never__) die/'
sr_ledger_mut "FR-010 the readers use the raw spec_dir" ledger.sh 's/SDA=\$(entry_spec_dir "\$E")/SDA=$(jq -r ".spec_dir \/\/ empty" <<<"$E")/'
sr_ledger_mut "FR-008 register records an undeclared name (checked after init)" ledger-lanes.sh 's/^    \[ -z "\$app" \] || spec_root_folder "\$rtop" "\$app" >\/dev\/null || exit 1$/    :/'
rm -rf "$(sld "$sr_r")"

head_ "An external board: the app is checked against the code repository's spec_roots, never the board's (FR-006, FR-008)"
x_fail=0
sr_k="$sr_t/kanban"; sr_o="$sr_t/ops"
( for d in "$sr_k" "$sr_o"; do git init -q -b main "$d" && mkdir -p "$d/.claude" && sr_git -C "$d" commit -q --allow-empty -m init; done \
  && mkdir -p "$sr_k/tasks" "$sr_o/api/.specify/specs" "$sr_t/plain" \
  && printf '# TODO\n\n## OPS-1 — owned\nrepo: ops\napp: api\n\n## OPS-2 — the board'"'"'s name\nrepo: ops\napp: wrong\n\n## PLN-1 — a plain folder\nrepo: plain\napp: wrong\n' > "$sr_k/tasks/TODO.md" \
  && for c in DOING DONE BACKLOG; do printf '# %s\n' "$c" > "$sr_k/tasks/$c.md"; done \
  && printf '{"source":"tasks-repo","root":"tasks","repos":{"ops":"../ops","plain":"../plain"},"spec_roots":{"wrong":"x"}}\n' > "$sr_k/.claude/project-status.json" \
  && printf '{"board":"../kanban","spec_roots":{"api":"api"}}\n' > "$sr_o/.claude/project-status.json" ) >/dev/null 2>&1
sr_ext_tests() {
  rm -rf "$(sld "$sr_k")"
  (cd "$sr_k" && bash "${SR_HOOKS:-$REPO/hooks}/ledger.sh" register OPS-1 --ref tasks/TODO.md#OPS-1) >/dev/null 2>&1
  [ "$(jq -r .spec_root "$(sld "$sr_k")/OPS-1.json" 2>/dev/null)" = api ] || { bad "FR-006 an external board records the app declared by the code repository (ops)"; x_fail=1; }
  if (cd "$sr_k" && bash "${SR_HOOKS:-$REPO/hooks}/ledger.sh" register OPS-2 --ref tasks/TODO.md#OPS-2) >/dev/null 2>&1; then
    bad "FR-006 an app declared only by the BOARD's config is refused on an external board"; x_fail=1; fi
  # code review round 2: a repos path that is no git repository is refused, never read as the board's own config
  if (cd "$sr_k" && bash "${SR_HOOKS:-$REPO/hooks}/ledger.sh" register PLN-1 --ref tasks/TODO.md#PLN-1) >/dev/null 2>&1 \
     || [ -e "$(sld "$sr_k")/PLN-1.json" ]; then
    bad "FR-006 a repos path that is not a git repository refuses registration (it read the board's spec_roots)"; x_fail=1; fi
  return 0
}
sr_ext_tests
[ "$x_fail" = 0 ] && ok "external board: spec_roots read from the code repository, the board's ignored (FR-006, FR-008)"
sr_ext_mut() { local md red; md="$(sr_mirror)"; sr_mutant "$md" ledger-lanes.sh "$1" || { rm -rf "$md"; return; }
  red="$(x_fail=0; SR_HOOKS="$md" sr_ext_tests >/dev/null 2>&1; echo "$x_fail")"; rm -rf "$md"
  [ "$red" = 1 ] && ok "mutant killed: FR-006 the board's spec_roots read on an external board" || bad "mutant survived: FR-006 the board's spec_roots read on an external board"; }
sr_ext_mut 's/^  if \[ -n "\$r" \]; then$/  if false; then/'
rm -rf "$(sld "$sr_k")"

head_ "No spec_roots: an app: line is just text, as in 9.2.0; a worker cannot move an item's app (US5, FR-007)"
x_fail=0
sr_cfg '{"source":"tasks-repo","root":"tasks"}'
printf '\n## HEF-9 — a bug template\nApp: Mobile\n\n## HEF-10 — a stray line\napp: backend\n' >> "$sr_r/tasks/TODO.md"
sr_noroots_tests() {
  rm -rf "$(sld "$sr_r")"
  sr_lg register HEF-9 --ref tasks/TODO.md#HEF-9 >/dev/null 2>&1 && [ "$(sr_ent HEF-9 .spec_root)" = null ] \
    || { bad "US5 with no spec_roots, an 'App: Mobile' line does not stop registration (review B2)"; x_fail=1; }
  sr_lg register HEF-10 --ref tasks/TODO.md#HEF-10 >/dev/null 2>&1 && [ "$(sr_ent HEF-10 .spec_root)" = null ] \
    || { bad "US5 with no spec_roots, a well-formed app: line is ignored at registration (review B2)"; x_fail=1; }
  return 0
}
sr_noroots_tests
sr_cfg '{"source":"tasks-repo","root":"tasks","spec_roots":{"backend":"backend","frontend":"frontend"}}'
if (cd "$sr_r" && HEFESTO_WORKER=1 bash "$REPO/hooks/ledger.sh" record HEF-9 --spec-root backend) >/dev/null 2>&1; then
  bad "FR-007 a launched worker may not set an item's app (it steers the next stage's folder; review S4)"; x_fail=1; fi
[ "$x_fail" = 0 ] && ok "no spec_roots: app: lines are not read at registration; a worker cannot record --spec-root (US5, FR-007)"
sr_nr_md="$(sr_mirror)"
if sr_mutant "$sr_nr_md" ledger-lanes.sh 's/^  if \[ "\$(jq length <<<"\$sj")" -gt 0 \]; then$/  if true; then/'; then
  [ "$(x_fail=0; SR_HOOKS="$sr_nr_md" sr_noroots_tests >/dev/null 2>&1; echo "$x_fail")" = 1 ] && ok "mutant killed: US5 the app: line read with no spec_roots" || bad "mutant survived: US5 the app: line read with no spec_roots"
fi
rm -rf "$sr_nr_md" "$(sld "$sr_r")"

head_ "status-board.sh --item-app and --add --app (FR-008)"
x_fail=0
sr_cfg '{"source":"tasks-repo","root":"tasks","spec_roots":{"backend":"backend","frontend":"frontend"}}'
[ "$(cd "$sr_r" && bash "$REPO/hooks/status-board.sh" --item-app HEF-1 2>&1)" = backend ] || { bad "FR-008 --item-app prints the app: line's name"; x_fail=1; }
[ -z "$(cd "$sr_r" && bash "$REPO/hooks/status-board.sh" --item-app HEF-2 2>&1)" ] || { bad "FR-008 --item-app prints nothing for an item with no line"; x_fail=1; }
sr_new="$(cd "$sr_r" && bash "$REPO/hooks/status-board.sh" --add "audit export" --rfc --app frontend 2>&1)"
grep -A3 -F "## $sr_new — audit export" "$sr_r/tasks/TODO.md" | grep -qx 'app: frontend' || { bad "FR-008 --add --app writes the app: line (got $sr_new)"; x_fail=1; }
[ "$(cd "$sr_r" && bash "$REPO/hooks/status-board.sh" --item-app "$sr_new" 2>&1)" = frontend ] || { bad "FR-008 the added item reads back its app"; x_fail=1; }
if (cd "$sr_r" && bash "$REPO/hooks/status-board.sh" --add "x" --app '../etc' >/dev/null 2>&1); then bad "FR-008 --add --app refuses a path"; x_fail=1; fi
[ "$x_fail" = 0 ] && ok "status-board: --item-app reads the line, --add --app writes it, a bad name is refused (FR-008)"

head_ "The launcher starts an app's item in the app folder, with the app's edit rule (FR-009, FR-014)"
x_fail=0
sr_l="$(cd "$(mktemp -d)" && pwd -P)/mono"; sr_lout="$(cd "$(mktemp -d)" && pwd -P)"; sr_lcfg="$(mktemp -d)"
mkdir -p "$sr_lout/.specify"
( git init -q -b main "$sr_l" && cd "$sr_l" && mkdir -p tasks .claude backend/.specify/memory frontend/.specify/memory nospec \
  && printf 'b\n' > backend/.specify/memory/constitution.md && printf 'f\n' > frontend/.specify/memory/constitution.md && printf 'n\n' > nospec/README \
  && ln -s "$sr_lout" linkout && mkdir -p linkspec && ln -s "$sr_lout/.specify" linkspec/.specify \
  && printf '# TODO\n\n## HEF-1 — owned\nbody\napp: backend\n\n## HEF-2 — none\nbody\n\n## HEF-3 — undeclared\napp: payments\n\n## HEF-5 — no spec\napp: nospec\n\n## HEF-6 — link out\napp: linkout\n\n## HEF-7 — spec link\napp: linkspec\n\n## HEF-8 — intake\napp: backend\n' > tasks/TODO.md \
  && for c in DOING DONE BACKLOG; do printf '# %s\n' "$c" > "tasks/$c.md"; done \
  && printf '{"source":"tasks-repo","root":"tasks","spec_roots":{"backend":"backend","frontend":"frontend","nospec":"nospec","linkout":"linkout","linkspec":"linkspec"}}\n' > .claude/project-status.json \
  && sr_git add -A && sr_git commit -q -m init \
  && for i in 1 2 3 5 6 7 8; do bash "$REPO/hooks/ledger.sh" init "HEF-$i" --kind tasks-repo --ref "tasks/TODO.md#HEF-$i" >/dev/null; done ) >/dev/null 2>&1
sr_sl() { (cd "$sr_l" && CLAUDE_CONFIG_DIR="$sr_lcfg" bash "${SR_HOOKS:-$REPO/hooks}/session-launch.sh" "$@" 2>&1); }
# a fake claude that records where it was started: a real (non-dry) run must never reach it from a wrong folder
sr_fb="$(mktemp -d)"; printf '#!/bin/sh\npwd -P > "%s/claude.cwd"\nexit 1\n' "$sr_fb" > "$sr_fb/claude"; chmod +x "$sr_fb/claude"
sr_run() { (cd "$sr_l" && PATH="$sr_fb:$PATH" CLAUDE_CONFIG_DIR="$sr_lcfg" bash "${SR_HOOKS:-$REPO/hooks}/session-launch.sh" "$@" 2>&1); }
sr_launch_tests() {
  local o wt="$sr_l/.claude/worktrees/HEF-1"
  o="$(sr_sl plan HEF-1 --dry-run)"
  [ "$(head -1 <<<"$o")" = "# cwd: $wt/backend" ] || { bad "FR-009 a plan dry run of an app item names the app folder as its cwd — got: $(head -c 200 <<<"$o")"; x_fail=1; }
  grep -qF "Edit(/$sr_l/.claude/worktrees/HEF-1/backend/.specify/**)" <<<"$o" || { bad "FR-009 the planner's absolute edit rule names the app's .specify/"; x_fail=1; }
  grep -qF 'Edit(/.specify/**)' <<<"$o" && { bad "FR-009 the planner of an app item has no rule for the top's .specify/"; x_fail=1; }
  grep -qF ' -w HEF-1' <<<"$o" && { bad "FR-009 an app item's worktree is made by the launcher, not claude -w"; x_fail=1; }
  grep -qF 'from the app folder backend/' <<<"$o" || { bad "FR-009 the plan prompt names the app folder"; x_fail=1; }
  grep -qF 'never cd into a subfolder' <<<"$o" && { bad "FR-009 the plan prompt no longer pins the worktree root"; x_fail=1; }
  o="$(sr_sl implement HEF-1 --dry-run)"
  [ "$(head -1 <<<"$o")" = "# cwd: $wt/backend" ] || { bad "FR-009 an implement dry run of an app item starts in the app folder"; x_fail=1; }
  grep -qF 'owned by the app in backend/' <<<"$o" || { bad "FR-009 the implement prompt names the owning app"; x_fail=1; }
  o="$(sr_sl plan HEF-2 --dry-run)"; grep -qF 'decide the owning app in the orchestrator' <<<"$o" || { bad "FR-008 an item with no app is refused while spec_roots is declared — got: $(head -c 200 <<<"$o")"; x_fail=1; }
  o="$(sr_sl plan HEF-3 --dry-run)"; grep -qF "app 'payments' is not declared" <<<"$o" || { bad "FR-009 an undeclared app is refused at launch — got: $(head -c 200 <<<"$o")"; x_fail=1; }
  o="$(sr_sl plan HEF-5 --dry-run)"; grep -qF 'has no .specify/' <<<"$o" || { bad "FR-009 an app folder with no .specify/ is refused, naming /hefesto:hef.init — got: $(head -c 200 <<<"$o")"; x_fail=1; }
  o="$(sr_sl plan HEF-6 --dry-run)"; grep -qF 'resolves outside' <<<"$o" || { bad "FR-009 an app folder that links out of the repository is refused — got: $(head -c 200 <<<"$o")"; x_fail=1; }
  # the migration rule: spec_dir recorded, spec_root null → the owner from spec_dir; no form, no refusal
  (cd "$sr_l" && bash "$REPO/hooks/ledger.sh" record HEF-2 --worktree "$sr_l/.claude/worktrees/HEF-2" --spec-dir frontend/.specify/specs/x) >/dev/null 2>&1
  o="$(sr_sl implement HEF-2 --dry-run)"
  [ "$(head -1 <<<"$o")" = "# cwd: $sr_l/.claude/worktrees/HEF-2/frontend" ] || { bad "FR-007 an entry planned before spec_roots launches in the app its spec_dir names — got: $(head -c 200 <<<"$o")"; x_fail=1; }
  # lane mode: a symlink in place of the worktree is refused on the app path too (today's pointer check)
  mkdir -p "$sr_l/.claude/worktrees"; rm -rf "$sr_l/.claude/worktrees/HEF-1"; ln -s "$sr_lout" "$sr_l/.claude/worktrees/HEF-1"
  o="$(cd "$sr_l" && HEFESTO_TRUSTED_TOP="$sr_l" CLAUDE_CONFIG_DIR="$sr_lcfg" bash "${SR_HOOKS:-$REPO/hooks}/session-launch.sh" plan HEF-1 --dry-run 2>&1)"
  grep -qF 'is not a worktree of this repository' <<<"$o" || { bad "FR-009 lane mode refuses a symlinked worktree for an app item — got: $(head -c 200 <<<"$o")"; x_fail=1; }
  rm -f "$sr_l/.claude/worktrees/HEF-1"
  # review B1: a dangling link where the worktree goes, outside lane mode — refused, the worker never starts elsewhere
  ln -s "$sr_lout/nowhere" "$sr_l/.claude/worktrees/HEF-1"; rm -f "$sr_fb/claude.cwd"
  o="$(sr_run plan HEF-1)"
  { [ ! -f "$sr_fb/claude.cwd" ] && grep -qF 'is a dangling link' <<<"$o"; } \
    || { bad "FR-009 a dangling link in place of the worktree is refused before claude starts (it started in $(cat "$sr_fb/claude.cwd" 2>/dev/null)) — got: $(head -c 200 <<<"$o")"; x_fail=1; }
  rm -f "$sr_l/.claude/worktrees/HEF-1"
  # review S5: an app folder whose .specify links out of the worktree is refused (FR-019 for the launcher)
  o="$(sr_sl plan HEF-7 --dry-run)"; grep -qF 'resolves outside' <<<"$o" || { bad "FR-019 an app whose .specify links out of the repository is refused — got: $(head -c 200 <<<"$o")"; x_fail=1; }
  # review S2: a launch refused at the person's gate records nothing — not even the app
  (cd "$sr_l" && bash "$REPO/hooks/ledger.sh" block HEF-8 --kind human:intake) >/dev/null 2>&1
  o="$(sr_run plan HEF-8)"
  [ "$(jq -r .spec_root "$(sld "$sr_l")/HEF-8.json" 2>/dev/null)" = null ] || { bad "FR-008 a launch refused at a human gate records no spec_root — got $(jq -r .spec_root "$(sld "$sr_l")/HEF-8.json" 2>/dev/null): $(head -c 160 <<<"$o")"; x_fail=1; }
  return 0
}
sr_launch_tests
[ "$x_fail" = 0 ] && ok "launcher: app folder as cwd, the app's edit rule, refusals (undecided, undeclared, no .specify/, link out, symlinked worktree), the migration (FR-007–FR-009)"
sr_launch_mut() { # label file sed-expr
  local md red; md="$(sr_mirror)"; sr_mutant "$md" "$2" "$3" || { rm -rf "$md"; return; }
  red="$(x_fail=0; SR_HOOKS="$md" sr_launch_tests >/dev/null 2>&1; echo "$x_fail")"; rm -rf "$md"
  [ "$red" = 1 ] && ok "mutant killed: $1" || bad "mutant survived: $1"
}
sr_launch_mut "FR-008 app_dir lets an undecided item through" launch-item.sh 's/\[ -n "\$name" \] || die "session-launch \$ROLE \$ID: the repository declares apps/[ -n "$name" ] || return 0; die "x/'
sr_launch_mut "FR-009 app_dir accepts an undeclared name" launch-item.sh 's/^  spec_root_folder "\$TOP" "\$name" >\/dev\/null || exit 1$/  :/'
sr_launch_mut "FR-009 an app folder with no .specify/ accepted" launch-item.sh 's/\[ -d "\$base\/\$APPDIR\/.specify" \] ||/true ||/'
sr_launch_mut "FR-009 an app folder that resolves outside the worktree accepted" launch-item.sh 's/"\$(cd "\$base" \&\& pwd -P)"\/?\*) ;;/*) ;;/'
sr_launch_mut "FR-009 the worktree pointer check dropped on the app path" launch-item.sh 's/\[ "\$LANE_MODE" = 0 \] || { \[ ! -L "\$w" \] \&\& wt_branch "\$w" >\/dev\/null; } || die/true || die/'
sr_launch_mut "FR-009 the cd skipped for any missing worktree, not only on a dry run (review B1)" launch-item.sh 's/\[ "\$DRY" = 1 \] \&\& \[ ! -e "\$w" \] \&\& return 0/[ ! -e "$w" ] \&\& return 0/'
sr_launch_mut "FR-019 the .specify link-out check dropped in app_check (review S5)" launch-item.sh 's/"\$(cd "\$base\/\$APPDIR\/.specify" \&\& pwd -P)\/"/"$base\/x\/"/'
sr_launch_mut "FR-007 the migration refused (owner from spec_dir dropped)" launch-item.sh 's/^  if \[ -z "\$sr" \] \&\& \[ -n "\$sd" \]; then/  if false; then/'
# FR-011: the byte-identity check above must catch a change to the no-app planner rules (a mutant of the default)
sr_fx_md="$(sr_mirror)"
if sr_mutant "$sr_fx_md" session-launch.sh 's/"Edit(\/.specify\/\*\*)",//'; then
  [ "$(sr_launch_lines "$sr_fx_md")" = "$(cat "$REPO/tests/fixtures/launch-920.txt")" ] && bad "mutant survived: FR-011 the no-app planner rule changed, the fixture check still passes" || ok "mutant killed: FR-011 the no-app planner rule changed"
fi
rm -rf "$sr_fx_md"

head_ "An interactive lane's --prepare names the app folder (FR-014)"
x_fail=0
jq '. + {orchestrate: {lane_mode: "interactive"}}' "$sr_l/.claude/project-status.json" > "$sr_l/.claude/ps.json" && mv "$sr_l/.claude/ps.json" "$sr_l/.claude/project-status.json"
rm -rf "$sr_l/.claude/worktrees/HEF-1"
sr_po="$(cd "$sr_l" && env -u CLAUDE_CODE_SESSION_ID -u HEFESTO_TRUSTED_TOP -u HEFESTO_LANE_MAP bash "$REPO/hooks/session-launch.sh" plan HEF-1 --prepare --lane mono-planner 2>&1)"
grep -qx "app: $sr_l/.claude/worktrees/HEF-1/backend" <<<"$sr_po" && [ -d "$sr_l/.claude/worktrees/HEF-1/backend/.specify" ] \
  || { bad "FR-014 --prepare makes the worktree and prints app: <worktree>/backend — got: $(head -c 300 <<<"$sr_po")"; x_fail=1; }
grep -q '^worktree: ' <<<"$sr_po" && grep -q '^prompt: ' <<<"$sr_po" && grep -q '^finish: ' <<<"$sr_po" || { bad "FR-014 --prepare still prints its three lines"; x_fail=1; }
[ "$x_fail" = 0 ] && ok "--prepare: the worktree made, app: <worktree>/<folder> printed beside the three lines (FR-014)"
# FR-010: --finish records the lane's relative spec_dir under the app folder, relative to the worktree
mkdir -p "$sr_l/.claude/worktrees/HEF-1/backend/.specify/specs/owned" && printf -- '- [ ] T001\n' > "$sr_l/.claude/worktrees/HEF-1/backend/.specify/specs/owned/tasks.md"
printf '{"summary":"planned","outcome":"tasks","spec_dir":".specify/specs/owned","blocked_on":null}\n' > "$sr_t/out.json"
sr_fo="$(cd "$sr_l" && env -u CLAUDE_CODE_SESSION_ID -u HEFESTO_TRUSTED_TOP -u HEFESTO_LANE_MAP bash "$REPO/hooks/session-launch.sh" plan HEF-1 --finish --lane mono-planner --outcome-file "$sr_t/out.json" 2>&1)"
[ "$(jq -r .spec_dir "$(sld "$sr_l")/HEF-1.json" 2>/dev/null)" = backend/.specify/specs/owned ] \
  || { bad "FR-010 --finish stores the lane's spec_dir relative to the worktree, under the app folder — got '$(jq -r .spec_dir "$(sld "$sr_l")/HEF-1.json" 2>/dev/null)': $(head -c 300 <<<"$sr_fo")"; x_fail=1; }
# review S6: the verifier of an app item starts in the app folder
[ "$(sr_sl verify HEF-1 --dry-run | head -1)" = "# cwd: $sr_l/.claude/worktrees/HEF-1/backend" ] || { bad "FR-009 a verify dry run of an app item starts in the app folder"; x_fail=1; }
# review S1: a spec_dir reported from the worktree root (backend/.specify/…) is not doubled under the app folder
rm -rf "$sr_l/.claude/worktrees/HEF-2"
sr_po="$(cd "$sr_l" && env -u CLAUDE_CODE_SESSION_ID -u HEFESTO_TRUSTED_TOP -u HEFESTO_LANE_MAP bash "$REPO/hooks/session-launch.sh" plan HEF-2 --prepare --lane mono-planner 2>&1)"
mkdir -p "$sr_l/.claude/worktrees/HEF-2/frontend/.specify/specs/y" && printf -- '- [ ] T001\n' > "$sr_l/.claude/worktrees/HEF-2/frontend/.specify/specs/y/tasks.md"
printf '{"summary":"planned","outcome":"tasks","spec_dir":"frontend/.specify/specs/y","blocked_on":null}\n' > "$sr_t/out2.json"
sr_fo="$(cd "$sr_l" && env -u CLAUDE_CODE_SESSION_ID -u HEFESTO_TRUSTED_TOP -u HEFESTO_LANE_MAP bash "$REPO/hooks/session-launch.sh" plan HEF-2 --finish --lane mono-planner --outcome-file "$sr_t/out2.json" 2>&1)"
[ "$(jq -r .spec_dir "$(sld "$sr_l")/HEF-2.json" 2>/dev/null)" = frontend/.specify/specs/y ] \
  || { bad "FR-010 a spec_dir reported from the worktree root is not doubled under the app folder — got '$(jq -r .spec_dir "$(sld "$sr_l")/HEF-2.json" 2>/dev/null)': $(head -c 200 <<<"$sr_po $sr_fo")"; x_fail=1; }
[ "$x_fail" = 0 ] && ok "--finish: the relative spec_dir is stored as <app>/.specify/specs/<name>, either frame; verify starts in the app folder (FR-009, FR-010)"

head_ "A bad spec_roots is reported by the display readers too (FR-006)"
sr_cfg '{"source":"tasks-repo","root":"tasks","spec_roots":{"x":"../up"}}'
grep -qF "bad entry 'x=../up'" <<<"$(cd "$sr_r/backend" && bash "$REPO/hooks/speckit-helper.sh" constitution 2>&1 >/dev/null)" \
  && ok "FR-006 constitution names a bad spec_roots entry on stderr (review S3)" || bad "FR-006 constitution names a bad spec_roots entry on stderr (review S3)"

head_ "The board's epics read every declared app (FR-012)"
x_fail=0
sr_cfg '{"source":"tasks-repo","root":"tasks","epics":{"specs":true},"spec_roots":{"backend":"backend","frontend":"frontend","web":"apps/web"}}'
mkdir -p "$sr_r/tasks/.specify/specs/top-thing" && printf -- '- [x] T001\n' > "$sr_r/tasks/.specify/specs/top-thing/tasks.md"   # the board reads the TASKS root's .specify/, as before
sr_ep="$(cd "$sr_r" && bash "$REPO/hooks/status-board.sh" 2>&1)"
# FR-012: the top's feature unlabelled, backend's labelled, an app with no specs adds no line and no error
grep -qE '^    top-thing ' <<<"$sr_ep" && grep -qE '^    backend/audit-log ' <<<"$sr_ep" && ! grep -qE 'web/|frontend/' <<<"$sr_ep" \
  || { bad "FR-012 epics list the top's features and each app's as <app>/<feature> — got: $(grep -A6 'Epics' <<<"$sr_ep" | head -c 400)"; x_fail=1; }
[ "$x_fail" = 0 ] && ok "epics: the top's features, then each declared app's as <app>/<feature> (FR-012)"
rm -rf "$(sld "$sr_l")" "$(sld "$sr_r")"; rm -rf "$sr_t" "$sr_l" "$sr_lout" "$sr_lcfg"

head_ "The commands carry the several-apps rules (FR-008, FR-013, FR-014, FR-015)"
x_fail=0
sr_cmd() { grep -qF -- "$2" "$REPO/commands/$1" || { bad "$3: commands/$1 lacks '$2'"; x_fail=1; }; }
sr_cmd hef.orchestrate.md 'ledger.sh list --undecided-app' "FR-008 the orchestrator asks the owning app"
sr_cmd hef.orchestrate.md 'ledger.sh record <id> --spec-root <name>' "FR-008 the app answer is recorded"
sr_cmd hef.orchestrate.md 'show `<worktree>/<spec_dir>`' "FR-010 the plan-approval form resolves a relative spec_dir"
sr_cmd hef.orchestrate.md 'printed an `app:` line, `cd` into that folder' "FR-014 an interactive lane works from the app folder"
sr_cmd hef.ship.md 'Add `--app <name>` to the `--add` call' "FR-008 /hefesto:hef.ship asks the app and writes the line"
sr_cmd hef.quality.md "run from the owning app's" "FR-013 app checks from the app folder"
sr_cmd hef.quality.md 'run once
from the repository top' "FR-013 repository-wide checks once from the top"
sr_cmd hef.verify.md "reads the owning app's spec and tests" "FR-013 verify in the owning app"
sr_cmd hef.tasks.md 'names that path in the task line' "FR-015 a cross-app path is named in its task"
sr_cmd hef.plan.md 'listed in Affected Files by its path from the repository top' "FR-015 a cross-app path is in the plan"
[ "$x_fail" = 0 ] && ok "commands: the app form, the app folder for lanes, app vs repository checks, cross-app paths named (FR-008, FR-013, FR-014, FR-015)"

head_ "SC-001: the #172 expected failure, now a walk from an app folder with no top .specify/"
x_fail=0
sr_w="$(cd "$(mktemp -d)" && pwd -P)"
( cd "$sr_w" && git init -q -b main . && sr_git commit -q --allow-empty -m init && git checkout -q -b feature/triage \
  && mkdir -p backend/.specify/memory backend/.specify/specs/triage backend/internal/svc frontend \
  && printf '# Backend\n' > backend/.specify/memory/constitution.md && printf '# Spec\nFR-001 x\n' > backend/.specify/specs/triage/spec.md ) >/dev/null 2>&1
for sr_d in backend backend/internal/svc; do
  [ "$(cd "$sr_w/$sr_d" && bash "$REPO/hooks/speckit-helper.sh" check-spec 2>&1)" = "SPEC_FOUND: triage" ] || { bad "SC-001 check-spec from $sr_d finds backend's spec"; x_fail=1; }
  # FR-007 (HEF-1): check-tasks-inputs is spec-root scoped too — backend's spec, no plan → the light path.
  # The subfolder iteration is the one that proves the dispatch: from backend/ itself $PWD already is the root
  sr_ti="$(cd "$sr_w/$sr_d" && bash "$REPO/hooks/speckit-helper.sh" check-tasks-inputs 2>&1)"
  [ "$sr_ti" = "LIGHT_PATH: triage" ] || { bad "FR-007 check-tasks-inputs from $sr_d must answer 'LIGHT_PATH: triage' (spec-root dispatch) — got '$sr_ti'"; x_fail=1; }
  (cd "$sr_w/$sr_d" && bash "$REPO/hooks/speckit-helper.sh" plan-phase-start && bash "$REPO/hooks/speckit-helper.sh" plan-phase-end \
    && bash "$REPO/hooks/speckit-helper.sh" implement-phase-start && bash "$REPO/hooks/speckit-helper.sh" implement-phase-end) >/dev/null 2>&1 \
    || { bad "SC-001 the phase markers work from $sr_d"; x_fail=1; }
  grep -qF '# Backend' <<<"$(cd "$sr_w/$sr_d" && bash "$REPO/hooks/speckit-helper.sh" constitution 2>&1)" || { bad "SC-001 the constitution from $sr_d is backend's"; x_fail=1; }
done
[ ! -e "$sr_w/.specify" ] && [ ! -e "$sr_w/backend/internal/.specify" ] && [ ! -e "$sr_w/backend/internal/svc/.specify" ] \
  || { bad "SC-001 no .specify/ is created at the top or in a subfolder of the app"; x_fail=1; }
rm -rf "$sr_w"
[ "$x_fail" = 0 ] && ok "SC-001: spec, markers and constitution from backend/ and a subfolder; no stray .specify/ anywhere"

# code review round 2 (B3): --prepare's app record calls undo(), so undo() must be defined above it (set -u, no -e:
# a call before the definition is "command not found" and the prepare goes on with the claim held)
sr_ud="$(grep -n '^  undo() {' "$REPO/hooks/session-launch.sh" | head -1 | cut -d: -f1)"
sr_ur="$(grep -n 'cannot record the app"$' "$REPO/hooks/session-launch.sh" | head -1 | cut -d: -f1)"
[ -n "$sr_ud" ] && [ -n "$sr_ur" ] && [ "$sr_ud" -lt "$sr_ur" ] && ok "FR-009 --prepare records the app after undo() is defined (its failure releases the claim)" \
  || bad "FR-009 --prepare's app record must follow the undo() definition (undo at ${sr_ud:-?}, record at ${sr_ur:-?})"
