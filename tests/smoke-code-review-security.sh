# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs, sed expressions and recipes are single-quoted on purpose
#
# exhaustive-review smoke checks, part 19s — the execution channel's dedicated security file: hooks/review-repro.sh
# (FR-006) run against a real linked worktree with recipes that mutate git, write, delete and rewrite; and the
# lane-guard.sh exception for the round's two heredoc helpers (FR-022) with its near misses.
#
# SOURCED by tests/smoke.sh after part 19, never run on its own. The suite runs unsandboxed, so the sandbox the helper
# probes for is faked the way it reads it: HOME points at a temp home whose .cache/hefesto is read-only (chmod 555) —
# hef_cache is $HOME/.cache/hefesto (lane-lib.sh). A writable one is the "not sandboxed" case. Every guard has a mutant.

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-code-review-security.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_)"
  else echo "tests/smoke-code-review-security.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

# --- review-repro.sh (FR-006) ---------------------------------------------------------------------------------------------
head_ "review-repro.sh: a recipe runs on a scratch copy with its own repository; the worktree is guarded; refused outside the sandbox (exhaustive-review FR-006)"
x_fail=0
rs_t="$(cd "$(mktemp -d)" && pwd -P)"
rs_git() { git -c user.email=t@t -c user.name=t "$@"; }
rs_main="$rs_t/main"; rs_wt="$rs_t/wt"
mkdir -p "$rs_main" && (cd "$rs_main" && git init -q -b main . && printf 'aaaa\n' >a.txt && printf 'build/\n' >.gitignore \
  && git add -A && rs_git commit -q -m init && rs_git worktree add -q -b feature/rs "$rs_wt") >/dev/null 2>&1
mkdir -p "$rs_t/home-sbx/.cache/hefesto" "$rs_t/home-open/.cache/hefesto" "$rs_t/home-none" "$rs_t/tmp"
chmod 555 "$rs_t/home-sbx/.cache/hefesto"
# RS_RECIPE=<recipe> rs_run <home | x for the sandboxed one> [extra env…] → stdout $rs_t/out, stderr $rs_t/err, exit
# $rs_t/rc; run from the linked worktree
rs_run() {
  local rc=0 home="$1"; shift; [ "$home" = x ] && home="$rs_t/home-sbx"
  if [ -n "${RS_ARG:-}" ]; then   # amendment A3: the recipe as one argument, stdin empty
    (cd "$rs_wt" && env HOME="$home" TMPDIR="$rs_t/tmp" "$@" bash "${RS_HOOKS:-$REPO/hooks}/review-repro.sh" "$RS_RECIPE" ${RS_ARG2:+"$RS_ARG2"} </dev/null) >"$rs_t/out" 2>"$rs_t/err" || rc=$?
  else
    (cd "$rs_wt" && printf '%s\n' "$RS_RECIPE" | env HOME="$home" TMPDIR="$rs_t/tmp" "$@" bash "${RS_HOOKS:-$REPO/hooks}/review-repro.sh") >"$rs_t/out" 2>"$rs_t/err" || rc=$?
  fi
  echo "$rc" >"$rs_t/rc"
}
rs_no() { bad "$1 — rc $(cat "$rs_t/rc"), out: $(head -c 300 "$rs_t/out" | tr '\n' '|'), err: $(head -c 300 "$rs_t/err" | tr '\n' '|')"; x_fail=1; }
rs_left() { [ -z "$(find "$rs_t/tmp" -maxdepth 1 -name 'hef-repro.*' 2>/dev/null)" ] || rs_no "$1: a hef-repro.* scratch copy was left in TMPDIR"; }
rs_state() { (cd "$rs_wt" && git rev-parse HEAD && git config --get x.y; git ls-files -s | cksum; cat a.txt) 2>/dev/null; }
rs_restore() { (cd "$rs_wt" && printf 'aaaa\n' >a.txt && rm -rf new.txt build) >/dev/null 2>&1; }

# exhaustive-review/FR-006: a git-mutating recipe acts on the scratch repository — the real config, index and HEAD stay
rs_t_git() {
  local before; before="$(rs_state)"
  RS_RECIPE='git config x.y 1; git commit -q --allow-empty -m x && git log --oneline | wc -l | tr -d " "; cat a.txt; echo x > a.txt' rs_run x
  [ "$(cat "$rs_t/rc")" = 0 ] && grep -qx 'exit: 0' "$rs_t/out" && grep -qx 'aaaa' "$rs_t/out" || rs_no "a git-mutating recipe runs on the copy (exit: 0, the file's content)"
  grep -qx '2' "$rs_t/out" || rs_no "the copy has its own repository with one commit, and the recipe's commit lands there"
  [ "$(rs_state)" = "$before" ] || rs_no "the real config, index, HEAD and a.txt must be unchanged"
  rs_left "after a success"
}
# exhaustive-review/FR-006: a write into the real worktree → exit 3 naming each path; an ignored build output is fine
rs_t_guard() {
  RS_RECIPE="echo n > '$rs_wt/new.txt'" rs_run x; [ "$(cat "$rs_t/rc")" = 3 ] && grep -qx 'created new.txt' "$rs_t/err" || rs_no "a created file → exit 3 'created new.txt'"
  rs_left "after an exit 3"; rs_restore
  RS_RECIPE="echo more >> '$rs_wt/a.txt'" rs_run x; [ "$(cat "$rs_t/rc")" = 3 ] && grep -qx 'modified a.txt' "$rs_t/err" || rs_no "a modified file → exit 3 'modified a.txt'"; rs_restore
  RS_RECIPE="rm '$rs_wt/a.txt'" rs_run x; [ "$(cat "$rs_t/rc")" = 3 ] && grep -qx 'deleted a.txt' "$rs_t/err" || rs_no "a deleted file → exit 3 'deleted a.txt'"; rs_restore
  RS_RECIPE="printf 'bbbb\\n' > '$rs_wt/a.txt'" rs_run x; [ "$(cat "$rs_t/rc")" = 3 ] && grep -qx 'modified a.txt' "$rs_t/err" || rs_no "a same-size rewrite → exit 3 'modified a.txt'"; rs_restore
  RS_RECIPE="mkdir -p '$rs_wt/build' && echo o > '$rs_wt/build/out.o'" rs_run x; [ "$(cat "$rs_t/rc")" = 0 ] || rs_no "an ignored build output is no worktree change (exit 0)"; rs_restore
}
# exhaustive-review/FR-006: refused (exit 2) outside the sandbox and with no cache folder to probe; an empty recipe too
rs_t_refuse() {
  RS_RECIPE='echo ran' rs_run "$rs_t/home-open"
  [ "$(cat "$rs_t/rc")" = 2 ] && grep -q 'not running inside the OS sandbox' "$rs_t/err" && ! grep -q ran "$rs_t/out" || rs_no "a writable \$HOME/.cache/hefesto → exit 2, not sandboxed, nothing run"
  [ -z "$(find "$rs_t/home-open/.cache/hefesto" -name '.repro-probe.*')" ] || rs_no "the probe file is removed"
  RS_RECIPE='echo ran' rs_run "$rs_t/home-none"
  [ "$(cat "$rs_t/rc")" = 2 ] && grep -q 'is missing, so the sandbox cannot be probed' "$rs_t/err" || rs_no "a missing \$HOME/.cache/hefesto → exit 2"
  RS_RECIPE='' rs_run x; [ "$(cat "$rs_t/rc")" = 2 ] || rs_no "an empty recipe → exit 2"
  rs_left "after a refusal"
}
# exhaustive-review/FR-006: output capped at 60 lines and 8 KiB; a timed-out recipe is reported, its copy removed
rs_t_cap() {
  local stub="$rs_t/stub" lines
  RS_RECIPE='seq 1 500' rs_run x; lines="$(wc -l <"$rs_t/out")"
  [ "$lines" -le 63 ] && grep -qE '^… \+[0-9]+ lines / [0-9]+ bytes cut$' "$rs_t/out" || rs_no "500 lines capped at 60 with the cut line ($lines lines)"
  RS_RECIPE='head -c 20000 /dev/zero | tr "\0" x' rs_run x
  [ "$(wc -c <"$rs_t/out")" -le 8300 ] && grep -q 'bytes cut' "$rs_t/out" || rs_no "20000 bytes on one line capped at 8 KiB"
  command -v timeout >/dev/null 2>&1 || { rs_left "after a capped recipe"; return 0; }   # stock macOS: runs untimed
  mkdir -p "$stub"; printf '#!/bin/bash\nshift\nexec "%s" 1 "$@"\n' "$(command -v timeout)" >"$stub/timeout"; chmod +x "$stub/timeout"
  RS_RECIPE='sleep 5; echo late' rs_run x PATH="$stub:$PATH"
  [ "$(cat "$rs_t/rc")" = 0 ] && grep -qx 'exit: 124' "$rs_t/out" && ! grep -q late "$rs_t/out" || rs_no "a timed-out recipe → exit: 124, nothing after"
  rs_left "after a timed-out recipe"
}
# exhaustive-review/FR-006 (amendment A3): the recipe as ONE argument runs like stdin's; the guard holds; extra args refused
rs_t_arg() {
  RS_ARG=1 RS_RECIPE='cat a.txt; echo "two words"' rs_run x
  [ "$(cat "$rs_t/rc")" = 0 ] && grep -qx 'exit: 0' "$rs_t/out" && grep -qx 'aaaa' "$rs_t/out" && grep -qx 'two words' "$rs_t/out" || rs_no "an argument recipe runs on the copy (exit: 0, its output)"
  RS_ARG=1 RS_RECIPE="echo n > '$rs_wt/new.txt'" rs_run x; [ "$(cat "$rs_t/rc")" = 3 ] && grep -qx 'created new.txt' "$rs_t/err" || rs_no "an argument recipe writing the worktree → exit 3"; rs_restore
  RS_ARG=1 RS_ARG2='echo second' RS_RECIPE='echo ran' rs_run x
  [ "$(cat "$rs_t/rc")" = 2 ] && ! grep -q ran "$rs_t/out" || rs_no "two arguments → exit 2, nothing run"
  RS_ARG=1 RS_RECIPE=' ' rs_run x; [ "$(cat "$rs_t/rc")" = 2 ] || rs_no "a blank argument recipe → exit 2"
  rs_left "after an argument recipe"
}
# exhaustive-review/FR-006 (amendment A4): a read-only temp folder → the scratch copy goes under a writable folder of the
# cache (here worker-cache/r below a read-only cache, as in a worker's sandbox), the recipe runs, its own heredoc too;
# neither writable → refused (exit 2) naming both, nothing run
mkdir -p "$rs_t/home-a4/.cache/hefesto/worker-cache/r" "$rs_t/tmp-ro"; chmod 555 "$rs_t/home-a4/.cache/hefesto/worker-cache" "$rs_t/home-a4/.cache/hefesto" "$rs_t/tmp-ro"
rs_t_rotmp() {
  local before; before="$(rs_state)"
  RS_ARG=1 RS_RECIPE='cat a.txt; pwd; echo "tmp=$TMPDIR"; cat <<HD'$'\n''heredoc ran'$'\n''HD' rs_run "$rs_t/home-a4" TMPDIR="$rs_t/tmp-ro"
  [ "$(cat "$rs_t/rc")" = 0 ] && grep -qx 'exit: 0' "$rs_t/out" && grep -qx 'aaaa' "$rs_t/out" || rs_no "a read-only temp folder: the recipe still runs (exit: 0, its output)"
  grep -q "^$rs_t/home-a4/.cache/hefesto/worker-cache/r/hef-repro\." "$rs_t/out" || rs_no "a read-only temp folder: the scratch copy is under the cache's writable folder"
  grep -qx 'heredoc ran' "$rs_t/out" && grep -q "^tmp=$rs_t/home-a4/.cache/hefesto/worker-cache/r/hef-repro\.[^/]*/tmp\$" "$rs_t/out" \
    || rs_no "a read-only temp folder: the recipe's TMPDIR is a writable folder in the copy, its heredoc runs"
  [ "$(rs_state)" = "$before" ] || rs_no "a read-only temp folder: the real worktree is unchanged"
  [ -z "$(find "$rs_t/home-a4/.cache/hefesto" -name 'hef-repro.*' 2>/dev/null)" ] || rs_no "a read-only temp folder: no hef-repro.* left under the cache"
  RS_ARG=1 RS_RECIPE='echo ran' rs_run x TMPDIR="$rs_t/tmp-ro"
  [ "$(cat "$rs_t/rc")" = 2 ] && grep -q "neither $rs_t/tmp-ro nor any folder under $rs_t/home-sbx/.cache/hefesto is writable" "$rs_t/err" \
    && ! grep -q ran "$rs_t/out" || rs_no "neither the temp folder nor the cache writable → exit 2 naming both, nothing run"
}
for rs_fn in rs_t_git rs_t_guard rs_t_refuse rs_t_cap rs_t_arg rs_t_rotmp; do "$rs_fn"; done
[ "$x_fail" -eq 0 ] && ok "review-repro.sh: git config/commit act on the copy's own repository (real config, index, HEAD unchanged); created/modified/deleted/same-size-rewritten worktree files → exit 3 naming them; an ignored build output passes; a writable or missing cache → exit 2; output capped at 60 lines and 8 KiB; a timed-out recipe reported; the recipe as one argument runs (amendment A3), two arguments refused; a read-only temp folder → the copy under the cache's writable folder, the recipe and its heredoc run, and neither writable → exit 2 naming both (amendment A4); no scratch copy left on any path (exhaustive-review/FR-006)"
x_fail=0
rs_mut() { # label sed-expr test-fn — a mutant of review-repro.sh must turn test-fn red
  local md red; md="$(mktemp -d)"; ln -s "$REPO/hooks/lane-lib.sh" "$md/lane-lib.sh"; sed "$2" "$REPO/hooks/review-repro.sh" >"$md/review-repro.sh"
  if cmp -s "$REPO/hooks/review-repro.sh" "$md/review-repro.sh"; then bad "review-repro mutant did not apply: $1"; x_fail=1; rm -rf "$md"; return; fi
  red="$(x_fail=0; RS_HOOKS="$md" "$3" >/dev/null 2>&1; echo "$x_fail")"; rm -rf "$md"; rs_restore
  [ "$red" = 1 ] && ok "mutant killed: $1" || { bad "mutant survived: $1"; x_fail=1; }
}
rs_mut "FR-006 the sandbox probe dropped" 's/if ( : >"\$PROBE" ) 2>\/dev\/null; then/if false; then/' rs_t_refuse
rs_mut "FR-006 the cache existence check dropped" 's/^\[ -d "\$CACHE" \] ||/true ||/' rs_t_refuse
rs_mut "FR-006 the worktree guard dropped" 's/^exit 3$/exit 0/' rs_t_guard
rs_mut "FR-006 the copy keeps no repository of its own" 's/git init -q \. \&\&/false \&\&/' rs_t_git
rs_mut "FR-006 the scratch copy is not removed" "s/^trap .*EXIT\$/:/" rs_t_git
rs_mut "FR-006 A3 the argument is ignored (stdin read instead)" "s/^  1) printf '%s\\\\n' \"\$1\" >/  1) cat >/" rs_t_arg
rs_mut "FR-006 A3 extra arguments accepted" 's/^  \*) refuse "\$# arguments/  *) printf "%s\\n" "$1" >"$SCRATCH\/.hef-recipe.sh"; : "/' rs_t_arg
rs_mut "FR-006 A4 no fallback under the cache" 's/^  for d in "\${TMPDIR:-\/tmp}" .*; do$/  for d in "${TMPDIR:-\/tmp}"; do/' rs_t_rotmp
rs_mut "FR-006 A4 the recipe keeps the read-only temp folder" 's/mkdir "\$SCRATCH\/tmp" && export TMPDIR="\$SCRATCH\/tmp"/:/' rs_t_rotmp
rs_mut "FR-006 A4 the refusal stops naming the cache" 's/ nor any folder under \$CACHE is writable here/ is writable/' rs_t_rotmp
[ "$x_fail" -eq 0 ] && ok "review-repro.sh: 10 mutants killed (exhaustive-review/FR-006)"
chmod -R u+w "$rs_t" 2>/dev/null

# --- lane-guard.sh: the review round's heredoc exception (FR-022) ---------------------------------------------------------
head_ "lane-guard: the round's two helper heredocs pass with excluded words in the body; every near miss is denied as today (exhaustive-review FR-022)"
x_fail=0
mkdir -p "$HOME/.cache/hefesto/sessions"
jq -nc --arg h "$REPO/hooks" '{title: "repo-verify", role: "verify", name: "repo-verify", lanes: true, worker: false,
  excluded: ["gh *", "\($h)/ledger.sh *", "\($h)/session-launch.sh *", "mytool *"]}' >"$HOME/.cache/hefesto/sessions/sid-crlg-0001.json"
lg_gd() { # lg_gd <command> [dds true|false] [hook] → deny | allow | none
  local o; o="$(jq -nc --arg c "$1" --argjson d "${2:-false}" '{tool_name: "Bash", tool_input: {command: $c, dangerouslyDisableSandbox: $d}, session_id: "sid-crlg-0001", cwd: "/tmp"}' \
    | bash "${3:-${LG_HOOK:-$REPO/hooks/lane-guard.sh}}" 2>/dev/null)"
  [ -n "$o" ] || { echo none; return; }; jq -r '.hookSpecificOutput.permissionDecision // "none"' <<<"$o" 2>/dev/null || echo none
}
lg_want() { local got; got="$(lg_gd "$2" "${3:-false}")"; [ "$got" = "$1" ] || { bad "lane-guard: must be $1, got $got — $(head -c 200 <<<"$2" | tr '\n' '|')"; x_fail=1; }; }
LG_CRC="$REPO/hooks/speckit-helper.sh code-review-check"; LG_RR="$REPO/hooks/review-repro.sh"
lg_hd() { printf "%s <<'%s'\n%s\n%s" "$1" "${3:-HEF_DELIM_END}" "$2" "${3:-HEF_DELIM_END}"; }   # head, body[, delimiter]
lg_t_admit() { # exhaustive-review/FR-022: admitted with gh, a custom excluded command, or gh + lane-build in the body
  local h
  for h in "$LG_CRC" "$LG_RR"; do
    lg_want none "$(lg_hd "$h" "- [F1] [BLOCKING] hooks/pr-watch.sh:9 — gh pr merge 7 runs unasked")"
    lg_want none "$(lg_hd "$h" "mytool --flag; echo data")"
    lg_want none "$(lg_hd "$h" "gh pr view 7 then hooks/lane-build.sh make")"
  done
}
lg_t_early() { # exhaustive-review/FR-022: an early delimiter ends the heredoc — what follows would run unread
  local h
  for h in "$LG_CRC" "$LG_RR"; do lg_want deny "$(lg_hd "$h" "x"$'\n'"HEF_DELIM_END"$'\n'"gh pr merge 7")"; done
}
lg_t_count() { # exhaustive-review/FR-022: the head is exactly the helper's word list — no word before it
  lg_want deny "$(lg_hd "/usr/bin/env $LG_RR" "gh pr merge 7")"
  lg_want deny "$(lg_hd "/usr/bin/env $LG_CRC" "gh pr merge 7")"
}
lg_t_abs() { # exhaustive-review/FR-022: an absolute path first
  lg_want deny "$(lg_hd "./hooks/review-repro.sh" "gh pr merge 7")"
  lg_want deny "$(lg_hd "./hooks/speckit-helper.sh code-review-check" "gh pr merge 7")"
}
lg_t_deny() { # exhaustive-review/FR-022: every other near miss is denied as today
  local h
  lg_want deny "$(lg_hd "$LG_RR extra" "gh pr merge 7")"
  lg_want deny "$(lg_hd "$LG_CRC extra" "gh pr merge 7")"
  lg_want deny "$(printf '%s <<HEF_DELIM_END\ngh pr merge 7\nHEF_DELIM_END' "$LG_RR")"
  lg_want deny "$(lg_hd "$LG_RR" "gh pr merge 7")"$'\n'"gh pr merge 7"
  lg_want deny "$(lg_hd "$REPO/hooks/speckit-helper.sh branch" "gh pr merge 7")"
  lg_want deny "$(lg_hd "$REPO/hooks/run-follow.sh" "gh pr merge 7")"
  lg_want deny "$(lg_hd "$LG_RR" "gh pr merge 7")" true
  lg_want deny "$(lg_hd "$LG_CRC" "gh pr merge 7")" true
  lg_want deny "$(lg_hd "$LG_RR" "CLAUDE_CODE_SESSION_ID=x gh pr view")"
  for h in "$LG_RR" "$LG_CRC"; do
    lg_want deny "$(lg_hd "gh pr comment 7 --body $h" "gh pr merge 7")"
    lg_want deny "$(lg_hd "HOME=/x $h" "gh pr merge 7")"
  done
}
# exhaustive-review/FR-022 (amendment A3): review-repro.sh with its recipe as ONE single-quoted argument
lg_t_arg_admit() {
  lg_want none "$LG_RR 'gh pr view 7 --json state; hooks/lane-build.sh make; mytool x'"
  lg_want none "$LG_RR '. hooks/pr-watch.sh"$'\n'"gh pr merge 7 is data here; echo \"\$(date)\"'"
}
lg_t_arg_tail() { # nothing after the closing quote
  lg_want deny "$LG_RR 'x'; gh pr merge 7"
  lg_want deny "$LG_RR 'x' 'gh pr merge 7'"
  lg_want deny "$LG_RR 'x'"$'\n'"gh pr merge 7"
  lg_want deny "$LG_RR 'gh pr view' extra"
}
lg_t_arg_head() { # nothing before the absolute path
  lg_want deny "HOME=/x $LG_RR 'gh pr view'"
  lg_want deny "/usr/bin/env $LG_RR 'gh pr view'"
  lg_want deny "gh pr comment 7 --body $LG_RR 'gh pr view'"
}
lg_t_arg_quote() { # one single-quoted string, no ' inside it
  lg_want deny "$LG_RR 'a'\\''; gh pr merge 7; echo '\\''b'"
  lg_want deny "$LG_RR 'a'\\''gh pr merge 7'"
}
lg_t_arg_deny() { # every other near miss
  lg_want deny "$LG_RR \"gh pr view 7\""
  lg_want deny "$LG_RR gh pr view 7"
  lg_want deny "./hooks/review-repro.sh 'gh pr view'"
  lg_want deny "$LG_CRC 'gh pr view'"
  lg_want deny "$REPO/hooks/run-follow.sh 'gh pr view'"
  lg_want deny "$LG_RR 'CLAUDE_CODE_SESSION_ID=x gh pr view'"
  lg_want deny "$LG_RR 'gh pr view 7'" true
}
LG_TESTS="lg_t_admit lg_t_early lg_t_count lg_t_abs lg_t_deny lg_t_arg_admit lg_t_arg_tail lg_t_arg_head lg_t_arg_quote lg_t_arg_deny"
for lg_fn in $LG_TESTS; do "$lg_fn"; done
[ "$x_fail" -eq 0 ] && ok "lane-guard: code-review-check and review-repro.sh heredocs pass with gh, a custom excluded command, or gh + lane-build in the body; an extra or leading word, a relative path, an unquoted or early delimiter, a command after it, another helper, a sandbox-disabled retry, CLAUDE_CODE_SESSION_ID= and an excluded command naming the helper are denied; review-repro.sh's one single-quoted argument passes with the same words in it, and anything after or before it, a quote inside it, a double-quoted or unquoted recipe, a relative path, another helper and a sandbox-disabled retry are denied (exhaustive-review/FR-022, amendment A3)"
x_fail=0
lg_mut() { # label sed-expr test-fn — a mutant of lane-guard.sh must turn test-fn red
  local md red; md="$(mktemp -d)"; ln -s "$REPO/hooks/lane-lib.sh" "$md/lane-lib.sh"; sed "$2" "$REPO/hooks/lane-guard.sh" >"$md/lane-guard.sh"
  if cmp -s "$REPO/hooks/lane-guard.sh" "$md/lane-guard.sh"; then bad "lane-guard mutant did not apply: $1"; x_fail=1; rm -rf "$md"; return; fi
  red="$(x_fail=0; LG_HOOK="$md/lane-guard.sh" "$3" >/dev/null 2>&1; echo "$x_fail")"; rm -rf "$md"
  [ "$red" = 1 ] && ok "mutant killed: $1" || { bad "mutant survived: $1"; x_fail=1; }
}
lg_mut "FR-022 the early exit dropped (the body is read again)" 's/^review_heredoc_ok && exit 0$/true/' lg_t_admit
lg_mut "FR-022 the one-delimiter-line count dropped" 's/\[ "\$n" = 1 \] || return 1/true/' lg_t_early
lg_mut "FR-022 a glob over the whole head instead of the word count" 's/case "\${#w\[@\]}:\${w\[0\]}" in/case "1:${w[*]}" in/' lg_t_count
lg_mut "FR-022 the absolute-path test dropped" '/an absolute path first: no word/d' lg_t_abs
lg_mut "FR-022 a sandbox-disabled retry admitted" '/never with the sandbox off/d' lg_t_deny
[ "$x_fail" -eq 0 ] && ok "lane-guard: 5 mutants of the heredoc exception killed (exhaustive-review/FR-022)"
x_fail=0
lg_q="'"
lg_mut "FR-022 A3 the argument form's early exit dropped" 's/^review_arg_ok && exit 0$/true/' lg_t_arg_admit
lg_mut "FR-022 A3 the end anchor dropped" 's/\*\\\$"$/*"/' lg_t_arg_tail
lg_mut "FR-022 A3 the start anchor dropped" 's/local re="^\//local re="\//' lg_t_arg_head
lg_mut "FR-022 A3 a quote allowed inside the argument" "s/${lg_q}[[]^${lg_q}[]][*]${lg_q}/${lg_q}.*${lg_q}/" lg_t_arg_quote
lg_mut "FR-022 A3 a sandbox-disabled retry admitted" '/^review_arg_ok() {$/,/^}$/{/never with the sandbox off/d;}' lg_t_arg_deny
[ "$x_fail" -eq 0 ] && ok "lane-guard: 5 mutants of the argument exception killed (exhaustive-review/FR-022, amendment A3)"
