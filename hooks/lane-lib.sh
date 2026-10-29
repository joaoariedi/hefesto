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
# A `#` starts a comment only at the start of a word, so inside one it is literal: `--ref todo#DET-24`, the form
# /hef.ship writes, was denied (live check 2026-10-29). A word still never STARTS with `#` (or `~`).
PLAIN_UNQ="[^][[:space:]'\"\$\`;&|<>(){}\\\\*?!~]"
PLAIN_QUO="'[^']*'|\"[^\"\$\`\\\\!]*\""
PLAIN_UNQ0="[^][[:space:]'\"\$\`;&|<>(){}\\\\*?!~#]"   # the first character of an unquoted word: never a #
PLAIN_WORD="(${PLAIN_UNQ0}${PLAIN_UNQ}*|${PLAIN_QUO})(${PLAIN_UNQ}+|${PLAIN_QUO})*"
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
    approve|answer|revise|request|direct|op|unblock|drop|fold|supersede|reopen) return 0 ;;
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

# Every hefesto hook runs outside the sandbox, in a repository a lane can write: its git calls ignore the config keys
# that run a program on a plain read (core.fsmonitor, core.hooksPath) — plan Revision 1 #1, code review of PR A — and,
# since 9.1 fetches origin unsandboxed at a merge or train take (forensic review of PR B), the ones that run a program
# on a fetch: the ext:: transport (also what a url.*.insteadOf would rewrite origin to), core.sshCommand, and the
# git:// transport, whose core.gitProxy is a program (hefesto never fetches over git://). A
# remote.origin.uploadpack (run locally for a path remote) is not pinned here — a config key for it would make every
# repo appear to have an origin, and the repo's own value still won — so hefesto fetches through hef_fetch_origin,
# whose --upload-pack does override it. A credential.helper is left alone: resetting it would break
# the person's fetch of a private repo. Appended after any GIT_CONFIG_* the person set. (Claude Code's sandbox also
# mounts .git/config read-only, and block-sensitive-files.sh blocks edits under .git/ — this is the line that holds
# if either is ever off.)
HEF_GIT_NEUTRAL="core.fsmonitor=false core.hooksPath=/dev/null protocol.ext.allow=never core.sshCommand=ssh protocol.git.allow=never"
hef_git_neutral() {
  local c="${GIT_CONFIG_COUNT:-}" kv; case "$c" in ''|*[!0-9]*) c=0 ;; esac
  for kv in $HEF_GIT_NEUTRAL; do export "GIT_CONFIG_KEY_$c=${kv%%=*}" "GIT_CONFIG_VALUE_$c=${kv#*=}"; c=$((c + 1)); done
  export "GIT_CONFIG_COUNT=$c"
}
hef_fetch_origin() { # git fetch --prune origin in the current repo, never with the repo's own upload-pack program
  git fetch --upload-pack=git-upload-pack --prune origin
}

# One gh resolution for every helper (lanes-parity FR-027, plan Sketch 10). HEFESTO_GH_BIN keeps its 9.0 meaning — a
# path that does not exist is "gh absent", the merge gate's unverified path (ledger.sh gh_present) — so it passes
# through untouched. EVAL_GH_BIN is the eval seam (prompt.md `env:` reaches Bash and hooks, never a settings file): a
# relative value resolves against the workspace top captured HERE, at source time, so a later cd cannot break it;
# set but not executable is a stop, never a fall back to the real gh. NR-007: gh_bin reads no file.
# Resolve it once, at the helper's entry: `GH=$(gh_bin) || exit 1` — an inline "$(gh_bin)" would swallow the stop.
case "${EVAL_GH_BIN:-}" in
  ''|/*) ;;
  *) [ -n "${HEFESTO_EVAL_ROOT:-}" ] || HEFESTO_EVAL_ROOT="$(git -c core.fsmonitor=false -c core.hooksPath=/dev/null \
       rev-parse --show-toplevel 2>/dev/null || pwd -P)"
     export HEFESTO_EVAL_ROOT ;;   # a child helper started after a cd resolves against the same top
esac
gh_bin() { # → the gh to run, or the reason on stderr + 1
  [ -n "${HEFESTO_GH_BIN:-}" ] && { printf '%s\n' "$HEFESTO_GH_BIN"; return 0; }
  [ -n "${EVAL_GH_BIN:-}" ] || { echo gh; return 0; }
  local g="$EVAL_GH_BIN"
  case "$g" in
    /*) ;;
    *) [ -n "${HEFESTO_EVAL_ROOT:-}" ] || { echo "hefesto: EVAL_GH_BIN=$g is relative and no workspace root is known" >&2; return 1; }
       g="$HEFESTO_EVAL_ROOT/$g" ;;
  esac
  [ -f "$g" ] && [ -x "$g" ] || { echo "hefesto: EVAL_GH_BIN=$EVAL_GH_BIN is not an executable file ($g) — refusing to fall back to the real gh" >&2; return 1; }
  printf '%s\n' "$g"
}
