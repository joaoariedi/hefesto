# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
#
# lanes-parity (9.1) smoke checks, part 3 — lane-guard: excluded commands run only when granted, and a grant waits
# for its step (T018: FR-015, FR-016, NR-002; plan Sketch 6 and Sketch 14, notes 7 and 8).
#
# SOURCED by tests/smoke.sh after the lifecycle parts, never run on its own. Self-contained: hand-written session
# records, action files and approval-store records, as session-start-context.sh and ledger-actions.sh write them, so
# the hook is tested as hook JSON in → decision out without a live ledger.

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-lane-grants.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_)"
  else echo "tests/smoke-lane-grants.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

head_ "Lane guard: excluded commands need a grant; grants wait for their step (FR-015, NR-002)"
x_fail=0
lgr_t="$(cd "$(mktemp -d)" && pwd -P)"; lgr_ld="$lgr_t/ledger/lgr-key"; mkdir -p "$lgr_ld/actions"
lgr_st="$HOME/.cache/hefesto/approvals/lgr-key"; mkdir -p "$lgr_st" "$HOME/.cache/hefesto/sessions"
# The record's .excluded, as the session start copies it: gh, hefesto's helpers (absolute paths into THIS clone),
# a setup --unsandboxed-command entry and a person's global excludedCommands entry.
lgr_ssh="/usr/bin/ssh debian@vm-apps"
for lgr_r in deployer nolane; do
  jq -nc --arg r "$lgr_r" --arg h "$REPO/hooks" --arg s "$lgr_ssh *" --arg l "$lgr_ld" \
    '{title: "repo-\($r)", role: (if $r == "nolane" then "" else "deploy" end), name: (if $r == "nolane" then "" else "repo-\($r)" end),
      lanes: true, worker: false, ledger: $l,
      excluded: ["gh *", "\($h)/ledger.sh *", "\($h)/session-launch.sh *", "\($h)/pr-watch.sh *", "\($h)/status-board.sh *", $s, "docker *"]}' \
    > "$HOME/.cache/hefesto/sessions/sid-lgr-$lgr_r-0001.json"
done
lgr_gd() { # lgr_gd <lane> <command> [hook] → deny | allow | none; the reason goes to $lgr_t/why
  local o; o="$(jq -nc --arg c "$2" --arg s "sid-lgr-$1-0001" --arg d "$lgr_t" '{tool_name: "Bash", tool_input: {command: $c}, session_id: $s, cwd: $d}' | bash "${3:-$REPO/hooks/lane-guard.sh}" 2>/dev/null)"
  jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"$o" > "$lgr_t/why" 2>/dev/null
  [ -n "$o" ] || { echo none; return; }; jq -r '.hookSpecificOutput.permissionDecision // "none"' <<<"$o" 2>/dev/null || echo none
}
lgr_want() { # lgr_want <lane> <command> <decision> [hook]
  local got; got="$(lgr_gd "$1" "$2" "${4:-}")"
  [ "$got" = "$3" ] || { bad "lane-guard ($1): '$2' must be $3, got $got — $(cat "$lgr_t/why")"; x_fail=1; }
}
lgr_action() { # lgr_action <aid> <commands JSON> <steps_done JSON>: a taken action with a valid approval in the store
  local a h
  a="$(jq -nc --arg a "$1" --argjson c "$2" --argjson d "$3" '{aid: $a, entry: ($a | sub("-A[0-9]+$"; "")), to: "repo-deployer", status: "taken",
       taken_at: "2026-10-27T00:00:00Z", steps_done: $d, scope: {title: "a deploy step", steps: ["one", "two"], commands: $c, heads: {}}}')"
  h="$(jq -cS '{entry, to, scope}' <<<"$a" | sha256sum | cut -c1-64)"
  jq --arg h "$h" '.sha256 = $h' <<<"$a" > "$lgr_ld/actions/$1.json"
  jq -nc --arg h "$h" '{sha256: $h, to: "repo-deployer", by: "Ana"}' > "$lgr_st/$1.json"
}

# NR-002: without a grant, a setup --unsandboxed-command entry and a global excludedCommands entry are denied — in a
# lane and in a session that is no lane — and the reason says the command leaves the sandbox (it starts bare).
for lgr_c in "$lgr_ssh uptime" "docker ps"; do
  lgr_want deployer "$lgr_c" deny
  grep -qF 'runs outside the sandbox' "$lgr_t/why" && grep -qF 'approved action' "$lgr_t/why" \
    || { bad "the deny of '$lgr_c' must say it runs outside the sandbox and needs an approved action — got: $(cat "$lgr_t/why")"; x_fail=1; }
  lgr_want nolane "$lgr_c" deny
done
# gh reads and hefesto's helpers stay free (their own rules decide, as 9.0)
for lgr_c in "gh pr view 7 --json title" "gh pr checks 7" "$REPO/hooks/pr-watch.sh state 7" "$REPO/hooks/status-board.sh --json" "$REPO/hooks/ledger.sh show HEF-1"; do
  lgr_want deployer "$lgr_c" none
done
lgr_want deployer "gh pr merge 7 --merge" deny   # the 9.0.1 gh-write rule still holds
# NR-002, with a grant: a pre-9.1 string command (note 8) and a 9.1 {cmd, after_step: null} both run
lgr_action OP-1-A1 "[\"$lgr_ssh uptime\", {\"cmd\": \"docker ps\", \"after_step\": null}]" '[]'
lgr_want deployer "$lgr_ssh uptime" allow
lgr_want deployer "docker ps" allow
lgr_want deployer "docker ps -a" deny          # a grant is the literal command, nothing more
# Sketch 14: a command with after_step k is granted only once step k is in steps_done
lgr_action OP-2-A1 '[{"cmd": "docker volume ls", "after_step": 2}]' '[{"n": 1, "evidence": "x", "at": "2026-10-27T00:00:00Z"}]'
lgr_want deployer "docker volume ls" deny
lgr_action OP-2-A1 '[{"cmd": "docker volume ls", "after_step": 2}]' '[{"n": 1, "evidence": "x", "at": "2026-10-27T00:00:00Z"}, {"n": 2, "evidence": "y", "at": "2026-10-27T00:01:00Z"}]'
lgr_want deployer "docker volume ls" allow
# Helpers by basename: lane-guard run from a copy in another directory (as a profile's plugin cache differs from the
# clone setup pointed the record at) still recognises them, and still denies the ungranted excluded command.
lgr_cp="$lgr_t/cache/hefesto/9.1.0/hooks"; mkdir -p "$lgr_cp" && cp "$REPO/hooks/lane-guard.sh" "$REPO/hooks/lane-lib.sh" "$lgr_cp/"
lgr_want deployer "$REPO/hooks/pr-watch.sh state 7" none "$lgr_cp/lane-guard.sh"
lgr_want deployer "$REPO/hooks/status-board.sh --json" none "$lgr_cp/lane-guard.sh"
lgr_want deployer "docker info" deny "$lgr_cp/lane-guard.sh"
rm -rf -- "${lgr_t:?}" "${lgr_st:?}"; rm -f "$HOME"/.cache/hefesto/sessions/sid-lgr-*-0001.json
[ "$x_fail" -eq 0 ] && ok "lane-guard: a setup --unsandboxed-command and a global excludedCommands entry are denied without a grant and allowed with one; a string command grants as after_step null; after_step waits for its step; gh reads and the helpers stay free, by basename from a copied hook (FR-015, FR-016, NR-002)"
