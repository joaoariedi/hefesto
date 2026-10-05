#!/bin/bash
# board-lib.sh — the board resolution (external-board FR-001), SOURCED by ledger.sh; never run on its own.
# Split out of ledger.sh to keep it under the 500-code-line limit (quality gate 2026-10-05). It expects the
# caller's `die` and, for the arms, its BCTX and DIR globals. One place answers which board this repo reads;
# status-board.sh, session-launch.sh and session-start-context.sh ask `ledger.sh board`, never this file.
# Zero-install: bash, jq, git (constitution 4).

project_config() { # the board config the launcher and the board read: <toplevel>/.claude/project-status.json
  # external-board FR-001: an external board's config lives in the board repo, resolved once by board_ctx.
  if [ -n "${BCTX:-}" ] && [ "$(jq -r .mode <<<"$BCTX")" = external ]; then jq -r .config <<<"$BCTX"; return 0; fi
  local top; top=$(git rev-parse --show-toplevel 2>/dev/null) || top="$PWD"
  [ -f "$top/.claude/project-status.json" ] && echo "$top/.claude/project-status.json"
}
main_top() { # the MAIN worktree's top. fxcube ignores .claude/ globally, so its pointer file is untracked and
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
  local out='{}' name p abs
  jq -e '.repos | type == "object" and length > 0 and all(.[]; type == "string" and length > 0)' "$2" >/dev/null 2>&1 \
    || die "ledger board: .repos in $2 must be a non-empty object of name → path, e.g. {\"ops\": \"../operations_api\"} (got $(jq -c .repos "$2" 2>/dev/null))"
  while IFS=$'\t' read -r name p; do
    [[ "$name" =~ ^[a-z0-9_-]+$ ]] || die "ledger board: repo name '$name' in $2 must match [a-z0-9_-]+"
    case "$p" in /*) abs="$p" ;; *) abs="$1/$p" ;; esac
    abs=$(cd "$abs" 2>/dev/null && pwd -P) || die "ledger board: repos.$name '$p' in $2 is not a directory (resolved against $1)"
    out=$(jq -c --arg n "$name" --arg p "$abs" '. + {($n): $p}' <<<"$out")
  done < <(jq -r '.repos | to_entries[] | "\(.key)\t\(.value)"' "$2")
  echo "$out"
}
board_top_check() { # $1 board top → the board config path, validated (exists, parses, no chained pointer, repos)
  local c="$1/.claude/project-status.json"
  [ -f "$c" ] || die "ledger board: no board config at $c — the board path must hold .claude/project-status.json with repos"
  jq empty "$c" 2>/dev/null || die "ledger board: the board config $c is not valid JSON (jq . $c shows the error)"
  jq -e '.board == null' "$c" >/dev/null || die "ledger board: the board config $c has a board pointer of its own ($(jq -c .board "$c")) — pointers do not chain; point at the board repo directly"
  echo "$c"
}
inrepo_ledger_dir() { # today's location, computed without creating it (the board arm is side-effect free)
  if [ -n "${HEFESTO_LEDGER_DIR:-}" ]; then echo "$HEFESTO_LEDGER_DIR"; return; fi
  local common; common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { [ -d "$PWD/.git" ] && common="$PWD/.git"; } || return 0
  echo "$common/hefesto/ledger"
}
board_inrepo_json() { # $1 top → the in-repo answer: today's config and ledger dir, nothing created
  local c=""; [ -f "$1/.claude/project-status.json" ] && c="$1/.claude/project-status.json"
  jq -nc --arg t "$1" --arg c "$c" --arg l "$(inrepo_ledger_dir)" '{mode: "in-repo", board_top: $t, config: (if $c == "" then null else $c end), ledger_dir: (if $l == "" then null else $l end), repos: null, repo: null}'
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
  ldir="${HEFESTO_LEDGER_DIR:-$common/hefesto/ledger}"
  [ -n "$2" ] && me=$(cd "$2" && pwd -P)
  jq -nc --arg t "$1" --arg c "$bcfg" --arg l "$ldir" --argjson r "$repos" --arg me "$me" \
    '{mode: "external", board_top: $t, config: $c, ledger_dir: $l, repos: $r, repo: ([$r | to_entries[] | select(.value == $me) | .key][0] // null)}'
}
board_ctx() { # → {"mode","board_top","config","ledger_dir","repos","repo"} as one JSON line, or die naming the field
  local top main role btop
  if top=$(git rev-parse --show-toplevel 2>/dev/null); then main=$(main_top) || main="$top"; else top="$PWD"; main=""; fi
  if [ -n "${HEFESTO_BOARD_TOP:-}" ]; then
    btop=$(cd "$HEFESTO_BOARD_TOP" 2>/dev/null && pwd -P) || die "ledger board: HEFESTO_BOARD_TOP '$HEFESTO_BOARD_TOP' is not a directory"
  else
    role=$(cfg_role "${main:-$top}/.claude/project-status.json") || exit 1
    [ -n "$role" ] || { board_inrepo_json "$top"; return 0; }
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
