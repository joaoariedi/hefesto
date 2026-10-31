#!/bin/bash
# board-lib.sh — the board resolution (external-board FR-001), SOURCED by ledger.sh; never run on its own.
# Split out of ledger.sh to keep it under the 500-code-line limit (quality gate 2026-10-05). It expects the
# caller's `die` and, for the arms, its BCTX and DIR globals. One place answers which board this repo reads;
# status-board.sh, session-launch.sh and session-start-context.sh ask `ledger.sh board`, never this file.
# Zero-install: bash, jq, git (constitution 4).

project_config() { # the board config the launcher and the board read: <toplevel>/.claude/project-status.json
  # external-board FR-001: an external board's config lives in the board repo, resolved once by board_ctx.
  if [ -n "${BCTX:-}" ] && [ "$(jq -r .mode <<<"$BCTX")" = external ]; then jq -r .config <<<"$BCTX"; return 0; fi
  # The MAIN checkout's file, never a linked worktree's: each worktree carries its own committed copy, as old as the
  # branch, and a lane in one read `lane_mode: worker` after the person had switched to interactive (#160).
  local top; top=$(main_top 2>/dev/null) || top=$(git rev-parse --show-toplevel 2>/dev/null) || top="$PWD"
  [ -f "$top/.claude/project-status.json" ] && echo "$top/.claude/project-status.json"
}
main_top() { # the MAIN worktree's top. Where .claude/ is ignored globally, the pointer file is untracked and
  # exists only there — a linked worktree has none. Assumes a standard .git directory (submodules and
  # --separate-git-dir are out of scope, docs/install.md §7 step 13).
  local c; c=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && [ -n "$c" ] || return 1
  dirname "$c"
}
repo_config() { # the CURRENT repo's own config (its .branches, HEF-15): this worktree's file when it exists — a
  # feature branch that edits its tracked .branches reads its own — else the main worktree's (an untracked file)
  local top main; top=$(git rev-parse --show-toplevel 2>/dev/null) || top="$PWD"
  [ -f "$top/.claude/project-status.json" ] && { echo "$top/.claude/project-status.json"; return 0; }
  main=$(main_top) || return 1
  [ -f "$main/.claude/project-status.json" ] && echo "$main/.claude/project-status.json"
}

# --- the board (external-board FR-001): ONE place resolves which board this repo reads ---------------
# A code repo names its board with `board` (a path relative to ITS top, or absolute); the board names the
# repos it feeds with `repos`. HEFESTO_BOARD_TOP (exported by the launcher to every child) overrides.
cfg_role() { # $1 config → "pointer\t<path>", "board", or nothing (in-repo); dies naming the file
  local f="$1" k
  [ -f "$f" ] || return 0
  if ! jq empty "$f" 2>/dev/null; then
    # An unparseable file that names board or repos cannot be told from an external one, so it dies. Any
    # other stays in-repo, where today's checks name it (branches, status-board's [MISSING] line).
    grep -qE '"(board|repos)"[[:space:]]*:' "$f" && die "ledger board: $f is not valid JSON (jq . $f shows the error) — it names board or repos, so the board cannot be resolved"
    return 0
  fi
  k=$(jq -r 'if type != "object" then "" elif .board != null and .repos != null then "both" elif .board != null then "pointer" elif .repos != null then "board" else "" end' "$f")
  case "$k" in
    both)    die "ledger board: $f declares both board and repos — a code repo points at its board with board, only the board config lists repos" ;;
    pointer) jq -e '.board | type == "string" and length > 0' "$f" >/dev/null || die "ledger board: .board in $f must be a path string like \"../tasks\" (got $(jq -c .board "$f"))"
             printf 'pointer\t%s\n' "$(jq -r .board "$f")" ;;
    board)   echo board ;;
  esac
}
board_repos() { # $1 board top, $2 board config → {"name": "/abs/path", …}, or die naming the field
  # lanes-parity US6 (FR-012): a value is "<path>" or {path, branches}; anything else dies naming the repo and the
  # file. The map stays name → path (cd_entry_repo, session-launch); board_repo_branches reads a block from $2.
  local out='{}' name p abs bad
  jq -e '.repos | type == "object" and length > 0' "$2" >/dev/null 2>&1 \
    || die "ledger board: .repos in $2 must be a non-empty object of name → path (or {path, branches}), e.g. {\"ops\": \"../api_service\"} (got $(jq -c .repos "$2" 2>/dev/null))"
  bad=$(jq -r '.repos | to_entries[] | select(.value | if type == "string" then length == 0
      elif type == "object" then ((.path | type) != "string" or (.path | length) == 0 or ((keys - ["path", "branches"]) | length) > 0)
      else true end) | .key' "$2" | head -1)
  [ -z "$bad" ] || die "ledger board: repos.$bad in $2 must be a path string or {\"path\": \"../repo\", \"branches\": {…}} with no other key (got $(jq -c --arg n "$bad" '.repos[$n]' "$2"))"
  while IFS=$'\t' read -r name p; do
    [[ "$name" =~ ^[a-z0-9_-]+$ ]] || die "ledger board: repo name '$name' in $2 must match [a-z0-9_-]+"
    case "$p" in /*) abs="$p" ;; *) abs="$1/$p" ;; esac
    abs=$(cd "$abs" 2>/dev/null && pwd -P) || die "ledger board: repos.$name '$p' in $2 is not a directory (resolved against $1)"
    out=$(jq -c --arg n "$name" --arg p "$abs" '. + {($n): $p}' <<<"$out")
  done < <(jq -r '.repos | to_entries[] | "\(.key)\t\(.value | if type == "object" then .path else . end)"' "$2")
  echo "$out"
}
board_top_check() { # $1 board top → the board config path, validated (exists, parses, no chained pointer, repos)
  local c="$1/.claude/project-status.json"
  [ -f "$c" ] || die "ledger board: no board config at $c — the board path must hold .claude/project-status.json with repos"
  jq empty "$c" 2>/dev/null || die "ledger board: the board config $c is not valid JSON (jq . $c shows the error)"
  jq -e '.board == null' "$c" >/dev/null || die "ledger board: the board config $c has a board pointer of its own ($(jq -c .board "$c")) — pointers do not chain; point at the board repo directly"
  echo "$c"
}
# lanes-interactive (9.0, plan Revision 2): the ledger lives in $HOME/.cache/hefesto/ledger/<key>, beside the
# approval store, outside every sandbox's write set — every writer (ledger.sh, the launcher, the hooks) runs
# unsandboxed. Inside the project a lane could rename the ledger folder and rebuild a forged one (plan review
# round 2). XDG_CACHE_HOME is deliberately NOT honoured: a worker's sandbox may write its own XDG cache.
# <key> is one function of the board's git common dir, so a worktree, a symlinked cwd and the trusted root agree.
hef_sha256() { { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-64; }   # stdin → 64 hex (GNU or BSD)
ledger_home() { printf '%s\n' "$HOME/.cache/hefesto/ledger"; }
ledger_key() { # $1 git common dir → 32 hex, or fail
  local p; p=$(cd -P "$1" 2>/dev/null && pwd -P) || return 1
  printf '%s' "$p" | hef_sha256 | cut -c1-32
}
ledger_override() { [ -n "${HEFESTO_LEDGER_DIR:-}" ] && [ -z "${HEFESTO_TRUSTED_TOP:-}" ]; }   # tests only: never in a set-up project
inrepo_common() { # the in-repo board's git common dir, or nothing
  local c; c=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { [ -d "$PWD/.git" ] && c="$PWD/.git"; } || return 0
  printf '%s\n' "$c"
}
ledger_of_common() { # $1 git common dir → the ledger folder (computed, never created)
  if ledger_override; then printf '%s\n' "$HEFESTO_LEDGER_DIR"; return; fi
  local k; k=$(ledger_key "$1") || return 1; printf '%s\n' "$(ledger_home)/$k"
}
board_inrepo_json() { # $1 top → the in-repo answer: the config and the ledger dir, nothing created
  local c="" g l=""; [ -f "$1/.claude/project-status.json" ] && c="$1/.claude/project-status.json"
  g=$(inrepo_common); [ -n "$g" ] && l=$(ledger_of_common "$g")
  jq -nc --arg t "$1" --arg c "$c" --arg l "$l" --arg g "$g" '{mode: "in-repo", board_top: $t, config: (if $c == "" then null else $c end), ledger_dir: (if $l == "" then null else $l end), git_common: (if $g == "" then null else $g end), repos: null, repo: null}'
}
board_top_of() { # $1 role (board | pointer<TAB>path), $2 top, $3 main → the board's top (physical path), or die
  local ptr
  if [ "$1" = board ]; then
    [ -n "$3" ] && cd "$3" 2>/dev/null && pwd -P && return 0
    die "ledger board: external board mode needs git (the board repo's git dir holds the ledger) — run it inside the repository"
  fi
  [ -n "$3" ] || die "ledger board: $2/.claude/project-status.json points at a board, and external board mode needs git — run it inside the repository with git available"
  ptr="${1#pointer$'\t'}"
  (cd "$3" && cd "$ptr" 2>/dev/null && pwd -P) || die "ledger board: .board '$ptr' in $3/.claude/project-status.json is not a directory (resolved against $3)"
}
board_external_json() { # $1 board top, $2 main worktree top (or "") → the external answer, or die naming the field
  local bcfg repos common ldir me=""
  bcfg=$(board_top_check "$1") || exit 1
  repos=$(board_repos "$1" "$bcfg") || exit 1
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || die "ledger board: the board $1 is not a git repository (or git is unavailable) — the central ledger lives in its git dir"
  ldir=$(ledger_of_common "$common") || die "ledger board: cannot resolve the board's git dir $common"
  [ -n "$2" ] && me=$(cd "$2" && pwd -P)
  jq -nc --arg t "$1" --arg c "$bcfg" --arg l "$ldir" --arg g "$common" --argjson r "$repos" --arg me "$me" \
    '{mode: "external", board_top: $t, config: $c, ledger_dir: $l, git_common: $g, repos: $r, repo: ([$r | to_entries[] | select(.value == $me) | .key][0] // null)}'
}
board_ctx() { # → {"mode","board_top","config","ledger_dir","repos","repo"} as one JSON line, or die naming the field
  local top main role btop
  if top=$(git rev-parse --show-toplevel 2>/dev/null); then main=$(main_top) || main="$top"; else top="$PWD"; main=""; fi
  if [ -n "${HEFESTO_BOARD_TOP:-}" ]; then
    btop=$(cd "$HEFESTO_BOARD_TOP" 2>/dev/null && pwd -P) || die "ledger board: HEFESTO_BOARD_TOP '$HEFESTO_BOARD_TOP' is not a directory"
  else
    role=$(cfg_role "${main:-$top}/.claude/project-status.json") || exit 1
    [ -n "$role" ] || { board_inrepo_json "${main:-$top}"; return 0; }   # the main checkout's config and board (#160)
    btop=$(board_top_of "$role" "$top" "$main") || exit 1
  fi
  board_external_json "$btop" "$main"
}
is_external() { [ "$(jq -r .mode <<<"$BCTX")" = external ]; }
repo_names() { jq -r '.repos // {} | keys_unsorted | join(", ")' <<<"$BCTX"; }
cd_entry_repo() { # $1 entry JSON: git checks for an entry run in ITS repo (external), wherever the caller stands
  local r p; r=$(jq -r '.repo // empty' <<<"$1"); [ -n "$r" ] || return 0
  p=$(jq -r --arg r "$r" '.repos[$r] // empty' <<<"$BCTX")
  [ -n "$p" ] || die "ledger: the entry records repo '$r', which the board does not feed ($(repo_names))"
  DIR=$(cd "$DIR" && pwd -P) || die "ledger: cannot resolve $DIR"   # writes stay put after the cd
  cd "$p" || die "ledger: cannot enter the entry's repo $p"
}

# --- branch models (lanes-parity US6: FR-012, FR-013, NR-005; plan Sketch 5, note 21) ----------------------------
# ONE resolver for every consumer: the repo file's .branches first, then the board's repos.<name>.branches, then the
# default. A line is "<source>␟<label for errors>␟<block JSON>" (␟ = \x1f: an IFS tab would merge empty fields).
BR_SEP=$'\x1f'
board_repo_branches() { # → "<name>␟<board config>␟<block>" for the repo we stand in NOW, or rc 1 (none)
  # Called after cd_entry_repo, so it matches the current main top (pwd -P) against $BCTX.repos — never $BCTX.repo,
  # which is the CALLER's repo, computed where board_ctx ran (plan Revision 4 #1).
  [ -n "${BCTX:-}" ] && is_external || return 1
  local top name cfg
  top=$(main_top) || top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  top=$(cd "$top" 2>/dev/null && pwd -P) || return 1
  name=$(jq -r --arg t "$top" '[.repos // {} | to_entries[] | select(.value == $t) | .key][0] // empty' <<<"$BCTX")
  cfg=$(jq -r .config <<<"$BCTX"); [ -n "$name" ] || return 1
  jq -e --arg n "$name" '.repos[$n] | type == "object" and .branches != null' "$cfg" >/dev/null 2>&1 || return 1
  printf '%s%s%s%s%s\n' "$name" "$BR_SEP" "$cfg" "$BR_SEP" "$(jq -c --arg n "$name" '.repos[$n].branches' "$cfg")"
}
branches_block() { # → a branch-model line; rc 0 declared (repo file or board), 1 none (default), 2 the repo file is not JSON
  local c b r
  c=$(repo_config) || c=""   # the same file branches_model reads — never the board config (external-board)
  if [ -n "$c" ]; then
    # A config that does not PARSE is malformed, never "unconfigured" (code review B1): without this check the
    # read below falls through to the defaults — dropping every protected branch on a typo.
    jq empty "$c" 2>/dev/null || { echo "ledger branches: $c is not valid JSON" >&2; return 2; }
    b=$(jq -c 'if type == "object" then .branches else null end' "$c" 2>/dev/null) || b=null
    [ "${b:-null}" = null ] || { printf 'repo file%s%s%s%s\n' "$BR_SEP" "$c" "$BR_SEP" "$b"; return 0; }
  fi
  if r=$(board_repo_branches); then
    IFS="$BR_SEP" read -r c b <<<"${r#*"$BR_SEP"}"
    printf 'board%srepos.%s in %s%s%s\n' "$BR_SEP" "${r%%"$BR_SEP"*}" "$c" "$BR_SEP" "$b"; return 0
  fi
  printf 'default%s<no branches block>%snull\n' "$BR_SEP" "$BR_SEP"; return 1
}
branches_cli() { # `ledger.sh branches [--configured] [--repo <name>]` — answered before ledger_dir: ledger-free
  # --configured: 0 declared (repo file or board), 1 none, 2 invalid (the file, the block) or an unresolvable board.
  local conf=0 name="" p blk rc out
  while [ $# -gt 0 ]; do case "$1" in
    --configured) conf=1 ;;
    --repo) name="${2:-}"; [ -n "$name" ] || { echo "ledger branches: --repo needs a repo name" >&2; return 2; }; shift ;;
    *) echo "usage: ledger.sh branches [--configured] [--repo <name>]" >&2; return 2 ;;
  esac; shift; done
  BCTX=$(board_ctx) || return 2   # cannot resolve the board: rc 2 (loud), never rc 1 = "unconfigured" (NR-005)
  if [ -n "$name" ]; then
    is_external || { echo "ledger branches --repo $name: this board is in-repo — --repo names a repo an external board feeds" >&2; return 2; }
    p=$(jq -r --arg n "$name" '.repos[$n] // empty' <<<"$BCTX")
    if [ -z "$p" ]; then blk="default${BR_SEP}<no branches block>${BR_SEP}null"; rc=1   # missing from the map: says default
    else cd "$p" || { echo "ledger branches: cannot enter repos.$name ($p)" >&2; return 2; }; fi
  fi
  [ -n "${blk:-}" ] || { blk=$(branches_block); rc=$?; }
  [ "$rc" -ne 2 ] || return 2
  out=$(branches_model "$blk") || { [ "$conf" = 1 ] && return 2; return 1; }
  [ "$conf" = 1 ] && return "$rc"
  echo "$out"
}

# The move from <git common dir>/hefesto/ledger (hefesto ≤ 8) to ledger_home, once, by the first call that can
# write there (plan review round 3, condition 2): locked, copied to a partial folder, counted, renamed into
# place; refused while an old lease is live (an 8.x launcher still renews it); the old folder is kept, renamed.
SETUP_HINT="run once, in a terminal in the project's main folder: bash \$HOME/.claude-framework/hooks/hefesto-setup.sh (or the copy in your profile's plugin folder) — it lets ledger.sh write there — then reopen the session"
ledger_settle() { # $1 the ledger folder, $2 the git common dir (or "") → 0 when $1 may be used; migrates once
  local new="$1" old moved lock part i live n1 n2
  [ -n "$2" ] || return 0; ledger_override && return 0
  old="$2/hefesto/ledger"; moved="$2/hefesto/MOVED"
  if [ -f "$moved" ] && [ -d "$old" ]; then
    die "ledger: $old reappeared after the ledger moved to $(head -1 "$moved") — an older hefesto (a launcher still running, or a profile not updated) wrote it. Stop it, update every profile, copy any entry in $old that $new lacks, then remove $old"
  fi
  [ -d "$new" ] && return 0
  [ -d "$old" ] || return 0                       # a fresh project: the first write creates $new
  mkdir -p "$(dirname "$new")" 2>/dev/null && [ -w "$(dirname "$new")" ] \
    || die "ledger: hefesto 9 keeps the ledger in $new and this shell cannot write there (it runs inside a sandbox), so the ledger in $old has not moved yet — $SETUP_HINT"
  live=$(find "$old" -name '*.lease' -mmin -5 2>/dev/null | head -1)
  [ -z "$live" ] || die "ledger: cannot move the ledger while a run is going ($(basename "$live" .lease) renewed its lease in the last 5 minutes) — wait for it to finish, then run the command again"
  lock="$new.lock"; i=0
  until mkdir "$lock" 2>/dev/null; do
    [ -d "$new" ] && return 0                     # another call finished the move meanwhile
    i=$((i + 1)); [ "$i" -le 20 ] || die "ledger: another call is moving the ledger to $new (lock $lock) — run again in a moment; if no hefesto command is running, remove $lock"
    sleep 0.5
  done
  [ -d "$new" ] && { rmdir "$lock"; return 0; }
  part="$new.partial-$$"
  if cp -Rp "$old" "$part" 2>/dev/null && n1=$(find "$old" -type f | wc -l) && n2=$(find "$part" -type f | wc -l) && [ "$n1" = "$n2" ] && mv "$part" "$new"; then
    printf '%s\n' "$new" > "$moved" && mv "$old" "$old.moved-$(date +%Y%m%d%H%M%S)" \
      || { rmdir "$lock"; die "ledger: the ledger was copied to $new but $old could not be marked as moved — rename $old yourself, then run the command again"; }
    rmdir "$lock"
    echo "ledger: moved the ledger ($(echo $n1) files) from $old to $new; the old folder is kept beside it, renamed" >&2
  else
    rm -rf -- "${part:?}"; rmdir "$lock"
    die "ledger: could not copy $old to $new — nothing was changed; fix the reason (disk space, permissions) and run the command again"
  fi
}
