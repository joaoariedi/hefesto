# shellcheck shell=bash
#
# lane-build-cache smoke checks, part 9: the lanes' build cache, reachable only inside the sandbox (#162; FR-001..FR-008,
# NR-001..NR-004).
#
# SOURCED by tests/smoke.sh, never run on its own. Self-contained: a fake HOME whose probe folder stands for the
# sandbox — read-only (chmod 555) where a sandboxed write would fail, writable where an unsandboxed one succeeds —
# and a canary program that writes the environment it was run with.

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-lane-cache.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_)"
  else echo "tests/smoke-lane-cache.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

lc_t="$(cd "$(mktemp -d)" && pwd -P)"; lc_h="$lc_t/home"; lc_key="0123456789abcdef0123456789abcdef"
lc_lc="$lc_h/.cache/hefesto/lane-cache/$lc_key"; lc_pr="$lc_h/.cache/hefesto/lane-cache-probe"
mkdir -p "$lc_lc" "$lc_pr"
printf '#!/bin/sh\nenv > "%s/canary.env"; echo "args:$*" >> "%s/canary.env"; exit 7\n' "$lc_t" "$lc_t" > "$lc_t/canary"; chmod +x "$lc_t/canary"
lc_sandboxed() { chmod 555 "$lc_pr"; }   # a write into the probe folder fails, as it does inside the sandbox
lc_unsandboxed() { chmod 755 "$lc_pr"; }
lc_wrap() { # [hook dir] → runs the wrapper on the canary with HOME=$lc_h; $lc_rc, $lc_err
  rm -f "$lc_t/canary.env"; lc_rc=0
  lc_err="$(HOME="$lc_h" HEFESTO_LANE_CACHE="${LC_ENV-$lc_lc}" bash "${1:-$REPO/hooks}/lane-build.sh" "$lc_t/canary" one 'two words' 2>&1 >/dev/null)" || lc_rc=$?
}
lc_mut() { # label sed-expr test-fn — a mutant of lane-build.sh must make the test fail
  local md red; md="$(mktemp -d)"; for h in "$REPO"/hooks/*.sh; do ln -s "$h" "$md/$(basename "$h")"; done
  rm "$md/lane-build.sh"; sed "$2" "$REPO/hooks/lane-build.sh" > "$md/lane-build.sh"
  if cmp -s "$REPO/hooks/lane-build.sh" "$md/lane-build.sh"; then bad "mutant did not apply: $1"; x_fail=1; rm -rf "$md"; return; fi
  red="$(x_fail=0; LC_DIR="$md" "$3" >/dev/null 2>&1; echo "$x_fail")"
  [ "$red" = 1 ] || { bad "mutant survived: $1"; x_fail=1; }; rm -rf "$md"
}

# --- FR-001 / FR-002 / NR-002: the wrapper ------------------------------------------------------------------------
head_ "lane-build.sh: the caches point into the lane cache, and only inside the sandbox (FR-001, FR-002, NR-002)"
x_fail=0
lc_sandboxed; lc_wrap
{ [ "$lc_rc" = 7 ] && grep -qx "GOCACHE=$lc_lc/go-build" "$lc_t/canary.env" && grep -qx "npm_config_cache=$lc_lc/npm" "$lc_t/canary.env" \
  && grep -qx "PIP_CACHE_DIR=$lc_lc/pip" "$lc_t/canary.env" && grep -qx "XDG_CACHE_HOME=$lc_lc/xdg" "$lc_t/canary.env" \
  && grep -qx "YARN_CACHE_FOLDER=$lc_lc/yarn" "$lc_t/canary.env" && grep -qx "BUN_INSTALL_CACHE_DIR=$lc_lc/bun" "$lc_t/canary.env" \
  && grep -qx 'args:one two words' "$lc_t/canary.env"; } \
  || { bad "inside the sandbox the command runs with every cache variable in the lane cache, its arguments and exit status unchanged (FR-001) — rc=$lc_rc err=$lc_err env=$(grep -E 'CACHE|args' "$lc_t/canary.env" 2>/dev/null | tr '\n' ' ')"; x_fail=1; }
t_unsb() { local r=0; lc_unsandboxed; lc_wrap "${LC_DIR:-}"; { [ "$lc_rc" = 2 ] && [ ! -f "$lc_t/canary.env" ] && grep -qF 'not running inside the sandbox' <<<"$lc_err"; } || r=1; lc_sandboxed; [ "$r" = 0 ] || { x_fail=1; return 1; }; }
t_unsb || bad "outside the sandbox (the probe write succeeds) the wrapper refuses and runs nothing (FR-002, NR-002, NR-001) — rc=$lc_rc err=$lc_err"
[ -z "$(ls -A "$lc_pr" 2>/dev/null)" ] || { bad "the refused probe write leaves no file behind: $(ls -A "$lc_pr")"; x_fail=1; }
t_noenv() { LC_ENV="" lc_wrap "${LC_DIR:-}"; { [ "$lc_rc" = 2 ] && [ ! -f "$lc_t/canary.env" ] && grep -qF 'no lane cache in this session' <<<"$lc_err"; } || { x_fail=1; return 1; }; }
t_noenv || bad "no HEFESTO_LANE_CACHE: refused, naming setup (FR-002) — rc=$lc_rc err=$lc_err"
t_shape() { # the .. spelling points at a folder that exists and is writable, so only the shape check can refuse it
  mkdir -p "$lc_h/.cache/hefesto/ledger"
  LC_ENV="$lc_h/.cache/hefesto/lane-cache/$lc_key/../../ledger" lc_wrap "${LC_DIR:-}"
  { [ "$lc_rc" = 2 ] && [ ! -f "$lc_t/canary.env" ] && grep -qF 'not a lane cache path' <<<"$lc_err"; } || { x_fail=1; return 1; }; }
t_shape || bad "a lane cache path not of the exact shape (a .. spelling) is refused (FR-002) — rc=$lc_rc"
t_noprobe() { rmdir "$lc_pr" 2>/dev/null || { chmod 755 "$lc_pr"; rmdir "$lc_pr"; }; lc_wrap "${LC_DIR:-}"; mkdir -p "$lc_pr"; lc_sandboxed
  { [ "$lc_rc" = 2 ] && [ ! -f "$lc_t/canary.env" ] && grep -qF 'probe folder' <<<"$lc_err"; } || { x_fail=1; return 1; }; }
t_noprobe || bad "a missing probe folder is refused, never read as sandboxed (FR-002, NR-002) — rc=$lc_rc err=$lc_err"
t_ro() { chmod 555 "$lc_lc"; lc_wrap "${LC_DIR:-}"; chmod 700 "$lc_lc"; { [ "$lc_rc" = 2 ] && [ ! -f "$lc_t/canary.env" ] && grep -qF 'not writable' <<<"$lc_err"; } || { x_fail=1; return 1; }; }
t_ro || bad "a lane cache that is not writable in this sandbox is refused with the fix (FR-002) — rc=$lc_rc err=$lc_err"
lc_mut "the probe check dropped (NR-002)" 's/^if ( : > "\$PROBE\/.w.\$\$" ) 2>\/dev\/null; then/if false; then/' t_unsb
lc_mut "the env check dropped (FR-002)" 's/^  \*) refuse "no lane cache/  *) : "no lane cache/' t_noenv
lc_mut "the exact shape loosened (FR-002)" 's/\[0-9a-f\]{32}\$/.*$/' t_shape
lc_mut "the probe folder check dropped (NR-002)" 's/^\[ -d "\$PROBE" \] || refuse/true || refuse/' t_noprobe
lc_mut "the cache writability check dropped (FR-002)" 's/^( : > "\$LC\/.w.\$\$" ) 2>\/dev\/null \&\& rm -f "\$LC\/.w.\$\$" || refuse/true || refuse/' t_ro
[ "$x_fail" -eq 0 ] && ok "lane-build.sh: inside the sandbox every cache variable points into the lane cache, arguments and exit status unchanged; outside it, with no env, a .. path, no probe folder or an unwritable cache it refuses and runs nothing; 5 mutations caught (FR-001, FR-002, NR-001, NR-002)"


# --- FR-003 / FR-004 / FR-006 / NR-001 / NR-003 / NR-004: setup ------------------------------------------------------
head_ "hefesto-setup.sh --lanes: the lane cache in allowWrite, its path in env, never a cache variable or an allow rule (FR-003, FR-004, FR-006, NR-001, NR-003, NR-004)"
x_fail=0
lc_p="$lc_t/proj"; git init -q -b main "$lc_p"; lc_sh="$lc_t/sh"; mkdir -p "$lc_sh"
lc_su() { (cd "$lc_p" && HOME="$lc_sh" CLAUDE_CONFIG_DIR= bash "${LC_SU:-$REPO/hooks/hefesto-setup.sh}" "$@" 2>&1); }
lc_set() { jq -r "$1" "$lc_p/.claude/settings.local.json" 2>/dev/null; }
lc_aw() { jq -r --arg p "$1" '[.sandbox.filesystem.allowWrite[]? | select(. == $p)] | length' "$lc_p/.claude/settings.local.json" 2>/dev/null || echo 0; }   # $1 in allowWrite: 1, else 0
lc_o="$(lc_su --lanes)"; lc_rc=$?
lc_path="$(lc_set '.env.HEFESTO_LANE_CACHE // empty')"
{ [ "$lc_rc" = 0 ] && [[ "$lc_path" =~ ^$lc_sh/\.cache/hefesto/lane-cache/[0-9a-f]{32}$ ]] && [ -d "$lc_path" ] \
  && [ "$(stat -c %a "$lc_path" 2>/dev/null || stat -f %Lp "$lc_path")" = 700 ] && [ -d "$lc_sh/.cache/hefesto/lane-cache-probe" ] \
  && [ "$(lc_aw "$lc_path")" = 1 ]; } \
  || { bad "setup --lanes creates the lane cache (0700) and the probe folder, puts the cache in allowWrite and its path in env (FR-003) — rc=$lc_rc path='$lc_path' out=$(head -c 300 <<<"$lc_o")"; x_fail=1; }
t_novar() { # NR-003: no toolchain cache variable in the settings env; NR-001 on the process: a run without the wrapper sees none
  local f="${1:-$lc_p/.claude/settings.local.json}" e
  jq -e '.env // {} | keys | any(test("^(GOCACHE|GOMODCACHE|npm_config_cache|PIP_CACHE_DIR|XDG_CACHE_HOME|YARN_CACHE_FOLDER|BUN_INSTALL_CACHE_DIR)$"))' "$f" >/dev/null && { x_fail=1; return 1; }
  e="$(jq -r '.env // {} | to_entries[] | "\(.key)=\(.value)"' "$f" | tr '\n' '\0' | xargs -0 env -i "$lc_t/canary" >/dev/null 2>&1; cat "$lc_t/canary.env" 2>/dev/null)"
  grep -E '^(GOCACHE|npm_config_cache|XDG_CACHE_HOME|PIP_CACHE_DIR)=.*lane-cache' <<<"$e" >/dev/null && { x_fail=1; return 1; }
  return 0
}
t_novar || bad "setup writes no toolchain cache variable, so a process run without the wrapper sees none (NR-003, NR-001)"
t_noallow() { jq -e '[.permissions.allow[]?, .permissions.ask[]?] | any(test("lane-build"))' "${1:-$lc_p/.claude/settings.local.json}" >/dev/null && { x_fail=1; return 1; }; return 0; }
t_noallow || bad "setup writes no permission rule naming lane-build.sh (NR-004)"
lc_o="$(lc_su --lanes)"; grep -qF 'unchanged' <<<"$lc_o" || { bad "a second setup --lanes changes nothing (FR-003): $lc_o"; x_fail=1; }
lc_o="$(lc_su --lanes --allow-command "$REPO/hooks/lane-build.sh *")" && { bad "--allow-command naming lane-build.sh must be refused (FR-006, NR-004)"; x_fail=1; }
lc_o="$(lc_su --lanes --unsandboxed-command "$REPO/hooks/lane-build.sh make")" && { bad "--unsandboxed-command naming lane-build.sh must be refused (FR-006)"; x_fail=1; }
printf '#!/bin/sh\n' > "$lc_path/tool"; chmod +x "$lc_path/tool"
lc_o="$(lc_su --lanes --unsandboxed-command "$lc_path/tool")" && { bad "--unsandboxed-command under the lane cache must be refused (FR-006)"; x_fail=1; }
grep -qF 'sandboxed session can write' <<<"$lc_o" || { bad "the refusal says the lane cache is sandbox-writable (FR-006): $lc_o"; x_fail=1; }
lc_o="$(lc_su --check)"; grep -qF 'setup: ok' <<<"$lc_o" || { bad "--check passes after setup (FR-003): $lc_o"; x_fail=1; }
# The Bash tool runs --check SANDBOXED (it is no excluded command), where the probe folder is unwritable by design: that
# caller must pass. Only a caller that says it is unsandboxed (the session-start hook) has the write tested (#162 review).
chmod 555 "$lc_sh/.cache/hefesto/lane-cache-probe"; lc_o="$(lc_su --check)"; lc_rc=$?
{ [ "$lc_rc" = 0 ] && grep -qF 'setup: ok' <<<"$lc_o"; } || { bad "--check from a sandboxed caller passes with the probe folder unwritable (FR-003) — rc=$lc_rc: $lc_o"; x_fail=1; }
lc_o="$( (cd "$lc_p" && HOME="$lc_sh" CLAUDE_CONFIG_DIR='' HEFESTO_CHECK_UNSANDBOXED=1 bash "$REPO/hooks/hefesto-setup.sh" --check 2>&1) )"; lc_rc=$?
chmod 755 "$lc_sh/.cache/hefesto/lane-cache-probe"
{ [ "$lc_rc" -ne 0 ] && grep -qF 'probe folder this shell can write' <<<"$lc_o"; } || { bad "--check from an unsandboxed caller reports a probe folder it cannot write (FR-003) — rc=$lc_rc: $lc_o"; x_fail=1; }
grep -qF 'HEFESTO_CHECK_UNSANDBOXED=1 bash "$HROOT/hooks/hefesto-setup.sh" --check' "$REPO/hooks/session-start-context.sh" \
  || { bad "the session-start hook, which runs outside the sandbox, asks --check for the probe write (FR-003)"; x_fail=1; }
mv "$lc_sh/.cache/hefesto/lane-cache-probe" "$lc_sh/pr.bak"; lc_o="$(lc_su --check)"; lc_rc=$?; mv "$lc_sh/pr.bak" "$lc_sh/.cache/hefesto/lane-cache-probe"
{ [ "$lc_rc" -ne 0 ] && grep -qF 'probe folder' <<<"$lc_o"; } || { bad "--check reports a missing probe folder from any caller (FR-003) — rc=$lc_rc: $lc_o"; x_fail=1; }
lc_o="$(lc_su --remove)"
{ [ -z "$(lc_set '.env.HEFESTO_LANE_CACHE // empty')" ] && [ "$(lc_aw "$lc_path")" = 0 ] \
  && [ -d "$lc_path" ] && grep -qF "$lc_path" <<<"$lc_o"; } || { bad "--remove takes the env key and the allowWrite entry out, keeps the cache and names it (FR-003): $lc_o"; x_fail=1; }
lc_o="$(lc_su)"; [ -z "$(lc_set '.env.HEFESTO_LANE_CACHE // empty')" ] || { bad "a single-lane setup gets no lane cache (FR-003)"; x_fail=1; }
lc_su --remove >/dev/null
# mutants: setup writing GOCACHE into env, and an allow rule for the wrapper
lc_smut() { # label sed-expr test-fn — the mutant sits in the real hooks folder (setup refuses a clone in a temp folder)
  local m="$REPO/hooks/.smoke-mut-lc-setup.sh" red
  sed "$2" "$REPO/hooks/hefesto-setup.sh" > "$m"
  if cmp -s "$REPO/hooks/hefesto-setup.sh" "$m"; then bad "setup mutant did not apply: $1"; x_fail=1; rm -f "$m"; return; fi
  red="$(x_fail=0; LC_SU="$m" lc_su --lanes >/dev/null; "$3" >/dev/null 2>&1; echo "$x_fail")"
  [ "$red" = 1 ] || { bad "setup mutant survived: $1"; x_fail=1; }; LC_SU="$m" lc_su --remove >/dev/null; rm -f "$m"
}
lc_smut "a GOCACHE in the settings env (NR-003)" 's/HEFESTO_LANE_CACHE: \$lc}/HEFESTO_LANE_CACHE: $lc, GOCACHE: ($lc + "\/go-build")}/' t_novar
lc_smut "an allow rule for the wrapper (NR-004)" 's|"Bash(\$h/run-follow.sh:\*)")|"Bash($h/run-follow.sh:*)" "Bash($h/lane-build.sh:*)")|' t_noallow
[ "$x_fail" -eq 0 ] && ok "setup --lanes: the lane cache (0700) and the probe folder, the cache in allowWrite and its path in env, idempotent; no cache variable (on the JSON and on a process) and no allow rule for the wrapper; --allow-command and --unsandboxed-command refuse the wrapper and the cache; --check reports an unwritable probe; --remove undoes it and names the cache; 2 mutations caught (FR-003, FR-004, FR-006, NR-001, NR-003, NR-004)"


# --- FR-005 / NR-001: lane-guard — a command leaving the sandbox never reaches the wrapper or the cache ---------------
head_ "lane-guard: no command that leaves the sandbox may name lane-build.sh or the lane cache (FR-005, NR-001)"
x_fail=0
mkdir -p "$HOME/.cache/hefesto/sessions" "$lc_t/led/k/actions" "$HOME/.cache/hefesto/approvals/k"
jq -nc --arg h "$REPO/hooks" --arg l "$lc_t/led/k" '{title: "repo-deployer", role: "deploy", name: "repo-deployer", lanes: true, worker: false, ledger: $l,
  excluded: ["gh *", "\($h)/ledger.sh *", "/usr/bin/ssh debian@vm *"]}' > "$HOME/.cache/hefesto/sessions/sid-lc-dep-0001.json"
lc_gd() { # command [dangerouslyDisableSandbox] [hook] → deny | allow | none; the reason in $lc_t/why
  local o; o="$(jq -nc --arg c "$1" --argjson d "${2:-false}" --arg w "$lc_t" '{tool_name: "Bash", tool_input: {command: $c, dangerouslyDisableSandbox: $d}, session_id: "sid-lc-dep-0001", cwd: $w}' \
    | bash "${3:-$REPO/hooks/lane-guard.sh}" 2>/dev/null)"
  jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"$o" > "$lc_t/why" 2>/dev/null
  [ -n "$o" ] || { echo none; return; }; jq -r '.hookSpecificOutput.permissionDecision // "none"' <<<"$o" 2>/dev/null || echo none
}
lc_deny() { # label command [dds] [hook] — must be denied by the lane-cache rule
  local g; g="$(lc_gd "$2" "${3:-false}" "${4:-}")"
  { [ "$g" = deny ] && grep -qF 'lane build cache' "$lc_t/why"; } || { x_fail=1; [ -n "${4:-}" ] || bad "$1 — got $g: $(cat "$lc_t/why")"; return 1; }
}
# an approved action whose command names the wrapper: the grant must not open it
lc_a="$(jq -nc --arg c "/usr/bin/ssh debian@vm $REPO/hooks/lane-build.sh make" '{aid: "LC-1-A1", entry: "LC-1", to: "repo-deployer", status: "taken",
  taken_at: "2026-11-05T00:00:00Z", steps_done: [], scope: {title: "a build", steps: ["one"], commands: [$c], heads: {}}}')"
lc_ah="$(jq -cS '{entry, to, scope}' <<<"$lc_a" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-64)"
jq --arg h "$lc_ah" '.sha256 = $h' <<<"$lc_a" > "$lc_t/led/k/actions/LC-1-A1.json"
jq -nc --arg h "$lc_ah" '{sha256: $h, to: "repo-deployer", by: "Ana"}' > "$HOME/.cache/hefesto/approvals/k/LC-1-A1.json"
t_g1() { lc_deny "an excluded command naming lane-build.sh, approved action and all, is denied (FR-005)" "/usr/bin/ssh debian@vm $REPO/hooks/lane-build.sh make" false "${1:-}"; }
t_g2() { lc_deny "a sandbox-disabled retry naming the wrapper is denied (FR-005)" "$REPO/hooks/lane-build.sh make check" true "${1:-}"; }
t_g3() { lc_deny "an excluded command naming the cache by a relative path is denied (FR-005)" "gh gist create .cache/hefesto/lane-cache/$lc_key/x" false "${1:-}"; }
t_g4() { lc_deny "an excluded command naming the cache in capitals is denied (a case-insensitive volume, FR-005)" "gh gist create .cache/hefesto/LANE-CACHE/$lc_key/x" false "${1:-}"; }
t_g1; t_g2; t_g3; t_g4
lc_d="$(lc_gd "$REPO/hooks/lane-build.sh make check")"
[ "$lc_d" = deny ] && grep -qF 'lane build cache' "$lc_t/why" && { bad "a sandboxed wrapper call is not touched by the rule (FR-005): $(cat "$lc_t/why")"; x_fail=1; }
lc_gmut() { # label sed test-fn
  local md red; md="$(mktemp -d)"; for h in "$REPO"/hooks/*.sh; do ln -s "$h" "$md/$(basename "$h")"; done
  rm "$md/lane-guard.sh"; sed "$2" "$REPO/hooks/lane-guard.sh" > "$md/lane-guard.sh"
  if cmp -s "$REPO/hooks/lane-guard.sh" "$md/lane-guard.sh"; then bad "lane-guard mutant did not apply: $1"; x_fail=1; rm -rf "$md"; return; fi
  red="$(x_fail=0; "$3" "$md/lane-guard.sh" >/dev/null 2>&1; echo "$x_fail")"
  [ "$red" = 1 ] || { bad "lane-guard mutant survived: $1"; x_fail=1; }; rm -rf "$md"
}
lc_gmut "the exclusion branch dropped (FR-005)" 's/{ \[ -n "\$EXCL_HIT" \] || \[ "\$DDS" = true \]; }/[ "$DDS" = true ]/' t_g1
lc_gmut "the sandbox-disabled branch dropped (FR-005)" 's/{ \[ -n "\$EXCL_HIT" \] || \[ "\$DDS" = true \]; }/[ -n "$EXCL_HIT" ]/' t_g2
lc_gmut "the cache substring dropped (FR-005)" 's/ || "\$LCMD" == \*lane-cache\*//' t_g3
lc_gmut "the case folding dropped (FR-005)" 's/^LCMD="\$(printf .%s. "\$CMD" | tr .\[:upper:\]. .\[:lower:\].)"/LCMD="$CMD"/' t_g4
[ "$x_fail" -eq 0 ] && ok "lane-guard: an excluded command (approved action or not), a sandbox-disabled retry, and a relative spelling of the cache are denied when they name lane-build.sh or the lane cache; a sandboxed wrapper call is left alone; names matched in any case; 4 mutations caught (FR-005, NR-001)"


# --- FR-007: the lanes are told ---------------------------------------------------------------------------------------
head_ "The stage pass and the --prepare header name lane-build.sh (FR-007)"
x_fail=0
grep -qF 'hooks/lane-build.sh <command>' "$REPO/commands/hef.orchestrate.md" || { bad "hef.orchestrate.md's stage pass names lane-build.sh (FR-007)"; x_fail=1; }
grep -qF 'lane-build.sh <command> (the sandbox makes the usual caches read-only)' "$REPO/hooks/session-launch.sh" || { bad "the --prepare header names lane-build.sh (FR-007)"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "the stage pass and the interactive --prepare header tell the lane to build and test through lane-build.sh (FR-007)"

chmod -R u+w "$lc_t" 2>/dev/null; rm -rf -- "${lc_t:?}"
