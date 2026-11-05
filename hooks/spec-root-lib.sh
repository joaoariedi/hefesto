# shellcheck shell=bash
#
# spec-root-lib.sh — a .specify/ per app folder in one git repository (monorepo-spec-roots, #172).
#
# SOURCED, never run: by speckit-helper.sh, the four spec guards, ledger.sh and session-launch.sh. It holds no
# state and calls no other hefesto file, so a guard can source it without board-lib.sh.
#
# A spec root is a folder holding .specify/. It is FOUND the way git finds .git: the nearest ancestor of a path
# that holds one, never above the repository top. An app is a NAMED spec root, declared by the code repository in
# its own .claude/project-status.json: "spec_roots": {"backend": "backend", "web": "apps/web"}. Every function
# that reads that config takes the repository top as $1, so the ledger, the launcher and the helper agree.

# spec_root_find <path> → the folder holding .specify/ nearest to <path> (a file or folder, which may not exist
# yet); the nearest existing folder of <path> when there is none up to the top. Example:
#   spec_root_find "$PWD/backend/internal/store"   # → /repo/backend
spec_root_find() {
  local d="$1" top start real
  [ -n "$d" ] || d="$PWD"
  while [ ! -d "$d" ]; do d="$(dirname "$d")"; done
  d="$(cd "$d" && pwd -P)" || return 1
  top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" && top="$(cd "$top" && pwd -P)" || top="$d"
  start="$d"
  while :; do
    if [ -d "$d/.specify" ]; then
      # FR-019: a .specify that resolves outside the top (a link to another repository) is not this one's
      real="$(cd "$d/.specify" && pwd -P)"
      [ "${real#"$top/"}" = "$real" ] || { printf '%s\n' "$d"; return 0; }
    fi
    # FR-017: never above the top (a home-folder .specify/). The check above already refuses any .specify outside
    # the top, so this bound only ends the walk early; it is kept so a deep tree is not walked to /.
    { [ "$d" = "$top" ] || [ "$d" = / ]; } && break
    d="$(dirname "$d")"
  done
  printf '%s\n' "$start"
}

# The code repository's config: its own file in this checkout, else the main worktree's (a linked worktree of a
# repository that ignores .claude/, #160) — the rule repo_config in board-lib.sh follows, copied here because the
# guards and the helper do not source board-lib.sh.
spec_roots_config() { # $1 repo top → the config path; nothing when neither file exists
  local c main
  [ -f "$1/.claude/project-status.json" ] && { printf '%s\n' "$1/.claude/project-status.json"; return 0; }
  c="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
  case "$c" in */.git) main="${c%/.git}" ;; *) return 0 ;; esac
  [ -f "$main/.claude/project-status.json" ] && printf '%s\n' "$main/.claude/project-status.json"
  return 0
}

# spec_roots_json <repo top> → the validated spec_roots as compact JSON ({} when undeclared); exit 1 naming the
# bad entry and the shape (FR-006). A name is `backend`; a folder is a plain relative path, never `.`, `..`,
# `.claude` or under it.
spec_roots_json() {
  local cfg bad
  # an empty top would make git -C "" read the CWD's config (on an external board, the board's): refused (code review)
  [ -n "$1" ] || { echo "spec_roots: no repository top to read spec_roots from" >&2; return 1; }
  cfg="$(spec_roots_config "$1")"; [ -n "$cfg" ] || { echo '{}'; return 0; }
  jq -e '(.spec_roots // {}) | type == "object"' "$cfg" >/dev/null 2>&1 \
    || { echo "spec_roots in $cfg must be an object like {\"backend\": \"backend\"}" >&2; return 1; }
  bad="$(jq -r '(.spec_roots // {}) | to_entries[]
    | select((.key | test("^[a-z0-9][a-z0-9-]{0,31}$") | not)
      or (.value | type) != "string"
      or (.value | test("^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$") | not)
      or (.value | split("/") | any(. == "." or . == ".."))
      or (.value | . == ".claude" or startswith(".claude/")))
    | "\(.key)=\(.value | tostring)"' "$cfg" | head -1 | tr -cd 'a-zA-Z0-9._/=-' | head -c 80)"
  [ -z "$bad" ] || { echo "spec_roots in $cfg: bad entry '$bad' — a name like backend (a-z, 0-9, -; at most 32) and a relative folder like apps/web (no '.', '..' or .claude)" >&2; return 1; }
  jq -c '.spec_roots // {}' "$cfg"
}

spec_root_names() { # $1 repo top → the declared names, space-separated (for messages and forms)
  local j; j="$(spec_roots_json "$1")" || return 1
  jq -r 'keys | join(" ")' <<<"$j"
}

spec_root_folder() { # $1 repo top, $2 name → the app's folder (relative to the top); exit 1 naming the declared ones
  local j f; j="$(spec_roots_json "$1")" || return 1
  f="$(jq -r --arg n "$2" '.[$n] // empty' <<<"$j")"
  [ -n "$f" ] || { echo "app '$(printf '%s' "$2" | tr -cd 'a-zA-Z0-9._-' | head -c 40)' is not declared in spec_roots (declared: $(jq -r 'keys | join(", ")' <<<"$j" | sed 's/^$/none/'))" >&2; return 1; }
  printf '%s\n' "$f"
}

spec_root_label() { # $1 a spec root folder → its declared app name, else its basename (the constitution heading)
  local top rel j n
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" && top="$(cd "$top" && pwd -P)" || { basename "$1"; return 0; }
  rel="${1#"$top"/}"
  j="$(spec_roots_json "$top")" || j='{}'   # a bad entry is named on stderr; the heading falls back to the folder
  n="$(jq -r --arg f "$rel" 'to_entries[] | select(.value == $f) | .key' <<<"$j" | head -1)"
  printf '%s\n' "${n:-$(basename "$1")}"
}

# spec_root_owner <repo top> <spec_dir> → the app owning a recorded spec_dir, `.` for the top: the LONGEST declared
# folder F that the relative spec_dir starts with F/ (apps/web, and backend/api over backend). An entry planned
# before spec_roots existed keeps working without a form (the migration rule; plan review round 4).
spec_root_owner() {
  local j; j="$(spec_roots_json "$1")" || return 1
  { [ -z "$2" ] || [ "${2#/}" != "$2" ]; } && { echo .; return 0; }   # absolute (9.2.0) or none: the top
  jq -r --arg s "$2" '[to_entries[] | select(.value as $v | $s | startswith($v + "/"))] | sort_by(.value | length) | last | .key // "."' <<<"$j"
}

# spec_dir_abs <entry JSON> [repo top] → the entry's spec folder as an absolute path, or nothing. A relative
# spec_dir is relative to the entry's worktree (FR-010); an absolute one from a 9.2.0 entry is used as is. A
# relative one recorded by hand on an entry with no worktree is the repository top's, as 9.2.0 read it from there;
# with no top given it resolves to nothing — never to /<path>.
spec_dir_abs() {
  jq -r --arg top "${2:-}" 'if (.spec_dir // "") == "" then empty elif (.spec_dir | startswith("/")) then .spec_dir
         elif (.worktree // "") != "" then .worktree + "/" + .spec_dir elif $top != "" then $top + "/" + .spec_dir else empty end' <<<"$1"
}

# The item's app (FR-008): an `app:` line, parsed like the rfc: line (status-board.sh rfc_lines). Item text is
# untrusted, so only the shape is checked here; a declared-name check needs the code repository's config, which
# the ledger and the launcher have and the board (external) does not.
app_lines() { tr -d '\r' | grep -iE '^[[:space:]]*([-*][[:space:]]+)?app:' | sed -E 's/^[[:space:]]*([-*][[:space:]]+)?[Aa][Pp][Pp]:[[:space:]]*//; s/[[:space:]]+$//'; }
item_app_shape() { # $1 label for messages, $2 the item text (comments stripped) → the one app name; nothing when no line
  local n a; a="$(app_lines <<<"$2" | sed '/^$/d')" || true
  n="$(grep -c . <<<"$a")"; [ "$n" -gt 0 ] || return 0
  [ "$n" -eq 1 ] || { echo "$1: names $n apps — one item, one owning app" >&2; return 1; }
  [[ "$a" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]] \
    || { echo "$1: app '$(printf '%s' "$a" | tr -cd 'a-zA-Z0-9._-' | head -c 40)' is not a name like backend (a-z, 0-9, -)" >&2; return 1; }
  printf '%s\n' "$a"
}

# spec_armed <cwd> <edited file or ""> <marker> → the marker's path, exit 0, when it is set in the spec root of the
# cwd OR of the edited file (FR-005: fails closed — a lane whose cwd moved, or an edit in another app, still arms
# it). A relative file is the session's (joined to the cwd), never the hook process's.
spec_armed() {
  local f="$2" r
  [ -z "$f" ] || [ "${f#/}" != "$f" ] || f="$1/$f"
  for r in "$(spec_root_find "$1")" ${f:+"$(spec_root_find "$f")"}; do
    [ -f "$r/.specify/$3" ] && { printf '%s\n' "$r/.specify/$3"; return 0; }
  done
  return 1
}
spec_roots_of() { # $1 cwd, $2 edited file → the distinct spec roots of the cwd and of the file, one per line
  local f="$2" a b
  [ -z "$f" ] || [ "${f#/}" != "$f" ] || f="$1/$f"
  a="$(spec_root_find "$1")"; printf '%s\n' "$a"
  [ -z "$f" ] || { b="$(spec_root_find "$f")"; [ "$b" = "$a" ] || printf '%s\n' "$b"; }
}

# spec_epic_roots <tasks root> <repo top> <board mode> → "label<TAB>folder" per spec root the board's epics read:
# the tasks root's own (no label), then each declared app as "<app>" (FR-012). An external board's code repos
# are not walked in 9.3.0: its epics stay the board's own .specify/, as before.
spec_epic_roots() {
  local j
  printf -- '-\t%s\n' "$1"   # '-': the top, no label (a leading tab would be eaten by read as whitespace)
  [ "$3" != external ] || return 0
  j="$(spec_roots_json "$2")" || return 0   # a bad entry is named on stderr; the board shows the top only
  jq -r --arg t "$2" 'to_entries[] | "\(.key)\t\($t)/\(.value)"' <<<"$j"
}
spec_armed_json() { # $1 a hook's JSON input, $2 marker → spec_armed on its cwd and tool_input.file_path
  local c f
  c="$(jq -r '.cwd // empty' <<<"$1")"; f="$(jq -r '.tool_input.file_path // empty' <<<"$1")"
  spec_armed "$c" "$f" "$2"
}
