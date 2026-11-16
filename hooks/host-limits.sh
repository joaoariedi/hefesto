# shellcheck shell=bash
# host-limits.sh — what a launch or a check may take from the host (run-survival, HEF-25). Sourced by
# session-launch.sh, speckit-helper.sh, quality-before-commit.sh, hefesto-setup.sh and the smoke suite.
#
# Why it exists: on a 24 GB host systemd-oomd killed the orchestrator's scope twice in one minute (2026-11-09). The
# workers were the launcher's children, so they sat in the orchestrator's cgroup and died with it, and a shellcheck
# over a 6800-line file had pushed the slice over its pressure limit. Every function here is pure: the inputs are
# arguments and paths, the outputs are stdout lines and return codes, nothing is read from the caller's globals.
# Zero-install (constitution 4): bash 3.2, awk, coreutils; systemd-run, setsid, systemctl and shellcheck are optional.

# The address-space limit for one shellcheck process, in KiB (2 GiB). Measured at the round-3 plan review
# (2026-11-09, shellcheck 0.11.0): it starts and checks every hook and install.sh under this limit (rc 0), so the
# limit never turns the gate silent (R1). tests/smoke.sh (6818 lines then) runs out of memory under 2, 4 AND 8 GiB
# (rc 251) — no limit fits it, which is why the callers skip files over 3000 lines instead of raising this (R8).
HL_SC_VMEM_KB="${HL_SC_VMEM_KB:-2097152}"

# hl_detacher <id> <role> <lane-mode> [<runs-dir>] → the words that run a command outside the caller's cgroup and session, on
# stdout (nothing: run attached). systemd-run --scope moves it out of the cgroup oomd kills; setsid out of the process
# group a closed terminal or a stopped Bash tool signals. `-w` makes setsid wait and return the child's exit code
# even when it has to fork. HEFESTO_RUN_DETACH=0 is the test suite's seam: honoured only outside lane mode (a lane
# must not keep its runs attached), and it also silences the "attached" note so a macOS CI log stays quiet.
#   e.g.  read -r -a PRE <<<"$(hl_detacher HEF-1 implement 0 "$RUNDIR")"
hl_detacher() {
  [ "${3:-0}" = 0 ] && [ "${HEFESTO_RUN_DETACH:-}" = 0 ] && return 0
  # $4, the runs folder: with a /../ in it the copy's marker fails the launcher's own path guard, so the copy would not
  # know it is the copy and would detach again, without end (code review 2026-11-16) — attached instead
  case "${4:-}" in *"/../"*) echo "session-launch: the runs folder $4 has a /../ in it — the run is attached to this shell" >&2; return 0 ;; esac
  if command -v systemd-run >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    # OOMPolicy=continue: a scope's default (stop) ends the whole run when the kernel OOM-kills one tool in it
    # (verify 2026-11-16: a 7.6 GB shellcheck took the run with it, exit 143) — the tool fails, the run goes on
    echo "systemd-run --user --scope --collect --quiet -p OOMPolicy=continue --unit hefesto-$1-$2-$$ -- setsid -w"
  elif command -v setsid >/dev/null 2>&1; then
    echo "setsid -w"
  else
    echo "session-launch: no systemd-run or setsid — the run is attached to this shell" >&2
  fi
  return 0
}

# hl_run_detached <launcher-log> <cwd> <script> <role> <id> <env-word>… -- <detacher-word>… → the copy's exit code.
# The launcher's run tail (claim, worker, lease, transcription) is re-executed by <script> under the detacher, from
# <cwd> (lane mode checks the folder), with `env <env-word>…` (the person's GIT_CONFIG_* back, nothing else) and
# HEFESTO_RUN_DETACHED=<launcher-log>. Its output goes to <launcher-log>.out / .err — files, never a pipe a dead caller
# held (no SIGPIPE) — and is relayed here once it exits. No signal is forwarded: `kill <owner.pid>` stops a run.
# The copy touches <launcher-log>.started as its first act, so a non-zero exit without it means the copy never ran
# (the user manager refused the scope): ONE setsid -w retry then; a copy that ran is never launched again.
hl_run_detached() {
  local ll="$1" cwd="$2" sl="$3" role="$4" id="$5" rc envw=() pre
  shift 5
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envw+=("$1"); shift; done
  shift; pre=("$@")
  mkdir -p "${ll%/*}" && chmod 700 "${ll%/*}" 2>/dev/null || { echo "session-launch $role $id: cannot create ${ll%/*} for the run's output" >&2; return 1; }
  hl_start_copy "$ll" "$cwd" "$sl" "$role" "$id" "${#envw[@]}" ${envw[@]+"${envw[@]}"} "${pre[@]}"; rc=$?
  if [ "$rc" -ne 0 ] && [ ! -e "$ll.started" ] && [ "${pre[0]}" = systemd-run ]; then
    echo "session-launch $role $id: systemd-run could not start the scope (exit $rc) — detaching with setsid instead" >&2
    hl_start_copy "$ll" "$cwd" "$sl" "$role" "$id" "${#envw[@]}" ${envw[@]+"${envw[@]}"} setsid -w; rc=$?
  fi
  cat "$ll.out" 2>/dev/null; cat "$ll.err" >&2 2>/dev/null; rm -f "$ll.out" "$ll.err" "$ll.started"
  return "$rc"
}
hl_start_copy() { # <launcher-log> <cwd> <script> <role> <id> <n> <n env words> <detacher…> → the copy's exit code
  local ll="$1" cwd="$2" sl="$3" role="$4" id="$5" n="$6" envw=()
  shift 6
  while [ "$n" -gt 0 ]; do envw+=("$1"); shift; n=$((n - 1)); done
  (cd "$cwd" && exec env ${envw[@]+"${envw[@]}"} HEFESTO_RUN_DETACHED="$ll" "$@" bash "$sl" "$role" "$id") </dev/null >"$ll.out" 2>"$ll.err" &
  wait "$!"
}

# hl_memory_gate <min-MiB> <meminfo> <psi> → 0, or the busy text on stdout and 75 (EX_TEMPFAIL). min 0 turns the
# free-memory floor off; the pressure half (PSI `some avg60` over 50) always applies. A file that is missing (macOS
# has no /proc) or carries no MemAvailable line skips that half with one stderr note — never a refusal.
hl_memory_gate() {
  local mb avg
  if [ -r "$2" ]; then
    mb=$(awk '/^MemAvailable:/ {print int($2 / 1024)}' "$2")
    if [ -z "$mb" ]; then echo "session-launch: note: $2 has no MemAvailable line — the free-memory floor is not checked here" >&2
    elif [ "$1" -gt 0 ] && [ "$mb" -lt "$1" ]; then echo "busy: memory — $mb MiB available < $1 MiB (orchestrate.min_free_mb)"; return 75; fi
  else
    echo "session-launch: note: no $2 — the free-memory floor is not checked here" >&2
  fi
  [ -r "$3" ] || { echo "session-launch: note: no $3 — memory pressure is not checked here" >&2; return 0; }
  avg=$(awk '/^some / {for (i = 2; i <= NF; i++) if (sub(/^avg60=/, "", $i)) print $i}' "$3")
  if awk -v a="${avg:-0}" 'BEGIN { exit !(a + 0 > 50) }'; then echo "busy: memory pressure some avg60=$avg > 50"; return 75; fi
  return 0
}

# hl_shellcheck_bounded <file> <severity> <max-lines> → 0 clean | 1 a finding | 2 skipped (over max-lines; 0 = no
# skip) | 3 could not check. One file per process, under `ulimit -v`: the split of exit 1 (a finding) from any
# other non-zero (shellcheck itself failed — killed for memory, exit 137) is the commit hook's old contract. A
# failing `ulimit` (a platform without -v) is ignored; the size skip still holds. Findings go to stdout.
#   e.g.  hl_shellcheck_bounded hooks/ledger.sh warning 3000
hl_shellcheck_bounded() {
  local n max="${3:-3000}" rc=0
  [ -r "$1" ] || { echo "shellcheck: could not check $1 (not readable)"; return 3; }
  n=$(wc -l < "$1" | tr -d ' ')
  if [ "$max" -gt 0 ] && [ "$n" -gt "$max" ]; then
    echo "shellcheck: skipped $1 ($n lines > $max) — too large to check here; split it, or check it by hand"; return 2
  fi
  ( ulimit -v "$HL_SC_VMEM_KB" 2>/dev/null; exec shellcheck -S "$2" "$1" ) || rc=$?
  case "$rc" in
    0) return 0 ;;
    1) return 1 ;;
    *) echo "shellcheck: could not check $1 (exit $rc — out of memory?)"; return 3 ;;
  esac
}

# hl_changed_shell_files --base <ref> → the changed .sh/.bash files that still exist, one per line, relative to the
# repository root: the diff against the merge base with <ref>, plus staged, unstaged and untracked files. An empty
# <ref> (a root commit, no base found) lists the working-tree changes only and says so on stderr; a <ref> git cannot diff against
# returns 1 with git's message, so the caller reports the check incomplete instead of a silent pass.
hl_changed_shell_files() {
  local base="" top all=""
  [ "${1:-}" = --base ] && base="${2:-}"
  top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "shellcheck-changed: not inside a git repository" >&2; return 1; }
  if [ -n "$base" ]; then
    all=$(git -C "$top" diff --name-only --diff-filter=d "$base...HEAD" 2>&1) || { echo "shellcheck-changed: cannot diff against '$base': $all" >&2; return 1; }
  else
    echo "shellcheck-changed: no base to diff against — checking staged, unstaged and untracked changes only" >&2
  fi
  all="$all"$'\n'"$(git -C "$top" diff --name-only --diff-filter=d --cached 2>/dev/null)"$'\n'"$(git -C "$top" diff --name-only --diff-filter=d 2>/dev/null)"
  # a new file never `git add`ed is a change too (code review 2026-11-16): it would otherwise read as clean
  all="$all"$'\n'"$(git -C "$top" ls-files --others --exclude-standard 2>/dev/null)"
  printf '%s\n' "$all" | grep -E '\.(sh|bash)$' | LC_ALL=C sort -u | while IFS= read -r f; do [ -f "$top/$f" ] && printf '%s\n' "$f"; done
  return 0
}

# hl_oomd_note → a `setup: note:` block on stdout when systemd-oomd is active and the user manager's slice is killed
# at oomd's default 60 % pressure (limit unset, 0 or 60 %); nothing otherwise, and nothing without systemctl (macOS).
# Read-only. It never suggests disabling oomd: with oomd off this host thrash-froze within the hour (2026-11-09,
# the owner's decision D10) — the run cap and the memory gate size the load, the drop-in only raises the limit.
hl_oomd_note() {
  command -v systemctl >/dev/null 2>&1 || return 0
  [ "$(systemctl is-active systemd-oomd 2>/dev/null)" = active ] || return 0
  local u p l
  u="user@$(id -u).service"
  p=$(systemctl show "$u" -p ManagedOOMMemoryPressure --value 2>/dev/null)
  l=$(systemctl show "$u" -p ManagedOOMMemoryPressureLimit --value 2>/dev/null)
  [ "$p" = kill ] || return 0
  # systemctl show prints the limit as a fraction of 2^32 (60% → 2576980377), not "60%" (HEF-25 verify B2): a bare
  # number is turned into whole percent, rounded, before the default test
  [[ ! "$l" =~ ^[0-9]{1,10}$ ]] || l="$(( (l * 100 + 2147483648) / 4294967296 ))%"
  case "$l" in ""|0|0%|60%|60.00%) ;; *) return 0 ;; esac
  printf '%s\n' "setup: note: systemd-oomd kills this user's slice ($u) at its default 60 % memory pressure — one busy run can take the whole session down" \
    "  your choice — the script writes nothing: /etc/systemd/system/user@.service.d/90-hefesto-oomd.conf with" \
    "    [Service]" "    ManagedOOMMemoryPressureLimit=80%" \
    "  then: sudo systemctl daemon-reload — keep systemd-oomd on; orchestrate.max_concurrent_runs and orchestrate.min_free_mb size the load"
}
