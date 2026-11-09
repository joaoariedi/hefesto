# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
#
# signature-dialogs smoke checks, part 11 (HEF-27; FR-001..FR-010, SC-001..SC-007): a permission dialog only where a
# person signs. hefesto-setup.sh writes the signature set as ask rules, every other ledger.sh subcommand as its own
# allow rule (claim and run: no rule — ledger.sh refuses them outside the launcher), one spelling per plugin root, and
# --check names a mechanics ask as the defect.
#
# SOURCED by tests/smoke.sh, never run on its own. Self-contained: a temp project, and a fake profile home whose
# installed hefesto copies sit BESIDE the repo — never under $TMPDIR, which setup rightly refuses to trust
# (unsafe_root): a fake root there would be skipped and every "two live roots" check would go red for the wrong
# reason (plan review round 5; the l3_su_mut pattern, tests/smoke.sh). Each fake root carries a
# hooks/session-launch.sh file, or setup's badx would drop its launcher exclusion as "missing" (round 6).

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ launcher >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-signatures.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_, launcher)"
  else echo "tests/smoke-signatures.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

head_ "Signature dialogs: ask only where a person signs, one spelling per root (HEF-27)"
sg_fail=0
SG_SU="$REPO/hooks/hefesto-setup.sh"
# beside the repo (trusted by setup), removed at the end of this part
sg_base="$(mktemp -d "$REPO/.smoke-sig.XXXXXX")"
sg_git() { git -c user.email=t@t -c user.name=t "$@"; }
sg_project() { # → a fresh git project (a temp folder: its own files are what a lane can write)
  local p; p="$(cd "$(mktemp -d)" && pwd -P)"; (cd "$p" && sg_git init -q -b main . && sg_git commit -q --allow-empty -m init && mkdir -p .claude)
  printf '%s\n' "$p"
}
sg_root() { # $1 a folder → a fake installed hefesto root there, with the launcher file setup's badx looks for
  mkdir -p "$1/hooks" && printf '#!/bin/bash\n' > "$1/hooks/session-launch.sh" && printf '%s\n' "$1"
}
sg_profile() { # $1 a profile (config) folder, then installPaths → its installed_plugins.json, user scope
  local cfg="$1"; shift; mkdir -p "$cfg/plugins"
  printf '%s\n' "$@" | jq -R . | jq -s '{plugins: {"hefesto@hefesto": map({scope: "user", installPath: .})}}' > "$cfg/plugins/installed_plugins.json"
}
# The profile is a CLAUDE_CONFIG_DIR beside the repo; HOME stays a temp folder. A HOME beside the repo would put the
# lanes' build cache (under ~/.cache/hefesto, sandbox-writable) inside the clone, and setup would rightly skip it.
sg_thome="$(mktemp -d)"
sg_su() { # $1 project, $2 profile folder, then setup's options → setup run there, as a person runs it from a terminal
  local p="$1" cfg="$2"; shift 2
  (cd "$p" && HOME="$sg_thome" CLAUDE_CONFIG_DIR="$cfg" env -u CLAUDE_PLUGIN_ROOT bash "${SG_SUM:-$SG_SU}" "$@")
}
# A setup mutant sits beside the real script, as tests/smoke.sh's l3_su_mut does (from a temp folder the script trusts
# no root, and the mutation would pass vacuously).
SG_SUM_FILE="$REPO/hooks/.smoke-mut-sig.sh"
sg_su_mut() { sed "$1" "$SG_SU" > "$SG_SUM_FILE"; cmp -s "$SG_SU" "$SG_SUM_FILE" && { bad "signature-dialogs setup mutation did not apply: $1"; sg_fail=1; }; SG_SUM="$SG_SUM_FILE"; }
sg_su_restore() { rm -f -- "${SG_SUM_FILE:?}"; SG_SUM=""; }
# The classification, read from setup itself — the single source the writer, --check and these checks share (FR-006).
# shellcheck disable=SC2034  # filled by the eval below, read by the checks further down
LEDGER_SIGN_WHOLE=(); LEDGER_SIGN_FLAG=(); LEDGER_LAUNCHER=(); LEDGER_ALLOW=(); LEDGER_ALLOW_EXACT=()
eval "$(sed -n '/^LEDGER_SIGN_WHOLE=/,/^LEDGER_ALLOW_EXACT=/p' "$SG_SU")"
[ "${#LEDGER_SIGN_WHOLE[@]}" -gt 0 ] && [ "${#LEDGER_SIGN_FLAG[@]}" -gt 0 ] && [ "${#LEDGER_ALLOW[@]}" -gt 0 ] \
  || { bad "hefesto-setup.sh must carry the classification lists LEDGER_SIGN_WHOLE / _FLAG / LEDGER_LAUNCHER / LEDGER_ALLOW / _EXACT (FR-006)"; sg_fail=1; }
sg_sign_rules() { # $1 hooks dir → the signature ask rules for it, as FR-001 spells them
  local s
  for s in "${LEDGER_SIGN_WHOLE[@]}"; do printf 'Bash(%s/ledger.sh %s:*)\n' "$1" "$s"; done
  for s in "${LEDGER_SIGN_FLAG[@]}"; do printf 'Bash(%s/ledger.sh %s * %s*)\n' "$1" "${s% *}" "${s#* }"; done
  printf 'Bash(%s/pr-watch.sh reply:*)\nBash(%s/pr-watch.sh comment:*)\n' "$1" "$1"
}

# --- SC-001 / FR-004 / US3: the 9.3-shape settings file is reduced to the signature set, one spelling per root ------
# signature-dialogs/FR-004 signature-dialogs/FR-001 signature-dialogs/FR-002 signature-dialogs/FR-008 (the --prepare
# launcher exclusion is part of the exact excludedCommands check; tests/smoke.sh's FR-014 --prepare case still claims)
sg_cfg="$sg_base/profile"; sg_v3="$sg_cfg/plugins/cache/hefesto/hefesto/9.3.0"; sg_v2="$sg_cfg/plugins/cache/hefesto/hefesto/9.2.0"
sg_root "$sg_v3" >/dev/null; sg_root "$sg_v2" >/dev/null; sg_profile "$sg_cfg" "$sg_v3"   # 9.2.0: stale, no longer installed
sg_p="$(sg_project)"; SG_F="$sg_p/.claude/settings.local.json"
sg_old() { # $1 hooks dir → the 9.3 writer's rules for it: 17 ledger asks × {plain, bash} spelling, then its allows
  local c
  for c in unblock record claim advance handoff block revise answer approve release drop fold supersede reopen "op close" "op drop"; do
    printf 'A\tBash(%s/ledger.sh %s:*)\nA\tBash(bash %s/ledger.sh %s:*)\n' "$1" "$c" "$1" "$c"
  done
  printf 'A\tBash(%s/pr-watch.sh reply:*)\nA\tBash(%s/pr-watch.sh comment:*)\n' "$1" "$1"
  for c in "status-board.sh" "status-board.sh --detailed:*" "hefesto-setup.sh --check" "ledger.sh board:*" "ledger.sh list:*" "ledger.sh register:*" \
           "ledger.sh op new:*" "ledger.sh park --all" "ledger.sh dir" "ledger.sh deployed:*" "session-launch.sh:*" "speckit-helper.sh:*" "pr-watch.sh:*"; do
    printf 'L\tBash(%s/%s)\n' "$1" "$c"
  done
  printf 'X\t%s/ledger.sh *\nX\t%s/session-launch.sh *\n' "$1" "$1"
}
sg_fixture() { # → the 9.3-shape settings.local.json: the clone and two installed versions, each in both slash spellings
  local h
  for h in "$REPO/hooks" "$REPO//hooks" "$sg_v3/hooks" "$sg_v3//hooks" "$sg_v2/hooks" "$sg_v2//hooks"; do sg_old "$h"; done \
    | jq -R 'split("\t")' | jq -s '{permissions: {ask: (map(select(.[0] == "A") | .[1]) + ["Bash(rm -rf:*)"]),
        allow: (["Bash(ls)"] + map(select(.[0] == "L") | .[1]))}, sandbox: {excludedCommands: (["docker *"] + map(select(.[0] == "X") | .[1]))}}' > "$SG_F"
}
sg_fixture
jq -e '(.permissions.ask | length) >= 200 and (.permissions.allow | length) >= 70' "$SG_F" >/dev/null \
  || { bad "the generated 9.3 fixture must be the measured shape (≥ 200 asks, ≥ 70 allows): $(jq -c '.permissions | map_values(length)' "$SG_F")"; sg_fail=1; }
sg_want_ask="$( { sg_sign_rules "$REPO/hooks"; sg_sign_rules "$sg_v3//hooks"; echo 'Bash(rm -rf:*)'; } | jq -R . | jq -sc 'sort')"
sg_reduced() { # → empty when $SG_F holds the reduced shape (SC-001), else the reason
  jq -r --argjson want "$sg_want_ask" --arg c "$REPO/hooks" --arg i "$sg_v3//hooks" --arg i1 "$sg_v3/hooks" --arg v2 "$sg_v2" --arg rd "$REPO//hooks" '
    def ours: test("/hooks/(ledger|pr-watch|session-launch|status-board|speckit-helper|run-follow|hefesto-setup)[.]sh");
    def tail($h): ltrimstr("Bash(" + $h + "/") | rtrimstr(")");
    (.permissions.allow | map(select(ours))) as $al
    | [ (if (.permissions.ask | sort) == $want then empty else "permissions.ask is not exactly the 17 signature forms × the two live roots + the rules of the person: extra \(.permissions.ask - $want), missing \($want - .permissions.ask)" end),
        (if ($want | length) == 35 then empty else "the signature set is not 17 forms per root (\($want | length) rules for two roots + 1)" end),
        (if (.permissions.allow | group_by(.) | all(length == 1)) then empty else "a duplicated allow rule" end),
        (if ($al | all(startswith("Bash(" + $c + "/") or startswith("Bash(" + $i + "/"))) then empty
         else "an allow rule in another spelling or version: \($al | map(select((startswith("Bash(" + $c + "/") or startswith("Bash(" + $i + "/")) | not)))" end),
        (if ([$al[] | select(startswith("Bash(" + $c + "/")) | tail($c)] | sort) == ([$al[] | select(startswith("Bash(" + $i + "/")) | tail($i)] | sort) then empty
         else "the two roots do not hold the same allow set" end),
        (if ($al | map(select(test("ledger[.]sh (claim|run)[ :)]"))) | length) == 0 then empty else "an allow rule for the launcher-only claim/run" end),
        (if (.sandbox.excludedCommands | sort) == ((["docker *", "gh *"] + ([$c, $i] | map(. + "/session-launch.sh *", . + "/ledger.sh *", . + "/pr-watch.sh *", . + "/status-board.sh *"))) | sort)
         then empty else "sandbox.excludedCommands is not one spelling per root: \(.sandbox.excludedCommands)" end),
        (if (tostring | contains($v2) or contains($rd) or contains("Bash(bash ") or contains($i1 + "/")) then "a stale version, the // spelling of the clone, a bash spelling or the installed single-slash spelling is left" else empty end),
        (if (.permissions.allow | index(["Bash(ls)"])) and (.permissions.allow[0] == "Bash(ls)") then empty else "the allow rule of the person, Bash(ls) moved or went" end)
      ] | join("; ")' "$SG_F" || echo "the reduction check could not read $SG_F"   # a jq error is never a pass
}
sg_o="$(sg_su "$sg_p" "$sg_cfg" --lanes 2>&1)"
sg_r="$(sg_reduced)"
# SC-001 / FR-004: the 9.3 file → the signature set once per live root, in that root's canonical spelling
[ -z "$sg_r" ] && ok "SC-001: the 9.3-shape file is reduced to 17 signature asks per live root, one spelling each, the person's rules kept" \
  || { bad "SC-001 (FR-004): setup --lanes on the 9.3-shape file: $sg_r — setup said: $(tail -3 <<<"$sg_o")"; sg_fail=1; }
[ "$(jq -c '.permissions.ask | index(["Bash(rm -rf:*)"]) != null' "$SG_F")" = true ] || { bad "SC-001: the person's own ask rule Bash(rm -rf:*) must stay"; sg_fail=1; }
sg_h="$(cksum < "$SG_F")"; sg_o="$(sg_su "$sg_p" "$sg_cfg" --lanes 2>&1)"
{ grep -qF 'unchanged:' <<<"$sg_o" && [ "$(cksum < "$SG_F")" = "$sg_h" ]; } || { bad "FR-004: a second setup run must be a no-op (unchanged:): $sg_o"; sg_fail=1; }
cp "$SG_F" "$sg_base/reduced.json"
sg_fixture; sg_su "$sg_p" "$sg_cfg" --remove >/dev/null 2>&1
jq -e '[.. | strings | select(test("/hooks/(ledger|pr-watch|session-launch|status-board|speckit-helper|run-follow|hefesto-setup)[.]sh"))] | length == 0' "$SG_F" >/dev/null \
  && [ "$(jq -c '.permissions' "$SG_F")" = '{"ask":["Bash(rm -rf:*)"],"allow":["Bash(ls)"]}' ] \
  || { bad "FR-004: --remove must take out every hefesto rule in any spelling and version, keeping the person's: $(jq -c . "$SG_F" | head -c 400)"; sg_fail=1; }
printf '[1,2]\n' > "$SG_F"; sg_su "$sg_p" "$sg_cfg" --lanes >/dev/null 2>&1 && { bad "US3: a settings file that is not a JSON object must be refused"; sg_fail=1; }
[ "$(cat "$SG_F")" = "[1,2]" ] || { bad "US3: a refused setup must write nothing"; sg_fail=1; }
# mutants (Principle 3): the clone back in its // spelling; the bash spelling back → SC-001 red
for sg_m in "s|printf '%s/hooks' \"\$1\"|printf '%s//hooks' \"\$1\"|" \
            "s|printf 'Bash(%s/ledger.sh %s:\\*)\\\\n' \"\$1\" \"\$s\"|printf 'Bash(%s/ledger.sh %s:*)\\\\nBash(bash %s/ledger.sh %s:*)\\\\n' \"\$1\" \"\$s\" \"\$1\" \"\$s\"|"; do
  sg_fixture; sg_su_mut "$sg_m"; sg_su "$sg_p" "$sg_cfg" --lanes >/dev/null 2>&1
  [ -n "$(sg_reduced)" ] || { bad "mutation survived (SC-001): $sg_m — the reduced shape still held"; sg_fail=1; }; sg_su_restore
done

# --- SC-004 / FR-006: every ledger.sh subcommand is classified exactly once, every classified entry exists ------------
# signature-dialogs/FR-006
sg_subs() { # $1 a ledger.sh → its subcommands, one per line: usage text ∪ pre-case dispatches ∪ top-level case arms
  local f="$1" line alt w
  { # (i) the usage text: the first word of each listed form, " | "-separated alternatives split (a flag is no form)
    while IFS= read -r line; do
      line="${line%%   *}"; line="${line# }"; line="${line# }"
      while [ -n "$line" ]; do alt="${line%% | *}"; [ "$alt" = "$line" ] && line="" || line="${line#* | }"
        read -r w rest <<<"$alt"; case "$w" in [a-z]*) ;; *) continue ;; esac
        case "$w" in op|park) printf '%s %s\n' "$w" "${rest%% *}" ;; *) printf '%s\n' "$w" ;; esac
      done
    done < <(sed -n '/^usage() {/,/^EOF$/p' "$f" | grep '^  [a-z]' | grep -v '^  cat ')   # (the heredoc's own cat line)
    # (ii) the dispatches answered before the case (branches, board)
    sed -n '1,/^case "\$SUB" in$/p' "$f" | grep -o '\[ "\$SUB" = [a-z][a-z-]* \]' | sed 's/.*= \([a-z-]*\) \]/\1/'
    # (iii) the top-level arms of the dispatch: exactly two-space indent, between `case "$SUB" in` and `esac` — the
    # read-only `case "$SUB" in dir|…` one-liner and the nested arms (publish's, next's) are not subcommands
    sed -n '/^case "\$SUB" in$/,/^esac$/p' "$f" | sed -n 's/^  \([a-z][a-z|-]*\)).*/\1/p' | tr '|' '\n' \
      | while IFS= read -r w; do case "$w" in op) printf 'op new\nop close\nop drop\n' ;; park) echo 'park --all' ;; *) echo "$w" ;; esac; done
  } | sort -u
}
sg_classified() { printf '%s\n' "${LEDGER_ALLOW[@]}" "${LEDGER_ALLOW_EXACT[@]}" "${LEDGER_SIGN_WHOLE[@]}" "${LEDGER_LAUNCHER[@]}"; }
sg_class_diff() { # $1 a ledger.sh → empty when the lists classify its dispatch exactly (SC-004), else the reason
  local s c d
  s="$(sg_subs "$1")"; c="$(sg_classified | sort)"; d="$(sg_classified | sort | uniq -d)"
  [ -z "$d" ] || echo "classified twice: $(tr '\n' ' ' <<<"$d")"
  [ "$s" = "$(sort -u <<<"$c")" ] || echo "unclassified: $(comm -23 <(echo "$s") <(sort -u <<<"$c") | tr '\n' ' ')— classified but not in the dispatch: $(comm -13 <(echo "$s") <(sort -u <<<"$c") | tr '\n' ' ')"
  for c in "${LEDGER_SIGN_FLAG[@]}"; do
    printf '%s\n' "${LEDGER_ALLOW[@]}" | grep -qx -- "${c% *}" || echo "the flagged signature '$c' names no allowed subcommand"
    grep -qF -- "${c#* }" "$1" || echo "the flag of '$c' is not in $1"
  done
}
sg_s="$(sg_subs "$REPO/hooks/ledger.sh")"
{ grep -qx 'claim' <<<"$sg_s" && grep -qx 'board' <<<"$sg_s" && grep -qx 'branches' <<<"$sg_s" && grep -qx 'op close' <<<"$sg_s" && grep -qx 'park --all' <<<"$sg_s" \
  && ! grep -qx 'tasks-repo' <<<"$sg_s" && ! grep -qx 'plan' <<<"$sg_s" && [ "$(wc -l <<<"$sg_s")" -ge 40 ]; } \
  || { bad "SC-004: the subcommand extractor must find claim, board, branches, op close, park --all — never a nested arm (tasks-repo, plan): $(tr '\n' ' ' <<<"$sg_s")"; sg_fail=1; }
sg_r="$(sg_class_diff "$REPO/hooks/ledger.sh")"
[ -z "$sg_r" ] && ok "SC-004 (FR-006): every ledger.sh subcommand ($(wc -l <<<"$sg_s")) is classified exactly once, and every classified entry exists" \
  || { bad "SC-004 (FR-006): $sg_r"; sg_fail=1; }
# mutants: a new arm, a new pre-case dispatch, a list entry removed → each red
sg_lm="$sg_base/ledger-mut.sh"
sed 's/^  dir) echo "\$DIR" ;;$/  dir) echo "$DIR" ;;\n  zap) echo z ;;/' "$REPO/hooks/ledger.sh" > "$sg_lm"
[ -n "$(sg_class_diff "$sg_lm")" ] || { bad "mutation survived (SC-004): a new case arm 'zap' went unclassified"; sg_fail=1; }
sed 's/^\[ "\$SUB" = branches \]/[ "$SUB" = zop ] \&\& exit 0\n[ "$SUB" = branches ]/' "$REPO/hooks/ledger.sh" > "$sg_lm"
grep -qF '"$SUB" = zop' "$sg_lm" || { bad "SC-004 mutation did not apply (pre-case dispatch)"; sg_fail=1; }
[ -n "$(sg_class_diff "$sg_lm")" ] || { bad "mutation survived (SC-004): a new pre-case dispatch 'zop' went unclassified"; sg_fail=1; }
[ -n "$( LEDGER_ALLOW=("${LEDGER_ALLOW[@]/verdict}"); sg_class_diff "$REPO/hooks/ledger.sh")" ] || { bad "mutation survived (SC-004): verdict removed from LEDGER_ALLOW"; sg_fail=1; }

# --- SC-006 / FR-007: every signature setup asks for is also refused from a lane (is_person_sub) ---------------------
# signature-dialogs/FR-007
sg_person() { # $1 a lane-lib.sh → the signature forms is_person_sub does NOT call a person's decision
  ( # shellcheck source=hooks/lane-lib.sh
    . "$1"; local s
    for s in "${LEDGER_SIGN_WHOLE[@]}"; do read -r -a w <<<"$s"; is_person_sub "${w[@]}" || echo "$s"; done
    for s in "${LEDGER_SIGN_FLAG[@]}"; do is_person_sub "${s% *}" HEF-1 --by A "${s#* }" || echo "$s"; done )
}
sg_r="$(sg_person "$REPO/hooks/lane-lib.sh")"
[ -z "$sg_r" ] && ok "SC-006 (FR-007): every signature form setup asks for is refused from a lane by is_person_sub" \
  || { bad "SC-006 (FR-007): is_person_sub does not cover: $sg_r"; sg_fail=1; }
sed 's/|--rfc)/)/' "$REPO/hooks/lane-lib.sh" > "$sg_base/lane-lib-mut.sh"
grep -qF -- '--body-from-board) return 0' "$sg_base/lane-lib-mut.sh" || { bad "SC-006 mutation did not apply (--rfc)"; sg_fail=1; }
grep -qx 'record --rfc' <<<"$(sg_person "$sg_base/lane-lib-mut.sh")" || { bad "mutation survived (SC-006): --rfc dropped from is_person_sub, yet record --rfc was still covered"; sg_fail=1; }

# --- SC-003 / FR-001 / FR-003: the documented rule grammar over a table of command lines ------------------------------
# signature-dialogs/FR-001 signature-dialogs/FR-002 signature-dialogs/FR-003
# deny → ask → allow; `:*` at the end = the prefix, then a space or nothing; `*` elsewhere = any text (D7,
# code.claude.com/docs/en/permissions). This is the plan's reading of the grammar: the live tier runs the same table
# against Claude Code's own matcher (tests/smoke.sh, SMOKE_LIVE).
sg_rule_match() { # $1 the rule's inside, $2 a command → 0 when it matches
  local p="$1" c="$2" g="" part
  if [ "${p%:\*}" != "$p" ]; then p="${p%:\*}"; [ "$c" = "$p" ] || [ "${c#"$p "}" != "$c" ]; return; fi
  while [ -n "$p" ]; do part="${p%%\**}"; g="$g$(printf '%q' "$part")"; [ "$part" = "$p" ] && break; g="$g*"; p="${p#*\*}"; [ -n "$p" ] || break; done
  eval "[[ \$c == $g ]]"
}
sg_decide() { # $1 a settings file, $2 a command → deny | ask | allow | none
  local k r
  for k in deny ask allow; do
    while IFS= read -r r; do sg_rule_match "$r" "$2" && { echo "$k"; return; }; done < <(jq -r --arg k "$k" '(.permissions[$k] // [])[] | strings | select(startswith("Bash(")) | ltrimstr("Bash(") | rtrimstr(")")' "$1")
  done; echo none
}
sg_table() { # $1 a settings file holding the clone's rules → the lines decided otherwise than the table says
  local h="$REPO/hooks" want cmd got
  while IFS='|' read -r want cmd; do
    got="$(sg_decide "$1" "$h/$cmd")"; [ "$got" = "$want" ] || echo "'$cmd' is $got, not $want"
  done < <(sg_rows)
}
sg_rows() { # the table: <ask|allow|none>|<helper and arguments> — read by sg_table and by the live check below
  cat <<EOF
ask|ledger.sh unblock HEF-1 --by "A" --reviewed-by-human
ask|ledger.sh unblock HEF-1 --merge-sha 0a1b2c3
ask|ledger.sh record HEF-1 --worktree w --body-file f
ask|ledger.sh record HEF-1 --branch b --body-from-board
ask|ledger.sh record HEF-1 --worktree w --rfc
ask|ledger.sh release HEF-1 --by "A" --reviewed-by-human
ask|ledger.sh approve A-1 --sha s --to l --title t --reviewed-by-human --by A
ask|ledger.sh answer HEF-1 --reviewed-by-human --by A
ask|ledger.sh revise HEF-1 --reviewed-by-human --by A
ask|ledger.sh drop HEF-1 --reason-file f
ask|ledger.sh fold HEF-1 --into HEF-2 --reason-file f
ask|ledger.sh supersede HEF-1 --by HEF-2 --reason-file f
ask|ledger.sh reopen HEF-1 --reason-file f
ask|ledger.sh op close OP-1 --outcome-file f
ask|ledger.sh op drop OP-1 --reason-file f
ask|pr-watch.sh reply 12 --body-file f
ask|pr-watch.sh comment 12 --body-file f
allow|ledger.sh record HEF-1 --worktree w --branch b
allow|ledger.sh unblock HEF-1
allow|ledger.sh release HEF-1
allow|ledger.sh advance HEF-1 pr
allow|ledger.sh handoff HEF-1 --pr https://x/pull/1
allow|ledger.sh block HEF-1 --kind ci
allow|ledger.sh verdict HEF-1 --gate verify --verdict PASS --by s
allow|ledger.sh op new --title t
allow|ledger.sh park --all
allow|ledger.sh dir
allow|ledger.sh board
allow|ledger.sh list --active
none|ledger.sh claim HEF-1 --session s --role implement
none|ledger.sh run HEF-1 --role implement --exit 0 --usd 0
EOF
}
sg_r="$(sg_table "$sg_base/reduced.json")"
[ -z "$sg_r" ] && ok "SC-003 (FR-001, FR-003): every signature form asks with its flag anywhere after the id; the mechanics allow; claim/run match no rule" \
  || { bad "SC-003 (FR-001, FR-003): $sg_r"; sg_fail=1; }
jq --arg r "Bash($REPO/hooks/ledger.sh record * --body-file*)" '.permissions.ask -= [$r]' "$sg_base/reduced.json" > "$sg_base/grammar-mut.json"
grep -qF 'body-file' <<<"$(sg_table "$sg_base/grammar-mut.json")" || { bad "mutation survived (SC-003): the record * --body-file* ask dropped, yet the table held"; sg_fail=1; }

# SC-003 live (SMOKE_LIVE=1; tasks T014): the same table against Claude Code's own matcher. The rules are written by
# setup for a stub root beside the repo (trusted) whose ledger.sh and pr-watch.sh only print their arguments, so a
# mechanic changes nothing. In -p a signature (ask) and claim/run (no rule) are denied for want of a dialog; a
# mechanic runs. A red here → the fallback: unblock and record back into LEDGER_SIGN_WHOLE (flag-qualified dialogs
# are not expressible). Then the spelling probe: --plugin-dir <clone> and <clone>/, the hooks path each substitutes.
if [ "${SMOKE_LIVE:-0}" = 1 ] && command -v claude >/dev/null 2>&1; then
  sg_lv="$(mktemp -d "$REPO/.smoke-live.XXXXXX")"; cp -R "$REPO/hooks" "$sg_lv/hooks"; mkdir -p "$sg_lv/cfg"
  for sg_f in ledger.sh pr-watch.sh; do printf '#!/bin/bash\necho "STUB-RAN %s $*"\n' "$sg_f" > "$sg_lv/hooks/$sg_f"; chmod +x "$sg_lv/hooks/$sg_f"; done
  sg_lp="$(sg_project)"
  (cd "$sg_lp" && HOME="$sg_thome" CLAUDE_CONFIG_DIR="$sg_lv/cfg" bash "$sg_lv/hooks/hefesto-setup.sh") >/dev/null 2>&1
  jq '{permissions: {allow: (.permissions.allow // []), ask: (.permissions.ask // [])}, sandbox: {enabled: false}}' "$sg_lp/.claude/settings.local.json" > "$sg_lv/settings.json"
  sg_claude() { (cd "$sg_lp" && HOME="${SMOKE_REAL_HOME:-$HOME}" env -u CLAUDE_CONFIG_DIR -u CLAUDE_CODE_SESSION_ID timeout 300 claude -p "$@" --model haiku --output-format stream-json --verbose 2>&1); }
  sg_live() { # $1 a command → ran | denied | no-call (the model never issued it: the row proves nothing)
    local o; o="$(sg_claude "Run exactly this command with the Bash tool, once, unchanged, then stop: $1" --settings "$sg_lv/settings.json" --permission-mode default)"
    jq -e --arg c "$1" 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "Bash" and .input.command == $c)' <<<"$o" >/dev/null 2>&1 || { echo no-call; return; }
    jq -r 'select(.type == "user") | .message.content[]? | select(.type == "tool_result") | (.content | if type == "array" then map(.text? // "") | join(" ") else tostring end)' <<<"$o" 2>/dev/null | grep -q 'STUB-RAN' && echo ran || echo denied
  }
  sg_lr=""
  while IFS='|' read -r sg_want sg_cmd; do
    sg_got="$(sg_live "$sg_lv/hooks/$sg_cmd")"; printf '       live: %-5s %-7s %s\n' "$sg_want" "$sg_got" "$sg_cmd"
    case "$sg_want:$sg_got" in allow:ran|ask:denied|none:denied) ;; *) sg_lr="$sg_lr '$sg_cmd' ($sg_want → $sg_got)" ;; esac
  done < <(sg_rows)
  [ -z "$sg_lr" ] && ok "SC-003 live: Claude Code's matcher asks for every signature form (flag anywhere after the id), runs the mechanics, gives claim/run no rule" \
    || { bad "SC-003 live (fallback: unblock and record back into LEDGER_SIGN_WHOLE):$sg_lr"; sg_fail=1; }
  for sg_pd in "$REPO" "$REPO/"; do
    sg_o="$(sg_claude "Invoke the skill hefesto:hef.context. Run only its first helper command with the Bash tool, then stop." --plugin-dir "$sg_pd")"
    printf '       spelling probe: --plugin-dir %s → %s\n' "$sg_pd" "$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "Bash") | .input.command' <<<"$sg_o" 2>/dev/null | grep -o '[^ ]*hooks/speckit-helper.sh' | head -1)"
  done
  rm -rf -- "${sg_lv:?}"
fi

# --- FR-005 / US4: --check reads this session's root kind from setup's own roots; installed wins over the clone ------
# signature-dialogs/FR-005 signature-dialogs/FR-004
# The production case of --check run from the installed copy (CLONE is then that path): here $REPO itself is listed as
# an installed copy, after another installed version — so ${roots[0]} is not the clone (the gauge_root mutant).
sg_cfg2="$sg_base/profile2"; sg_profile "$sg_cfg2" "$sg_v3" "$REPO"
sg_p2="$(sg_project)"; SG_F2="$sg_p2/.claude/settings.local.json"
sg_chk() { # $1 project, $2 profile, $3 CLAUDE_PLUGIN_ROOT → setup --check, as the session start runs it
  (cd "$1" && HOME="$sg_thome" CLAUDE_CONFIG_DIR="$2" CLAUDE_PLUGIN_ROOT="$3" bash "${SG_SUM:-$SG_SU}" --check 2>&1)
}
sg_kind_ok() { # → empty when setup wrote the installed spelling for $REPO and the gauge on the clone's path
  jq -r --arg i "$REPO//hooks" --arg c "$REPO/hooks" '[
      (if (.permissions.ask | index(["Bash(\($i)/ledger.sh fold:*)"])) then empty else "no ask under \($i)" end),
      (if ([.. | strings | select(startswith("Bash(" + $c + "/") or startswith($c + "/session-launch"))] | length) == 0 then empty else "a rule under the single-slash \($c)" end),
      (if (.statusLine.command | startswith($c + "/")) then empty else "the status line is \(.statusLine.command), not under \($c)/" end)
    ] | join("; ")' "$SG_F2" || echo "could not read $SG_F2"
}
sg_su "$sg_p2" "$sg_cfg2" >/dev/null 2>&1
sg_r="$(sg_kind_ok)"
[ -z "$sg_r" ] && ok "FR-005: a root that is both the clone and an installed copy keeps the installed spelling (<root>//hooks); the status line stays on the release-stable path" \
  || { bad "FR-005 (kind lookup): $sg_r"; sg_fail=1; }
sg_o="$(sg_chk "$sg_p2" "$sg_cfg2" "$REPO/")"
[ "$(tail -1 <<<"$sg_o")" = "setup: ok" ] || { bad "FR-005: --check from CLAUDE_PLUGIN_ROOT=$REPO/ must pass right after setup: $sg_o"; sg_fail=1; }
sg_o="$(sg_chk "$sg_p2" "$sg_cfg2" /elsewhere/hefesto)" && { bad "FR-005: --check from a root setup never saw must exit 1"; sg_fail=1; }
grep -qF 'the hefesto folder this session runs from (/elsewhere/hefesto) is not one setup trusts' <<<"$sg_o" || { bad "FR-005: the untrusted root must be named: $sg_o"; sg_fail=1; }
cp "$SG_F2" "$sg_base/kind.json"
jq --arg r "Bash($REPO//hooks/ledger.sh fold:*)" '.permissions.ask -= [$r]' "$sg_base/kind.json" > "$SG_F2"
sg_o="$(sg_chk "$sg_p2" "$sg_cfg2" "$REPO/")" && { bad "FR-005: --check must fail when a signature ask is missing under this root's spelling"; sg_fail=1; }
grep -qF 'ledger.sh fold' <<<"$sg_o" || { bad "FR-005: --check must name the missing signature ask: $sg_o"; sg_fail=1; }
# mutants: hooks_of always single-slash; the clone added before the installed roots; gauge_root = ${roots[0]} → red
for sg_m in "s|printf '%s//hooks' \"\$1\"|printf '%s/hooks' \"\$1\"|" \
            '/^add_root "\$CLONE" clone$/d; /^for cfg in "\${CLAUDE_CONFIG_DIR:-}"/i add_root "$CLONE" clone' \
            "s|^gauge_root() {.*|gauge_root() { printf '%s' \"\${roots[0]}\"; }|"; do
  printf '{}\n' > "$SG_F2"; sg_su_mut "$sg_m"; sg_su "$sg_p2" "$sg_cfg2" >/dev/null 2>&1
  [ -n "$(sg_kind_ok)" ] || { bad "mutation survived (FR-005): $sg_m"; sg_fail=1; }; sg_su_restore
done

# --- SC-002 / FR-005 / US4: a mechanics ask rule, in any applying settings file, is the defect --check names ---------
# signature-dialogs/FR-005
cp "$sg_base/kind.json" "$SG_F2"
sg_defect() { # $1 the settings file to inject into, $2 the rule → --check's output; 0 when it exits 1 and names both
  local o; cp "$1" "$sg_base/inj.bak"; jq --arg r "$2" '.permissions.ask = ((.permissions.ask // []) + [$r])' "$sg_base/inj.bak" > "$1"
  o="$(sg_chk "$sg_p2" "$sg_cfg2" "$REPO/")"; local rc=$?; cp "$sg_base/inj.bak" "$1"
  [ "$rc" -ne 0 ] && grep -qF "no ask rule outside the signature set ($2 in $1" <<<"$o"
}
printf '{}\n' > "$sg_cfg2/settings.json"
sg_defect "$SG_F2" "Bash($REPO//hooks/ledger.sh claim:*)" && sg_defect "$sg_cfg2/settings.json" "Bash($REPO//hooks/ledger.sh claim:*)" \
  && sg_defect "$SG_F2" "Bash(bash /old/clone/hooks/ledger.sh advance:*)" \
  && sg_defect "$SG_F2" "Bash($REPO//hooks/ledger.sh record HEF-1 --worktree /w/hooks/x:*)" \
  && ok "SC-002 (FR-005): a mechanics ask (claim:*) in settings.local.json or the profile's settings.json, or under an old clone, makes --check exit 1 naming the rule and its file" \
  || { bad "SC-002 (FR-005): --check must exit 1 naming a mechanics ask rule and its file"; sg_fail=1; }
jq --arg r "Bash($REPO//hooks/ledger.sh approve)" '.permissions.ask += [$r]' "$sg_base/kind.json" > "$SG_F2"
sg_o="$(sg_chk "$sg_p2" "$sg_cfg2" "$REPO/")"
{ [ "$(tail -1 <<<"$sg_o")" = "setup: ok" ] && ! grep -qF 'outside the signature set' <<<"$sg_o"; } \
  || { bad "FR-005: a signature in another form (approve, no :*) must never be called a mechanic: $sg_o"; sg_fail=1; }
cp "$sg_base/kind.json" "$SG_F2"
sg_su_mut 's|done < <(ask_defects "\$sf")|done < <(:)|'
sg_defect "$SG_F2" "Bash($REPO//hooks/ledger.sh claim:*)" && { bad "mutation survived (SC-002): the defect pass removed, yet --check named the mechanics ask"; sg_fail=1; }
sg_su_restore

# --- SC-007 / FR-010: claim and run are the launcher's, in every project — with or without lanes ----------------------
# signature-dialogs/FR-010 signature-dialogs/FR-008 (the launcher's own claim and run pass)
# sg_p2 was set up without --lanes. The launcher calls them with HEFESTO_LAUNCHER=1 and no session id; a session's
# call (its id set, marked or not) and a person's terminal call (neither) are refused, nothing written.
sg_lg() { (cd "$sg_p2" && bash "${SG_LG:-$REPO/hooks/ledger.sh}" "$@"); }
sg_ent() { printf '%s/%s.json\n' "$(sg_lg dir 2>/dev/null)" "$1"; }
sg_lg init SG-1 --kind tasks-repo --ref t#SG-1 >/dev/null 2>&1; sg_lg init SG-2 --kind tasks-repo --ref t#SG-2 >/dev/null 2>&1
sg_lg advance SG-2 implement >/dev/null 2>&1
sg_refused() { # $1 what must be named besides session-launch.sh, then the env and the ledger call → 0 when refused with nothing written
  local also="$1" s o; shift; s="$(cksum < "$(sg_ent SG-1)")"
  o="$(cd "$sg_p2" && env "$@" 2>&1)" && return 1
  grep -qF 'session-launch.sh' <<<"$o" && grep -qF -- "$also" <<<"$o" && [ "$(cksum < "$(sg_ent SG-1)")" = "$s" ]
}
sg_launcher_gate_ok() { # → empty when every non-launcher claim/run is refused and the launcher's passes
  local lg="${SG_LG:-$REPO/hooks/ledger.sh}"
  [ -f "$(sg_ent SG-1)" ] || { echo "no ledger entry SG-1 to claim"; return; }
  sg_refused session-launch -u HEFESTO_LAUNCHER CLAUDE_CODE_SESSION_ID=sid-sg-fake-0001 bash "$lg" claim SG-1 --session s --role implement || echo "a session's claim (fake sid) was not refused"
  sg_refused session-launch CLAUDE_CODE_SESSION_ID=sid-sg-fake-0001 HEFESTO_LAUNCHER=1 bash "$lg" claim SG-1 --session s --role implement || echo "a marked claim with the session id still set was not refused"
  sg_refused session-launch CLAUDE_CODE_SESSION_ID=sid-sg-fake-0001 HEFESTO_LAUNCHER=1 bash "$lg" run SG-1 --role implement --exit 0 --usd 0 || echo "a marked run with the session id still set was not refused"
  sg_refused release -u CLAUDE_CODE_SESSION_ID -u HEFESTO_LAUNCHER bash "$lg" claim SG-1 --session s --role implement || echo "a terminal claim (no id, no marker) was not refused naming release"
  sg_refused release -u CLAUDE_CODE_SESSION_ID -u HEFESTO_LAUNCHER bash "$lg" run SG-1 --role implement --exit 0 --usd 0 || echo "a terminal run (no id, no marker) was not refused"
  (cd "$sg_p2" && launcher bash "$lg" claim SG-1 --session s --role implement) >/dev/null 2>&1 && (cd "$sg_p2" && launcher bash "$lg" run SG-1 --role implement --exit 0 --usd 0) >/dev/null 2>&1 \
    || echo "the launcher's own claim and run (marked, no session id) did not pass"
}
sg_r="$(sg_launcher_gate_ok)"
[ -z "$sg_r" ] && ok "SC-007 (FR-010): claim/run from a session or a terminal are refused naming session-launch.sh (and release), nothing written; the launcher's pass" \
  || { bad "SC-007 (FR-010): $sg_r"; sg_fail=1; }
# FR-010 (plan review round 5): handoff stays a hand command — a lane session's handoff is refused up front, before the
# owner write, so the marked inner `run` never runs for a lane
sg_sid="sid-sg-lane-0001"; mkdir -p "$HOME/.cache/hefesto/sessions"
jq -n '{title: "sg-builder", name: "sg-builder", role: "build", lanes: true, worker: false}' > "$HOME/.cache/hefesto/sessions/$sg_sid.json"
(cd "$sg_p2" && sg_git checkout -q -b feature/sg)
sg_handoff_refused() { # → 0 when a lane session's handoff is refused naming --finish with the entry byte-identical
  local s o; s="$(cksum < "$(sg_ent SG-2)")"
  o="$(cd "$sg_p2" && CLAUDE_CODE_SESSION_ID="$sg_sid" bash "${SG_LG:-$REPO/hooks/ledger.sh}" handoff SG-2 --pr https://x/o/r/pull/7 2>&1)" && return 1
  grep -qF -- '--finish' <<<"$o" && [ "$(cksum < "$(sg_ent SG-2)")" = "$s" ]
}
sg_handoff_refused && ok "FR-010: a lane session's handoff is refused up front naming session-launch.sh --finish; the entry is byte-identical" \
  || { bad "FR-010: a lane session's handoff must be refused naming --finish, with nothing written"; sg_fail=1; }
# mutants on a mirror of the hooks: the launcher_gate call removed; the handoff arm's lanes refusal removed → each red
sg_md="$sg_base/hooks"; mkdir -p "$sg_md"; for sg_f in "$REPO"/hooks/*.sh; do ln -s "$sg_f" "$sg_md/$(basename "$sg_f")"; done
sg_lg_mut() { rm -f "$sg_md/ledger.sh"; sed "$1" "$REPO/hooks/ledger.sh" > "$sg_md/ledger.sh"; cmp -s "$REPO/hooks/ledger.sh" "$sg_md/ledger.sh" && { bad "FR-010 mutation did not apply: $1"; sg_fail=1; }; SG_LG="$sg_md/ledger.sh"; }
sg_lg_mut 's/^launcher_gate$/:/'
[ -n "$(sg_launcher_gate_ok)" ] || { bad "mutation survived (SC-007): the launcher_gate call removed, yet claim/run were still refused"; sg_fail=1; }
sg_lg_mut 's/^    in_lanes_session \&\& die "ledger handoff/    false \&\& die "ledger handoff/'
sg_handoff_refused && { bad "mutation survived (FR-010): the handoff lanes refusal removed, yet the lane's handoff was refused"; sg_fail=1; }
SG_LG=""

# --- FR-007 (amended 2026-11-09): a signature flag spelled other than plain is denied by the lane guard -----------------
# The ask rules match the literal text ` --merge-sha`; a quoted, escaped or tab-separated flag matches none of them and
# the `unblock:*` / `record:*` / `release:*` / `pr-watch.sh:*` allow rules let it through with no dialog. The guard
# (tests/smoke.sh's gd: hook JSON in, decision out) denies it in every lane, the orchestrator included.
# signature-dialogs/FR-007
sg_gd_want() { [ "$(gd "$1" "$2")" = "$3" ] || { bad "FR-007 lane-guard ($1): '$2' must be $3, got $(gd "$1" "$2")"; sg_fail=1; }; }
SG_PW="$REPO/hooks/pr-watch.sh"
sg_gd_want orchestrator "$LGL unblock LT-2 \"--merge-sha\" abc123" deny
sg_gd_want orchestrator "$LGL unblock LT-2 '--reviewed-by-human' --by Ana" deny
sg_gd_want orchestrator "$LGL unblock LT-2"$'\t'"--merge-sha abc123" deny
sg_gd_want orchestrator "$LGL unblock LT-2 --reviewed-by-\"human\" --by Ana" deny
sg_gd_want orchestrator "$LGL record LT-2 \\--rfc" deny
sg_gd_want orchestrator "$LGL release LT-2 --reviewed-by-'human' --by Ana" deny
sg_gd_want orchestrator "$SG_PW \"reply\" 7 --body-file b.md" deny
sg_gd_want orchestrator "$LGL unblock LT-2 --merge-sha abc123" none
sg_gd_want orchestrator "$LGL unblock LT-2 --reviewed-by-human --by \"Ana Lima\"" none
sg_gd_want orchestrator "$LGL record LT-2 --rfc" none
sg_gd_want orchestrator "$LGL show LT-2 \"the --rfc flag pins it\"" none
sg_gd_want orchestrator "$SG_PW reply 7 --body-file b.md" none
sg_gd_want orchestrator "$SG_PW status 7" none
sg_gd_want orchestrator "git commit -m \"--rfc\"" none
# a command that only NAMES a helper is not that helper's command (stage-1 review of T022): no deny
sg_gd_want builder "grep -n -- '--rfc' hooks/ledger.sh" none
sg_gd_want builder "git commit -m \"fix: ledger.sh unblock takes '--merge-sha'\"" none
sg_gd_want builder "echo \"see pr-watch.sh 'reply'\"" none
sg_gd_want builder "$LGL show LT-2" none
# shellcheck disable=SC2154,SC2034  # l3_md and LG_GD belong to tests/smoke.sh's lane-guard part (gd reads LG_GD)
{
  l3_mut lane-guard.sh 's/^sign_spelling_check$/:/'; LG_GD="$l3_md/lane-guard.sh"
  [ "$(gd orchestrator "$LGL unblock LT-2 \"--merge-sha\" abc123")" = deny ] && { bad "mutation survived (FR-007): the signature-spelling check removed, yet the quoted --merge-sha was denied"; sg_fail=1; }
  l3_restore lane-guard.sh; LG_GD=""
}

# --- FR-009 / US5: the docs say one spelling, the signature set, launcher-only claim/run, the --check defect -----------
# signature-dialogs/FR-009
sg_docs() { # $1 the repo root to read → the doc statements missing
  grep -qF 'A dialog only where a person signs' "$1/docs/install.md" && grep -qF 'no ask rule outside the signature set' "$1/docs/install.md" \
    && grep -qF 'One spelling per root' "$1/docs/install.md" || echo "docs/install.md §2"
  grep -qF '<installPath>/hooks/speckit-helper.sh' "$1/SETUP.md" && echo "SETUP.md still prescribes the single-slash installed spelling"
  grep -qF 'which only the launcher may call' "$1/docs/hooks.md" && grep -qF '`claim` and `run` are the launcher'"'"'s alone' "$1/docs/hooks.md" || echo "docs/hooks.md (the hefesto-setup.sh and ledger.sh rows)"
  grep -qE 'ledger\.sh claim HEF-|`ledger\.sh run`, then' "$1/README.md" "$1/docs/case-study-sdlc.md" && echo "a by-hand ledger.sh claim/run in README.md or docs/case-study-sdlc.md"
  grep -qF 'ask rule on a hefesto helper outside the signature set' "$1/hooks/hefesto-setup.sh" || echo "the hefesto-setup.sh header"
}
sg_r="$(sg_docs "$REPO")"
[ -z "$sg_r" ] && ok "FR-009: install.md, hooks.md, SETUP.md, README.md, the case study and the setup header say one spelling, the signature set, launcher-only claim/run and the --check defect" \
  || { bad "FR-009: $(tr '\n' ';' <<<"$sg_r")"; sg_fail=1; }
mkdir -p "$sg_base/docmut/docs" "$sg_base/docmut/hooks"; cp "$REPO"/docs/{install,hooks,case-study-sdlc}.md "$sg_base/docmut/docs/"; cp "$REPO/SETUP.md" "$REPO/README.md" "$sg_base/docmut/"; cp "$SG_SU" "$sg_base/docmut/hooks/"
printf '      "Bash(<installPath>/hooks/speckit-helper.sh:*)"\n' >> "$sg_base/docmut/SETUP.md"
[ -n "$(sg_docs "$sg_base/docmut")" ] || { bad "mutation survived (FR-009): the single-slash installed rule back in SETUP.md"; sg_fail=1; }

rm -rf -- "${sg_base:?}" "${SG_SUM_FILE:?}"
[ "$sg_fail" -eq 0 ] && ok "signature dialogs: every check of part 11 held (HEF-27)"
