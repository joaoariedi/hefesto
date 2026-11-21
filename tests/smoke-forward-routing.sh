# shellcheck shell=bash
# shellcheck disable=SC2016  # sed scripts are single-quoted on purpose
# shellcheck disable=SC2154  # fw_w, fw_hh, fw_t come from part 17 (tests/smoke-forward.sh), sourced just before
#
# merge-forward (HEF-31) smoke checks, part 17b — the routing mutations FR-017 lists ("the routing of deploy and merge
# conflict/behind"): each routing caller reverted to the pre-HEF-31 shape (a conflict block that leaves the entry in
# pr) must turn the suite red. The positive cases live in part 17 (tests/smoke-forward.sh); this part was split off
# because that file sits at the 500-code-line limit.
#
# SOURCED by tests/smoke.sh right after tests/smoke-forward.sh, whose fixture and helpers (fw_*, $fw_t) it reuses and
# then removes — the fixture's cleanup lives here, last.

if [ -z "${REPO:-}" ] || [ -z "${fw_t:-}" ] || ! declare -F ok bad head_ fw fw_sl fw_mut fw_mut_sl fw_take fw_pr_entry >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-forward-routing.sh: source it from tests/smoke.sh right after tests/smoke-forward.sh"
  else echo "tests/smoke-forward-routing.sh: source it from tests/smoke.sh after tests/smoke-forward.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

head_ "Merge forward: each routing caller reverted to the old conflict block turns the suite red (merge-forward FR-017 FR-006 FR-007)"
x_fail=0
fw_moved() { fw_j "$1" '.phase == "implement" and (.forwards | length) == 1'; }
# merge-forward/FR-006: the headless deploy transcription — conflict back to a plain block, then behind dropped
fw_pr_entry HEF-70 feat70; fw_dep conflict
fw_mut_sl session-launch.sh 's/conflict|behind) forward_route "\$V" ;;/conflict|behind) "$LEDGER" block "$ID" --kind conflict >\/dev\/null ;;/' \
  && { fw_sl deploy HEF-70 >/dev/null 2>&1; fw_moved HEF-70 && fw_survived "the deploy route blocks conflict again, yet the entry was forwarded"; }; fw_unmut
fw_pr_entry HEF-71 feat71; fw_gh BEHIND feat71 "$fw_hh"; fw_dep behind
fw_mut_sl session-launch.sh 's/conflict|behind) forward_route/conflict) forward_route/' \
  && { fw_sl deploy HEF-71 >/dev/null 2>&1; fw_moved HEF-71 && fw_survived "the deploy route drops behind, yet a behind PR was forwarded"; }; fw_unmut
# merge-forward/FR-007: the lane merge — merge_state_step and action stop --block conflict no longer forward
printf '{"name":"app","orchestrate":{"merge_by":"lane"}}\n' > "$fw_w/.claude/project-status.json"; printf 'pr-watch.sh state: conflict\n' > "$fw_t/why.md"
fw_take HEF-72 feat72 && { fw_gh DIRTY feat72 "$fw_hh"
  fw_mut ledger-recipes.sh 's/case "\$v" in conflict|behind) if fw=/case "$v" in NEVER) if fw=/' \
    && { fw action step HEF-72-A1 1 --evidence-file "$fw_t/why.md" >/dev/null 2>&1; fw_moved HEF-72 && fw_survived "merge_state_step no longer forwards, yet a DIRTY PR was forwarded"; }; fw_unmut; }
fw_take HEF-73 feat73 && { fw_gh DIRTY feat73 "$fw_hh"
  fw_mut ledger-actions.sh 's/^              if \[ -n "\$blk" \]; then$/              if false; then/' \
    && { fw action stop HEF-73-A1 --step 1 --block conflict --reason-file "$fw_t/why.md" >/dev/null 2>&1; fw_moved HEF-73 && fw_survived "action stop --block conflict no longer forwards, yet a DIRTY PR was forwarded"; }; fw_unmut; }
printf '{"name":"app"}\n' > "$fw_w/.claude/project-status.json"
[ "$x_fail" -eq 0 ] && ok "routing mutations caught: the deploy transcription blocking conflict again or dropping behind, merge_state_step and action stop --block conflict no longer forwarding (merge-forward/FR-017 merge-forward/FR-006 merge-forward/FR-007 SC-004)"

# The fixture of parts 17 and 17b is removed last.
git -C "$fw_w" worktree prune >/dev/null 2>&1
rm -rf -- "${fw_t:?}"; rm -f "$HOME"/.cache/hefesto/sessions/sid-fw-*-0001.json
