#!/bin/bash
# hefesto-setup.sh — set a project up for the hefesto lanes, once per project and machine (lanes-v3 FR-001..005).
# Run it in a normal terminal from the project's main folder:
#
#   bash ~/.claude-framework/hooks/hefesto-setup.sh [--lanes] [--strict] [--keep-statusline]
#        [--allow-command <p>]... [--unsandboxed-command <p>]... [--forget-commands] [--check | --remove | --print]
#
# It merges into <main checkout>/.claude/settings.local.json (kept out of git) what a lane needs, so a lane
# opens with plain `claude --name <repo>-<lane>` — or any wrapper that forwards claude's arguments:
#   permissions.allow         hefesto's own helper calls, as exact rules — every ledger.sh subcommand but the
#                             signatures one by one (never ledger.sh as a whole; claim and run get no rule: ledger.sh
#                             refuses them unless session-launch.sh calls); gh's read and PR-opening forms; each
#                             --allow-command
#   permissions.ask           only where a person signs: the ledger.sh forms that record a person's decision (approve,
#                             answer, revise, drop, fold, supersede, reopen, op close|drop; unblock/record/release with
#                             their signature flag anywhere after the id) and pr-watch.sh reply|comment — their dialog
#                             always shows
#   permissions.deny          Edit on ~/.cache/hefesto/{ledger,approvals,sessions}, by every spelling of the path
#   sandbox.enabled / failIfUnavailable  true: a lane never runs unsandboxed by accident
#   sandbox.excludedCommands  session-launch.sh, ledger.sh, pr-watch.sh, status-board.sh, `gh *`, and each
#                             --unsandboxed-command (an absolute path no sandboxed session can write)
#   sandbox.network.deniedDomains  api.github.com: only the unsandboxed gh, decided by the rules, reaches it
#   sandbox.filesystem.allowWrite  with --lanes, the lanes' build cache ~/.cache/hefesto/lane-cache/<key>
#                             (created here; env.HEFESTO_LANE_CACHE names it, lane-build.sh uses it); the 8.x
#                             grant of the ledger folder is taken out (since 9.0 the ledger is in ~/.cache/hefesto)
#   permissions.additionalDirectories  with --lanes on an external board, the code repos its `repos` names
#   statusLine                the context gauge, run as `context-gauge.sh --with-user`: your profile's own status
#                             line first, then `ctx 45% · 90k/200k` (left alone when this file already has one);
#                             the run rows below it are opt-in with context.gauge_rows: true in
#                             .claude/project-status.json (default false — this script writes nothing for it)
#   crossSessionInbound       "accept", with --lanes: the orchestrator's doorbells reach the stage lanes
#   sandbox.autoAllowBashIfSandboxed  false, only with --strict: any command outside the allowlist asks,
#                             sandboxed or not (without --strict an earlier setup's false is taken back out)
#   env.HEFESTO_TRUSTED_TOP / HEFESTO_TRUSTED_BOARD  the folders the launcher may run in, fixed here where no
#                             sandboxed session can change them; with --lanes also HEFESTO_LANES, HEFESTO_LANE_MAP
# Every other key is kept. A plugin cannot ship these settings itself, hence this step.
#   --lanes                    the four-lane setup (doorbells, the lane map, the build cache)
#   --strict                   autoAllowBashIfSandboxed false
#   --keep-statusline          never touch statusLine
#   --allow-command <p>        also allow this plain read-only command pattern (remembered across runs)
#   --unsandboxed-command <p>  also run this absolute-path command outside the sandbox (remembered across runs)
#   --forget-commands          drop the remembered --allow-command / --unsandboxed-command patterns
#   --check                    read-only: "setup: ok", or what is missing for this plugin root (exit 1) — including any
#                              ask rule on a hefesto helper outside the signature set, named with its settings file
#   --remove                   take out every entry this script writes (for any hefesto version)
#   --print                    show the merged file; write nothing
# Rules name each plugin root explicitly — the clone this runs from and each profile's installed copy, in the one
# spelling the matcher sees for it (<installPath>//hooks, <clone>/hooks) — never with a wildcard inside a path: `…/hefesto/*/hooks/session-launch.sh *` would also match
# `…/hefesto/../../../tmp/x/hooks/session-launch.sh`, a file a sandboxed session can write, and run it outside
# the sandbox. For the same reason a root inside this project or a temp folder is skipped. Each run drops the
# rules of hefesto versions no longer installed; after a plugin update run it again (the session start says so).
set -uo pipefail
die() { echo "hefesto-setup: $*" >&2; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CLONE="$(dirname "$HERE")"
LANES=0; KEEP=0; STRICT=0; MODE="write"; FORGET=0; NEW_ALLOW=(); NEW_EXCL=()
while [ $# -gt 0 ]; do case "$1" in
  --lanes) LANES=1 ;; --keep-statusline) KEEP=1 ;; --strict) STRICT=1 ;; --forget-commands) FORGET=1 ;;
  # the person's own command lists, typed here — never read from a file a lane can write (code review of PR A)
  --allow-command) [ -n "${2:-}" ] || die "--allow-command needs a pattern"; NEW_ALLOW+=("$2"); shift ;;
  --unsandboxed-command) [ -n "${2:-}" ] || die "--unsandboxed-command needs a pattern"; NEW_EXCL+=("$2"); shift ;;
  --check|--remove|--print) [ "$MODE" = write ] || die "one of --check, --remove, --print at a time (got --$MODE and $1)"; MODE="${1#--}" ;;
  -h|--help) sed -n '2,49p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "unknown option '$1' (expected --lanes, --strict, --keep-statusline, --allow-command, --unsandboxed-command, --forget-commands, --check, --remove or --print)" ;;
esac; shift; done
[ "$LANES" = 0 ] || [ "$MODE" != remove ] || die "--lanes does not go with --remove (it takes every hefesto entry out, the lane ones included)"
command -v jq >/dev/null 2>&1 || die "jq not found — install jq: https://jqlang.org"
CDIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || die "not inside a git repository — run it from the project's main folder"
case "$CDIR" in */.git) TOP="${CDIR%/.git}" ;; *) die "no main checkout for $CDIR (a bare repository?) — run it from the project's main folder" ;; esac
F="$TOP/.claude/settings.local.json"

CUR='{}'
if [ -f "$F" ]; then CUR="$(jq -c . "$F" 2>/dev/null)" && jq -e 'type == "object"' <<<"$CUR" >/dev/null 2>&1 \
  || die "$F is not a JSON object — fix or move it, then run this again (nothing was written)"; fi
# Everything a sandboxed session can write: the project, the temp folders, and every path a settings file that
# can apply to a lane here grants — sandbox.filesystem.allowWrite, permissions.additionalDirectories, and the
# folders of Edit allow rules (they widen the sandbox too) — in every profile's user settings and the project's.
writable=("$TOP" "${TMPDIR:-/tmp}" /tmp /private/tmp /var/folders /private/var/folders)
granted=()   # only what a settings file grants (the check below: none may reach hefesto's state)
grant_paths() { # stdin: one settings JSON → "S<TAB>path" (sandbox syntax: /abs, ~/) or "E<TAB>path" (Edit rule: //abs, /project)
  jq -r '(((.sandbox.filesystem.allowWrite // []) + (.permissions.additionalDirectories // [])) | .[] | strings | "S\t" + .),
         ((.permissions.allow // [])[] | strings | capture("^Edit\\((?<p>[^)]*)\\)$").p | "E\t" + .)' 2>/dev/null
}
for sf in "$F" "$TOP/.claude/settings.json" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" "$HOME/.claude/settings.json" "$HOME"/.claude-*/settings.json; do
  [ -f "$sf" ] || continue
  while IFS="$(printf '\t')" read -r kind w; do
    w="${w%%\**}"                                   # a glob grants from its fixed part down
    case "$kind:$w" in
      *:) continue ;;
      *:\~|*:\~/) w="$HOME" ;;
      *:\~/*) w="$HOME/${w#\~/}" ;;
      E://*) w="${w#/}" ;;
      # an Edit rule's /path is relative to the settings file's base — the project for a project file,
      # unclear for a user file: count both, the safe side
      E:/*) writable+=("$(dirname "$(dirname "$sf")")$w"); w="$TOP$w" ;;
      S:/*) ;;                                       # sandbox paths: /abs
      *) w="$TOP/$w" ;;
    esac
    [ -d "$w" ] && w="$(cd "$w" 2>/dev/null && pwd -P)"   # resolve .. and links, as the roots are
    writable+=("$w"); granted+=("$w")
  done < <(grant_paths < "$sf")
done
# A root a sandboxed session can write is never trusted: the launcher there would run outside the sandbox.
unsafe_root() { # $1 path → 0 when it lies under a sandbox-writable path, or a writable path lies inside it
  local p t
  p="$(printf '%s/' "$1" | tr -s /)"
  for t in "${writable[@]}"; do
    t="$(printf '%s/' "$t" | tr -s /)"
    case "$p" in "$t"*) return 0 ;; esac             # the root is inside a writable path (a grant of /, //**: everything)
    case "$t" in "$p"*) return 0 ;; esac             # a writable path is inside the root (its hooks/, say)
  done; return 1
}
roots=(); kinds=(); skipped=(); cfgs=()
add_root() { local p="${1%/}" k="$2"; [ -n "$p" ] || return 0
  if unsafe_root "$p"; then skipped+=("$p"); return 0; fi
  case " ${roots[*]-} " in *" $p "*) ;; *) roots+=("$p"); kinds+=("$k") ;; esac; }
# Installed copies first, the clone last: run from the installed copy, CLONE is that same path, and the dedup keeps
# its `installed` kind — the spelling Claude Code substitutes for it (HEF-27 plan review round 2).
for cfg in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.claude" "$HOME"/.claude-*; do
  [ -n "$cfg" ] && [ -f "$cfg/plugins/installed_plugins.json" ] || continue
  case " ${cfgs[*]-} " in *" $cfg "*) continue ;; esac; cfgs+=("$cfg")
  while IFS= read -r p; do add_root "$p" installed; done \
    < <(jq -r '[.plugins["hefesto@hefesto"][]? | select(.scope == "user") | .installPath // empty] | .[]' "$cfg/plugins/installed_plugins.json" 2>/dev/null)
done
add_root "$CLONE" clone
[ "${#roots[@]}" -gt 0 ] || die "no usable hefesto folder: every candidate lies inside this project or a temp folder (${skipped[*]-}) — run it from your hefesto install (~/.claude-framework)"
# The one spelling ${CLAUDE_PLUGIN_ROOT}/hooks reaches the permission matcher in (D4, tests/smoke.sh:860-862): an
# installed copy's root ends in `/`, so its helpers arrive as <root>//hooks/…; the clone (--plugin-dir, a terminal)
# as <root>/hooks/…. The matcher does no normalization, so a rule in the other spelling never matches.
hooks_of() { # $1 root, $2 kind (installed | clone) → the hooks folder as the matcher sees it
  if [ "$2" = installed ]; then printf '%s//hooks' "$1"; else printf '%s/hooks' "$1"; fi
}
# The status line keeps a release-stable path: the clone when it is a root, never a version-pinned cache folder
# the next plugin update deletes (the reorder above moved ${roots[0]} onto one — plan review round 3).
gauge_root() { local i; for i in "${!roots[@]}"; do [ "${roots[$i]}" = "$CLONE" ] && { printf '%s' "$CLONE"; return; }; done; printf '%s' "${roots[0]}"; }

# What marks an entry as ours, for any version: the clone, and every profile's plugin cache.
prefixes=("$CLONE"); for c in ${cfgs[@]+"${cfgs[@]}"}; do prefixes+=("$c/plugins/cache/hefesto"); done
# HEF-27: a dialog only where a person signs. Everything else in ledger.sh's dispatch is allowed, one by one —
# never ledger.sh as a whole, so a new subcommand is classified before it runs without asking (FR-006; the
# completeness check in tests/smoke-signatures.sh diffs these lists against ledger.sh's dispatch both ways).
# merge-auto grant/revoke: a person turns auto-merge on or off — the dialog is the signature (HEF-30 FR-015)
LEDGER_SIGN_WHOLE=(approve answer revise drop fold supersede reopen "op close" "op drop" "merge-auto grant" "merge-auto revoke")
LEDGER_SIGN_FLAG=("unblock --reviewed-by-human" "unblock --merge-sha" "record --body-file" "record --body-from-board" "record --rfc"
  "release --reviewed-by-human")   # it records a person's name → a signature (spec Clarifications 2026-11-09)
# no rule at all: ledger.sh refuses claim and run unless session-launch.sh calls (FR-010); automerge is the deploy
# launcher's, gated by itself on the person's grant and the verdicts at the verified head (HEF-30 FR-010)
# shellcheck disable=SC2034  # written nowhere on purpose; tests/smoke-signatures.sh reads it (FR-006)
LEDGER_LAUNCHER=(claim run automerge)
LEDGER_ALLOW=(board list next show metrics register publish escalate questions request actions action "op new" direct
  directives directive note lanes deployed record advance handoff block release unblock verdict init where branches spec-roots
  merge-by)   # read-only (HEF-30)
LEDGER_ALLOW_EXACT=("park --all" dir "merge-auto preview" "merge-auto show")
# The signature ask rules for one hooks folder (FR-001): written by setup, looked for by --check. ask outranks allow
# (D7), so `record:*` in allow and `record * --body-file*` here coexist: the flag anywhere after the id asks.
# `record * --rfc*` also matches the launcher-only --rfc-snapshot — an over-ask, never an under-ask.
sign_asks() { # $1 hooks folder → one rule per line
  local s
  for s in "${LEDGER_SIGN_WHOLE[@]}"; do printf 'Bash(%s/ledger.sh %s:*)\n' "$1" "$s"; done
  for s in "${LEDGER_SIGN_FLAG[@]}"; do printf 'Bash(%s/ledger.sh %s * %s*)\n' "$1" "${s% *}" "${s#* }"; done
  # pr-watch's two verbs that write to GitHub (a reply, a comment) ask — the rest of it reads
  printf 'Bash(%s/pr-watch.sh reply:*)\nBash(%s/pr-watch.sh comment:*)\n' "$1" "$1"
}
ask_defects() { # $1 a settings file → each of its ask rules on a hefesto helper that is not a signature, one per line
  jq -r --argjson w "$(printf '%s\n' "${LEDGER_SIGN_WHOLE[@]}" | jq -R . | jq -sc .)" --argjson fl "$(printf '%s\n' "${LEDGER_SIGN_FLAG[@]}" | jq -R . | jq -sc .)" '
    # the strip stops at the first word (the helper path): an argument that holds another /hooks/ path must not swallow it
    def signature: (sub("^Bash\\((bash )?[^ ]*/hooks/"; "") | rtrimstr(")") | capture("^(?<hp>[a-z-]+[.]sh)(?<rest>.*)$")) as $c
      | ($c.rest | sub(":\\*$"; "") | split(" ") | map(select(. != ""))) as $a
      | if $c.hp == "pr-watch.sh" then ($a[0] == "reply" or $a[0] == "comment")
        elif $c.hp == "ledger.sh" then (if $a[0] == "op" or $a[0] == "merge-auto" then "\($a[0]) \($a[1] // "")" else ($a[0] // "") end) as $s
          | ($w | index([$s]) != null) or any($fl[]; split(" ") as [$fs, $ff] | $fs == $s and any($a[1:][]; startswith($ff)))
        else false end;
    (.permissions.ask // [])[] | strings
    | select(test("^Bash\\((bash )?/.*/hooks/(ledger|pr-watch|session-launch|status-board|speckit-helper|run-follow|hefesto-setup)[.]sh( |:|\\)|$)"))
    | select(signature | not)' "$1" 2>/dev/null
}
allow=(); ask=(); excl=()
for i in "${!roots[@]}"; do h="$(hooks_of "${roots[$i]}" "${kinds[$i]}")"
  # status-board.sh --set-status is never allowed here: it writes a GitHub Project card, and its one caller is
  # ledger.sh publish (github-project-board NR-004; tests/smoke-github-board.sh checks every pattern below).
  allow+=("Bash($h/status-board.sh)" "Bash($h/status-board.sh --detailed:*)" "Bash($h/status-board.sh --check:*)" "Bash($h/status-board.sh --item:*)"
          "Bash($h/status-board.sh --add:*)" "Bash($h/status-board.sh --list:*)" "Bash($h/status-board.sh --init)" "Bash($h/status-board.sh --detect)" "Bash($h/status-board.sh --item-raw:*)" "Bash($h/hefesto-setup.sh --check)"
          "Bash($h/session-launch.sh:*)" "Bash($h/speckit-helper.sh:*)" "Bash($h/run-follow.sh:*)")
  for s in "${LEDGER_ALLOW[@]}"; do allow+=("Bash($h/ledger.sh $s:*)"); done
  for s in "${LEDGER_ALLOW_EXACT[@]}"; do allow+=("Bash($h/ledger.sh $s)"); done
  while IFS= read -r s; do ask+=("$s"); done < <(sign_asks "$h")
  # pr-watch: the babysitter's gh calls live in it; status-board: a github-project board is read through gh — both
  # need the API the lanes' sandbox no longer reaches (code review of PR A)
  excl+=("$h/session-launch.sh *" "$h/ledger.sh *" "$h/pr-watch.sh *" "$h/status-board.sh *")
  allow+=("Bash($h/pr-watch.sh:*)")
done
# hefesto 9 keeps the ledger in ~/.cache/hefesto, outside every sandbox: the 8.x grant of the board repo's
# .git/hefesto (and this project's) is taken out, and nothing a sandbox can reach is granted in its place.
wr=()
BCTX="$(cd "$TOP" && bash "$HERE/ledger.sh" board 2>/dev/null)" || BCTX=""
GCOM="$(jq -r '.git_common // empty' <<<"$BCTX" 2>/dev/null)"; [ -n "$GCOM" ] && wr+=("$GCOM/hefesto")
if [ "$(jq -r '.mode // empty' <<<"$BCTX" 2>/dev/null)" = external ]; then BTOP="$(jq -r '.board_top // empty' <<<"$BCTX")"; fi
BCFG="$(jq -r '.config // empty' <<<"$BCTX" 2>/dev/null)"; [ -n "$BCFG" ] || BCFG="$TOP/.claude/project-status.json"
# shellcheck source=hooks/lane-lib.sh
. "$HERE/lane-lib.sh"
# The lanes (FR-020): resolved here and written into the env, where no lane can change the map it is judged by.
LMAP='{}'; if [ "$LANES" = 1 ]; then LMAP="$(resolve_lane_map "$BCFG" "$TOP" 2>&1)" || die "the lane names in $BCFG: ${LMAP#jq: error*: }"; fi
# The lanes' build cache (#162): only hooks/lane-build.sh, inside the sandbox, points the toolchain caches at it. No cache
# variable is ever set here — a settings env reaches hooks and approved unsandboxed actions too, and an unsandboxed build
# would link what a sandboxed lane planted. The env holds the path only; the cache is sandbox-writable, so nothing under
# it may become an unsandboxed command (it joins the writable roots unsafe_root checks).
LCP=""; LCPROBE="$(hef_cache)/lane-cache-probe"
if [ "$LANES" = 1 ]; then
  # shellcheck source=hooks/board-lib.sh
  . "$HERE/board-lib.sh"
  LCK="$(ledger_key "$CDIR")" || die "cannot compute the lane cache key for $CDIR"
  LCP="$(hef_cache)/lane-cache/$LCK"; writable+=("$LCP")
fi
envj="$(jq -nc --arg t "$TOP" --arg b "${BTOP:-}" --argjson lanes "$LANES" --arg m "$LMAP" --arg lc "$LCP" '{HEFESTO_TRUSTED_TOP: $t} + (if $b != "" then {HEFESTO_TRUSTED_BOARD: $b} else {} end)
  + (if $lanes == 1 then {HEFESTO_LANES: "1", HEFESTO_LANE_MAP: $m, HEFESTO_LANE_CACHE: $lc} else {} end)')"
# What else setup adds (lanes-interactive FR-022, review rounds 2–3), recorded in env.HEFESTO_SETUP_EXTRA so every run
# can take its previous set out first: gh outside the sandbox (so a merge is decided by the rules) with only its
# read and PR-opening forms allowed; the project's read-only and unsandboxed command lists; Edit denied on
# hefesto's own state, by every spelling of the path.
x_allow=("Bash(gh pr view:*)" "Bash(gh pr list:*)" "Bash(gh pr checks:*)" "Bash(gh pr diff:*)" "Bash(gh pr create:*)"
         "Bash(gh run list:*)" "Bash(gh run view:*)" "Bash(gh repo view:*)" "Bash(gh auth status)")
x_excl=("gh *"); x_deny=(); x_dirs=(); x_net=("api.github.com")
# the GitHub API is out of the lanes' sandbox: only the unsandboxed gh, decided by the permission rules, reaches it —
# a sandboxed `if :; then gh pr merge …; fi`, or a script that runs gh, gets no network for it (code review of PR A)
# An external board's code repos sit beside it, outside this project: with --lanes the lanes edit and build in their
# worktrees, so they are added to permissions.additionalDirectories (which also widens the lanes' sandbox to them).
if [ "$LANES" = 1 ] && [ -n "${BTOP:-}" ]; then
  while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$d" ] || continue; d="$(cd "$d" && pwd -P)"
    # the repos map is in the board config, a file a lane can edit (code review of PR B, B6): never a grant that
    # contains hefesto's state, $HOME or / (a temp folder or one inside the project is writable already)
    case "$(printf '%s/' "$HOME/.cache/hefesto" | tr -s /)" in "$(printf '%s/' "$d" | tr -s /)"*) die "the board's repos map names $d, which contains $HOME/.cache/hefesto — refusing to grant it to the lanes' sandbox (nothing was written)" ;; esac
    { [ "$d" = / ] || [ "$d" = "$(cd "$HOME" && pwd -P)" ]; } && die "the board's repos map names $d — / and your home are never granted to the lanes (nothing was written)"
    x_dirs+=("$d")
  done < <(jq -r '.repos // {} | .[]' <<<"$BCTX")
fi
HC="$HOME/.cache/hefesto"; HCP="$(mkdir -p "$HC" 2>/dev/null; cd -P "$HC" 2>/dev/null && pwd -P)"
for b in "$HC" ${HCP:+"$HCP"}; do for sub in ledger approvals sessions; do r="Edit(/$b/$sub/**)"; case " ${x_deny[*]-} " in *" $r "*) ;; *) x_deny+=("$r") ;; esac; done; done
cmd_ok() { # $1 a command pattern → 0 when safe to write as a rule (review round 1 #6, code review of PR A)
  local w
  case "$1" in ""|"*"*|*$'\n'*) return 1 ;; esac
  [[ "$1" =~ [\;\&\|\<\>\`\$\(\)\{\}] ]] && return 1
  w="${1%% *}"; w="${w##*/}"   # by basename: /bin/sh is a shell too
  case "$w" in sh|bash|zsh|dash|ksh|fish|env|eval|exec|xargs|sudo|doas|nohup|timeout|command|builtin|nice|time|setsid|script \
    |python|python[0-9]*|perl|ruby|node|deno|bun|php|lua|tclsh|awk|gawk|mawk|sed|find|git|make|osascript|busybox|toybox \
    |lane-build.sh) return 1 ;; esac   # lane-build.sh runs any command it is given (lane-build-cache NR-004)
  case " $1 " in *" -c "*|*" -e "*) return 1 ;; esac
  return 0
}
gh_read_ok() { # $1 an allow pattern: a gh one may only be a read form
  case "$1" in gh\ *) case "$1" in "gh pr view"*|"gh pr list"*|"gh pr checks"*|"gh pr diff"*|"gh run view"*|"gh run list"*|"gh issue view"*|"gh issue list"*|"gh repo view"*) return 0 ;; *) return 1 ;; esac ;; esac
  return 0
}
PREV="$(jq -c '(.env.HEFESTO_SETUP_EXTRA? // "{}") | (try fromjson catch {}) | if type == "object" then . else {} end' <<<"$CUR")"
u_allow=(); u_excl=()
if [ "$FORGET" = 0 ]; then
  while IFS= read -r c; do [ -n "$c" ] && u_allow+=("$c"); done < <(jq -r '.user_allow // [] | .[]' <<<"$PREV")
  while IFS= read -r c; do [ -n "$c" ] && u_excl+=("$c"); done < <(jq -r '.user_excl // [] | .[]' <<<"$PREV")
fi
for c in ${NEW_ALLOW[@]+"${NEW_ALLOW[@]}"}; do case " ${u_allow[*]-} " in *" $c "*) ;; *) u_allow+=("$c") ;; esac; done
for c in ${NEW_EXCL[@]+"${NEW_EXCL[@]}"}; do case " ${u_excl[*]-} " in *" $c "*) ;; *) u_excl+=("$c") ;; esac; done
for c in ${u_allow[@]+"${u_allow[@]}"}; do
  cmd_ok "$c" && gh_read_ok "$c" || die "--allow-command '$c' is not a plain read-only pattern (no shell operators, wrapper or interpreter, no -c/-e; for gh only its view/list/checks/diff forms) — nothing was written"
  x_allow+=("Bash($c)")
done
for c in ${u_excl[@]+"${u_excl[@]}"}; do
  cmd_ok "$c" || die "--unsandboxed-command '$c' is not a plain command pattern (no shell operators, wrapper or interpreter, no -c/-e) — nothing was written"
  case "$c" in /*) ;; *) die "--unsandboxed-command '$c' must start with an absolute path (a bare name is found on PATH, which a lane can change)" ;; esac
  unsafe_root "$(dirname "${c%% *}")" && die "--unsandboxed-command: '${c%% *}' lies where a sandboxed session can write — it would run whatever a lane put there outside the sandbox"
  x_excl+=("$c")
done
# An exclusion for a launcher that is gone, or that a sandboxed session could write, would let whoever
# creates that file run it outside the sandbox: every run drops such entries, whoever wrote them.
badx=()
while IFS= read -r x; do
  case "$x" in */hooks/session-launch.sh\ \*) f="${x% \*}"; { [ -f "$f" ] && ! unsafe_root "$(dirname "$(dirname "$f")")"; } || badx+=("$x") ;; esac
done < <(jq -r '.sandbox.excludedCommands // [] | .[] | strings' <<<"$CUR")
jarr() { if [ $# -eq 0 ]; then echo '[]'; else printf '%s\n' "$@" | jq -R . | jq -sc .; fi; }
jarr_lines() { jq -R . | jq -sc .; }   # stdin, one string per line → a JSON array
RULES="$(jq -nc --argjson a "$(jarr "${allow[@]}")" --argjson k "$(jarr "${ask[@]}")" --argjson x "$(jarr "${excl[@]}")" \
  --argjson w "$(jarr ${wr[@]+"${wr[@]}"})" --argjson px "$(jarr "${prefixes[@]}")" --argjson bad "$(jarr ${badx[@]+"${badx[@]}"})" --argjson env "$envj" \
  --arg g "$(gauge_root)/hooks/context-gauge.sh --with-user" --argjson lanes "$LANES" --argjson keep "$KEEP" --argjson strict "$STRICT" \
  --argjson xa "$(jarr "${x_allow[@]}")" --argjson xe "$(jarr "${x_excl[@]}")" --argjson xd "$(jarr "${x_deny[@]}")" --argjson xr "$(jarr ${x_dirs[@]+"${x_dirs[@]}"})" \
  --argjson xn "$(jarr "${x_net[@]}")" --argjson xw "$(jarr ${LCP:+"$LCP"})" --argjson ua "$(jarr ${u_allow[@]+"${u_allow[@]}"})" --argjson ue "$(jarr ${u_excl[@]+"${u_excl[@]}"})" \
  '{allow: $a, ask: $k, exclude: $x, write: $w, prefixes: $px, bad: $bad, env: $env, gauge: {type: "command", command: $g}, lanes: $lanes, keep: $keep,
    strict: $strict, xallow: $xa, xexcl: $xe, xdeny: $xd, xdirs: $xr, xnet: $xn, xwrite: $xw, uallow: $ua, uexcl: $ue}')" || die "could not build the rules"

if [ "$MODE" = check ]; then
  me="${CLAUDE_PLUGIN_ROOT:-$CLONE}"; me="${me%/}"
  # This session's root and its kind come from setup's own roots/kinds (installed wins, FR-005); a root setup does
  # not trust — or never saw — is reported, never given a guessed spelling.
  mh=""; for i in "${!roots[@]}"; do [ "${roots[$i]}" = "$me" ] && { mh="$(hooks_of "$me" "${kinds[$i]}")"; break; }; done
  miss="$(jq -r --arg h "$mh" --arg me "$me" --argjson sig "$(if [ -n "$mh" ]; then jarr_lines < <(sign_asks "$mh"); else echo '[]'; fi)" '[
      (if $h == "" then "the hefesto folder this session runs from (\($me)) is not one setup trusts" else
      (if ((.permissions.allow // []) | index(["Bash(\($h)/ledger.sh board:*)"])) then empty else "the helper allowlist" end),
      ($sig[] as $r | if ((.permissions.ask // []) | index([$r])) then empty else "the ask rule \($r | ltrimstr("Bash(\($h)/") | rtrimstr(")"))" end),
      (if ((.sandbox.excludedCommands // []) | index(["\($h)/session-launch.sh *"])) then empty else "the launcher sandbox exclusion" end),
      (if ((.sandbox.excludedCommands // []) | index(["\($h)/ledger.sh *"])) then empty else "the ledger.sh sandbox exclusion (hefesto 9 keeps the ledger outside the project)" end) end),
      (if ((.sandbox.excludedCommands // []) | index(["gh *"])) then empty else "gh outside the sandbox (so a merge is decided by the permission rules)" end),
      (if .sandbox.enabled == true then empty else "sandbox.enabled true" end),
      (if ((.sandbox.network.deniedDomains // []) | index(["api.github.com"])) then empty else "the GitHub API denied to the sandbox (sandbox.network.deniedDomains)" end),
      (if ((.env.HEFESTO_SETUP_SET // "") | split(",") | index(["autoallow"])) and .sandbox.autoAllowBashIfSandboxed != false then "sandbox.autoAllowBashIfSandboxed false (--strict)" else empty end),
      (if .env.HEFESTO_TRUSTED_TOP then empty else "the trusted project folder" end)
    ] | join(", ")' <<<"$CUR")"
  [ "${#badx[@]}" -eq 0 ] || miss="${miss:+$miss, }the removal of a launcher exclusion for a missing or writable file (${badx[*]})"
  if [ "$(jq -r '.env.HEFESTO_LANES // empty' <<<"$CUR")" = 1 ]; then
    lcr="$(jq -r '.env.HEFESTO_LANE_CACHE // empty' <<<"$CUR")"
    if [ -z "$lcr" ]; then miss="${miss:+$miss, }the lanes' build cache (HEFESTO_LANE_CACHE)"
    else   # the probe folder beside the cache setup recorded: <hefesto cache>/lane-cache/<key> → <hefesto cache>/lane-cache-probe
      lpr="$(dirname "$(dirname "$lcr")")/lane-cache-probe"
      # The Bash tool runs --check SANDBOXED, where this write fails by design (#162 review): only a caller that runs
      # outside the sandbox — the session-start hook sets HEFESTO_CHECK_UNSANDBOXED=1 (exactly 1) — has the write tested. Setup's
      # own run tests it too. A sandboxed caller that sets the flag only gets a false "missing".
      if [ ! -d "$lpr" ]; then miss="${miss:+$miss, }the lane-build.sh probe folder ($lpr)"
      elif [ "${HEFESTO_CHECK_UNSANDBOXED:-}" = 1 ]; then
        t="$(mktemp "$lpr/.check.XXXXXX" 2>/dev/null)" && rm -f "$t" || miss="${miss:+$miss, }a lane-build.sh probe folder this shell can write ($lpr)"
      fi
    fi
  fi
  # Refusals (lanes-interactive FR-023, reviews): a grant that reaches hefesto's own state, a sandbox turned off,
  # a hook command a sandboxed session could rewrite, a lane map that no longer matches the config.
  HCR="$HC"; [ -n "$HCP" ] && HCR="$HCP"
  for t in ${granted[@]+"${granted[@]}"}; do
    tt="$(printf '%s/' "$t" | tr -s /)"
    case "$(printf '%s/' "$HC" | tr -s /)" in "$tt"*) miss="${miss:+$miss, }no sandbox write grant that reaches $HC (granted: $t)"; break ;; esac
    case "$(printf '%s/' "$HCR" | tr -s /)" in "$tt"*) miss="${miss:+$miss, }no sandbox write grant that reaches $HCR (granted: $t)"; break ;; esac
  done
  for sf in "$F" "$TOP/.claude/settings.json" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; do
    [ -f "$sf" ] || continue
    [ "$(jq -r '.sandbox.enabled // empty' "$sf" 2>/dev/null)" = false ] && miss="${miss:+$miss, }the sandbox on ($sf sets sandbox.enabled false)"
    # HEF-27 FR-005: an ask rule on a hefesto helper outside the signature set stops every lane pass on a dialog.
    # Read from every applying file, under any prefix (a moved clone, a removed profile) — reported, never edited
    # outside $F (D6). Classified by subcommand + signature flag, never by exact text, so a signature written in
    # another form (`ledger.sh approve`, no `:*`) is never called a mechanic.
    while IFS= read -r r; do miss="${miss:+$miss, }no ask rule outside the signature set ($r in $sf — every lane pass would stop on it)"
    done < <(ask_defects "$sf")
    while IFS= read -r hc; do
      hp="$(first_word "$hc")"; case "$hp" in /*) ;; *) continue ;; esac
      unsafe_root "$(dirname "$hp")" && miss="${miss:+$miss, }no hook command where a sandboxed session can write ($hp, in $sf)"
    done < <(jq -r '.hooks // {} | .[]? | .[]? | .hooks[]? | .command // empty' "$sf" 2>/dev/null)
    m="$(jq -r '.permissions.defaultMode // empty' "$sf" 2>/dev/null)"
    case "$m" in auto|bypassPermissions|dontAsk) echo "setup: note: $sf sets defaultMode $m — in that mode a command no rule matches is not asked about (hefesto's ask rules still ask)" ;; esac
  done
  if [ "$(jq -r '.env.HEFESTO_LANES // empty' <<<"$CUR")" = 1 ]; then
    now="$(resolve_lane_map "$BCFG" "$TOP" 2>&1)" || now=""
    if [ -z "$now" ] || [ "$(jq -S . <<<"$now" 2>/dev/null)" != "$(jq -r '.env.HEFESTO_LANE_MAP // "{}"' <<<"$CUR" | jq -S . 2>/dev/null)" ]; then
      miss="${miss:+$miss, }the lane names of $BCFG (they changed since setup — run it again with --lanes)"
    else
      echo "setup: lanes $(jq -r 'to_entries | group_by(.value) | map("\(.[0].value): \(map(.key) | join(" "))") | join(" · ")' <<<"$now")"
    fi
  fi
  if [ -n "$miss" ]; then echo "setup: missing $miss for $me — run: bash $CLONE/hooks/hefesto-setup.sh$([ "$(jq -r '.env.HEFESTO_LANES // empty' <<<"$CUR")" = 1 ] || [ "$LANES" = 1 ] && echo ' --lanes')"; exit 1; fi
  [ "${#u_excl[@]}" -eq 0 ] || echo "setup: your commands outside the sandbox: ${u_excl[*]}"
  [ "${#u_allow[@]}" -eq 0 ] || echo "setup: your allowed commands: ${u_allow[*]}"
  echo "setup: ok"; exit 0
fi

# Ours = an entry under a known hefesto prefix (any version), in either spelling. Every run removes all of
# ours, then (unless --remove) adds the current set: stale versions go, the person's own entries stay. A
# container we emptied is deleted only if it held something before — a person's own `{}` is kept.
NEW="$(jq -c --argjson r "$RULES" --arg mode "$MODE" '
  # ours: under a known root, and naming one of the hefesto helpers — the other rules of a person under the
  # same folder are left alone
  def ours: (sub("^Bash\\((bash )?"; "")) as $s | any($r.prefixes[]; . as $p | ($s | startswith($p + "/"))
    and ($s[($p | length):] | test("^/([^/ ]+/)*/?hooks/(status-board|ledger|session-launch|speckit-helper|hefesto-setup|run-follow|pr-watch)\\.sh( |:|\\)|$)")));
  def addu($xs): (. // []) as $a | $a + [$xs[] | select(. as $x | $a | index([$x]) | not)];
  def strip: (. // []) | map(select((type == "string" and ours) | not));
  def gaugeours: (.statusLine.command? // "") as $c | ($c | type == "string") and ($c | test("/hooks/context-gauge[.]sh( --with-user)?$"))
    and any($r.prefixes[]; . as $p | $c | startswith($p + "/"));
  def keep_own_empty($o): with_entries(.key as $k | select((.value != [] and .value != {}) or (($o | type) == "object" and ($o | has($k)) and $o[$k] == .value)));
  . as $old
  # the extras the previous run added (env.HEFESTO_SETUP_EXTRA) come out first, whatever they were then
  | (($old.env.HEFESTO_SETUP_EXTRA? // "{}") | (try fromjson catch {}) | if type == "object" then . else {} end) as $px
  | def minus($xs): (. // []) - ($xs // []);
    (if .permissions then .permissions.allow |= (strip | minus($px.allow)) | .permissions.ask |= strip
       | (if .permissions.deny then .permissions.deny |= minus($px.deny) else . end)
       | (if .permissions.additionalDirectories then .permissions.additionalDirectories |= minus($px.dirs) else . end) else . end)
  | (if .sandbox.excludedCommands then .sandbox.excludedCommands |= minus($px.excl) else . end)
  | (if .sandbox.network.deniedDomains then .sandbox.network.deniedDomains |= minus($px.net) else . end)
  | (if .sandbox.filesystem.allowWrite then .sandbox.filesystem.allowWrite |= minus($px.write) else . end)
  | (if .sandbox then .sandbox.excludedCommands |= (strip | map(select(. as $x | $r.bad | index([$x]) | not)))
       | (if .sandbox.filesystem then .sandbox.filesystem.allowWrite |= ((. // []) - $r.write) else . end) else . end)
  | (if gaugeours and ($r.keep == 0 or $mode == "remove") then del(.statusLine) else . end)
  # The two keys a person may have set themselves are removed only when setup set them (env.HEFESTO_SETUP_SET).
  | (($old.env.HEFESTO_SETUP_SET? // "") | split(",") | map(select(. != ""))) as $mk
  | (if $mode == "remove" and ($mk | index(["inbound"])) and .crossSessionInbound == "accept" then del(.crossSessionInbound) else . end)
  | (if $mode == "remove" and ($mk | index(["autoallow"])) then del(.sandbox.autoAllowBashIfSandboxed) else . end)
  | (if $mode == "remove" and ($mk | index(["sandbox"])) then del(.sandbox.enabled, .sandbox.failIfUnavailable) else . end)
  | (if $mode == "remove" and .env then .env |= (del(.HEFESTO_TRUSTED_TOP, .HEFESTO_TRUSTED_BOARD, .HEFESTO_SETUP_SET, .HEFESTO_LANES, .HEFESTO_LANE_MAP, .HEFESTO_LANE_CACHE, .HEFESTO_SETUP_EXTRA)) else . end)
  # 9.0: without --strict, sandboxed commands run without a dialog again (7.x behaviour, user decision 2026-10-23):
  # the autoAllowBashIfSandboxed false of an 8.x setup is taken back out; the env lane keys follow the current --lanes.
  | (if $mode != "remove" and $r.strict == 0 and ($mk | index(["autoallow"])) then del(.sandbox.autoAllowBashIfSandboxed) else . end)
  | (if $mode != "remove" and $r.lanes == 0 and .env then .env |= del(.HEFESTO_LANES, .HEFESTO_LANE_MAP, .HEFESTO_LANE_CACHE) else . end)
  | ($mk | map(select(. != "autoallow" or $r.strict == 1))) as $mk
  | (if $mode == "remove" then .
     else .permissions.allow |= addu($r.allow) | .permissions.ask |= addu($r.ask)
       | .sandbox.excludedCommands |= addu($r.exclude)
       | .permissions.allow |= addu($r.xallow) | .sandbox.excludedCommands |= addu($r.xexcl) | .permissions.deny |= addu($r.xdeny)
       | (if ($r.xdirs | length) > 0 then .permissions.additionalDirectories |= addu($r.xdirs) else . end)
       | .sandbox.network.deniedDomains |= addu($r.xnet)
       | (if ($r.xwrite | length) > 0 then .sandbox.filesystem.allowWrite |= addu($r.xwrite) else . end)
       | (if $r.keep == 0 and .statusLine == null then .statusLine = $r.gauge else . end)
       | (if $r.lanes == 1 and .crossSessionInbound == null then .crossSessionInbound = "accept" | .__m += ["inbound"] else . end)
       | (if $r.strict == 0 or .sandbox.autoAllowBashIfSandboxed == false then . else .sandbox.autoAllowBashIfSandboxed = false | .__m += ["autoallow"] end)
       | (if .sandbox.enabled == true and .sandbox.failIfUnavailable == true then . else .sandbox.enabled = true | .sandbox.failIfUnavailable = true | .__m += ["sandbox"] end)
       | (($mk + (.__m // [])) | unique) as $m | del(.__m)
       | .env = ((.env // {}) + $r.env + {HEFESTO_SETUP_EXTRA: ({allow: $r.xallow, excl: $r.xexcl, deny: $r.xdeny, dirs: $r.xdirs, net: $r.xnet, write: $r.xwrite, user_allow: $r.uallow, user_excl: $r.uexcl} | tojson)}
                + (if ($m | length) > 0 then {HEFESTO_SETUP_SET: ($m | join(","))} else {} end)) end)
  | (if .env then .env |= . else . end)
  | (if .permissions then .permissions |= keep_own_empty($old.permissions) else . end)
  | (if .sandbox.filesystem then .sandbox.filesystem |= keep_own_empty($old.sandbox.filesystem) else . end)
  | (if .sandbox.network then .sandbox.network |= keep_own_empty($old.sandbox.network) else . end)
  | (if .sandbox then .sandbox |= keep_own_empty($old.sandbox) else . end)
  | with_entries(select((.key != "permissions" and .key != "sandbox" and .key != "env") or .value != {} or ($old[.key] == {})))' <<<"$CUR")" || die "could not merge into $F (nothing was written)"

# HEF-30 FR-015 (spec D6): orchestrate.decider, the --by name the orchestrator records decisions with, from
# `git config user.name` — written only when the key is absent, never overwritten; a label, not proof (the permission
# dialog stays the proof). The board config is a file a lane can write, so a symlink there is never written through.
# --remove leaves it: the key belongs to the board, not to these settings.
decider_plan() { # → DEC_MSG, and DEC_NEW (the name to write) when setup would write it
  DEC_NEW=""; DEC_MSG=""
  [ -f "$BCFG" ] || { DEC_MSG="no board config at $BCFG — orchestrate.decider not written"; return 0; }
  if jq -e '(.orchestrate // {}) | type == "object" and has("decider")' "$BCFG" >/dev/null 2>&1; then
    DEC_MSG="orchestrate.decider is set ($(jq -c '.orchestrate.decider' "$BCFG")) — left as it is"; return 0; fi
  jq -e '(.orchestrate // {}) | type == "object"' "$BCFG" >/dev/null 2>&1 || { DEC_MSG="$BCFG has no orchestrate object setup can add to — orchestrate.decider not written"; return 0; }
  [ ! -L "$BCFG" ] || { DEC_MSG="$BCFG is a symlink — orchestrate.decider not written (set it there by hand)"; return 0; }
  DEC_NEW="$(git -C "$TOP" config user.name 2>/dev/null)"
  [ -n "$DEC_NEW" ] || { DEC_MSG="git config user.name is empty — orchestrate.decider not written; the orchestrator asks your name once per session"; return 0; }
  # the ledger's --by rule (ledger-lanes.sh person_gate): a decider it would refuse is never written
  [[ "$DEC_NEW" =~ ^[A-Za-z0-9]([A-Za-z0-9._@\ -]{0,62}[A-Za-z0-9._@-])?$ ]] \
    || { DEC_MSG="git config user.name '$(printf '%s' "$DEC_NEW" | head -c 64 | tr -d '\n\r')' is not a name the ledger accepts as --by (letters, digits, space . _ @ -) — orchestrate.decider not written; set it by hand"; DEC_NEW=""; return 0; }
  DEC_MSG="orchestrate.decider: \"$DEC_NEW\" (from git config user.name) in $BCFG"
}
[ "$MODE" = remove ] || decider_plan
# --print's stdout stays the settings JSON (callers parse it); the decider it would write goes to stderr
if [ "$MODE" = print ]; then jq . <<<"$NEW"; [ -z "${DEC_NEW:-}" ] || echo "decider: $DEC_MSG" >&2; exit 0; fi
if [ "$MODE" != remove ] && [ -n "$LCP" ]; then
  mkdir -p "$LCP" "$LCPROBE" && chmod 700 "$LCP" || die "cannot create the lanes' build cache $LCP (nothing was written)"
  # the probe write must succeed here, outside the sandbox: lane-build.sh reads a failed write as "sandboxed"
  t="$(mktemp "$LCPROBE/.check.XXXXXX")" && rm -f "$t" || die "the probe folder $LCPROBE is not writable from this shell — lane-build.sh would take this machine's unsandboxed shell for the sandbox (nothing was written)"
fi
for s in ${skipped[@]+"${skipped[@]}"}; do echo "skipped $s: a sandboxed session can write there (the project, a temp folder, or a granted path), so it could rewrite the launcher"; done
if [ "$(jq -S . <<<"$NEW")" = "$(jq -S . <<<"$CUR")" ] && { [ -f "$F" ] || [ "$NEW" = '{}' ]; }; then
  echo "unchanged: $F already holds hefesto's lane settings$([ "$MODE" = remove ] && echo ' — none of them, rather')"
else
  mkdir -p "$TOP/.claude" || die "cannot create $TOP/.claude"
  TMP="$(mktemp "$TOP/.claude/.settings.local.XXXXXX")" || die "mktemp failed in $TOP/.claude"
  jq . <<<"$NEW" > "$TMP" && jq -e 'type == "object"' "$TMP" >/dev/null || { rm -f "$TMP"; die "could not prepare $F"; }
  # Write through a symlink (a stowed file stays a link) only from the validated copy; a plain file is replaced.
  if [ -L "$F" ]; then cat "$TMP" > "$F" && rm -f "$TMP" || { rm -f "$TMP"; die "could not write through the link $F"; }
  else mv "$TMP" "$F" || { rm -f "$TMP"; die "could not write $F"; }; fi
  if [ "$MODE" = remove ]; then echo "removed hefesto's lane settings from $F"
    OLDLC="$(jq -r '.env.HEFESTO_LANE_CACHE // empty' <<<"$CUR")"; [ -z "$OLDLC" ] || echo "the lanes' build cache is left at $OLDLC — delete it when no lane needs it"
  else echo "wrote hefesto's lane settings to $F (${#roots[@]} plugin folder(s)$([ "$LANES" = 1 ] && echo ', four-lane doorbells on')$([ "${#wr[@]}" -gt 0 ] && echo ", the board's ledger folder writable"))"; fi
fi
if [ "$MODE" != remove ] && ! git -C "$TOP" check-ignore -q .claude/settings.local.json 2>/dev/null; then
  printf '/.claude/settings.local.json\n' >> "$CDIR/info/exclude" && echo "kept out of git: added .claude/settings.local.json to $CDIR/info/exclude"
fi
[ "$MODE" = remove ] && exit 0
if [ -n "${DEC_NEW:-}" ]; then
  DT="$(mktemp "$(dirname "$BCFG")/.project-status.XXXXXX")" && jq --arg d "$DEC_NEW" '.orchestrate.decider = $d' "$BCFG" > "$DT" && jq -e . "$DT" >/dev/null \
    && mv "$DT" "$BCFG" && echo "wrote $DEC_MSG" || { rm -f "${DT:-}"; echo "could not write orchestrate.decider into $BCFG — set it by hand"; }
else echo "decider: $DEC_MSG"; fi
if [ "$LANES" = 1 ] && [ "$(jq -r '.crossSessionInbound // ""' <<<"$NEW")" != accept ]; then
  echo "note: crossSessionInbound is '$(jq -r '.crossSessionInbound' <<<"$NEW")' in $F (your setting, kept) — the stage lanes will not receive the orchestrator's doorbells until it is \"accept\""
fi
if [ "$KEEP" = 0 ] && [ "$(jq -c '.statusLine' <<<"$NEW")" != "$(jq -c '.gauge' <<<"$RULES")" ]; then
  echo "your own status line is kept; to show the context gauge in it, print: \"\$(printf '%s' \"\$INPUT\" | $(gauge_root)/hooks/context-gauge.sh)\""
fi
if [ "$LANES" = 1 ]; then
  echo "next: open each lane with  claude --name <name>  (any wrapper that forwards claude's arguments works), one per role:"
  jq -r 'to_entries | group_by(.value) | map("  \(.[0].value): \(map(.key) | join(", "))") | .[]' <<<"$LMAP"
  echo "  (names come from orchestrate.lanes, orchestrate.lane_prefix or the folder name; edit them there and run this again)"
else
  echo "next: open the lane with  claude --name $(basename "$TOP")-orchestrator  (any wrapper that forwards claude's arguments works)"
fi
