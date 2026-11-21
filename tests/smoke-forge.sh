# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs and sed expressions are single-quoted on purpose
# shellcheck disable=SC1090  # forge-lib.sh, or a mutant of it, is sourced through FG_LIB on purpose
#
# forge-setup smoke checks, part 14: setup configures the forge for the workers once — the forge hosts in
# orchestrate.allowed_domains, the HTTPS push rewrite for an SSH remote, the stale config.lock report — and an
# infrastructure outcome becomes a stall whose reason is a fixed fix line (HEF-22; forge-setup FR-001..FR-017,
# SC-001..SC-006).
#
# SOURCED by tests/smoke.sh, never run on its own. Self-contained: temp repositories with fixture remotes, a fake HOME
# for setup (the lc_su pattern of part 9), the library called directly, the ledger and the launcher's lane
# --prepare/--finish path driven with fixture outcomes (no model — constitution 3: assertions sit on git config, the
# board config and the ledger JSON the scripts wrote). Every guard has a mutant, by one of three routes:
#   * library guards: the lib is sed-ed into a temp file and sourced in a subshell, then the function is called;
#   * setup guards: a mutated copy of hefesto-setup.sh inside the real hooks folder (setup refuses a temp-folder root);
#   * ledger/launcher guards: a temp folder of links to every hook, with the one mutated file replaced (pr_mirror).
# Each keeps the "mutant did not apply" cmp guard.

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-forge.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_)"
  else echo "tests/smoke-forge.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

fg_t="$(cd "$(mktemp -d)" && pwd -P)"
fg_git() { git -c user.email=t@t -c user.name=t "$@"; }
fg_lmut() { # label sed-expr test-fn — a mutant of forge-lib.sh, sourced by test-fn through FG_LIB, must turn it red
  local m="$fg_t/forge-lib.mut.sh" red
  sed "$2" "$REPO/hooks/forge-lib.sh" > "$m"
  if cmp -s "$REPO/hooks/forge-lib.sh" "$m"; then bad "library mutant did not apply: $1"; x_fail=1; return; fi
  red="$(x_fail=0; FG_LIB="$m" "$3" >/dev/null 2>&1; echo "$x_fail")"
  [ "$red" = 1 ] || { bad "library mutant survived: $1"; x_fail=1; }
}

# --- FR-001 / FR-002 / FR-008 / FR-013: the library ------------------------------------------------------------------
head_ "forge-lib.sh: hostname rule, forge hosts, remote → host and SSH prefix, stale lock, fix table (FR-001, FR-002, FR-008, FR-013)"
x_fail=0
fg_lib_hosts() { # forge-setup/FR-002
  . "${FG_LIB:-$REPO/hooks/forge-lib.sh}"
  local h
  for h in github.com '*.npmjs.org' gitlab.example.org registry.npmjs.org:443; do forge_public_host "$h" || { bad "FR-002 forge_public_host must accept '$h'"; x_fail=1; }; done
  # DNS is case-insensitive: an upper-case internal name is the same host (verify gate 2026-11-14)
  for h in 10.0.0.5 localhost metadata.google.internal host.docker.internal printer.local github.com:70000 'https://github.com' github.com/o '' \
    metadata.google.INTERNAL a.LOCAL LocalHost Host.Docker.Internal; do
    forge_public_host "$h" && { bad "FR-002 forge_public_host must refuse '$h'"; x_fail=1; }; done
  [ "$(forge_domains github.com | tr '\n' ' ')" = "github.com api.github.com " ] || { bad "FR-002 github.com → github.com, api.github.com (D3)"; x_fail=1; }
  [ "$(forge_domains gitlab.example.org)" = gitlab.example.org ] || { bad "FR-002 a self-hosted forge → that host alone (D3)"; x_fail=1; }
  [ "$(forge_https_form github.com git@github.com:o/r.git) $(forge_https_form github.com ssh://git@github.com/o/r.git)" = "https://github.com/o/r.git https://github.com/o/r.git" ] \
    || { bad "FR-005 forge_https_form: both SSH spellings → https://github.com/o/r.git"; x_fail=1; }
  [ "$(forge_domains GitHub.com | tr '\n' ' ')" = "github.com api.github.com " ] || { bad "FR-002 GitHub.com is github.com: both hosts, lowercased (D3)"; x_fail=1; }
  return 0
}
fg_lib_urls() { # forge-setup/FR-001
  . "${FG_LIB:-$REPO/hooks/forge-lib.sh}"
  local u w r rc
  while IFS='|' read -r u w; do
    r="$(forge_host "$u")" || r="<1>"; [ "$r" = "$w" ] || { bad "FR-001 forge_host '$u' → '$w' (got '$r')"; x_fail=1; }
  done <<'EOF'
git@github.com:o/r.git|github.com
ssh://git@github.com/o/r.git|github.com
ssh://git@gitlab.example.org:2222/o/r.git|gitlab.example.org
ssh://deploy@host.example.com/o/r.git|host.example.com
https://github.com/o/r.git|github.com
https://user@gitlab.example.org:8443/o/r.git|gitlab.example.org
git@10.0.0.5:o/r.git|10.0.0.5
/srv/git/r.git|<1>
EOF
  while IFS='|' read -r u w; do
    rc=0; r="$(forge_ssh_prefix "$u")" || rc=$?; r="$rc:$(printf '%s' "$r" | tr '\t' '>')"
    [ "$r" = "$w" ] || { bad "FR-001 forge_ssh_prefix '$u' → '$w' (got '$r')"; x_fail=1; }
  done <<'EOF'
git@github.com:o/r.git|0:github.com>git@github.com:
ssh://git@github.com/o/r.git|0:github.com>ssh://git@github.com/
ssh://git@gitlab.example.org:2222/o/r.git|2:
ssh://deploy@host.example.com/o/r.git|2:
https://github.com/o/r.git|1:
/srv/git/r.git|1:
EOF
  # D4: pushurl before url; exactly "origin", else the only remote; several without origin → none
  w="$fg_t/remotes"; rm -rf "$w"; git init -q "$w"
  forge_remote_url "$w" >/dev/null && { bad "FR-001 no remote → forge_remote_url returns 1"; x_fail=1; }
  git -C "$w" remote add up git@up.example.com:o/r.git
  [ "$(forge_remote_url "$w")" = git@up.example.com:o/r.git ] || { bad "FR-001 the only remote (not origin) is used"; x_fail=1; }
  git -C "$w" remote add origin2 git@o2.example.com:o/r.git
  forge_remote_url "$w" >/dev/null && { bad "FR-001 two remotes, none exactly 'origin' (origin2 is not origin) → 1"; x_fail=1; }
  git -C "$w" remote add origin https://github.com/o/r.git
  [ "$(forge_remote_url "$w")" = https://github.com/o/r.git ] || { bad "FR-001 origin wins among several remotes"; x_fail=1; }
  git -C "$w" config remote.origin.pushurl git@github.com:o/r.git
  [ "$(forge_remote_url "$w")" = git@github.com:o/r.git ] || { bad "FR-001 remote.origin.pushurl comes before remote.origin.url"; x_fail=1; }
  return 0
}
fg_lib_lock() { # forge-setup/FR-008
  . "${FG_LIB:-$REPO/hooks/forge-lib.sh}"
  local d="$fg_t/lockdir"; rm -rf "$d"; mkdir -p "$d"
  forge_stale_lock "$d" >/dev/null && { bad "FR-008 no lock → nothing reported"; x_fail=1; }
  : > "$d/config.lock"
  forge_stale_lock "$d" >/dev/null && { bad "FR-008 a zero-byte lock younger than 60 s is not stale (D7)"; x_fail=1; }
  touch -t 202601010000 "$d/config.lock"
  [ "$(forge_stale_lock "$d")" = "$d/config.lock" ] || { bad "FR-008 a zero-byte lock older than 60 s is reported with its path (D7)"; x_fail=1; }
  printf 'x' > "$d/config.lock"; touch -t 202601010000 "$d/config.lock"
  forge_stale_lock "$d" >/dev/null && { bad "FR-008 a non-empty lock is never stale, whatever its age (D7)"; x_fail=1; }
  return 0
}
fg_lib_fix() { # forge-setup/FR-013
  . "${FG_LIB:-$REPO/hooks/forge-lib.sh}"
  local o rc
  o="$(forge_infra_fix push-refused /h /c/ps.json "")"; [ "$o" = "run in a terminal: bash /h/hefesto-setup.sh (it sets the HTTPS push rewrite and the forge hosts)" ] || { bad "FR-013 push-refused → run setup in a terminal (got '$o')"; x_fail=1; }
  o="$(forge_infra_fix credential-helper-missing /h /c/ps.json "")"; [ "$o" = "run in a terminal: gh auth setup-git" ] || { bad "FR-013 credential-helper-missing → gh auth setup-git (got '$o')"; x_fail=1; }
  o="$(forge_infra_fix host-denied /h /c/ps.json pypi.org)"
  grep -qF 'the worker reports it was denied pypi.org — if the run log confirms' <<<"$o" && grep -qF 'orchestrate.allowed_domains in /c/ps.json' <<<"$o" \
    || { bad "FR-013 host-denied names the host as the worker's claim ('reports'), never a bare 'add' (P6; got '$o')"; x_fail=1; }
  o="$(forge_infra_fix host-denied /h /c/ps.json "")"; grep -qF 'find the denied host in the run log' <<<"$o" || { bad "FR-014 host-denied without a valid host points to the run log (got '$o')"; x_fail=1; }
  rc=0; o="$(forge_infra_fix not-a-cause /h /c "")" || rc=$?
  { [ "$rc" = 1 ] && [ -z "$o" ]; } || { bad "FR-013 an unknown cause returns 1 with no line (constitution 5; rc=$rc out='$o')"; x_fail=1; }
  return 0
}
fg_lib_hosts; fg_lib_urls; fg_lib_lock; fg_lib_fix
fg_lmut "the deny list matched case-sensitively again (FR-002)" 's/local lc; lc="\$(printf .%s. "\$1" | tr .\[:upper:\]. .\[:lower:\].)"/local lc="$1"/' fg_lib_hosts
fg_lmut "the zero-byte test dropped (D7)" 's/\[ -f "\$l" \] && \[ ! -s "\$l" \] || return 1/[ -f "$l" ] || return 1/' fg_lib_lock
fg_lmut "the age test dropped (D7)" 's/-gt 60 \] || return 1/-gt -1 ] || return 1/' fg_lib_lock
fg_lmut "the explicit-port arm dropped (D5)" '/git@\*:\*) return 2 ;;/d' fg_lib_urls
fg_lmut "the host-denied line loses 'reports' (P6)" 's/the worker reports it was denied \$4/add $4/' fg_lib_fix
fg_lmut "forge_infra_fix's unknown cause answers at exit 0 (constitution 5)" '/^forge_infra_fix/,/^}/s/^    \*) return 1 ;;$/    *) echo "" ;;/' fg_lib_fix
fg_lmut "the internal-suffix refusal dropped (FR-002)" 's/^  \[\[ ! "\$lc" =~ (^|\\.)(localhost.*$/  true/' fg_lib_hosts
[ "$x_fail" -eq 0 ] && ok "forge-lib.sh: the public-hostname rule, the D3 hosts, remote → host and SSH prefix (pushurl first, exact origin, codes 0/1/2), the stale lock (zero bytes and > 60 s), the fix table (P6 'reports', unknown → 1); 6 mutations caught (FR-001, FR-002, FR-008, FR-013)"

# --- FR-001..FR-007 / FR-010 / SC-001: setup's forge pass -------------------------------------------------------------
head_ "hefesto-setup.sh: the forge hosts in allowed_domains (only when absent, only in jq form), the push rewrite for an SSH remote, the stale-lock pre-check (FR-001..FR-007, FR-010, SC-001)"
x_fail=0
fg_h="$fg_t/home"; mkdir -p "$fg_h"
fg_noenv() { local v; for v in $(env | sed -n 's/^\(GIT_CONFIG_[A-Z_0-9]*\)=.*/\1/p'); do unset "$v"; done; }
fg_su() { # repo args… — setup as a person runs it in a terminal: a fake HOME, no system git config, no lane env
  local d="$1"; shift
  (cd "$d" && fg_noenv && env -u HEFESTO_TRUSTED_TOP -u HEFESTO_TRUSTED_BOARD -u HEFESTO_WORKER -u HEFESTO_LANES -u HEFESTO_LANE_MAP -u XDG_CONFIG_HOME \
    HOME="$fg_h" CLAUDE_CONFIG_DIR='' GIT_CONFIG_NOSYSTEM=1 bash "${FG_SU:-$REPO/hooks/hefesto-setup.sh}" "$@" 2>&1)
}
FG_BCFG='{"source":"tasks-repo","root":"tasks","orchestrate":{"decider":"t","usd_cap":5}}'
fg_proj() { # name remote-url [board-config-json] → a fresh repository with that origin and a jq-formatted board config
  local p="$fg_t/p-$1"; rm -rf "$p"; git init -q -b main "$p"; mkdir -p "$p/.claude"
  [ -z "$2" ] || git -C "$p" remote add origin "$2"
  jq . <<<"${3:-$FG_BCFG}" > "$p/.claude/project-status.json"
  printf '%s\n' "$p"
}
fg_rw_of() { git -C "$1" config --get-all "url.https://$2/.pushinsteadof" 2>/dev/null | tr '\n' ' '; }   # repo host → values
fg_ad() { jq -c '.orchestrate.allowed_domains // "absent"' "$1/.claude/project-status.json"; }
fg_norw() { [ -z "$(git -C "$1" config --get-regexp 'pushinsteadof' 2>/dev/null)" ]; }   # repo → 0 when no rewrite at all
fg_case_scp() { # forge-setup/FR-001 FR-002 FR-003 FR-005 FR-007 US1 US2
  local p o
  p="$(fg_proj scp git@github.com:o/r.git)"; cp "$p/.claude/project-status.json" "$fg_t/before.json"
  o="$(fg_su "$p")" || { bad "FR-003 setup on an SSH github remote must pass: $o"; x_fail=1; }
  [ "$(fg_rw_of "$p" github.com)" = "git@github.com: " ] || { bad "FR-005 scp SSH → url.https://github.com/.pushinsteadof git@github.com: (got '$(fg_rw_of "$p" github.com)')"; x_fail=1; }
  [ "$(fg_ad "$p")" = '["github.com","api.github.com"]' ] || { bad "FR-003 allowed_domains written as github.com, api.github.com (got $(fg_ad "$p"))"; x_fail=1; }
  [ "$(jq -S 'del(.orchestrate.allowed_domains)' "$p/.claude/project-status.json")" = "$(jq -S . "$fg_t/before.json")" ] || { bad "FR-003 every other board key unchanged"; x_fail=1; }
  grep -qF 'changed a tracked file: commit it' <<<"$o" && grep -qF 'forge: push over HTTPS: url."https://github.com/".pushInsteadOf git@github.com:' <<<"$o" \
    || { bad "FR-003 FR-005 setup says it changed a tracked file and prints the rewrite: $o"; x_fail=1; }
  jq -e --arg r "$p/.git" '.env.HEFESTO_SETUP_EXTRA | fromjson | .push_rewrites == [{"repo": $r, "key": "url.https://github.com/.pushinsteadof", "value": "git@github.com:"}]' "$p/.claude/settings.local.json" >/dev/null \
    || { bad "FR-007 the rewrite setup added is recorded in env.HEFESTO_SETUP_EXTRA.push_rewrites (P8): $(jq -r '.env.HEFESTO_SETUP_EXTRA' "$p/.claude/settings.local.json" 2>&1 | head -c 300)"; x_fail=1; }
  cp "$p/.claude/project-status.json" "$fg_t/after1.json"
  o="$(fg_su "$p")"
  { [ "$(fg_rw_of "$p" github.com)" = "git@github.com: " ] && cmp -s "$fg_t/after1.json" "$p/.claude/project-status.json" && grep -qF 'already lists' <<<"$o" && grep -qF 'unchanged' <<<"$o"; } \
    || { bad "FR-005 SC-001 a second run adds no duplicate value, leaves the board config and says so: $o"; x_fail=1; }
  jq -e '.env.HEFESTO_SETUP_EXTRA | fromjson | .push_rewrites | length == 1' "$p/.claude/settings.local.json" >/dev/null || { bad "FR-007 a second run that adds nothing still records the first run's rewrite (P8)"; x_fail=1; }
  git -C "$p" config --add url.https://github.com/.pushinsteadof git@gh-alias:
  o="$(fg_su "$p" --remove)"
  { [ "$(fg_rw_of "$p" github.com)" = "git@gh-alias: " ] && grep -qF 'removed the push rewrite' <<<"$o" && grep -qF 'allowed_domains' <<<"$o" && [ "$(fg_ad "$p")" != '"absent"' ]; } \
    || { bad "FR-007 --remove unsets only the recorded rewrite (a hand-added one stays) and leaves allowed_domains with a note: $o"; x_fail=1; }
  return 0
}
fg_case_forms() { # forge-setup/FR-001 FR-002 FR-005 FR-006 SC-001: ssh://, a port, another user, HTTPS, self-hosted, an IP
  local p o
  p="$(fg_proj sshurl ssh://git@github.com/o/r.git)"; o="$(fg_su "$p")"
  [ "$(fg_rw_of "$p" github.com)" = "ssh://git@github.com/ " ] || { bad "FR-005 ssh://git@github.com/ is the rewritten form (got '$(fg_rw_of "$p" github.com)')"; x_fail=1; }
  grep -qF 'auth setup-git' <<<"$o" || { bad "FR-006 no credential helper for https://github.com/ → the setup-git hint: $o"; x_fail=1; }
  p="$(fg_proj helper git@github.com:o/r.git)"; git -C "$p" config credential.helper store; o="$(fg_su "$p")"
  grep -qF 'auth setup-git' <<<"$o" && { bad "FR-006 with a credential helper there is no hint: $o"; x_fail=1; }
  p="$(fg_proj port ssh://git@gitlab.example.org:2222/o/r.git)"; o="$(fg_su "$p")"
  { fg_norw "$p" && grep -qF 'explicit port' <<<"$o" && [ "$(fg_ad "$p")" = '["gitlab.example.org"]' ]; } \
    || { bad "FR-005 ssh:// with a port: no rewrite, the reason printed, the host still listed: $o"; x_fail=1; }
  p="$(fg_proj user ssh://deploy@host.example.com/o/r.git)"; o="$(fg_su "$p")"
  { fg_norw "$p" && grep -qF 'a user other than git' <<<"$o"; } || { bad "FR-005 ssh://deploy@host/: no rewrite, the reason printed: $o"; x_fail=1; }
  p="$(fg_proj https https://github.com/o/r.git)"; o="$(fg_su "$p")"
  { fg_norw "$p" && ! grep -qF 'push over HTTPS' <<<"$o" && [ "$(fg_ad "$p")" = '["github.com","api.github.com"]' ]; } \
    || { bad "FR-005 an HTTPS remote: no rewrite and no message about it, the hosts written: $o"; x_fail=1; }
  p="$(fg_proj self git@gitlab.example.org:o/r.git)"; o="$(fg_su "$p")"
  { [ "$(fg_ad "$p")" = '["gitlab.example.org"]' ] && [ "$(fg_rw_of "$p" gitlab.example.org)" = "git@gitlab.example.org: " ]; } || { bad "FR-002 a self-hosted forge → [gitlab.example.org] and its rewrite: $o"; x_fail=1; }
  p="$(fg_proj ip git@10.0.0.5:o/r.git)"; cp "$p/.claude/project-status.json" "$fg_t/ip.json"; o="$(fg_su "$p")"
  { cmp -s "$fg_t/ip.json" "$p/.claude/project-status.json" && fg_norw "$p" && grep -qF "'10.0.0.5' is not a public hostname" <<<"$o"; } \
    || { bad "FR-002 an IP remote: nothing written, the host named with why: $o"; x_fail=1; }
  return 0
}
fg_case_keys() { # forge-setup/FR-003 FR-004 FR-007 (D2, P3): a present key and a hand-formatted file stay byte-identical
  local p o
  p="$(fg_proj key git@github.com:o/r.git '{"orchestrate":{"decider":"t","allowed_domains":["registry.npmjs.org"]}}')"; cp "$p/.claude/project-status.json" "$fg_t/key.json"; o="$(fg_su "$p")"
  { cmp -s "$fg_t/key.json" "$p/.claude/project-status.json" && grep -qF 'lacks github.com api.github.com' <<<"$o"; } || { bad "FR-004 a present key is left byte-identical, the missing forge hosts named: $o"; x_fail=1; }
  p="$(fg_proj hand git@github.com:o/r.git)"; printf '{"source": "tasks-repo", "orchestrate": {"decider": "t", "lanes": ["a", "b"]}}\n' > "$p/.claude/project-status.json"
  cp "$p/.claude/project-status.json" "$fg_t/hand.json"; o="$(fg_su "$p")"
  { cmp -s "$fg_t/hand.json" "$p/.claude/project-status.json" && grep -qF 'is hand-formatted' <<<"$o" && grep -qF '"allowed_domains": ["github.com", "api.github.com"]' <<<"$o"; } \
    || { bad "FR-003 a hand-formatted board config is left byte-identical and the exact snippet printed (P3): $o"; x_fail=1; }
  p="$(fg_proj print git@github.com:o/r.git)"; cp "$p/.claude/project-status.json" "$fg_t/print.json"; o="$(fg_su "$p" --print)"
  { cmp -s "$fg_t/print.json" "$p/.claude/project-status.json" && [ -z "$(fg_rw_of "$p" github.com)" ] && [ ! -f "$p/.claude/settings.local.json" ] \
    && grep -qF 'forge: would set push over HTTPS' <<<"$o" && grep -qF 'forge: would write github.com api.github.com' <<<"$o"; } \
    || { bad "FR-007 --print reports the forge changes with 'would' and writes nothing: $o"; x_fail=1; }
  return 0
}
fg_case_lock() { # forge-setup/FR-010 US2: a stale lock where a rewrite is due → nothing written, the path and rm, non-zero
  local p o rc=0
  p="$(fg_proj lock git@github.com:o/r.git)"; : > "$p/.git/config.lock"; touch -t 202601010000 "$p/.git/config.lock"; cp "$p/.claude/project-status.json" "$fg_t/lock.json"
  o="$(fg_su "$p")" || rc=$?
  { [ "$rc" != 0 ] && grep -qF "rm $p/.git/config.lock" <<<"$o" && grep -qF 'nothing was written' <<<"$o" && [ -f "$p/.git/config.lock" ] \
    && [ ! -f "$p/.claude/settings.local.json" ] && cmp -s "$fg_t/lock.json" "$p/.claude/project-status.json" && fg_norw "$p"; } \
    || { bad "FR-010 a stale config.lock stops setup before any write, names the path and rm, keeps the lock (rc=$rc): $o"; x_fail=1; }
  return 0
}
fg_case_external() { # forge-setup/FR-001 FR-008 FR-010: an external board, two repos on github.com, a lock in the one with no write due
  local b="$fg_t/ext" o
  rm -rf "$b"; mkdir -p "$b"; git init -q -b main "$b/board"; git init -q -b main "$b/api"; git init -q -b main "$b/ui"
  git -C "$b/api" remote add origin git@github.com:o/api.git; git -C "$b/ui" remote add origin git@github.com:o/ui.git
  git -C "$b/api" config --add url.https://github.com/.pushinsteadof git@github.com:
  : > "$b/api/.git/config.lock"; touch -t 202601010000 "$b/api/.git/config.lock"
  mkdir -p "$b/board/.claude"; jq . <<<'{"source":"tasks-repo","root":"tasks","repos":{"api":"../api","ui":"../ui"},"orchestrate":{"decider":"t"}}' > "$b/board/.claude/project-status.json"
  o="$(fg_su "$b/board")" || { bad "FR-010 a lock in a repository with no write due does not stop setup: $o"; x_fail=1; }
  { [ "$(jq -c .orchestrate.allowed_domains "$b/board/.claude/project-status.json")" = '["github.com","api.github.com"]' ] \
    && [ "$(fg_rw_of "$b/ui" github.com)" = "git@github.com: " ] && grep -qF "a stale $b/api/.git/config.lock" <<<"$o"; } \
    || { bad "FR-001 the repos map: github.com listed once, ui's rewrite written, api's lock reported: $o"; x_fail=1; }
  o="$(HEFESTO_CHECK_UNSANDBOXED=1 fg_su "$b/board" --check)"
  grep -qF "rm $b/api/.git/config.lock" <<<"$(tail -1 <<<"$o")" || { bad "FR-008 --check names the repos map repository's stale lock in its last line: $(tail -1 <<<"$o")"; x_fail=1; }
  return 0
}
fg_case_scp; fg_case_forms; fg_case_keys; fg_case_lock; fg_case_external
fg_case_livelock() { # forge-setup/FR-007 FR-010 (verify gate 2026-11-14): a rewrite git could not write is never recorded as setup's
  local p o rc=0
  # a live lock (not zero bytes, so the stale-lock pre-check lets setup through): the rewrite write fails
  p="$(fg_proj live git@github.com:o/r.git)"; printf 'x' > "$p/.git/config.lock"
  o="$(fg_su "$p")" || rc=$?
  rm -f "$p/.git/config.lock"
  { [ "$rc" != 0 ] && grep -qF 'could not write the push rewrite' <<<"$o" && fg_norw "$p"; } \
    || { bad "FR-010 a live config.lock fails the rewrite and setup says so (rc=$rc): $o"; x_fail=1; }
  [ ! -f "$p/.claude/settings.local.json" ] \
    || jq -e '(.env.HEFESTO_SETUP_EXTRA // "{}") | fromjson | (.push_rewrites // []) | length == 0' "$p/.claude/settings.local.json" >/dev/null \
    || { bad "FR-007 a rewrite whose write failed must not be recorded in push_rewrites: $(jq -r '.env.HEFESTO_SETUP_EXTRA' "$p/.claude/settings.local.json" 2>&1 | head -c 300)"; x_fail=1; }
  # the person then adds the same value by hand: --remove must leave it (it was never setup's)
  git -C "$p" config --add url.https://github.com/.pushinsteadof git@github.com:
  o="$(fg_su "$p" --remove)"
  [ "$(fg_rw_of "$p" github.com)" = "git@github.com: " ] || { bad "FR-007 --remove deleted a hand-added rewrite setup never wrote: $o"; x_fail=1; }
  return 0
}
fg_case_livelock   # called here, after its definition (it ran only as a mutant before: SC2218)
fg_case_dup() { # forge-setup/FR-005 (verify gate 2026-11-14): a board whose repos map lists the board repository itself and a
  # linked worktree of a code repository — each git config is planned once, so each rewrite is added once
  local b="$fg_t/dup" o
  rm -rf "$b"; mkdir -p "$b"; git init -q -b main "$b/board"; git init -q -b main "$b/api"
  git -C "$b/board" remote add origin git@github.com:o/board.git; git -C "$b/api" remote add origin git@github.com:o/api.git
  git -C "$b/api" commit -q --allow-empty -m init; git -C "$b/api" worktree add -q "$b/api-wt" -b wt 2>/dev/null
  mkdir -p "$b/board/.claude"
  jq . <<<'{"source":"tasks-repo","root":"tasks","repos":{"self":".","api":"../api","apiwt":"../api-wt"},"orchestrate":{"decider":"t"}}' > "$b/board/.claude/project-status.json"
  o="$(fg_su "$b/board")" || { bad "FR-005 setup on a board that lists itself must pass: $o"; x_fail=1; }
  { [ "$(fg_rw_of "$b/board" github.com)" = "git@github.com: " ] && [ "$(fg_rw_of "$b/api" github.com)" = "git@github.com: " ] \
    && [ "$(grep -c 'pushInsteadOf git@github.com: (in' <<<"$o")" = 2 ]; } \
    || { bad "FR-005 each git config gets its rewrite once (board listed in its own map, a linked worktree of api): board '$(fg_rw_of "$b/board" github.com)' api '$(fg_rw_of "$b/api" github.com)': $o"; x_fail=1; }
  return 0
}
fg_case_dup
fg_case_pushurl() { # forge-setup/FR-005 FR-009 (verify gate 2026-11-14): an explicit SSH push URL takes no pushInsteadOf (git
  # documents it), so setup writes no rewrite there, names the set-url fix, and --check counts it as missing
  local p o rc=0
  p="$(fg_proj pushurl git@github.com:o/r.git)"; git -C "$p" config remote.origin.pushurl git@github.com:o/r.git
  o="$(fg_su "$p")" || { bad "FR-005 setup with an explicit SSH push URL must still pass (a note, not a failure): $o"; x_fail=1; }
  { fg_norw "$p" && grep -qF "remote set-url --push origin https://github.com/o/r.git" <<<"$o" && ! grep -qF 'forge: push over HTTPS' <<<"$o"; } \
    || { bad "FR-005 an explicit SSH push URL: no useless rewrite, and the set-url fix named: $o"; x_fail=1; }
  o="$(HEFESTO_CHECK_UNSANDBOXED=1 fg_su "$p" --check)" || rc=$?
  { [ "$rc" != 0 ] && grep -qF 'an HTTPS push URL' <<<"$(tail -1 <<<"$o")"; } \
    || { bad "FR-009 --check counts an explicit SSH push URL as missing (rc=$rc): $(tail -1 <<<"$o")"; x_fail=1; }
  return 0
}
fg_case_pushurl
fg_smut() { # label sed-expr test-fn — the setup mutant sits in the real hooks folder (setup refuses a clone in a temp folder)
  local m="$REPO/hooks/.smoke-mut-fg-setup.sh" red
  sed "$2" "$REPO/hooks/hefesto-setup.sh" > "$m"
  if cmp -s "$REPO/hooks/hefesto-setup.sh" "$m"; then bad "setup mutant did not apply: $1"; x_fail=1; rm -f "$m"; return; fi
  red="$(trap 'rm -f "$m"' EXIT; x_fail=0; FG_SU="$m" "$3" >/dev/null 2>&1; echo "$x_fail")"; rm -f "$m"
  [ "$red" = 1 ] || { bad "setup mutant survived: $1"; x_fail=1; }
}
fg_smut "unless set: a present allowed_domains read as absent (D2)" 's/type == "object" and has("allowed_domains")'"'"' "\$BCFG" >\/dev\/null 2>&1; then echo present/type == "object" and has("x")'"'"' "$BCFG" >\/dev\/null 2>\&1; then echo present/' fg_case_keys
fg_smut "the byte-identical jq-form test dropped (P3)" 's/ && jq \. "\$BCFG" 2>\/dev\/null | cmp -s - "\$BCFG"$/ \&\& true/' fg_case_keys
fg_smut "a failed rewrite left in push_rewrites (FR-007, verify gate 2026-11-14)" 's/|| forge_unrecord "\${gone\[@\]}" ||/|| true ||/' fg_case_livelock
fg_smut "an explicit SSH push URL rewritten anyway (FR-005, verify gate 2026-11-14)" 's/^    if \[ -n "\$(git -C "\$r" config --get "remote\.\$(forge_remote_name "\$r")\.pushurl" 2>\/dev\/null)" \]; then$/    if false; then/' fg_case_pushurl
fg_smut "the same git config planned twice (FR-005, verify gate 2026-11-14)" '/case "\$seen" in \*/d' fg_case_dup
fg_smut "the rewrite dedupe dropped (FR-005)" '/that exact value is set already (FR-005)/d' fg_case_scp
fg_smut "the pre-check widened to every repository's lock (FR-010)" 's/ && fg_lock+=("\$l")  / \&\& fg_lock+=("$l") \&\& fg_block+=("$l")  /' fg_case_external
[ "$x_fail" -eq 0 ] && ok "setup: SSH github → the push rewrite and [github.com, api.github.com], recorded, idempotent, removable (a hand-added rewrite stays); ssh:// rewritten; a port or another user noted; HTTPS untouched; self-hosted; an IP refused; a present key and a hand-formatted file byte-identical; --print writes nothing; a stale lock stops a due write; an external board lists github.com once; 4 mutations caught (FR-001..FR-007, FR-010, SC-001)"

# --- FR-008 / FR-009 / SC-002: --check -----------------------------------------------------------------------------
head_ "hefesto-setup.sh --check: a stale config.lock and the missing forge setup inside the one missing line; never a write (FR-008, FR-009, SC-002)"
x_fail=0
fg_case_check() { # forge-setup/FR-008 FR-009 US3 SC-002
  local p o rc
  p="$(fg_proj chk https://github.com/o/r.git)"; fg_su "$p" >/dev/null   # set up: hosts written, no rewrite due (HTTPS)
  rc=0; o="$(HEFESTO_CHECK_UNSANDBOXED=1 fg_su "$p" --check)" || rc=$?
  { [ "$rc" = 0 ] && grep -qF 'setup: ok' <<<"$o"; } || { bad "FR-009 --check passes once the forge is set up (rc=$rc): $o"; x_fail=1; }
  : > "$p/.git/config.lock"; touch -t 202601010000 "$p/.git/config.lock"; cp "$p/.claude/settings.local.json" "$fg_t/chk.json"
  rc=0; o="$(HEFESTO_CHECK_UNSANDBOXED=1 fg_su "$p" --check)" || rc=$?
  { [ "$rc" = 1 ] && grep -qF "a stale $p/.git/config.lock (zero bytes, left by a sandboxed session — rm $p/.git/config.lock)" <<<"$(tail -1 <<<"$o")" \
    && [ -f "$p/.git/config.lock" ] && cmp -s "$fg_t/chk.json" "$p/.claude/settings.local.json"; } \
    || { bad "SC-002 FR-008 a stale lock: exit 1, the path and rm in the last line, the lock kept, nothing written (rc=$rc): $o"; x_fail=1; }
  : > "$p/.git/config.lock"; rc=0; o="$(HEFESTO_CHECK_UNSANDBOXED=1 fg_su "$p" --check)" || rc=$?
  [ "$rc" = 0 ] || { bad "SC-002 a young zero-byte lock is not reported (rc=$rc): $o"; x_fail=1; }
  printf 'x' > "$p/.git/config.lock"; touch -t 202601010000 "$p/.git/config.lock"; rc=0; o="$(HEFESTO_CHECK_UNSANDBOXED=1 fg_su "$p" --check)" || rc=$?
  [ "$rc" = 0 ] || { bad "SC-002 a non-empty lock is not reported (rc=$rc): $o"; x_fail=1; }
  rm -f "$p/.git/config.lock"
  git -C "$p" remote set-url origin git@github.com:o/r.git; rc=0; o="$(fg_su "$p" --check)" || rc=$?
  { [ "$rc" = 1 ] && grep -qF 'the HTTPS push rewrite for' <<<"$(tail -1 <<<"$o")" && grep -qF 'hefesto-setup.sh' <<<"$(tail -1 <<<"$o")"; } \
    || { bad "FR-009 an SSH remote without its rewrite is missing, with the setup command (rc=$rc): $o"; x_fail=1; }
  p="$(fg_proj chk2 https://github.com/o/r.git)"; fg_su "$p" >/dev/null
  jq 'del(.orchestrate.allowed_domains)' "$p/.claude/project-status.json" > "$fg_t/x.json" && mv "$fg_t/x.json" "$p/.claude/project-status.json"
  rc=0; o="$(fg_su "$p" --check)" || rc=$?
  { [ "$rc" = 1 ] && grep -qF 'the forge hosts in orchestrate.allowed_domains' <<<"$(tail -1 <<<"$o")"; } || { bad "FR-009 an absent allowed_domains key is missing (rc=$rc): $o"; x_fail=1; }
  jq '.orchestrate.allowed_domains = ["registry.npmjs.org"]' "$p/.claude/project-status.json" > "$fg_t/x.json" && mv "$fg_t/x.json" "$p/.claude/project-status.json"
  rc=0; o="$(fg_su "$p" --check)" || rc=$?
  { [ "$rc" = 0 ] && grep -qF 'setup: note: orchestrate.allowed_domains' <<<"$o" && grep -qF 'lacks github.com api.github.com' <<<"$o"; } \
    || { bad "FR-009 a present key lacking the forge hosts is a note, not a failure (D2; rc=$rc): $o"; x_fail=1; }
  grep -qF 'needs an unsandboxed caller' <<<"$(fg_su "$p" --help)" || { bad "FR-008 the help text says the lock report needs an unsandboxed caller"; x_fail=1; }
  return 0
}
fg_case_check
[ "$x_fail" -eq 0 ] && ok "--check: ok once set up; a stale lock (only a zero-byte one older than 60 s) in the last line with its rm, kept; an SSH remote without the rewrite and an absent key are missing; a present key lacking hosts is a note; the help names the unsandboxed caller (FR-008, FR-009, SC-002)"

# --- the ledger and the launcher: an infrastructure outcome is a stall with the plugin's fix line --------------------
# A tasks-repo board in interactive lane mode, HEF-1..HEF-9 in its ledger; the lane --prepare/--finish path transcribes
# a fixture outcome exactly as a run's (no model). The lane env of the session running the suite is cleared, as
# smoke-lifecycle.sh's lc_sl does.
fg_env() { env -u CLAUDE_CODE_SESSION_ID -u HEFESTO_TRUSTED_TOP -u HEFESTO_TRUSTED_BOARD -u HEFESTO_LANE_MAP -u HEFESTO_WORKER -u HEFESTO_LANES "$@"; }
fg_l() { local t="$1"; shift; (cd "$t" && fg_env bash "${FG_HOOKS:-$REPO/hooks}/ledger.sh" "$@" 2>&1); }
fg_sl() { local t="$1"; shift; (cd "$t" && unset XDG_CACHE_HOME && fg_env bash "${FG_HOOKS:-$REPO/hooks}/session-launch.sh" "$@" 2>&1); }
fg_board() { # → a fresh board repository; prints its path
  local t i c; t="$(cd "$(mktemp -d)" && pwd -P)"
  ( cd "$t" && git init -q -b main . && mkdir -p tasks .claude && printf '.claude/\n' >> .git/info/exclude \
    && { printf '# TODO\n'; for i in 1 2 3 4 5 6 7 8 9; do printf '\n## HEF-%s — item %s\nbody %s\n' "$i" "$i" "$i"; done; } > tasks/TODO.md \
    && for c in DOING DONE BACKLOG; do printf '# %s\n' "$c" > "tasks/$c.md"; done \
    && fg_git add tasks && fg_git commit -q -m board \
    && printf '{"source":"tasks-repo","root":"tasks","orchestrate":{"lane_mode":"interactive"}}\n' > .claude/project-status.json ) >/dev/null 2>&1
  for i in 1 2 3 4 5 6 7 8 9; do fg_l "$t" init "HEF-$i" --kind tasks-repo --ref "tasks/TODO.md#HEF-$i" >/dev/null; done
  printf '%s\n' "$t"
}
fg_bo() { fg_l "$1" show "$2" | jq -c '.blocked_on // {} | {kind, cause, reason}' 2>/dev/null; }   # repo id → the block
fg_stage() { # repo role id outcome-json → $fg_rc and $fg_o of the lane's --finish after its --prepare
  local f="$fg_t/oc-$3-$RANDOM.json"; printf '%s\n' "$4" > "$f"
  fg_o="$(fg_sl "$1" "$2" "$3" --prepare --lane repo-builder)" || { fg_rc=99; return 0; }
  fg_rc=0; fg_o="$(fg_sl "$1" "$2" "$3" --finish --lane repo-builder --outcome-file "$f")" || fg_rc=$?
}
fg_mirror() { # [source hooks dir] → a temp folder of links to every hook, for a mutant to replace one file in
  local md h src="${1:-$REPO/hooks}"; md="$(mktemp -d)"; for h in "$src"/*.sh; do ln -s "$h" "$md/$(basename "$h")"; done; printf '%s\n' "$md"
}
fg_hmut() { # label file sed-expr test-fn — a mutant of hooks/<file>, run from a mirror, must turn test-fn red
  local md red; md="$(fg_mirror)"; rm "$md/$2"; sed "$3" "$REPO/hooks/$2" > "$md/$2"
  if cmp -s "$REPO/hooks/$2" "$md/$2"; then bad "mutant did not apply to $2: $1"; x_fail=1; rm -rf "$md"; return; fi
  red="$(x_fail=0; FG_HOOKS="$md" "$4" >/dev/null 2>&1; echo "$x_fail")"; rm -rf "$md"
  [ "$red" = 1 ] || { bad "mutant survived: $1"; x_fail=1; }
}

head_ "ledger.sh block --kind stall --cause: the enum, stall only, the host check, the reason from the fix table, never over human:intake (FR-013, FR-014)"
x_fail=0
fg_case_ledger() { # forge-setup/FR-013 FR-014 US4
  local t o rc md
  t="$(fg_board)"
  rc=0; o="$(fg_l "$t" block HEF-7 --kind ci --cause push-refused)" || rc=$?
  { [ "$rc" != 0 ] && grep -qF -- '--kind stall only' <<<"$o" && [ "$(fg_bo "$t" HEF-7)" = '{"kind":null,"cause":null,"reason":null}' ]; } \
    || { bad "FR-014 --cause with another kind is refused naming it (rc=$rc): $o"; x_fail=1; }
  rc=0; o="$(fg_l "$t" block HEF-7 --kind stall --cause disk-full)" || rc=$?
  { [ "$rc" != 0 ] && grep -qF 'push-refused host-denied credential-helper-missing' <<<"$o"; } || { bad "FR-013 an unknown cause is refused listing the enum (rc=$rc): $o"; x_fail=1; }
  fg_l "$t" block HEF-7 --kind stall --cause host-denied --host 10.0.0.5 >/dev/null
  o="$(fg_bo "$t" HEF-7)"
  { jq -e '.kind == "stall" and .cause == "host-denied" and (.reason | contains("find the denied host in the run log")) and (.reason | contains("10.0.0.5") | not)' <<<"$o" >/dev/null; } \
    || { bad "FR-014 a host that is not public is dropped and the reason points to the run log: $o"; x_fail=1; }
  fg_l "$t" block HEF-6 --kind stall --cause host-denied --host pypi.org >/dev/null
  jq -e '.reason | contains("the worker reports it was denied pypi.org") and contains("'"$t"'/.claude/project-status.json")' <<<"$(fg_bo "$t" HEF-6)" >/dev/null \
    || { bad "FR-013 a public host is named as the worker's claim, with the board config path: $(fg_bo "$t" HEF-6)"; x_fail=1; }
  fg_l "$t" block HEF-8 --kind human:intake >/dev/null
  rc=0; o="$(fg_l "$t" block HEF-8 --kind stall --cause push-refused)" || rc=$?
  { [ "$rc" != 0 ] && [ "$(fg_bo "$t" HEF-8 | jq -r .kind)" = human:intake ]; } || { bad "FR-013 an infra stall never replaces human:intake (rc=$rc): $o"; x_fail=1; }
  fg_l "$t" block HEF-9 --kind stall >/dev/null
  fg_l "$t" show HEF-9 | jq -e '.blocked_on.kind == "stall" and (.blocked_on | has("cause") or has("reason") | not)' >/dev/null || { bad "FR-013 a stall without --cause keeps today's shape (no cause, no reason)"; x_fail=1; }
  # the fix table and the enum drifting apart: the ledger must die rather than store an empty reason (constitution 5)
  md="$(fg_mirror "${FG_HOOKS:-$REPO/hooks}")"; rm "$md/forge-lib.sh"; sed 's/^FORGE_CAUSES="/FORGE_CAUSES="extra /' "$REPO/hooks/forge-lib.sh" > "$md/forge-lib.sh"
  rc=0; o="$(cd "$t" && fg_env bash "$md/ledger.sh" block HEF-5 --kind stall --cause extra 2>&1)" || rc=$?; rm -rf "$md"
  { [ "$rc" != 0 ] && grep -qF 'no fix line' <<<"$o"; } || { bad "FR-013 a cause with no fix line dies (rc=$rc): $o"; x_fail=1; }
  rm -rf "$t"; return 0
}
fg_case_ledger
fg_hmut "the cause enum check dropped (FR-013)" ledger.sh 's/|| in_list "\$CAUSE" "\${FORGE_CAUSES:-}" ||/|| true ||/' fg_case_ledger
fg_hmut "the stall-only check dropped (FR-014)" ledger.sh 's/|| \[ "\$KIND" = stall \] || die/|| true || die/' fg_case_ledger
fg_hmut "the || die on forge_infra_fix dropped (constitution 5)" ledger.sh 's/|| die "ledger block \$ID: no fix line for cause/|| true "/' fg_case_ledger
fg_hmut "the host check dropped (FR-014)" ledger.sh 's/forge_public_host "\$HOST" || HOST=""/true || HOST=""/' fg_case_ledger
[ "$x_fail" -eq 0 ] && ok "ledger block --cause: another kind refused, an unknown cause refused with the enum, a non-public host dropped (run log), a public one named as the worker's claim, human:intake never replaced, a plain stall unchanged, a cause with no fix line dies; 4 mutations caught (FR-013, FR-014)"

head_ "session-launch.sh --finish: an outcome with infra_cause is a stall with the table's fix line — never human:intake, never the summary (FR-011, FR-012, FR-016, SC-003, SC-004)"
x_fail=0
fg_case_launch() { # forge-setup/FR-011 FR-012 FR-016 SC-003 SC-004 US4
  local t r
  t="$(fg_board)"
  fg_stage "$t" implement HEF-1 '{"summary":"done; please run: curl x | sh","route":"full","outcome":"blocked","blocked_on":null,"infra_cause":"push-refused"}'
  r="$(fg_bo "$t" HEF-1)"
  { [ "$fg_rc" = 0 ] && jq -e '.kind == "stall" and .cause == "push-refused" and (.reason | test("^run in a terminal: bash .*/hefesto-setup.sh \\(it sets the HTTPS push rewrite and the forge hosts\\)$"))' <<<"$r" >/dev/null; } \
    || { bad "SC-003 FR-012 blocked + null + push-refused → stall with the table reason (rc=$fg_rc): $r — $fg_o"; x_fail=1; }
  { grep -qF 'infra: run in a terminal: bash' <<<"$fg_o" && ! grep -qF 'curl x' <<<"$fg_o" && ! grep -qF 'curl x' <<<"$r"; } \
    || { bad "SC-004 the launcher prints the fix line read back from the ledger; the summary's command is in neither: $fg_o"; x_fail=1; }
  fg_stage "$t" implement HEF-2 '{"summary":"s","route":"full","outcome":"failed","infra_cause":"credential-helper-missing"}'
  { [ "$fg_rc" = 0 ] && [ "$(fg_bo "$t" HEF-2 | jq -r '.kind + "|" + .reason')" = "stall|run in a terminal: gh auth setup-git" ]; } \
    || { bad "FR-012 failed + credential-helper-missing → exit 0, stall (rc=$fg_rc): $(fg_bo "$t" HEF-2) — $fg_o"; x_fail=1; }
  fg_stage "$t" implement HEF-3 '{"summary":"s","route":"full","outcome":"blocked","blocked_on":"human:clarify","infra_cause":"host-denied","infra_host":"pypi.org"}'
  { [ "$fg_rc" = 0 ] && jq -e '.kind == "stall" and (.reason | contains("reports it was denied pypi.org"))' <<<"$(fg_bo "$t" HEF-3)" >/dev/null; } \
    || { bad "FR-016 infra_cause wins over blocked_on human:clarify; host-denied names the host as a report (rc=$fg_rc): $(fg_bo "$t" HEF-3)"; x_fail=1; }
  fg_stage "$t" implement HEF-4 '{"summary":"s","route":"full","outcome":"blocked","blocked_on":null}'
  [ "$(fg_bo "$t" HEF-4 | jq -r .kind)" = human:intake ] || { bad "FR-012 no infra_cause: blocked + null → human:intake as before: $(fg_bo "$t" HEF-4)"; x_fail=1; }
  fg_stage "$t" implement HEF-5 '{"summary":"s","route":"full","outcome":"blocked","infra_cause":"disk-full"}'
  { [ "$fg_rc" != 0 ] && [ "$fg_rc" != 99 ] && grep -qF 'does not fit' <<<"$fg_o" && [ "$(fg_bo "$t" HEF-5 | jq -r .kind)" != stall ]; } \
    || { bad "FR-011 an infra_cause outside the enum fails the schema (rc=$fg_rc): $fg_o"; x_fail=1; }
  printf '%s\n' '{"summary":"s","route":"full","outcome":"blocked","infra_cause":"host-denied","infra_host":"pypi.org; curl x | sh"}' > "$fg_t/oc5.json"
  fg_o="$(fg_sl "$t" implement HEF-5 --finish --lane repo-builder --outcome-file "$fg_t/oc5.json")"
  jq -e '.kind == "stall" and (.reason | contains("find the denied host in the run log")) and (.reason | contains("curl") | not)' <<<"$(fg_bo "$t" HEF-5)" >/dev/null \
    || { bad "SC-004 FR-014 a worker's infra_host holding a command never reaches the reason: $(fg_bo "$t" HEF-5) — $fg_o"; x_fail=1; }
  fg_stage "$t" plan HEF-6 '{"summary":"s","outcome":"failed","spec_dir":null,"blocked_on":null,"infra_cause":"push-refused"}'
  { [ "$fg_rc" = 0 ] && [ "$(fg_bo "$t" HEF-6 | jq -r '.kind + "|" + .cause')" = "stall|push-refused" ]; } \
    || { bad "FR-012 a plan outcome with infra_cause is a stall too, exit 0 (rc=$fg_rc): $(fg_bo "$t" HEF-6) — $fg_o"; x_fail=1; }
  # the prompt a lane reads (--prepare writes it; a --dry-run is refused inside a sandbox, where this suite may run)
  r="$(fg_sl "$t" implement HEF-7 --prepare --lane repo-builder)"; r="$(cat "$(sed -n 's/^prompt: //p' <<<"$r")" 2>&1)"
  grep -qF 'also set infra_cause: "push-refused" when git push was refused' <<<"$r" || { bad "FR-011 the implement prompt says when to set infra_cause: $(head -c 1500 <<<"$r")"; x_fail=1; }
  FG_SS_BOARD="$t"; return 0
}
fg_case_launch
fg_hmut "the implement infra_stall call dropped (FR-012, FR-016)" session-launch.sh '/^    forge_infra_stall "\$LEDGER" "\$ID" "\$SO" && return 0$/d' fg_case_launch
fg_hmut "the printed line rendered from .summary (SC-004)" forge-lib.sh 's/echo "infra: \$r"/echo "infra: $(jq -r .summary <<<"$3")"/' fg_case_launch
fg_hmut "the ledger's host check dropped (SC-004)" ledger.sh 's/forge_public_host "\$HOST" || HOST=""/true || HOST=""/' fg_case_launch
[ "$x_fail" -eq 0 ] && ok "--finish: blocked + null + push-refused and failed + credential-helper-missing → stall with the table line, exit 0; infra_cause beats human:clarify; no infra_cause → human:intake; an off-enum cause fails the schema; a command in the summary or infra_host never reaches the reason; plan too; 3 mutations caught (FR-011, FR-012, FR-016, SC-003, SC-004)"

head_ "session start and the orchestrator: an infra stall goes to the orchestrator with its fix, never a form (FR-015)"
x_fail=0
fg_case_ss() { # forge-setup/FR-015 (P7)
  local t="${FG_SS_BOARD:?}" o
  fg_l "$t" block HEF-7 --kind stall >/dev/null
  o="$(printf '{"cwd":"%s","source":"startup"}' "$t" | fg_env bash "${FG_HOOKS:-$REPO/hooks}/session-start-context.sh" 2>&1)"
  grep -E '^ledger: HEF-1 ' <<<"$o" | grep -qF 'blocked_on stall (push-refused)' && grep -E '^ledger: HEF-1 ' <<<"$o" | grep -qF '→ orchestrator: run in a terminal: bash' \
    || { bad "FR-015 the session-start line of an infra stall names the orchestrator and its fix: $(grep -E '^ledger: HEF-1 ' <<<"$o")"; x_fail=1; }
  grep -E '^ledger: HEF-7 ' <<<"$o" | grep -qF '→ build pane' || { bad "FR-015 a stall without a cause keeps its pane (PANES_DEFAULT unchanged): $(grep -E '^ledger: HEF-7 ' <<<"$o")"; x_fail=1; }
  return 0
}
fg_case_ss
fg_orch() { # forge-setup/FR-015 — the reasoned-stall rule and the Your move line in the orchestrator's command
  local md; md="$(tr '\n' ' ' < "${FG_ORCH:-$REPO/commands/hef.orchestrate.md}" | tr -s ' ')"
  grep -qF 'a `stall` with a `blocked_on.reason` (an infrastructure stop: `blocked_on.cause` is set) | no form' <<<"$md" || { bad "FR-015 hef.orchestrate.md: a reasoned stall is no form"; x_fail=1; }
  grep -qF 'a `stall` with no `blocked_on.reason` (the attempts stall)' <<<"$md" || { bad "FR-015 hef.orchestrate.md: an attempts stall keeps Retry/Later"; x_fail=1; }
  grep -qF 'Your move: <reason>, then say "retry <ids>"' <<<"$md" && grep -qF 'one line per distinct reason' <<<"$md" \
    || { bad "FR-015 hef.orchestrate.md: the Your move line, one per distinct reason"; x_fail=1; }
  grep -qF 'hooks/ledger.sh unblock <id>` for each item' <<<"$md" || { bad "FR-015 hef.orchestrate.md: retry runs ledger.sh unblock per item (D8)"; x_fail=1; }
  return 0
}
fg_orch
fg_omut() { # label phrase — hef.orchestrate.md with the line holding <phrase> deleted must turn fg_orch red
  local f="$fg_t/orch.md" red; grep -vF "$2" "$REPO/commands/hef.orchestrate.md" > "$f"
  cmp -s "$f" "$REPO/commands/hef.orchestrate.md" && { bad "doc mutant did not apply: $1"; x_fail=1; return; }
  red="$(x_fail=0; FG_ORCH="$f" fg_orch >/dev/null 2>&1; echo "$x_fail")"; [ "$red" = 1 ] || { bad "doc mutant survived: $1"; x_fail=1; }
}
fg_omut "the reasoned-stall row" 'an infrastructure stop: `blocked_on.cause` is set'
fg_omut "the Your move line" 'Your move: <reason>, then say'
fg_hmut "the session-start infra arm dropped (P7)" session-start-context.sh 's/if .blocked_on.kind == "stall" and (.blocked_on.cause \/\/ "") != "" then/if false then/' fg_case_ss
[ "$x_fail" -eq 0 ] && ok "an infra stall's session-start line → orchestrator with its fix; an attempts stall keeps the build pane; hef.orchestrate.md: no form for a reasoned stall, Your move once per distinct reason, retry = unblock per item; 3 mutations caught (FR-015)"

# --- FR-017: the docs describe the forge step, the lock check and the infra stall -------------------------------------
head_ "docs: install.md pairs setup with the push rewrite and the unsandboxed lock check, no manual pushInsteadOf step; hooks.md has forge-lib.sh (FR-017)"
x_fail=0
fg_docs() { # forge-setup/FR-017
  local im hm; im="$(tr '\n' ' ' < "${FG_INSTALL:-$REPO/docs/install.md}" | tr -s ' ')"; hm="$(tr '\n' ' ' < "$REPO/docs/hooks.md" | tr -s ' ')"
  grep -qF '`hefesto-setup.sh` also sets the HTTPS push rewrite and the forge'"'"'s hosts' <<<"$im" || { bad "FR-017 install.md pairs hefesto-setup.sh with the push rewrite"; x_fail=1; }
  grep -qF 'the lock check needs an unsandboxed caller' <<<"$im" || { bad "FR-017 install.md names the unsandboxed lock check"; x_fail=1; }
  grep -qF 'in the repository, `git config url."https://github.com/".pushInsteadOf' <<<"$im" && { bad "FR-017 install.md still instructs the manual pushInsteadOf step of §8b"; x_fail=1; }
  grep -qF 'branch protection' <<<"$im" || { bad "FR-017 install.md says branch protection stops a merge (D9, P4)"; x_fail=1; }
  grep -qF '| 🧩 `forge-lib.sh` |' <<<"$hm" || { bad "FR-017 hooks.md has the forge-lib.sh row"; x_fail=1; }
  grep -qF 'block <id> --kind stall --cause <c>' <<<"$hm" || { bad "FR-017 hooks.md describes the infra stall under ledger.sh block"; x_fail=1; }
  return 0
}
fg_docs
fg_dmut() { # label phrase — install.md with the line holding <phrase> deleted must turn fg_docs red
  local f="$fg_t/install.md" red; grep -vF "$2" "$REPO/docs/install.md" > "$f"
  cmp -s "$f" "$REPO/docs/install.md" && { bad "doc mutant did not apply: $1"; x_fail=1; return; }
  red="$(x_fail=0; FG_INSTALL="$f" fg_docs >/dev/null 2>&1; echo "$x_fail")"; [ "$red" = 1 ] || { bad "doc mutant survived: $1"; x_fail=1; }
}
fg_dmut "the forge step's pairing line" 'also sets the HTTPS push rewrite and the forge'
fg_dmut "the unsandboxed lock check line" 'unsandboxed caller (a terminal, or the session-start hook)'
[ "$x_fail" -eq 0 ] && ok "install.md: setup sets the push rewrite and the hosts, the lock check needs an unsandboxed caller, no manual pushInsteadOf step, branch protection named; hooks.md: the forge-lib.sh row and the infra stall; 2 mutations caught (FR-017)"
rm -rf "$fg_t"
