#!/bin/bash
# hefesto-setup.sh — set a project up for the hefesto lanes, once per project and machine (lanes-v3 FR-001..005).
# Run it in a normal terminal from the project's main folder:
#
#   bash ~/.claude-framework/hooks/hefesto-setup.sh [--lanes] [--keep-statusline] [--check | --remove | --print]
#
# It merges into <main checkout>/.claude/settings.local.json (kept out of git) what a lane needs, so a lane
# opens with plain `claude --name <repo>-<lane>` — or any wrapper that forwards claude's arguments:
#   permissions.allow         hefesto's own read-only and registering helper calls, as exact rules
#   permissions.ask           the commands that clear or rewrite a person's decision — their dialog always shows
#   sandbox.excludedCommands  the launcher only: the lane keeps its sandbox, its background sessions still run
#   sandbox.filesystem.allowWrite  on an external board, the board's ledger folder (never the board repository)
#   statusLine                the context gauge, run as `context-gauge.sh --with-user`: your profile's own status
#                             line first, then `ctx 45% · 90k/200k` (left alone when this file already has one)
#   crossSessionInbound       "accept", with --lanes: the orchestrator's doorbells reach the stage lanes
#   sandbox.autoAllowBashIfSandboxed  false: any command outside the allowlist asks, sandboxed or not — else a
#                             sandboxed call could rewrite the ledger (.git/hefesto) and clear a gate silently
#   env.HEFESTO_TRUSTED_TOP / HEFESTO_TRUSTED_BOARD  the folders the launcher may run in, fixed here where no
#                             sandboxed session can change them
# Every other key is kept. A plugin cannot ship these settings itself, hence this step.
#   --lanes            the four-lane setup (adds crossSessionInbound)
#   --keep-statusline  never touch statusLine
#   --check            read-only: "setup: ok", or what is missing for this plugin root (exit 1)
#   --remove           take out every entry this script writes (for any hefesto version)
#   --print            show the merged file; write nothing
# Rules name each plugin root explicitly — the clone this runs from and each profile's installed copy —
# never with a wildcard inside a path: `…/hefesto/*/hooks/session-launch.sh *` would also match
# `…/hefesto/../../../tmp/x/hooks/session-launch.sh`, a file a sandboxed session can write, and run it outside
# the sandbox. For the same reason a root inside this project or a temp folder is skipped. Each run drops the
# rules of hefesto versions no longer installed; after a plugin update run it again (the session start says so).
set -uo pipefail
die() { echo "hefesto-setup: $*" >&2; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CLONE="$(dirname "$HERE")"
LANES=0; KEEP=0; STRICT=0; MODE="write"
while [ $# -gt 0 ]; do case "$1" in
  --lanes) LANES=1 ;; --keep-statusline) KEEP=1 ;; --strict) STRICT=1 ;;
  --check|--remove|--print) [ "$MODE" = write ] || die "one of --check, --remove, --print at a time (got --$MODE and $1)"; MODE="${1#--}" ;;
  -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "unknown option '$1' (expected --lanes, --strict, --keep-statusline, --check, --remove or --print)" ;;
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
roots=(); skipped=(); cfgs=()
add_root() { local p="${1%/}"; [ -n "$p" ] || return 0
  if unsafe_root "$p"; then skipped+=("$p"); return 0; fi
  case " ${roots[*]-} " in *" $p "*) ;; *) roots+=("$p") ;; esac; }
add_root "$CLONE"
for cfg in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.claude" "$HOME"/.claude-*; do
  [ -n "$cfg" ] && [ -f "$cfg/plugins/installed_plugins.json" ] || continue
  case " ${cfgs[*]-} " in *" $cfg "*) continue ;; esac; cfgs+=("$cfg")
  while IFS= read -r p; do add_root "$p"; done \
    < <(jq -r '[.plugins["hefesto@hefesto"][]? | select(.scope == "user") | .installPath // empty] | .[]' "$cfg/plugins/installed_plugins.json" 2>/dev/null)
done
[ "${#roots[@]}" -gt 0 ] || die "no usable hefesto folder: every candidate lies inside this project or a temp folder (${skipped[*]-}) — run it from your hefesto install (~/.claude-framework)"

# What marks an entry as ours, for any version: the clone, and every profile's plugin cache.
prefixes=("$CLONE"); for c in ${cfgs[@]+"${cfgs[@]}"}; do prefixes+=("$c/plugins/cache/hefesto"); done
allow=(); ask=(); excl=()
for r in "${roots[@]}"; do for h in "$r/hooks" "$r//hooks"; do
  allow+=("Bash($h/status-board.sh)" "Bash($h/status-board.sh --detailed:*)" "Bash($h/status-board.sh --check:*)" "Bash($h/status-board.sh --item:*)"
          "Bash($h/status-board.sh --add:*)" "Bash($h/status-board.sh --init)" "Bash($h/status-board.sh --detect)" "Bash($h/status-board.sh --item-raw:*)" "Bash($h/hefesto-setup.sh --check)"
          "Bash($h/ledger.sh board:*)" "Bash($h/ledger.sh list:*)" "Bash($h/ledger.sh next:*)" "Bash($h/ledger.sh show:*)" "Bash($h/ledger.sh metrics:*)"
          "Bash($h/ledger.sh register:*)" "Bash($h/ledger.sh publish:*)" "Bash($h/ledger.sh escalate:*)" "Bash($h/ledger.sh questions:*)"
          "Bash($h/session-launch.sh:*)" "Bash($h/speckit-helper.sh:*)" "Bash($h/run-follow.sh:*)")
  for c in unblock record claim advance handoff block revise answer; do
    ask+=("Bash($h/ledger.sh $c:*)" "Bash(bash $h/ledger.sh $c:*)")   # the second spelling would miss the first rule
  done
  excl+=("$h/session-launch.sh *" "$h/ledger.sh *")
done; done
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
envj="$(jq -nc --arg t "$TOP" --arg b "${BTOP:-}" --argjson lanes "$LANES" --arg m "$LMAP" '{HEFESTO_TRUSTED_TOP: $t} + (if $b != "" then {HEFESTO_TRUSTED_BOARD: $b} else {} end)
  + (if $lanes == 1 then {HEFESTO_LANES: "1", HEFESTO_LANE_MAP: $m} else {} end)')"
# What else setup adds (lanes-interactive FR-022, review rounds 2–3), recorded in env.HEFESTO_SETUP_EXTRA so every run
# can take its previous set out first: gh outside the sandbox (so a merge is decided by the rules) with only its
# read and PR-opening forms allowed; the project's read-only and unsandboxed command lists; Edit denied on
# hefesto's own state, by every spelling of the path.
x_allow=("Bash(gh pr view:*)" "Bash(gh pr list:*)" "Bash(gh pr checks:*)" "Bash(gh pr diff:*)" "Bash(gh pr create:*)"
         "Bash(gh run list:*)" "Bash(gh run view:*)" "Bash(gh repo view:*)" "Bash(gh auth status)")
x_excl=("gh *"); x_deny=()
HC="$HOME/.cache/hefesto"; HCP="$(mkdir -p "$HC" 2>/dev/null; cd -P "$HC" 2>/dev/null && pwd -P)"
for b in "$HC" ${HCP:+"$HCP"}; do for sub in ledger approvals sessions; do r="Edit(/$b/$sub/**)"; case " ${x_deny[*]-} " in *" $r "*) ;; *) x_deny+=("$r") ;; esac; done; done
cmd_ok() { # $1 a configured command pattern → 0 when safe to write as a rule (review round 1 #6)
  case "$1" in ""|"*"*|*$'\n'*) return 1 ;; esac
  [[ "$1" =~ [\;\&\|\<\>\`\$\(\)\{\}] ]] && return 1
  case "${1%% *}" in sh|bash|zsh|env|eval|exec|xargs|sudo|nohup|timeout|command|builtin) return 1 ;; esac
  case " $1 " in *" -c "*) return 1 ;; esac
  return 0
}
while IFS= read -r c; do [ -n "$c" ] || continue
  cmd_ok "$c" || die "orchestrate.readonly_commands: '$c' is not a plain command pattern (no shell operators, no wrapper or interpreter, no -c, not starting with *)"
  x_allow+=("Bash($c)")
done < <(jq -r '.orchestrate.readonly_commands // [] | .[]' "$BCFG" 2>/dev/null)
while IFS= read -r c; do [ -n "$c" ] || continue
  cmd_ok "$c" || die "orchestrate.unsandboxed_commands: '$c' is not a plain command pattern"
  case "$c" in /*) ;; *) die "orchestrate.unsandboxed_commands: '$c' must start with an absolute path (a bare name is found on PATH, which a lane can change)" ;; esac
  unsafe_root "$(dirname "${c%% *}")" && die "orchestrate.unsandboxed_commands: '${c%% *}' lies where a sandboxed session can write — it would run whatever a lane put there outside the sandbox"
  x_excl+=("$c")
done < <(jq -r '.orchestrate.unsandboxed_commands // [] | .[]' "$BCFG" 2>/dev/null)
# An exclusion for a launcher that is gone, or that a sandboxed session could write, would let whoever
# creates that file run it outside the sandbox: every run drops such entries, whoever wrote them.
badx=()
while IFS= read -r x; do
  case "$x" in */hooks/session-launch.sh\ \*) f="${x% \*}"; { [ -f "$f" ] && ! unsafe_root "$(dirname "$(dirname "$f")")"; } || badx+=("$x") ;; esac
done < <(jq -r '.sandbox.excludedCommands // [] | .[] | strings' <<<"$CUR")
jarr() { if [ $# -eq 0 ]; then echo '[]'; else printf '%s\n' "$@" | jq -R . | jq -sc .; fi; }
RULES="$(jq -nc --argjson a "$(jarr "${allow[@]}")" --argjson k "$(jarr "${ask[@]}")" --argjson x "$(jarr "${excl[@]}")" \
  --argjson w "$(jarr ${wr[@]+"${wr[@]}"})" --argjson px "$(jarr "${prefixes[@]}")" --argjson bad "$(jarr ${badx[@]+"${badx[@]}"})" --argjson env "$envj" \
  --arg g "${roots[0]}/hooks/context-gauge.sh --with-user" --argjson lanes "$LANES" --argjson keep "$KEEP" --argjson strict "$STRICT" \
  --argjson xa "$(jarr "${x_allow[@]}")" --argjson xe "$(jarr "${x_excl[@]}")" --argjson xd "$(jarr "${x_deny[@]}")" \
  '{allow: $a, ask: $k, exclude: $x, write: $w, prefixes: $px, bad: $bad, env: $env, gauge: {type: "command", command: $g}, lanes: $lanes, keep: $keep,
    strict: $strict, xallow: $xa, xexcl: $xe, xdeny: $xd}')" || die "could not build the rules"

if [ "$MODE" = check ]; then
  me="${CLAUDE_PLUGIN_ROOT:-$CLONE}"; me="${me%/}"
  miss="$(jq -r --arg h "$me/hooks" '[
      (if ((.permissions.allow // []) | index(["Bash(\($h)/ledger.sh board:*)"])) then empty else "the helper allowlist" end),
      (if ((.permissions.ask // []) | index(["Bash(\($h)/ledger.sh unblock:*)"])) then empty else "the ask rules" end),
      (if ((.sandbox.excludedCommands // []) | index(["\($h)/session-launch.sh *"])) then empty else "the launcher sandbox exclusion" end),
      (if ((.sandbox.excludedCommands // []) | index(["\($h)/ledger.sh *"])) then empty else "the ledger.sh sandbox exclusion (hefesto 9 keeps the ledger outside the project)" end),
      (if ((.sandbox.excludedCommands // []) | index(["gh *"])) then empty else "gh outside the sandbox (so a merge is decided by the permission rules)" end),
      (if .sandbox.enabled == true then empty else "sandbox.enabled true" end),
      (if ((.env.HEFESTO_SETUP_SET // "") | split(",") | index(["autoallow"])) and .sandbox.autoAllowBashIfSandboxed != false then "sandbox.autoAllowBashIfSandboxed false (--strict)" else empty end),
      (if .env.HEFESTO_TRUSTED_TOP then empty else "the trusted project folder" end)
    ] | join(", ")' <<<"$CUR")"
  [ "${#badx[@]}" -eq 0 ] || miss="${miss:+$miss, }the removal of a launcher exclusion for a missing or writable file (${badx[*]})"
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
  echo "setup: ok"; exit 0
fi

# Ours = an entry under a known hefesto prefix (any version), in either spelling. Every run removes all of
# ours, then (unless --remove) adds the current set: stale versions go, the person's own entries stay. A
# container we emptied is deleted only if it held something before — a person's own `{}` is kept.
NEW="$(jq -c --argjson r "$RULES" --arg mode "$MODE" '
  # ours: under a known root, and naming one of the hefesto helpers — the other rules of a person under the
  # same folder are left alone
  def ours: (sub("^Bash\\((bash )?"; "")) as $s | any($r.prefixes[]; . as $p | ($s | startswith($p + "/"))
    and ($s[($p | length):] | test("^/([^/ ]+/)*/?hooks/(status-board|ledger|session-launch|speckit-helper|hefesto-setup|run-follow)\\.sh( |:|\\)|$)")));
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
       | (if .permissions.deny then .permissions.deny |= minus($px.deny) else . end) else . end)
  | (if .sandbox.excludedCommands then .sandbox.excludedCommands |= minus($px.excl) else . end)
  | (if .sandbox then .sandbox.excludedCommands |= (strip | map(select(. as $x | $r.bad | index([$x]) | not)))
       | (if .sandbox.filesystem then .sandbox.filesystem.allowWrite |= ((. // []) - $r.write) else . end) else . end)
  | (if gaugeours and ($r.keep == 0 or $mode == "remove") then del(.statusLine) else . end)
  # The two keys a person may have set themselves are removed only when setup set them (env.HEFESTO_SETUP_SET).
  | (($old.env.HEFESTO_SETUP_SET? // "") | split(",") | map(select(. != ""))) as $mk
  | (if $mode == "remove" and ($mk | index(["inbound"])) and .crossSessionInbound == "accept" then del(.crossSessionInbound) else . end)
  | (if $mode == "remove" and ($mk | index(["autoallow"])) then del(.sandbox.autoAllowBashIfSandboxed) else . end)
  | (if $mode == "remove" and ($mk | index(["sandbox"])) then del(.sandbox.enabled, .sandbox.failIfUnavailable) else . end)
  | (if $mode == "remove" and .env then .env |= (del(.HEFESTO_TRUSTED_TOP, .HEFESTO_TRUSTED_BOARD, .HEFESTO_SETUP_SET, .HEFESTO_LANES, .HEFESTO_LANE_MAP, .HEFESTO_SETUP_EXTRA)) else . end)
  # 9.0: without --strict, sandboxed commands run without a dialog again (7.x behaviour, user decision 2026-10-23):
  # the autoAllowBashIfSandboxed false of an 8.x setup is taken back out; the env lane keys follow the current --lanes.
  | (if $mode != "remove" and $r.strict == 0 and ($mk | index(["autoallow"])) then del(.sandbox.autoAllowBashIfSandboxed) else . end)
  | (if $mode != "remove" and $r.lanes == 0 and .env then .env |= del(.HEFESTO_LANES, .HEFESTO_LANE_MAP) else . end)
  | ($mk | map(select(. != "autoallow" or $r.strict == 1))) as $mk
  | (if $mode == "remove" then .
     else .permissions.allow |= addu($r.allow) | .permissions.ask |= addu($r.ask)
       | .sandbox.excludedCommands |= addu($r.exclude)
       | .permissions.allow |= addu($r.xallow) | .sandbox.excludedCommands |= addu($r.xexcl) | .permissions.deny |= addu($r.xdeny)
       | (if $r.keep == 0 and .statusLine == null then .statusLine = $r.gauge else . end)
       | (if $r.lanes == 1 and .crossSessionInbound == null then .crossSessionInbound = "accept" | .__m += ["inbound"] else . end)
       | (if $r.strict == 0 or .sandbox.autoAllowBashIfSandboxed == false then . else .sandbox.autoAllowBashIfSandboxed = false | .__m += ["autoallow"] end)
       | (if .sandbox.enabled == true and .sandbox.failIfUnavailable == true then . else .sandbox.enabled = true | .sandbox.failIfUnavailable = true | .__m += ["sandbox"] end)
       | (($mk + (.__m // [])) | unique) as $m | del(.__m)
       | .env = ((.env // {}) + $r.env + {HEFESTO_SETUP_EXTRA: ({allow: $r.xallow, excl: $r.xexcl, deny: $r.xdeny} | tojson)}
                + (if ($m | length) > 0 then {HEFESTO_SETUP_SET: ($m | join(","))} else {} end)) end)
  | (if .env then .env |= . else . end)
  | (if .permissions then .permissions |= keep_own_empty($old.permissions) else . end)
  | (if .sandbox.filesystem then .sandbox.filesystem |= keep_own_empty($old.sandbox.filesystem) else . end)
  | (if .sandbox then .sandbox |= keep_own_empty($old.sandbox) else . end)
  | with_entries(select((.key != "permissions" and .key != "sandbox" and .key != "env") or .value != {} or ($old[.key] == {})))' <<<"$CUR")" || die "could not merge into $F (nothing was written)"

if [ "$MODE" = print ]; then jq . <<<"$NEW"; exit 0; fi
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
  else echo "wrote hefesto's lane settings to $F (${#roots[@]} plugin folder(s)$([ "$LANES" = 1 ] && echo ', four-lane doorbells on')$([ "${#wr[@]}" -gt 0 ] && echo ", the board's ledger folder writable"))"; fi
fi
if [ "$MODE" != remove ] && ! git -C "$TOP" check-ignore -q .claude/settings.local.json 2>/dev/null; then
  printf '/.claude/settings.local.json\n' >> "$CDIR/info/exclude" && echo "kept out of git: added .claude/settings.local.json to $CDIR/info/exclude"
fi
[ "$MODE" = remove ] && exit 0
if [ "$LANES" = 1 ] && [ "$(jq -r '.crossSessionInbound // ""' <<<"$NEW")" != accept ]; then
  echo "note: crossSessionInbound is '$(jq -r '.crossSessionInbound' <<<"$NEW")' in $F (your setting, kept) — the stage lanes will not receive the orchestrator's doorbells until it is \"accept\""
fi
if [ "$KEEP" = 0 ] && [ "$(jq -c '.statusLine' <<<"$NEW")" != "$(jq -c '.gauge' <<<"$RULES")" ]; then
  echo "your own status line is kept; to show the context gauge in it, print: \"\$(printf '%s' \"\$INPUT\" | ${roots[0]}/hooks/context-gauge.sh)\""
fi
if [ "$LANES" = 1 ]; then
  echo "next: open each lane with  claude --name <name>  (any wrapper that forwards claude's arguments works), one per role:"
  jq -r 'to_entries | group_by(.value) | map("  \(.[0].value): \(map(.key) | join(", "))") | .[]' <<<"$LMAP"
  echo "  (names come from orchestrate.lanes, orchestrate.lane_prefix or the folder name; edit them there and run this again)"
else
  echo "next: open the lane with  claude --name $(basename "$TOP")-orchestrator  (any wrapper that forwards claude's arguments works)"
fi
