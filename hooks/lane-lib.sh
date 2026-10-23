#!/bin/bash
# lane-lib.sh — what lane-guard.sh, ledger.sh and the session start share about a session's lane
# (lanes-interactive, 9.0). Sourced, never run.
#
# The trust anchor is the session record: ~/.cache/hefesto/sessions/<session id>.json, written by the SessionStart
# hook from the title Claude Code gave it and the project's settings.local.json. Hooks run outside the sandbox and a
# sandboxed command cannot write there; the model cannot set its own title. Everything that decides "is this the
# orchestrator, is this the deployer" reads this record — never an environment variable a command line could set.

hef_cache() { printf '%s\n' "$HOME/.cache/hefesto"; }   # $HOME, never XDG (board-lib.sh says why)
valid_sid() { [[ "${1:-}" =~ ^[A-Za-z0-9_-]{8,80}$ ]]; }
session_file() { printf '%s\n' "$(hef_cache)/sessions/$1.json"; }
session_get() { # $1 session id, $2 field → the value, or nothing
  valid_sid "$1" || return 0
  jq -r --arg f "$2" '.[$f] // empty | if type == "string" then . else tojson end' "$(session_file "$1")" 2>/dev/null
}

# The setup a session runs under: the project's settings.local.json, read from the MAIN checkout (a lane may stand
# in a worktree). A lane cannot change that file: Claude Code's sandbox mounts it read-only and an Edit asks.
setup_settings() { # $1 a folder in the project → the settings JSON of its main checkout, or nothing
  local c top
  c=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  case "$c" in */.git) top="${c%/.git}" ;; *) return 0 ;; esac
  [ -f "$top/.claude/settings.local.json" ] || return 0
  jq -c 'if type == "object" then . else empty end' "$top/.claude/settings.local.json" 2>/dev/null
}

# A plain word list: one command, its words unquoted or in quotes with nothing the shell would expand or chain.
# What an excluded (unsandboxed) command line must be — a redirection would leave the sandbox with it (plan review
# round 3: `gh pr view 7 --json body -q .body > <store>/<aid>.json`).
PLAIN_WORD="([^][[:space:]'\"\$\`;&|<>(){}\\\\*?!#~]+|'[^']*'|\"[^\"\$\`\\\\!]*\")+"
plain_words() { # $1 command → 0 when it is one plain word list
  local re="^[[:space:]]*${PLAIN_WORD}([[:space:]]+${PLAIN_WORD})*[[:space:]]*\$"
  [[ "$1" != *$'\n'* ]] && [[ "$1" =~ $re ]]
}
first_word() { # $1 command → its first word, unquoted
  local w; w="$(printf '%s' "$1" | sed -E 's/^[[:space:]]*//; s/[[:space:]].*$//')"; w="${w#[\"\']}"; printf '%s\n' "${w%[\"\']}"
}

# The claim and the run record are written by hefesto's launcher only (its own calls are not tool calls); a lane that
# ran them could free or take another lane's interactive claim (code review of PR B, B3).
is_launcher_sub() { case "${1:-}" in run|claim) return 0 ;; esac; return 1; }

# Which ledger subcommands record a person's decision — one list, read by lane-guard.sh (the hook) and by ledger.sh
# itself (the second gate, in case a hook fails open). With --lanes they run only from the orchestrator lane.
is_person_sub() { # $1 subcommand, then its arguments → 0 when it records a person's decision
  local a
  case "${1:-}" in
    approve|answer|revise|request|direct|op|unblock) return 0 ;;
    release|record) shift; for a in "$@"; do case "$a" in --reviewed-by-human|--body-file|--body-from-board|--rfc) return 0 ;; esac; done ;;
  esac
  return 1
}

# A --lanes project: its settings carry env.HEFESTO_LANES = "1". hefesto's hooks that run a command a project file
# names (package.json's test script, node_modules/.bin, npx) stand down there: a hook runs outside the sandbox, and
# a lane can edit those files — that would be a way out of its sandbox (plan review round 1).
lanes_project() { # $1 a folder in the project → 0 when it is a --lanes project
  local s; s="$(setup_settings "$1")"; [ -n "$s" ] || return 1
  [ "$(jq -r '.env.HEFESTO_LANES // empty' <<<"$s" 2>/dev/null)" = 1 ]
}

# The lane map, {name: role}, resolved from the board config (FR-020): orchestrate.lanes {orchestrator, plan, build
# (a name or a list of up to 8), deploy}; else orchestrate.lane_prefix (default: the main folder's name) with the
# usual suffixes; else the legacy orchestrate.pane_sessions. Setup writes the result into the settings env, where no
# lane can change it; the session start and lane-guard read only that copy.
resolve_lane_map() { # $1 board config (may not exist), $2 the main folder → the map as one JSON line, or die-worthy stderr + 1
  local cfg='{}'; [ -f "$1" ] && cfg="$(jq -c '.orchestrate // {}' "$1" 2>/dev/null)" || cfg='{}'
  jq -ce --arg base "$(basename "$2")" '
    def nm: type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$");
    def bad($w): error("orchestrate.\($w) must be a session name ([A-Za-z0-9._-], ≤ 64)");
    if (.lanes | type) == "object" then
      .lanes as $l
      | ([$l.orchestrator, $l.plan, $l.deploy] | map(select(. != null)) | all(nm)) as $ok
      | (($l.build // []) | if type == "string" then [.] else . end) as $b
      | if ($ok | not) then bad("lanes.*")
        elif ($b | type) != "array" or ($b | length) > 8 or ($b | all(nm) | not) then bad("lanes.build (a name or a list of up to 8)")
        else ({} + (if $l.orchestrator then {($l.orchestrator): "orchestrator"} else {} end)
                 + (if $l.plan then {($l.plan): "plan"} else {} end)
                 + ([$b[] | {(.): "build"}] | add // {})
                 + (if $l.deploy then {($l.deploy): "deploy"} else {} end)) end
    elif .lane_prefix != null or (.pane_sessions | type) != "object" then
      (.lane_prefix // $base) as $p
      | if ($p | nm | not) then bad("lane_prefix") else
          {("\($p)-orchestrator"): "orchestrator", ("\($p)-planner"): "plan", ("\($p)-plan"): "plan",
           ("\($p)-builder"): "build", ("\($p)-build"): "build", ("\($p)-deployer"): "deploy", ("\($p)-deploy"): "deploy"}
          + ([range(2; 9) | {("\($p)-builder\(.)"): "build"}] | add) end
    else .pane_sessions as $s
      | [["orchestrator","orchestrator"],["plan","plan"],["build","build"],["deploy","deploy"]]
      | map(. as [$k,$r] | $s[$k] | select(nm) | {(.): $r}) | add // {} end' <<<"$cfg"
}

# Every hefesto hook runs outside the sandbox, in a repository a lane can write: its git calls ignore the two config
# keys that run a program on a plain read (core.fsmonitor, core.hooksPath) — plan Revision 1 #1, code review of PR A.
# Appended after any GIT_CONFIG_* the person set. (Claude Code's sandbox also mounts .git/config read-only, and
# block-sensitive-files.sh blocks edits under .git/ — this is the line that holds if either is ever off.)
hef_git_neutral() {
  local c="${GIT_CONFIG_COUNT:-}"; case "$c" in ''|*[!0-9]*) c=0 ;; esac
  export "GIT_CONFIG_KEY_$c=core.fsmonitor" "GIT_CONFIG_VALUE_$c=false" \
         "GIT_CONFIG_KEY_$((c + 1))=core.hooksPath" "GIT_CONFIG_VALUE_$((c + 1))=/dev/null" "GIT_CONFIG_COUNT=$((c + 2))"
}
