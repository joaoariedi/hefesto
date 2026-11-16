# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs and sed expressions are single-quoted on purpose
# shellcheck disable=SC1090  # host-limits.sh, or a mutant of it, is sourced by variable on purpose
#
# run-survival (HEF-25) smoke checks, part 15 — a launched run survives the orchestrator and never starves the host.
# Every test cites its requirement as run-survival/FR-NNN. The assertions are at the tool-call level (constitution 3):
# named fakes for systemd-run, setsid, systemctl, shellcheck and claude record their argv and environment, and the
# ledger the launcher wrote is read back — never text a model could produce. Each guard has a mutation (spec SC-007,
# (a)–(l)), applied to a copy in a mirror of hooks/ and checked with cmp first, so a mutation that did not apply is red.
#
# SOURCED by tests/smoke.sh, never run on its own. tests/smoke.sh exports HEFESTO_RUN_DETACH=0 and ample-memory /proc
# fixtures for the rest of the suite; the cases below unset or override them, one launch at a time.

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ launcher sld >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-run-survival.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_, launcher, sld)"
  else echo "tests/smoke-run-survival.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

RS_HL="$REPO/hooks/host-limits.sh"; RS_SL="$REPO/hooks/session-launch.sh"; RS_LG="$REPO/hooks/ledger.sh"
rs_w="$(cd "$(mktemp -d)" && pwd -P)"   # every fixture of this part lives under it
# A mirror of hooks/ (one link per script) in which ONE file is replaced by its mutant: RS_MD names it. Not in a
# subshell, so a mutation that did not apply is reported here, as a FAIL of the suite.
rs_mutant() { # file sed-expr → RS_MD, or 1 (reported) when the sed changed nothing
  local h; RS_MD="$(mktemp -d)"
  for h in "$REPO"/hooks/*.sh; do ln -s "$h" "$RS_MD/$(basename "$h")"; done
  rm "$RS_MD/$1"; sed "$2" "$REPO/hooks/$1" > "$RS_MD/$1"
  if cmp -s "$REPO/hooks/$1" "$RS_MD/$1"; then bad "run-survival mutation did not apply ($1): $2"; rs_fail=1; return 1; fi
  return 0
}
rs_wait() { # condition max-tenths → 0 once the condition holds, 1 if it never did
  local n=0
  while ! eval "$1"; do [ "$n" -ge "$2" ] && return 1; sleep 0.1; n=$((n + 1)); done
  return 0
}

# --- the library, unit by unit (T003–T007) -------------------------------------------------------------------------
head_ "host-limits.sh: memory gate, bounded shellcheck, changed files, detacher, oomd note (run-survival FR-006 FR-007 FR-009 FR-001 FR-012)"
rs_fail=0
printf 'MemTotal:       25165824 kB\nMemAvailable:    2097152 kB\n' > "$rs_w/mem2048"   # 2048 MiB
printf 'MemTotal:       25165824 kB\nMemAvailable:       1024 kB\n' > "$rs_w/mem1"      # 1 MiB
printf 'MemTotal:       25165824 kB\n' > "$rs_w/memnoavail"
printf 'some avg10=0.00 avg60=63.20 avg300=12.00 total=1\nfull avg10=0.00 avg60=1.00 avg300=0.00 total=1\n' > "$rs_w/psi63"
rs_mg() { # min meminfo psi [lib] → stdout in rs_o, stderr in rs_e, rc in rs_rc
  rs_rc=0; rs_o="$( (. "${4:-$RS_HL}"; hl_memory_gate "$1" "$2" "$3") 2>"$rs_w/mg.err")" || rs_rc=$?; rs_e="$(cat "$rs_w/mg.err")"
}
# run-survival/FR-006: under the floor → 75 with the measured value and the limit; over 50 % pressure → 75; 0 = off
rs_mg 4096 "$rs_w/mem2048" "$HEFESTO_PROC_PRESSURE"
{ [ "$rs_rc" = 75 ] && grep -qF 'busy: memory — 2048 MiB available < 4096 MiB' <<<"$rs_o"; } || { bad "FR-006 2048 MiB under a 4096 floor must be busy (75) with both values — rc=$rs_rc: $rs_o"; rs_fail=1; }
rs_mg 4096 "$HEFESTO_PROC_MEMINFO" "$rs_w/psi63"
{ [ "$rs_rc" = 75 ] && grep -qF 'busy: memory pressure some avg60=63.20 > 50' <<<"$rs_o"; } || { bad "FR-006 PSI avg60 63.20 must be busy (75) — rc=$rs_rc: $rs_o"; rs_fail=1; }
rs_mg 0 "$rs_w/mem2048" "$HEFESTO_PROC_PRESSURE"
[ "$rs_rc" = 0 ] || { bad "FR-006 min_free_mb 0 turns the floor off — rc=$rs_rc: $rs_o"; rs_fail=1; }
rs_mg 0 "$rs_w/mem2048" "$rs_w/psi63"
[ "$rs_rc" = 75 ] || { bad "FR-006 min_free_mb 0 still checks the pressure — rc=$rs_rc"; rs_fail=1; }
# run-survival/FR-007: a missing file (or no MemAvailable line) skips that half with one note, never a refusal
rs_mg 4096 "$rs_w/nope-meminfo" "$rs_w/nope-psi"
{ [ "$rs_rc" = 0 ] && grep -qF "no $rs_w/nope-meminfo" <<<"$rs_e" && grep -qF "no $rs_w/nope-psi" <<<"$rs_e"; } \
  || { bad "FR-007 missing /proc files must pass with one note each — rc=$rs_rc: $rs_e"; rs_fail=1; }
rs_mg 4096 "$rs_w/memnoavail" "$HEFESTO_PROC_PRESSURE"
{ [ "$rs_rc" = 0 ] && grep -qF 'has no MemAvailable line' <<<"$rs_e"; } || { bad "FR-007 a meminfo with no MemAvailable line skips the floor with a note — rc=$rs_rc: $rs_e"; rs_fail=1; }
# mutation (c): the MemAvailable comparison inverted → the 2048 MiB fixture passes the 4096 floor
if rs_mutant host-limits.sh 's/\[ "\$mb" -lt "\$1" \]/[ "$mb" -gt "$1" ]/'; then
  rs_mg 4096 "$rs_w/mem2048" "$HEFESTO_PROC_PRESSURE" "$RS_MD/host-limits.sh"
  [ "$rs_rc" = 75 ] && { bad "mutation (c) survived: the MemAvailable comparison inverted, 2048 < 4096 still busy"; rs_fail=1; }
  rm -rf "$RS_MD"
fi

# run-survival/FR-009: one bounded process per file. FakeShellcheck logs `ulimit -v` and its argv, exits RS_SC_RC.
rs_scf="$rs_w/fake-sc"; mkdir -p "$rs_scf"; RS_SC_LOG="$rs_w/sc.log"; export RS_SC_LOG
printf '#!/bin/sh\n# FakeShellcheck (run-survival): what it was asked, under which limit\necho "ulimit=$(ulimit -v)" >> "$RS_SC_LOG"\necho "args=$*" >> "$RS_SC_LOG"\nexit "${RS_SC_RC:-0}"\n' > "$rs_scf/shellcheck"
chmod +x "$rs_scf/shellcheck"
awk 'BEGIN { print "#!/bin/bash"; for (i = 1; i < 3500; i++) print "echo " i }' > "$rs_w/big.sh"
awk 'BEGIN { print "#!/bin/bash"; for (i = 1; i < 40; i++) print "echo \"line " i "\"" }' > "$rs_w/small.sh"
rs_sb() { # file sev max [lib] [rc] → output in rs_o, rc in rs_rc; the fake on PATH
  : > "$RS_SC_LOG"; rs_rc=0
  rs_o="$(PATH="$rs_scf:$PATH" RS_SC_RC="${5:-0}" bash -c '. "$1"; hl_shellcheck_bounded "$2" "$3" "$4"' _ "${4:-$RS_HL}" "$1" "$2" "$3" 2>&1)" || rs_rc=$?
}
rs_sb "$rs_w/big.sh" warning 3000
{ [ "$rs_rc" = 2 ] && grep -qF "shellcheck: skipped $rs_w/big.sh (3500 lines > 3000) — too large to check here; split it, or check it by hand" <<<"$rs_o" && [ ! -s "$RS_SC_LOG" ]; } \
  || { bad "FR-009 a 3500-line file is skipped with the note and never handed to shellcheck — rc=$rs_rc: $rs_o / $(cat "$RS_SC_LOG")"; rs_fail=1; }
rs_sb "$rs_w/big.sh" warning 0
{ [ "$rs_rc" = 0 ] && grep -qF "args=-S warning $rs_w/big.sh" "$RS_SC_LOG"; } || { bad "FR-009 max-lines 0 checks any size — rc=$rs_rc"; rs_fail=1; }
rs_sb "$rs_w/small.sh" warning 3000 "" 1
[ "$rs_rc" = 1 ] || { bad "FR-009 a finding (exit 1) is 1 — rc=$rs_rc: $rs_o"; rs_fail=1; }
rs_sb "$rs_w/small.sh" warning 3000 "" 137
{ [ "$rs_rc" = 3 ] && grep -qF "shellcheck: could not check $rs_w/small.sh (exit 137" <<<"$rs_o"; } || { bad "FR-009 a shellcheck killed (137) is 'could not check' (3) — rc=$rs_rc: $rs_o"; rs_fail=1; }
rs_vm_ok=0; (ulimit -v 2097152) 2>/dev/null && rs_vm_ok=1   # a platform without -v keeps only the size skip
rs_sb "$rs_w/small.sh" error 3000
if [ "$rs_vm_ok" = 1 ]; then
  grep -qx 'ulimit=2097152' "$RS_SC_LOG" || { bad "FR-009 shellcheck must run under ulimit -v HL_SC_VMEM_KB (2097152) — log: $(cat "$RS_SC_LOG")"; rs_fail=1; }
  # mutation (g): the ulimit line removed → the fake runs with the suite's own limit
  if rs_mutant host-limits.sh 's/( ulimit -v "\$HL_SC_VMEM_KB" 2>\/dev\/null; exec shellcheck/( exec shellcheck/'; then
    rs_sb "$rs_w/small.sh" error 3000 "$RS_MD/host-limits.sh"
    grep -qx 'ulimit=2097152' "$RS_SC_LOG" && { bad "mutation (g) survived: the ulimit -v line removed, the limit still applied"; rs_fail=1; }
    rm -rf "$RS_MD"
  fi
fi
# mutation (d): the line skip removed → the 3500-line file reaches shellcheck
if rs_mutant host-limits.sh 's/if \[ "\$max" -gt 0 \] && \[ "\$n" -gt "\$max" \]; then/if false; then/'; then
  rs_sb "$rs_w/big.sh" warning 3000 "$RS_MD/host-limits.sh"
  [ "$rs_rc" = 2 ] && { bad "mutation (d) survived: the 3000-line skip removed, big.sh still skipped"; rs_fail=1; }
  rm -rf "$RS_MD"
fi
# R1: the real shellcheck (never the host's wrapper — command -v -p) still runs under the default limit; a gate that
# could not start would turn every check into "could not check" and go silent
rs_real_sc="$(command -v -p shellcheck 2>/dev/null || command -v shellcheck 2>/dev/null)"
if [ -n "$rs_real_sc" ]; then
  rs_rsc="$rs_w/real-sc"; mkdir -p "$rs_rsc"; ln -s "$rs_real_sc" "$rs_rsc/shellcheck"
  rs_rc=0; rs_o="$(PATH="$rs_rsc:$PATH" bash -c '. "$1"; hl_shellcheck_bounded "$2" warning 3000' _ "$RS_HL" "$rs_w/small.sh" 2>&1)" || rs_rc=$?
  [ "$rs_rc" = 0 ] || { bad "FR-009 R1: the real shellcheck must check a clean 40-line file under HL_SC_VMEM_KB (rc 0) — rc=$rs_rc: $rs_o"; rs_fail=1; }
  printf '#!/bin/bash\nif true; then\n  echo x\n' > "$rs_w/broken.sh"
  rs_rc=0; rs_o="$(PATH="$rs_rsc:$PATH" bash -c '. "$1"; hl_shellcheck_bounded "$2" error 3000' _ "$RS_HL" "$rs_w/broken.sh" 2>&1)" || rs_rc=$?
  [ "$rs_rc" = 1 ] || { bad "FR-009 R1: the real shellcheck must report an error as a finding (1) — rc=$rs_rc: $rs_o"; rs_fail=1; }
fi

# run-survival/FR-009: the changed shell files — the merge base, staged and unstaged; an unusable base is an error
rs_g="$rs_w/gitrepo"; mkdir -p "$rs_g"
( cd "$rs_g" && git init -q -b main . && printf '#!/bin/bash\necho c\n' > c.bash && printf 'x\n' > README.md && git add . \
  && git -c user.email=t@t -c user.name=t commit -q -m base && git checkout -q -b feat \
  && cp "$rs_w/small.sh" a.sh && cp "$rs_w/big.sh" big.sh && printf 'notes\n' > notes.md && git add . \
  && git -c user.email=t@t -c user.name=t commit -q -m feat && printf '#!/bin/bash\necho b\n' > b.sh && git add b.sh \
  && printf 'echo more\n' >> c.bash && printf '#!/bin/bash\necho d\n' > d.sh ) >/dev/null 2>&1   # d.sh: never git-added
rs_cf() { rs_rc=0; rs_o="$(cd "$rs_g" && bash -c '. "$1"; shift; hl_changed_shell_files "$@"' _ "$RS_HL" "$@" 2>"$rs_w/cf.err")" || rs_rc=$?; rs_e="$(cat "$rs_w/cf.err")"; }
rs_cf --base main
{ [ "$rs_rc" = 0 ] && [ "$(tr '\n' ' ' <<<"$rs_o")" = "a.sh b.sh big.sh c.bash d.sh " ]; } || { bad "FR-009 changed shell files against main + staged + unstaged + untracked — rc=$rs_rc: $(tr '\n' ' ' <<<"$rs_o")"; rs_fail=1; }
rs_cf --base ""
{ [ "$rs_rc" = 0 ] && [ "$(tr '\n' ' ' <<<"$rs_o")" = "b.sh c.bash d.sh " ] && grep -qF 'staged, unstaged and untracked changes only' <<<"$rs_e"; } \
  || { bad "FR-009 an empty base lists the working-tree changes only and says so — rc=$rs_rc: $(tr '\n' ' ' <<<"$rs_o") / $rs_e"; rs_fail=1; }
rs_cf --base no-such-ref
{ [ "$rs_rc" = 1 ] && grep -qF "cannot diff against 'no-such-ref'" <<<"$rs_e"; } || { bad "FR-009 a base git cannot diff against is an error, never an empty list — rc=$rs_rc: $rs_e"; rs_fail=1; }

# run-survival/FR-001: the detacher. FakeSystemdRun / FakeSetsid / FakeSystemctl (the user manager answers or not).
rs_dboth="$rs_w/det-both"; rs_dsid="$rs_w/det-setsid"; rs_dlog="$rs_w/detach.log"; mkdir -p "$rs_dboth" "$rs_dsid"; : > "$rs_dlog"
cat > "$rs_dboth/systemd-run" <<EOF
#!/bin/sh
# FakeSystemdRun: records its argv. RS_SDR_FAIL=1 refuses like a user manager that will not start the scope; RS_BADCFG
# hands the copy it starts an unwritable config dir, so the copy refuses at a check that comes before its claim.
echo "systemd-run \$*" >> "$rs_dlog"
[ "\$(grep -c . "$rs_dlog")" -le 6 ] || exit 97   # a fuse: a launcher that detaches again and again stops here
[ "\${RS_SDR_FAIL:-0}" = 1 ] && exit 1
[ -n "\${RS_BADCFG:-}" ] && { CLAUDE_CONFIG_DIR="\$RS_BADCFG"; export CLAUDE_CONFIG_DIR; }
while [ "\$1" != -- ]; do shift; done; shift; exec "\$@"
EOF
cat > "$rs_dboth/setsid" <<EOF
#!/bin/sh
# FakeSetsid: records its argv; RS_LOWMEM hands the copy (and only the copy) a low-memory fixture
echo "setsid \$*" >> "$rs_dlog"
[ "\$(grep -c . "$rs_dlog")" -le 6 ] || exit 97   # a fuse: a launcher that detaches again and again stops here
[ -n "\${RS_LOWMEM:-}" ] && { HEFESTO_PROC_MEMINFO="\$RS_LOWMEM"; export HEFESTO_PROC_MEMINFO; }
[ "\$1" = -w ] && shift; exec "\$@"
EOF
printf '#!/bin/sh\n# FakeSystemctl: the user manager answers\n[ "$1 $2" = "--user show-environment" ]\n' > "$rs_dboth/systemctl"
cp "$rs_dboth/setsid" "$rs_dsid/setsid"
printf '#!/bin/sh\n# FakeSystemctl: no user manager\nexit 1\n' > "$rs_dsid/systemctl"
chmod +x "$rs_dboth"/* "$rs_dsid"/*
# A PATH with neither systemd-run nor setsid (nor systemctl, nor shellcheck): every other tool of this host, linked
rs_farm="$rs_w/farm"; mkdir -p "$rs_farm"
IFS=: read -r -a rs_pd <<<"$PATH"
for rs_d in "${rs_pd[@]}"; do [ -d "$rs_d" ] && ln -s "$rs_d"/* "$rs_farm"/ 2>/dev/null; done
rm -f "$rs_farm/setsid" "$rs_farm/systemd-run" "$rs_farm/systemctl" "$rs_farm/shellcheck"
rs_det() { # PATH lane-mode [lib] → the detacher words in rs_o, stderr in rs_e
  rs_o="$(PATH="$1" bash -c '. "$1"; hl_detacher RS-0 implement "$2"' _ "${3:-$RS_HL}" "$2" 2>"$rs_w/det.err")"; rs_e="$(cat "$rs_w/det.err")"
}
(unset HEFESTO_RUN_DETACH; rs_det "$rs_dboth:$PATH" 0; [[ "$rs_o" == "systemd-run --user --scope --collect --quiet -p OOMPolicy=continue --unit hefesto-RS-0-implement-"*" -- setsid -w" ]]) \
  || { bad "FR-001 systemd-run + a user manager → systemd-run --user --scope … -p OOMPolicy=continue … -- setsid -w"; rs_fail=1; }
(unset HEFESTO_RUN_DETACH; rs_det "$rs_dsid:$PATH" 0; [ "$rs_o" = "setsid -w" ]) || { bad "FR-001 no user manager → setsid -w"; rs_fail=1; }
(unset HEFESTO_RUN_DETACH; rs_det "$rs_farm" 0; [ -z "$rs_o" ] && grep -qF 'session-launch: no systemd-run or setsid — the run is attached to this shell' <<<"$rs_e") \
  || { bad "FR-001 neither → no words and the attached note"; rs_fail=1; }
(HEFESTO_RUN_DETACH=0; export HEFESTO_RUN_DETACH; rs_det "$rs_farm" 0; [ -z "$rs_o" ] && [ -z "$rs_e" ]) || { bad "FR-001 HEFESTO_RUN_DETACH=0 outside lane mode → attached, and the note silenced"; rs_fail=1; }
(HEFESTO_RUN_DETACH=0; export HEFESTO_RUN_DETACH; rs_det "$rs_dsid:$PATH" 1; [ "$rs_o" = "setsid -w" ]) || { bad "FR-001 HEFESTO_RUN_DETACH=0 is ignored in lane mode"; rs_fail=1; }
# a runs folder with a /../ in it: the copy's marker would fail the path guard, so no detach at all (code review)
(unset HEFESTO_RUN_DETACH; rs_o="$(PATH="$rs_dboth:$PATH" bash -c '. "$1"; hl_detacher RS-0 implement 0 /c/../runs/1' _ "$RS_HL" 2>"$rs_w/det.err")"
 [ -z "$rs_o" ] && grep -qF 'the runs folder /c/../runs/1 has a /../ in it — the run is attached to this shell' "$rs_w/det.err") \
  || { bad "FR-001 a runs folder with /../ → no detacher words and the attached note"; rs_fail=1; }

# run-survival/FR-012: the oomd note — FakeSystemctl answers is-active and show from the environment
rs_om="$rs_w/oomd"; mkdir -p "$rs_om"
cat > "$rs_om/systemctl" <<'EOF'
#!/bin/sh
# FakeSystemctl (oomd): is-active and show answer from RS_OOMD_ACTIVE / RS_OOMD_MODE / RS_OOMD_LIMIT; nothing else exists
case "$1" in
  is-active) echo "${RS_OOMD_ACTIVE:-inactive}" ;;
  show) case "$*" in *ManagedOOMMemoryPressureLimit*) echo "${RS_OOMD_LIMIT-}" ;; *ManagedOOMMemoryPressure*) echo "${RS_OOMD_MODE:-kill}" ;; esac ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$rs_om/systemctl"
rs_oom() { # active limit [lib] → the note in rs_o
  rs_o="$(PATH="$rs_om:$PATH" RS_OOMD_ACTIVE="$1" RS_OOMD_LIMIT="$2" bash -c '. "$1"; hl_oomd_note' _ "${3:-$RS_HL}" 2>&1)"
}
rs_oom active 0
{ grep -qF 'setup: note: systemd-oomd' <<<"$rs_o" && grep -qF '/etc/systemd/system/user@.service.d/90-hefesto-oomd.conf' <<<"$rs_o" \
  && grep -qF 'ManagedOOMMemoryPressureLimit=80%' <<<"$rs_o" && grep -qF 'daemon-reload' <<<"$rs_o" && ! grep -qF 'systemctl disable' <<<"$rs_o"; } \
  || { bad "FR-012 oomd active, kill, limit 0 → the note with the drop-in and daemon-reload, never 'systemctl disable': $rs_o"; rs_fail=1; }
for rs_l in "" 60% 60.00%; do rs_oom active "$rs_l"; grep -qF 'setup: note:' <<<"$rs_o" || { bad "FR-012 a limit of '$rs_l' is oomd's default — the note is due"; rs_fail=1; }; done
rs_oom active 80%; [ -z "$rs_o" ] || { bad "FR-012 a limit of 80% → no note: $rs_o"; rs_fail=1; }
rs_oom inactive 0; [ -z "$rs_o" ] || { bad "FR-012 oomd inactive → no note: $rs_o"; rs_fail=1; }
# what systemctl show really prints: the limit as a fraction of 2^32 (verify gate 2026-11-16, B2, on this host)
rs_oom active 2576980377; grep -qF 'setup: note:' <<<"$rs_o" || { bad "FR-012 a raw limit 2576980377 is 60 % of 2^32, oomd's default — the note is due"; rs_fail=1; }
rs_oom active 3435973837; [ -z "$rs_o" ] || { bad "FR-012 a raw limit 3435973837 is 80 % — no note: $rs_o"; rs_fail=1; }
if rs_mutant host-limits.sh '/(l \* 100 + 2147483648) \/ 4294967296/d'; then
  rs_oom active 2576980377 "$RS_MD/host-limits.sh"; [ -z "$rs_o" ] || { bad "mutation (e2) survived: the 2^32 conversion dropped, yet the raw 60 % still noted"; rs_fail=1; }
  rm -rf "$RS_MD"
fi
rs_o="$(PATH="$rs_farm" bash -c '. "$1"; hl_oomd_note' _ "$RS_HL" 2>&1)"; [ -z "$rs_o" ] || { bad "FR-012 no systemctl (macOS) → no note: $rs_o"; rs_fail=1; }
# mutation (e): the limit test dropped → an 80% limit still gets the note
if rs_mutant host-limits.sh 's/^  case "\$l" in ""|0|0%|60%|60\.00%) ;; \*) return 0 ;; esac$/  :/'; then
  rs_oom active 80% "$RS_MD/host-limits.sh"; [ -n "$rs_o" ] || { bad "mutation (e) survived: the oomd limit test dropped, 80% still quiet"; rs_fail=1; }
  rm -rf "$RS_MD"
fi
[ "$rs_fail" -eq 0 ] && ok "host-limits.sh: memory gate 75 with value and limit, notes for missing files; one bounded shellcheck per file (skip, finding, could not check, ulimit -v); changed files with the empty/failed base contract; detacher choice and the lane-safe seam; oomd note never says disable; mutations c d e g caught (run-survival FR-001 FR-006 FR-007 FR-009 FR-012)"

# --- the run cap in ledger claim (T008) --------------------------------------------------------------------------
head_ "ledger claim: at most max_concurrent_runs launched runs across the ledger (run-survival FR-004 FR-005)"
rs_fail=0
rs_t="$rs_w/proj"; mkdir -p "$rs_t"; rs_cfg="$rs_w/cfg"; mkdir -p "$rs_cfg"
( cd "$rs_t" && git init -q -b main . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init && mkdir -p tasks .claude \
  && { printf '# TODO\n'; for i in $(seq 1 40); do printf '\n## RS-%s — item %s\nb\n' "$i" "$i"; done; } > tasks/TODO.md \
  && printf '# D\n' > tasks/DOING.md && printf '# D\n' > tasks/DONE.md && printf '# B\n' > tasks/BACKLOG.md \
  && printf '{"source":"tasks-repo","root":"tasks"}\n' > .claude/project-status.json \
  && for i in $(seq 1 40); do bash "$RS_LG" init "RS-$i" --kind tasks-repo --ref t >/dev/null; done ) >/dev/null 2>&1
rs_ld="$(sld "$rs_t")"
rs_conf() { printf '{"source":"tasks-repo","root":"tasks","orchestrate":%s}\n' "$1" > "$rs_t/.claude/project-status.json"; }
rs_claim() { # id role pid|interactive [ledger] → rc in rs_rc, stderr in rs_e
  rs_rc=0
  if [ "$3" = pid ]; then rs_e="$(cd "$rs_t" && launcher bash "${4:-$RS_LG}" claim "$1" --session "s-$1" --role "$2" --pid "$$" 2>&1 >/dev/null)" || rs_rc=$?
  else rs_e="$(cd "$rs_t" && launcher bash "${4:-$RS_LG}" claim "$1" --session "s-$1" --role "$2" --mode interactive 2>&1 >/dev/null)" || rs_rc=$?; fi
}
rs_free() { local f; for f in "$rs_ld"/RS-*.json; do jq '.owner = null' "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done; }
[ -f "$rs_ld/RS-40.json" ] || { bad "the run-survival fixture ledger was not created at $rs_ld"; rs_fail=1; }
# run-survival/FR-004: default 2 — two launched runs, then a third (another role, another stage limit) is busy
rs_claim RS-1 plan pid; rs_claim RS-2 deploy pid
rs_claim RS-3 implement pid
{ [ "$rs_rc" != 0 ] && grep -qF 'busy: 2 runs at once (orchestrate.max_concurrent_runs 2): ' <<<"$rs_e" && grep -qF 'RS-1 (owned by s-RS-1)' <<<"$rs_e"; } \
  || { bad "FR-004 a third --pid claim over the default cap of 2 must be refused 'busy:' naming the runs — rc=$rs_rc: $rs_e"; rs_fail=1; }
jq -e '.owner == null' "$rs_ld/RS-3.json" >/dev/null || { bad "FR-004 a busy claim must write nothing on the entry"; rs_fail=1; }
rs_claim RS-3 implement interactive; [ "$rs_rc" = 0 ] || { bad "FR-004 an interactive claim is no run: never refused by the cap — rc=$rs_rc: $rs_e"; rs_fail=1; }
# interactive claims are not counted: one run + one lane → a second run still passes (mutation b counts the lane)
rs_free; rs_claim RS-1 plan pid; rs_claim RS-7 implement interactive; rs_claim RS-2 deploy pid
[ "$rs_rc" = 0 ] || { bad "FR-004 one run + one interactive claim → a second run passes — rc=$rs_rc: $rs_e"; rs_fail=1; }
if rs_mutant ledger.sh 's/ and \.owner\.pid != null)/)/'; then
  rs_free; rs_claim RS-1 plan pid "$RS_MD/ledger.sh"; rs_claim RS-8 implement interactive "$RS_MD/ledger.sh"; rs_claim RS-2 deploy pid "$RS_MD/ledger.sh"
  [ "$rs_rc" = 0 ] && { bad "mutation (b) survived: interactive claims counted, the second run still passed"; rs_fail=1; }
  rm -rf "$RS_MD"
fi
if rs_mutant ledger.sh 's/\[ -z "\$RUNS" \] || die/true || die/'; then
  rs_free; rs_claim RS-1 plan pid "$RS_MD/ledger.sh"; rs_claim RS-2 deploy pid "$RS_MD/ledger.sh"; rs_claim RS-9 implement pid "$RS_MD/ledger.sh"
  [ "$rs_rc" = 0 ] || { bad "mutation (b) survived: the cap check dropped, the third run still refused"; rs_fail=1; }
  rm -rf "$RS_MD"
fi
# max_concurrent_runs 3 → a third passes, a fourth (verify — not exempt from this cap) is busy
rs_free; rs_conf '{"max_concurrent_runs":3}'
rs_claim RS-1 plan pid; rs_claim RS-2 deploy pid; rs_claim RS-4 verify pid
[ "$rs_rc" = 0 ] || { bad "FR-004 max_concurrent_runs 3 admits a third run — rc=$rs_rc: $rs_e"; rs_fail=1; }
rs_claim RS-5 verify pid
{ [ "$rs_rc" != 0 ] && grep -qF 'busy: 3 runs at once (orchestrate.max_concurrent_runs 3)' <<<"$rs_e"; } || { bad "FR-004 a fourth run over 3 is busy, verify included — rc=$rs_rc: $rs_e"; rs_fail=1; }
# run-survival/FR-005: an invalid value dies naming it and the range
for rs_v in 0 9 '"two"' 1.5; do
  rs_free; rs_conf "{\"max_concurrent_runs\":$rs_v}"; rs_claim RS-6 plan pid
  { [ "$rs_rc" != 0 ] && grep -qF "orchestrate.max_concurrent_runs must be a whole number from 1 to 8 (got '$(tr -d '"' <<<"$rs_v")')" <<<"$rs_e"; } \
    || { bad "FR-005 max_concurrent_runs $rs_v must die naming the value and 1–8 — rc=$rs_rc: $rs_e"; rs_fail=1; }
done
rs_free; rs_conf '{}'
[ "$rs_fail" -eq 0 ] && ok "ledger claim --pid: busy over max_concurrent_runs (default 2, ledger-wide, verify counted), interactive claims neither counted nor refused, 3 admits a third, invalid values die with 1–8; mutation b (both halves) caught (run-survival FR-004 FR-005)"

# --- the launcher: detach, relay, survive (T009–T012) -----------------------------------------------------------
head_ "session-launch: the run tail detached, relayed, surviving its caller; busy is exit 75 (run-survival FR-001 FR-002 FR-003 FR-006 FR-007 FR-008)"
rs_fail=0
rs_bin="$rs_w/bin"; mkdir -p "$rs_bin"; rs_res="$rs_bin/result.json"
cat > "$rs_bin/claude" <<EOF
#!/bin/bash
# FakeClaude (run-survival): records its argv and what it inherited, makes the worktree -w names, and — while
# $rs_bin/hold exists — reports its parent and waits for $rs_bin/go; then prints the result the test set.
printf '%s\n' "\$*" >> "$rs_bin/claude.argv"
{ echo "ppid=\$PPID"; echo "xdg=\${XDG_CACHE_HOME-unset}"; echo "gcc=\${GIT_CONFIG_COUNT-unset}"; echo "det=\${HEFESTO_RUN_DETACHED-unset}"; } > "$rs_bin/claude.env"
prev=""; for a in "\$@"; do if [ "\$prev" = "-w" ]; then git worktree add -q "\$PWD/.claude/worktrees/\$a" -b "\$a" >/dev/null 2>&1 && git -C "\$PWD/.claude/worktrees/\$a" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "work \$a" >/dev/null 2>&1; fi; prev="\$a"; done
if [ -e "$rs_bin/hold" ]; then echo "\$PPID" > "$rs_bin/started"; n=0; while [ ! -e "$rs_bin/go" ] && [ "\$n" -lt 600 ]; do sleep 0.1; n=\$((n + 1)); done; fi
cat "$rs_res"
EOF
chmod +x "$rs_bin/claude"
rs_pr() { printf '{"session_id":"s","total_cost_usd":0,"structured_output":{"summary":"ok","route":"fix","outcome":"%s","pr_url":"https://github.com/o/r/pull/1","blocked_on":null,"spec_dir":null}}\n' "${1:-pr}" > "$rs_res"; }
rs_phase() { jq -r '.phase' "$rs_ld/$1.json"; }
# rs_sd <detacher dir> <launcher> <args…>: a launch with HEFESTO_RUN_DETACH unset and the fakes first on PATH;
# extra env pairs in RS_XENV. stdout → $rs_w/sl.out, stderr → $rs_w/sl.err, rc → rs_rc
RS_XENV=()
rs_sd() {
  local p="$1" sl="$2"; shift 2; rs_rc=0
  (cd "$rs_t" && env -u HEFESTO_RUN_DETACH ${RS_XENV[@]+"${RS_XENV[@]}"} PATH="$p" CLAUDE_CONFIG_DIR="$rs_cfg" bash "$sl" "$@") > "$rs_w/sl.out" 2> "$rs_w/sl.err" || rs_rc=$?
}
rs_pr pr
# run-survival/FR-001 (SC-001): both on PATH → systemd-run --user --scope, then setsid; the run completes
rs_sd "$rs_dboth:$rs_bin:$PATH" "$RS_SL" implement RS-10
{ [ "$rs_rc" = 0 ] && head -1 "$rs_dlog" | grep -q '^systemd-run --user --scope --collect --quiet -p OOMPolicy=continue --unit hefesto-RS-10-implement-[0-9]* -- setsid -w bash ' \
  && sed -n 2p "$rs_dlog" | grep -qF "setsid -w bash $RS_SL implement RS-10" && [ "$(rs_phase RS-10)" = verify ]; } \
  || { bad "FR-001 systemd-run + setsid on PATH → the run goes through both and completes — rc=$rs_rc log: $(cat "$rs_dlog") err: $(head -c 300 "$rs_w/sl.err")"; rs_fail=1; }
# run-survival/FR-003 (SC-002): the caller prints the run's stdout — the final ledger entry
jq -e '.id == "RS-10" and .phase == "verify"' "$rs_w/sl.out" >/dev/null 2>&1 || { bad "FR-003 the caller relays the run's stdout (the final entry): $(head -c 200 "$rs_w/sl.out")"; rs_fail=1; }
# run-survival/FR-002: the worker inherited the caller's cache (no nesting), not the marker, not the git neutralisers
rs_wc="$XDG_CACHE_HOME/hefesto/worker-cache/$(basename "$rs_t")-$(printf '%s' "$rs_t" | cksum | cut -d' ' -f1)"
{ grep -qxF "xdg=$rs_wc" "$rs_bin/claude.env" && grep -qx 'det=unset' "$rs_bin/claude.env" && grep -qxF "gcc=${GIT_CONFIG_COUNT-unset}" "$rs_bin/claude.env"; } \
  || { bad "FR-002 the detached worker sees XDG_CACHE_HOME=$rs_wc, no HEFESTO_RUN_DETACHED and the caller's GIT_CONFIG_COUNT: $(tr '\n' ' ' < "$rs_bin/claude.env")"; rs_fail=1; }
rs_rundir="$XDG_CACHE_HOME/hefesto/runs/$(printf '%s' "$(cd "$rs_t" && bash "$RS_LG" dir)" | cksum | cut -d' ' -f1)"
{ [ -f "$rs_rundir/RS-10.current" ] && ls "$rs_rundir"/RS-10.implement.*.events.jsonl >/dev/null 2>&1 && [ ! -d "$rs_wc/hefesto/runs" ]; } \
  || { bad "FR-002 the copy's events and .current land in the caller's RUNDIR ($rs_rundir), never in the worker cache"; rs_fail=1; }
ls "$rs_rundir"/RS-10.*.launcher.* >/dev/null 2>&1 && { bad "FR-003 the caller removes the launcher log it relayed: $(ls "$rs_rundir"/RS-10.*.launcher.*)"; rs_fail=1; }
: > "$rs_dlog"
# only setsid usable (no user manager) → setsid alone
rs_sd "$rs_dsid:$rs_bin:$PATH" "$RS_SL" implement RS-12
{ [ "$rs_rc" = 0 ] && grep -q '^setsid -w bash ' "$rs_dlog" && ! grep -q '^systemd-run' "$rs_dlog"; } || { bad "FR-001 only setsid usable → setsid -w alone — rc=$rs_rc log: $(cat "$rs_dlog")"; rs_fail=1; }
: > "$rs_dlog"
# neither → attached, with the note
rs_sd "$rs_bin:$rs_farm" "$RS_SL" implement RS-13
{ [ "$rs_rc" = 0 ] && grep -qF 'session-launch: no systemd-run or setsid — the run is attached to this shell' "$rs_w/sl.err" && [ "$(rs_phase RS-13)" = verify ]; } \
  || { bad "FR-001 neither systemd-run nor setsid → attached with the note, same outcome — rc=$rs_rc: $(head -c 300 "$rs_w/sl.err")"; rs_fail=1; }
# --dry-run never detaches
rs_sd "$rs_dboth:$rs_bin:$PATH" "$RS_SL" implement RS-14 --dry-run
[ -s "$rs_dlog" ] && { bad "FR-001 --dry-run must call neither systemd-run nor setsid: $(cat "$rs_dlog")"; rs_fail=1; }
: > "$rs_dlog"
# run-survival/FR-003: a refusal in the copy — the worker reported failed — comes back with its code and both streams
rs_pr failed
rs_sd "$rs_dsid:$rs_bin:$PATH" "$RS_SL" implement RS-15
{ [ "$rs_rc" = 1 ] && grep -qF "the worker reported outcome 'failed'" "$rs_w/sl.err" && jq -e '.id == "RS-15"' "$rs_w/sl.out" >/dev/null 2>&1 && grep -q '^setsid' "$rs_dlog"; } \
  || { bad "FR-003 the copy's exit code and both streams reach the caller — rc=$rs_rc err: $(head -c 300 "$rs_w/sl.err")"; rs_fail=1; }
: > "$rs_dlog"; rs_pr pr
# mutation (a): the detach call dropped → nothing recorded by the fakes
if rs_mutant session-launch.sh 's/read -r -a PRE <<<"\$(hl_detacher/PRE=(); : "$(hl_detacher/'; then
  rs_sd "$rs_dboth:$rs_bin:$PATH" "$RS_MD/session-launch.sh" implement RS-16
  grep -q '^setsid' "$rs_dlog" && { bad "mutation (a) survived: the detach call dropped, setsid still recorded"; rs_fail=1; }
  rm -rf "$RS_MD"; : > "$rs_dlog"
fi

# run-survival/FR-002 FR-003 (SC-002): the claim's pid is the copy's; SIGKILL of the caller leaves the run going
: > "$rs_bin/hold"; rm -f "$rs_bin/go" "$rs_bin/started"
(cd "$rs_t" && exec env -u HEFESTO_RUN_DETACH PATH="$rs_dsid:$rs_bin:$PATH" CLAUDE_CONFIG_DIR="$rs_cfg" bash "$RS_SL" implement RS-17) >/dev/null 2>&1 &
rs_caller=$!
if rs_wait '[ -s "$rs_bin/started" ]' 300; then
  rs_opid="$(jq -r '.owner.pid // empty' "$rs_ld/RS-17.json")"
  { [ "$rs_opid" = "$(cat "$rs_bin/started")" ] && [ "$rs_opid" != "$rs_caller" ]; } \
    || { bad "FR-002 owner.pid ($rs_opid) must be the copy — the fake claude's parent ($(cat "$rs_bin/started")) — not the caller ($rs_caller)"; rs_fail=1; }
  kill -9 "$rs_caller" 2>/dev/null; wait "$rs_caller" 2>/dev/null
  : > "$rs_bin/go"
  rs_wait '[ "$(rs_phase RS-17)" = verify ]' 300 || { bad "FR-003 after kill -9 of the caller the run must still transcribe — phase $(rs_phase RS-17), owner $(jq -c .owner "$rs_ld/RS-17.json")"; rs_fail=1; }
else
  bad "FR-002 the held run never started (no $rs_bin/started)"; rs_fail=1; kill -9 "$rs_caller" 2>/dev/null
fi
# kill <owner.pid> stops a run: its trap stops the worker and records exit 143; the caller relays 143
rm -f "$rs_bin/go" "$rs_bin/started"
(cd "$rs_t" && exec env -u HEFESTO_RUN_DETACH PATH="$rs_dsid:$rs_bin:$PATH" CLAUDE_CONFIG_DIR="$rs_cfg" bash "$RS_SL" implement RS-18) >/dev/null 2>&1 &
rs_caller=$!
if rs_wait '[ -s "$rs_bin/started" ]' 300; then
  kill "$(jq -r '.owner.pid' "$rs_ld/RS-18.json")" 2>/dev/null
  wait "$rs_caller"; rs_rc=$?
  { [ "$rs_rc" = 143 ] && jq -e '.owner == null and .runs[-1].exit == 143' "$rs_ld/RS-18.json" >/dev/null; } \
    || { bad "FR-003 kill <owner.pid> → the run records exit 143 and the caller exits 143 — rc=$rs_rc runs: $(jq -c '.runs[-1]' "$rs_ld/RS-18.json")"; rs_fail=1; }
else
  bad "FR-003 the held run RS-18 never started"; rs_fail=1; kill -9 "$rs_caller" 2>/dev/null
fi
rm -f "$rs_bin/hold" "$rs_bin/go" "$rs_bin/started"; : > "$rs_dlog"

# The retry: a systemd-run that never ran the copy → exactly one setsid -w retry; a copy that ran and refused → none
RS_XENV=(RS_SDR_FAIL=1); rs_sd "$rs_dboth:$rs_bin:$PATH" "$RS_SL" implement RS-19; RS_XENV=()
{ [ "$rs_rc" = 0 ] && [ "$(grep -c '^setsid -w ' "$rs_dlog")" = 1 ] && grep -qF 'detaching with setsid instead' "$rs_w/sl.err" && [ "$(rs_phase RS-19)" = verify ]; } \
  || { bad "FR-001 a refused scope → one setsid -w retry, and the run completes — rc=$rs_rc log: $(cat "$rs_dlog")"; rs_fail=1; }
: > "$rs_dlog"
rs_badcfg="$rs_w/ro-cfg"; mkdir -p "$rs_badcfg"; chmod 555 "$rs_badcfg"
cp "$rs_ld/RS-20.json" "$rs_w/before.json"
RS_XENV=(RS_BADCFG="$rs_badcfg"); rs_sd "$rs_dboth:$rs_bin:$PATH" "$RS_SL" implement RS-20
{ [ "$rs_rc" = 1 ] && [ "$(grep -c '^setsid -w ' "$rs_dlog")" = 1 ] && grep -qi 'sandbox' "$rs_w/sl.err" && cmp -s "$rs_w/before.json" "$rs_ld/RS-20.json"; } \
  || { bad "FR-001 a copy that ran and refused (before its claim) is never launched again — rc=$rs_rc log: $(cat "$rs_dlog")"; rs_fail=1; }
: > "$rs_dlog"
# mutation (i): the .started condition dropped from the retry → the refused copy is launched a second time
if rs_mutant host-limits.sh 's/ \[ ! -e "\$ll\.started" \] &&//'; then
  rs_sd "$rs_dboth:$rs_bin:$PATH" "$RS_MD/session-launch.sh" implement RS-21
  [ "$(grep -c '^setsid -w ' "$rs_dlog")" -ge 2 ] || { bad "mutation (i) survived: the .started condition dropped, yet no second launch"; rs_fail=1; }
  rm -rf "$RS_MD"; : > "$rs_dlog"
fi
RS_XENV=(); chmod 755 "$rs_badcfg"

# run-survival/FR-006 FR-007 (SC-004): the memory gate in the launcher — 75, nothing claimed or written
rs_mem_case() { # id meminfo psi → rc in rs_rc, stderr in rs_se; the entry kept in before.json for a byte comparison
  cp "$rs_ld/$1.json" "$rs_w/before.json"; rs_rc=0
  (cd "$rs_t" && env HEFESTO_PROC_MEMINFO="$2" HEFESTO_PROC_PRESSURE="$3" PATH="$rs_bin:$PATH" CLAUDE_CONFIG_DIR="$rs_cfg" bash "${RS_LAUNCHER:-$RS_SL}" implement "$1") >/dev/null 2>"$rs_w/sl.err" || rs_rc=$?
  rs_se="$(cat "$rs_w/sl.err")"
}
rs_mem_case RS-22 "$rs_w/mem2048" "$HEFESTO_PROC_PRESSURE"
{ [ "$rs_rc" = 75 ] && grep -qF 'busy: memory — 2048 MiB available < 4096 MiB' <<<"$rs_se" && cmp -s "$rs_w/before.json" "$rs_ld/RS-22.json"; } \
  || { bad "FR-006 2048 MiB available under the default 4096 → exit 75, entry unchanged — rc=$rs_rc: $rs_se"; rs_fail=1; }
rs_mem_case RS-22 "$HEFESTO_PROC_MEMINFO" "$rs_w/psi63"
{ [ "$rs_rc" = 75 ] && grep -qF 'busy: memory pressure some avg60=63.20 > 50' <<<"$rs_se" && cmp -s "$rs_w/before.json" "$rs_ld/RS-22.json"; } \
  || { bad "FR-006 PSI avg60 63.20 → exit 75, entry unchanged — rc=$rs_rc: $rs_se"; rs_fail=1; }
# verify gate 2026-11-16 (B1): a plan launch refused as busy on an item with an rfc: line — the RFC pin was written
# ~190 lines before the gate; now it is recorded only after the claim, so the entry stays byte-identical
mkdir -p "$rs_t/docs/rfcs"; printf '# RFC RS-41\nthe idea\n' > "$rs_t/docs/rfcs/RS-41.md"
printf '\n## RS-41 — item with an RFC\nb\nrfc: docs/rfcs/RS-41.md\n' >> "$rs_t/tasks/TODO.md"
(cd "$rs_t" && bash "$RS_LG" init RS-41 --kind tasks-repo --ref t >/dev/null 2>&1)
rs_plan_busy() { # [launcher] → rc in rs_rc; RS-41's entry kept in before.json
  cp "$rs_ld/RS-41.json" "$rs_w/before.json"; rs_rc=0
  (cd "$rs_t" && env HEFESTO_PROC_MEMINFO="$rs_w/mem2048" HEFESTO_PROC_PRESSURE="$HEFESTO_PROC_PRESSURE" PATH="$rs_bin:$PATH" CLAUDE_CONFIG_DIR="$rs_cfg" bash "${1:-$RS_SL}" plan RS-41) >/dev/null 2>"$rs_w/sl.err" || rs_rc=$?
}
rs_plan_busy
{ [ "$rs_rc" = 75 ] && cmp -s "$rs_w/before.json" "$rs_ld/RS-41.json"; } \
  || { bad "FR-006 a busy plan launch on an item with an RFC writes nothing (no source.rfc) — rc=$rs_rc: $(jq -c .source "$rs_ld/RS-41.json") $(head -c 200 "$rs_w/sl.err")"; rs_fail=1; }
if rs_mutant launch-item.sh 's/^  \[ -z "\${RFC_PIN:-}" \] || cp "\$snap" "\$RFC_PIN"/  "$LEDGER" record "$ID" --rfc-snapshot "$snap" >\/dev\/null; [ -z "${RFC_PIN:-}" ] || cp "$snap" "$RFC_PIN"/'; then
  rs_plan_busy "$RS_MD/session-launch.sh"
  cmp -s "$rs_w/before.json" "$rs_ld/RS-41.json" && { bad "mutation (B1) survived: the pin recorded before the gate, yet the busy plan launch left the entry unchanged"; rs_fail=1; }
  rm -rf "$RS_MD"
fi
rs_conf '{"min_free_mb":0}'; rs_mem_case RS-23 "$rs_w/mem2048" "$HEFESTO_PROC_PRESSURE"
{ [ "$rs_rc" = 0 ] && [ "$(rs_phase RS-23)" = verify ]; } || { bad "FR-006 min_free_mb 0 → the floor is off and the launch runs — rc=$rs_rc: $rs_se"; rs_fail=1; }
for rs_v in -1 '"4G"'; do
  rs_conf "{\"min_free_mb\":$rs_v}"; rs_mem_case RS-24 "$HEFESTO_PROC_MEMINFO" "$HEFESTO_PROC_PRESSURE"
  { [ "$rs_rc" = 1 ] && grep -qF "orchestrate.min_free_mb must be a whole number of MiB, 0 or more (got '$(tr -d '"' <<<"$rs_v")')" <<<"$rs_se"; } \
    || { bad "FR-007 min_free_mb $rs_v → exit 1 naming the value and the shape — rc=$rs_rc: $rs_se"; rs_fail=1; }
done
rs_conf '{}'
(cd "$rs_t" && env HEFESTO_PROC_MEMINFO="$rs_w/mem2048" PATH="$rs_bin:$PATH" CLAUDE_CONFIG_DIR="$rs_cfg" bash "$RS_SL" implement RS-24 --dry-run) >/dev/null 2>&1 \
  || { bad "FR-006 --dry-run is never refused for memory"; rs_fail=1; }
# mutation (h): the gate moved to the caller only — the copy, which claims, must still measure (FakeSetsid hands the
# copy alone a low fixture: memory that ran out between the two)
RS_XENV=(RS_LOWMEM="$rs_w/mem2048")
rs_sd "$rs_dsid:$rs_bin:$PATH" "$RS_SL" implement RS-25
[ "$rs_rc" = 75 ] || { bad "FR-006 the copy that claims runs the memory gate (a low fixture seen only by the copy → 75) — rc=$rs_rc: $(head -c 300 "$rs_w/sl.err")"; rs_fail=1; }
rs_gate="$(grep '^MEMMSG="\$(hl_memory_gate' "$RS_SL")"
RS_MD="$(mktemp -d)"; for rs_h in "$REPO"/hooks/*.sh; do ln -s "$rs_h" "$RS_MD/$(basename "$rs_h")"; done; rm "$RS_MD/session-launch.sh"
RS_GATE="$rs_gate" awk 'index($0, "MEMMSG=\"$(hl_memory_gate") == 1 { next }
  index($0, "  [ \"${#PRE[@]}\" -eq 0 ] || { rm -f \"${RFC_PIN:-}\"; hl_run_detached") == 1 { print "  " ENVIRON["RS_GATE"] } { print }' "$RS_SL" > "$RS_MD/session-launch.sh"
if [ -z "$rs_gate" ] || cmp -s "$RS_SL" "$RS_MD/session-launch.sh" || [ "$(grep -c '^ *MEMMSG="\$(hl_memory_gate' "$RS_MD/session-launch.sh")" != 1 ] \
   || grep -q '^MEMMSG=' "$RS_MD/session-launch.sh"; then
  bad "mutation (h) did not apply (the gate line moved into the caller's detach branch)"; rs_fail=1
else
  rs_sd "$rs_dsid:$rs_bin:$PATH" "$RS_MD/session-launch.sh" implement RS-26
  [ "$rs_rc" = 75 ] && { bad "mutation (h) survived: the memory gate in the caller only, yet the copy's low memory still refused"; rs_fail=1; }
fi
rm -rf "$RS_MD"; : > "$rs_dlog"; RS_XENV=()

# run-survival/FR-004 run-survival/FR-008 (SC-003): a launch over the run cap exits 75 with nothing recorded
rs_free; rs_claim RS-1 plan pid; rs_claim RS-2 deploy pid
rs_mem_case RS-27 "$HEFESTO_PROC_MEMINFO" "$HEFESTO_PROC_PRESSURE"
{ [ "$rs_rc" = 75 ] && grep -qF ': busy: 2 runs at once' <<<"$rs_se" && cmp -s "$rs_w/before.json" "$rs_ld/RS-27.json"; } \
  || { bad "FR-008 a launch refused by the run cap → exit 75, entry unchanged — rc=$rs_rc: $rs_se"; rs_fail=1; }
# mutation (f): the busy → 75 mapping dropped → exit 1
if rs_mutant session-launch.sh 's/case "\$CLERR" in \*": busy: "\*) exit 75 ;; esac; //'; then
  RS_LAUNCHER="$RS_MD/session-launch.sh" rs_mem_case RS-27 "$HEFESTO_PROC_MEMINFO" "$HEFESTO_PROC_PRESSURE"
  [ "$rs_rc" = 75 ] && { bad "mutation (f) survived: the busy → 75 mapping dropped, still 75"; rs_fail=1; }
  rm -rf "$RS_MD"
fi
# run-survival/FR-008: every other refusal keeps exit 1 — a claim refused because the entry is already owned
rs_free; rs_claim RS-28 implement interactive
rs_mem_case RS-28 "$HEFESTO_PROC_MEMINFO" "$HEFESTO_PROC_PRESSURE"
{ [ "$rs_rc" = 1 ] && grep -qF 'already owned' <<<"$rs_se"; } || { bad "FR-008 a non-busy claim refusal keeps exit 1 — rc=$rs_rc: $rs_se"; rs_fail=1; }
rs_free

# Lane mode (HEFESTO_TRUSTED_TOP set): an existing worktree launched through the detacher from the main checkout must
# not die as "not the main checkout" (the copy starts where the caller did); the /proc seam is ignored (D8, mutation
# j); HEFESTO_RUN_DETACH=0 is ignored (mutation l); a lane-set HEFESTO_RUN_DETACHED writes no marker (mutation k)
rs_conf '{"min_free_mb":2}'
rs_lane() { # launcher id [extra env…] → rc in rs_rc, stderr in rs_se; the detach seam set, a 1 MiB fixture, both fakes
  local sl="$1" id="$2"; shift 2; rs_rc=0
  (cd "$rs_t" && env HEFESTO_TRUSTED_TOP="$rs_t" HEFESTO_RUN_DETACH=0 HEFESTO_PROC_MEMINFO="$rs_w/mem1" "$@" PATH="$rs_dboth:$rs_bin:$PATH" CLAUDE_CONFIG_DIR="$rs_cfg" bash "$sl" implement "$id") >/dev/null 2>"$rs_w/sl.err" || rs_rc=$?
  rs_se="$(cat "$rs_w/sl.err")"
}
rs_existing_wt() { # id → a worktree made by an attached run whose worker failed (the entry stays re-dispatchable)
  rs_pr failed; (cd "$rs_t" && env PATH="$rs_bin:$PATH" CLAUDE_CONFIG_DIR="$rs_cfg" bash "$RS_SL" implement "$1") >/dev/null 2>&1; rs_pr pr
  [ -d "$rs_t/.claude/worktrees/$1" ]
}
rs_existing_wt RS-30 || { bad "the lane-mode fixture RS-30 has no worktree"; rs_fail=1; }
: > "$rs_dlog"; rs_lane "$RS_SL" RS-30
{ [ "$rs_rc" = 0 ] && ! grep -qF 'is not the main checkout' <<<"$rs_se" && ! grep -qF '1 MiB available' <<<"$rs_se" && grep -q '^setsid -w ' "$rs_dlog" && [ "$(rs_phase RS-30)" = verify ]; } \
  || { bad "FR-001 FR-007 lane mode: an existing worktree through the detacher runs from the main checkout, reads the real /proc and still detaches — rc=$rs_rc log: $(cat "$rs_dlog") err: $(head -c 400 <<<"$rs_se")"; rs_fail=1; }
: > "$rs_dlog"
if rs_mutant session-launch.sh 's/\[ "\$LANE_MODE" = 1 \] || { MEMINFO=/{ MEMINFO=/'; then   # mutation (j)
  rs_existing_wt RS-31; : > "$rs_dlog"; rs_lane "$RS_MD/session-launch.sh" RS-31
  { [ "$rs_rc" = 75 ] || grep -qF '1 MiB available' <<<"$rs_se"; } || { bad "mutation (j) survived: the LANE_MODE test on the /proc seam dropped, the fixture still unread — rc=$rs_rc"; rs_fail=1; }
  rm -rf "$RS_MD"; : > "$rs_dlog"
fi
if rs_mutant host-limits.sh 's/\[ "\${3:-0}" = 0 \] && \[ "\${HEFESTO_RUN_DETACH:-}" = 0 \]/[ "${HEFESTO_RUN_DETACH:-}" = 0 ]/'; then   # mutation (l)
  rs_existing_wt RS-32; : > "$rs_dlog"; rs_lane "$RS_MD/session-launch.sh" RS-32
  grep -q '^setsid' "$rs_dlog" && { bad "mutation (l) survived: HEFESTO_RUN_DETACH=0 honoured in lane mode, yet a detacher was recorded"; rs_fail=1; }
  rm -rf "$RS_MD"; : > "$rs_dlog"
fi
rs_k="$rs_w/lane-set"; mkdir -p "$rs_k"
: > "$rs_dlog"; rs_lane "$RS_SL" RS-33 HEFESTO_RUN_DETACHED="$rs_k/x.launcher"
{ [ "$rs_rc" = 0 ] && [ ! -e "$rs_k/x.launcher.started" ] && grep -q '^setsid -w ' "$rs_dlog"; } \
  || { bad "FR-001 R4: a lane-set HEFESTO_RUN_DETACHED outside the runs folder writes no .started and does not stop the detach — rc=$rs_rc log: $(cat "$rs_dlog") $(ls "$rs_k") $(head -c 300 <<<"$rs_se")"; rs_fail=1; }
: > "$rs_dlog"
if rs_mutant session-launch.sh 's|"\${XDG_CACHE_HOME:-\$HOME/.cache}/hefesto/runs/"\*\.launcher) RUN_COPY=1;|*) RUN_COPY=1;|'; then   # mutation (k)
  rs_lane "$RS_MD/session-launch.sh" RS-34 HEFESTO_RUN_DETACHED="$rs_k/x.launcher"
  [ -e "$rs_k/x.launcher.started" ] || { bad "mutation (k) survived: the .started path guard dropped, yet nothing was written under $rs_k"; rs_fail=1; }
  rm -rf "$RS_MD"; : > "$rs_dlog"
fi
# run-survival/FR-001 (code review 2026-11-16): a cache root with /../ in it — the copy's marker fails the path guard,
# so a launcher that detached anyway would detach again at every level; it runs attached instead, once
rs_dots="$rs_w/xdg-dots/../xdg-real"; mkdir -p "$rs_w/xdg-dots" "$rs_w/xdg-real"; : > "$rs_dlog"
RS_XENV=(XDG_CACHE_HOME="$rs_dots"); rs_sd "$rs_dboth:$rs_bin:$PATH" "$RS_SL" implement RS-35
{ [ "$rs_rc" = 0 ] && [ ! -s "$rs_dlog" ] && grep -qF 'has a /../ in it — the run is attached to this shell' "$rs_w/sl.err" && [ "$(rs_phase RS-35)" = verify ]; } \
  || { bad "FR-001 a cache root with /../ → one attached run, no detach — rc=$rs_rc log: $(cat "$rs_dlog") err: $(head -c 300 "$rs_w/sl.err")"; rs_fail=1; }
: > "$rs_dlog"
if rs_mutant host-limits.sh '/has a \/\.\.\/ in it — the run is attached to this shell/d'; then   # the runs-folder check dropped
  rs_sd "$rs_dboth:$rs_bin:$PATH" "$RS_MD/session-launch.sh" implement RS-36
  [ "$(grep -c '^setsid' "$rs_dlog")" -ge 2 ] || { bad "mutation survived: the /../ runs-folder check dropped, yet the launcher did not detach again from its own copy — log: $(cat "$rs_dlog")"; rs_fail=1; }
  rm -rf "$RS_MD"
fi
RS_XENV=(); : > "$rs_dlog"
rs_conf '{}'
[ "$rs_fail" -eq 0 ] && ok "session-launch: the run tail detached (systemd-run → setsid → attached with a note), --dry-run never; output and exit code relayed; owner.pid is the copy; kill -9 of the caller leaves the run transcribing; kill <owner.pid> records 143; one setsid retry only when the copy never started; memory and run cap → 75 with the entry unchanged; lane mode safe; mutations a f h i j k l caught (run-survival FR-001 FR-002 FR-003 FR-006 FR-007 FR-008)"

# --- the shellcheck helpers, the commit hook and setup (T013, T014, T016) -----------------------------------------
head_ "speckit-helper shellcheck-changed / shellcheck-files; the commit hook; setup --check's oomd note (run-survival FR-009 FR-010 FR-012 FR-014)"
rs_fail=0
rs_hp() { # dir PATH args… → stdout+stderr in rs_o, rc in rs_rc, FakeShellcheck log in RS_SC_LOG
  local d="$1" p="$2"; shift 2; : > "$RS_SC_LOG"; rs_rc=0
  rs_o="$(cd "$d" && PATH="$p" bash "$REPO/hooks/speckit-helper.sh" "$@" 2>&1)" || rs_rc=$?
}
# run-survival/FR-009: the changed files only; big.sh skipped with its note; exit 2 (incomplete) for the skip
rs_hp "$rs_g" "$rs_scf:$PATH" shellcheck-changed --base main
{ [ "$rs_rc" = 2 ] && grep -qF "shellcheck: skipped $rs_g/big.sh (3500 lines > 3000)" <<<"$rs_o" && grep -qF "args=-S warning $rs_g/a.sh" "$RS_SC_LOG" \
  && grep -qF "$rs_g/b.sh" "$RS_SC_LOG" && grep -qF "$rs_g/c.bash" "$RS_SC_LOG" && grep -qF "$rs_g/d.sh" "$RS_SC_LOG" && ! grep -qF 'big.sh' "$RS_SC_LOG" && grep -qF 'shell check incomplete' <<<"$rs_o"; } \
  || { bad "FR-009 shellcheck-changed checks a.sh b.sh c.bash, skips big.sh with the note, exits 2 — rc=$rs_rc: $rs_o / $(cat "$RS_SC_LOG")"; rs_fail=1; }
rs_hp "$rs_g" "$rs_scf:$PATH" shellcheck-changed
{ [ "$rs_rc" = 2 ] && grep -qF "$rs_g/a.sh" "$RS_SC_LOG"; } || { bad "FR-009 shellcheck-changed without --base diffs against pr_base (main) — rc=$rs_rc: $rs_o"; rs_fail=1; }
RS_SC_RC=1 rs_hp "$rs_g" "$rs_scf:$PATH" shellcheck-changed --base main
[ "$rs_rc" = 1 ] || { bad "FR-009 a finding exits 1 — rc=$rs_rc: $rs_o"; rs_fail=1; }
RS_SC_RC=137 rs_hp "$rs_g" "$rs_scf:$PATH" shellcheck-changed --base main
{ [ "$rs_rc" = 2 ] && grep -qF "shellcheck: could not check $rs_g/a.sh (exit 137" <<<"$rs_o"; } || { bad "FR-009 a shellcheck killed (137) → could not check, exit 2 — rc=$rs_rc: $rs_o"; rs_fail=1; }
rs_hp "$rs_g" "$rs_farm" shellcheck-changed --base main
{ [ "$rs_rc" = 2 ] && grep -qxF 'shellcheck: not installed — skipped' <<<"$rs_o"; } || { bad "FR-009 shellcheck not installed → 'not installed — skipped', exit 2 — rc=$rs_rc: $rs_o"; rs_fail=1; }
rs_hp "$rs_g" "$rs_scf:$PATH" shellcheck-changed --base no-such-ref
[ "$rs_rc" = 2 ] || { bad "FR-009 a base that cannot be diffed is incomplete (2), never clean — rc=$rs_rc: $rs_o"; rs_fail=1; }
rs_clean="$rs_w/clean-repo"; git init -q -b main "$rs_clean"; git -C "$rs_clean" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
rs_hp "$rs_clean" "$rs_scf:$PATH" shellcheck-changed --base HEAD
{ [ "$rs_rc" = 0 ] && grep -qxF 'shellcheck: no changed shell files' <<<"$rs_o"; } || { bad "FR-009 no changed shell file → 'shellcheck: no changed shell files', exit 0 — rc=$rs_rc: $rs_o"; rs_fail=1; }
# run-survival/FR-014: shellcheck-files — the named files, no line skip
rs_hp "$rs_g" "$rs_scf:$PATH" shellcheck-files --severity warning big.sh a.sh
{ [ "$rs_rc" = 0 ] && grep -qxF 'args=-S warning big.sh' "$RS_SC_LOG" && grep -qxF 'args=-S warning a.sh' "$RS_SC_LOG"; } \
  || { bad "FR-014 shellcheck-files checks every named file, one process each, no skip — rc=$rs_rc: $rs_o / $(cat "$RS_SC_LOG")"; rs_fail=1; }
RS_SC_RC=137 rs_hp "$rs_g" "$rs_scf:$PATH" shellcheck-files a.sh
[ "$rs_rc" = 2 ] || { bad "FR-014 shellcheck-files: could not check → 2 — rc=$rs_rc"; rs_fail=1; }

# run-survival/FR-010: the commit hook skips a staged 3500-line file with an advisory; a finding in a small one blocks
rs_q="$rs_w/qbc"; mkdir -p "$rs_q"
# big.sh is 3500 comment lines: no code to trip the hook's 500-code-line gate first, so only the shellcheck skip shows
( cd "$rs_q" && git init -q . && awk 'BEGIN { print "#!/bin/bash"; for (i = 1; i < 3500; i++) print "# line " i }' > big.sh && printf '#!/bin/bash\necho hi\n' > a.sh && git add a.sh big.sh ) >/dev/null 2>&1
rs_qbc() { rs_rc=0; : > "$RS_SC_LOG"; rs_o="$(jq -nc --arg d "$rs_q" '{tool_input:{command:"git commit -m \"feat: x\""},cwd:$d}' | RS_SC_RC="$1" PATH="$rs_scf:/usr/bin:/bin" bash "$REPO/hooks/quality-before-commit.sh" 2>&1)" || rs_rc=$?; }
rs_qbc 0
{ grep -qF 'skipped big.sh (3500 lines > 3000)' <<<"$rs_o" && ! grep -qF 'big.sh' "$RS_SC_LOG" && grep -qF 'a.sh' "$RS_SC_LOG"; } \
  || { bad "FR-010 a staged 3500-line file is skipped with an advisory, never checked; a.sh is — rc=$rs_rc: $rs_o / $(cat "$RS_SC_LOG")"; rs_fail=1; }
if [ "$rs_vm_ok" = 1 ]; then grep -qx 'ulimit=2097152' "$RS_SC_LOG" || { bad "FR-010 the commit hook's shellcheck runs under ulimit -v: $(cat "$RS_SC_LOG")"; rs_fail=1; }; fi
rs_qbc 1
{ [ "$rs_rc" = 2 ] && grep -qF 'shellcheck errors in a.sh' <<<"$rs_o"; } || { bad "FR-010 a finding in a small staged file still blocks — rc=$rs_rc: $rs_o"; rs_fail=1; }

# run-survival/FR-012 (SC-006): setup --check prints the note, with the same exit code and `setup: ok`
rs_p="$rs_w/setup-proj"; rs_sh="$rs_w/setup-home"; git init -q -b main "$rs_p"; mkdir -p "$rs_sh"
rs_su() { (cd "$rs_p" && HOME="$rs_sh" CLAUDE_CONFIG_DIR='' PATH="$rs_om:$PATH" bash "$REPO/hooks/hefesto-setup.sh" "$@" 2>&1); }
rs_su >/dev/null
rs_o1="$(RS_OOMD_ACTIVE=active RS_OOMD_LIMIT=0 rs_su --check)"; rs_rc1=$?
rs_o2="$(RS_OOMD_ACTIVE=active RS_OOMD_LIMIT=80% rs_su --check)"; rs_rc2=$?
{ grep -qF 'setup: note: systemd-oomd' <<<"$rs_o1" && grep -qF 'daemon-reload' <<<"$rs_o1" && grep -qF '90-hefesto-oomd.conf' <<<"$rs_o1" \
  && ! grep -qF 'systemctl disable' <<<"$rs_o1" && [ "$rs_rc1" = "$rs_rc2" ] && [ "$(tail -1 <<<"$rs_o1")" = "$(tail -1 <<<"$rs_o2")" ] \
  && [ "$(tail -1 <<<"$rs_o1")" = "setup: ok" ] && ! grep -qF 'systemd-oomd' <<<"$rs_o2"; } \
  || { bad "FR-012 setup --check: the oomd note at limit 0, none at 80%, same rc and 'setup: ok' — rc $rs_rc1/$rs_rc2: $rs_o1 /// $rs_o2"; rs_fail=1; }
[ "$rs_fail" -eq 0 ] && ok "shellcheck-changed: changed files only, 3000-line skip, 1 finding, 2 incomplete (skip, could not check, not installed, bad base), nothing changed → 0; shellcheck-files: named files, no skip; the commit hook skips a 3500-line file with an advisory under ulimit -v; setup --check's oomd note leaves rc and 'setup: ok' alone (run-survival FR-009 FR-010 FR-012 FR-014)"

# --- the command text (T017, T020) -------------------------------------------------------------------------------
head_ "Command text: shell checks through the helpers; exit 75, the verifier's wait and kill <owner.pid> (run-survival FR-011 FR-013 FR-014)"
rs_fail=0
# run-survival/FR-011: quality and verify check shell files only through shellcheck-changed, and call 2 incomplete
for rs_c in hef.quality.md hef.verify.md; do
  { grep -qF 'speckit-helper.sh shellcheck-changed' "$REPO/commands/$rs_c" && grep -qiF 'shell check incomplete' "$REPO/commands/$rs_c" \
    && grep -qF 'over a tree or a glob' "$REPO/commands/$rs_c"; } || { bad "FR-011 commands/$rs_c routes shell checks through shellcheck-changed, never a tree or glob, exit 2 = incomplete"; rs_fail=1; }
done
# run-survival/FR-014: the doctor no longer runs one shellcheck over hooks/*.sh
{ grep -qF 'speckit-helper.sh shellcheck-files --severity warning' "$REPO/commands/hef.doctor.md" && ! grep -qE '`shellcheck -S warning [^`]*hooks/\*\.sh`' "$REPO/commands/hef.doctor.md"; } \
  || { bad "FR-014 commands/hef.doctor.md checks the hooks through shellcheck-files, never shellcheck over the glob"; rs_fail=1; }
# run-survival/FR-013 (SC-009): orchestrate names 75 in step 3 and in the stage pass, the 10-minute wait, kill <owner.pid>
rs_omd="$REPO/commands/hef.orchestrate.md"
rs_step3="$(sed -n '/^3\. \*\*Send each stage its work/,/^4\. \*\*Publish/p' "$rs_omd")"
rs_stage="$(sed -n '/^3\. \*\*Launch\*\*/,/^4\. \*\*Narrate/p' "$rs_omd")"
{ grep -qF 'Exit 75 is busy' <<<"$rs_step3" && grep -qF '10-minute window' <<<"$rs_step3" && grep -qF 'max_concurrent_runs' <<<"$rs_step3" \
  && grep -qF 'kill <owner.pid>' <<<"$rs_step3" && grep -qF 'exits 75' <<<"$rs_stage" && grep -qF 'busy — next pass' <<<"$rs_stage" \
  && grep -qF 'done busy <id>' <<<"$rs_stage" && grep -qF 'kill <owner.pid>' <<<"$rs_stage" && ! grep -qF 'stopped stops its worker first' "$rs_omd"; } \
  || { bad "FR-013 hef.orchestrate.md: step 3 names exit 75, the run cap, the 10-minute verifier wait and kill <owner.pid>; the stage pass reports 75 as 'busy — next pass' with a done busy doorbell"; rs_fail=1; }
for rs_qs in docs/quickstart.md docs/quickstart.pt-BR.md; do
  { grep -qF 'max_concurrent_runs' "$REPO/$rs_qs" && grep -qF 'min_free_mb' "$REPO/$rs_qs" && grep -qF '**75**' "$REPO/$rs_qs" && grep -qF 'kill <owner.pid>' "$REPO/$rs_qs"; } \
    || { bad "FR-013 $rs_qs names max_concurrent_runs, min_free_mb, exit 75 and kill <owner.pid>"; rs_fail=1; }
done
{ grep -qF '`host-limits.sh`' "$REPO/docs/hooks.md" && grep -qF 'shellcheck-changed' "$REPO/docs/hooks.md"; } || { bad "FR-013 docs/hooks.md has the host-limits.sh row and shellcheck-changed"; rs_fail=1; }
[ "$rs_fail" -eq 0 ] && ok "quality/verify route shell checks through shellcheck-changed; doctor uses shellcheck-files; orchestrate and both quickstarts name exit 75, the run cap, min_free_mb, the 10-minute verifier wait and kill <owner.pid> (run-survival FR-011 FR-013 FR-014)"

chmod -R u+w "$rs_w" 2>/dev/null; rm -rf "$rs_w"
