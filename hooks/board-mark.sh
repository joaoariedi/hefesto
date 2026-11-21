# shellcheck shell=bash
# shellcheck disable=SC2154  # COL_*, TROOT, ITEM_HEADING, CONFIG are status-board.sh's, set before any call
# board-mark.sh — the board's ONE write path (--mark) and its write-nothing twin (--locate). Sourced by
# status-board.sh, functions only; they read its globals (TROOT, ITEM_HEADING, CONFIG, COL_*, col, die,
# resolve_link, PUBLISH_MARKERS_DEFAULT, KINDS_DEFAULT) at call time. Moved out of status-board.sh, which is
# at its size limit (publish-commit FR-004, HEF-16).
#
# Both resolve the column through item_column, so the path ledger.sh publish guards (from --locate) and the
# path --mark rewrites come from one resolution and cannot diverge.

item_column() { # $1 id → "<column file name>\t<abs resolved path>", or "done\t-"; dies when absent
  local col f
  for col in todo doing backlog 'done'; do
    f="$TROOT/$(col "$col")"; [ -f "$f" ] || continue
    awk -v h="$ITEM_HEADING" -v id="$1" '$0 ~ h && $0 ~ ("(^|[^A-Z0-9-])" id "([^A-Z0-9-]|$)") {found=1; exit} END {exit !found}' "$f" || continue
    # DONE is checked before the resolution, as the old mark_item did: its message stays byte-identical.
    [ "$col" = 'done' ] && { printf 'done\t-\n'; return 0; }
    # Write through a symlink to its target and keep the file's mode: a symlinked column (a specs-in-repo
    # layout) must not be replaced by a private regular file (quality gate 2026-10-02).
    f=$(readlink -f "$f" 2>/dev/null || resolve_link "$f") || die "status-board --mark: cannot resolve $f"
    printf '%s\t%s\n' "$(col "$col")" "$f"; return 0
  done
  die "status-board --mark $1: no such item in $COL_todo, $COL_doing, $COL_backlog or $COL_done under $TROOT"
}

# --locate: where --mark would write, writing nothing (ledger.sh publish guards this path before marking).
locate_item() { # $1 id
  local loc; loc=$(item_column "$1") || exit 1
  printf '%s\n' "$loc"
}

# Put a publish state marker first on an item's heading (ledger-surfaces FR-002). Leading tokens that are
# publish markers are replaced, never stacked; every other token (a kind marker such as 🐞) is kept; an item
# already in DONE is left alone. On success a second line `path: <abs>` names the file rewritten (FR-004).
mark_item() { # $1 id, $2 marker or "-", $3 the marker publish last wrote (stripped too: a superseded map's glyph)
  local set loc f tmp
  set=$(jq -r --argjson d "$PUBLISH_MARKERS_DEFAULT" '$d + ((.orchestrate.publish_markers // {}) | if type == "object" then . else {} end) | [.[]] + [$d[]] | map(select(type == "string" and test("^[^\\s\\\\]+$"))) | unique | join(" ")' "$CONFIG" 2>/dev/null) \
    || set=$(jq -r '[.[]] | join(" ")' <<<"$PUBLISH_MARKERS_DEFAULT")
  # --was strips the marker publish last wrote — never a kind glyph, whatever a misconfigured map says
  if [ -n "${3:-}" ] && [ "$3" != - ]; then
    jq -e --arg w "$3" --argjson d "$KINDS_DEFAULT" 'def novs: gsub("[\ufe0e\ufe0f]"; ""); ($d + ((.kinds // {}) | if type == "object" then . else {} end)) | with_entries(.key |= novs) | has($w | novs)' "$CONFIG" >/dev/null 2>&1 \
      || set="$set $3"
  fi
  loc=$(item_column "$1") || exit 1
  # A DONE heading is a dated section the quarter count parses (^## YYYY-MM-DD); a marker in front would
  # break it — and the column already says the item is done.
  if [ "${loc%%	*}" = 'done' ]; then echo "$1 is in $COL_done — the column says it; not marked"; return 0; fi
  f="${loc#*	}"
  tmp=$(mktemp "$(dirname "$f")/.mark.XXXXXX") || die "status-board --mark: cannot write next to $f"
  chmod "$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f" 2>/dev/null || echo 644)" "$tmp"   # GNU, then BSD stat
  # The marker and the set reach awk through ENVIRON, not -v: -v processes backslash escapes.
  if ! HB_MARK="$2" HB_SET="$set" awk -v h="$ITEM_HEADING" -v id="$1" '
      BEGIN { m = ENVIRON["HB_MARK"]; n = split(ENVIRON["HB_SET"], S, " "); for (i = 1; i <= n; i++) mine[S[i]] = 1 }
      !done && $0 ~ h && $0 ~ ("(^|[^A-Z0-9-])" id "([^A-Z0-9-]|$)") {
        match($0, /^#+ */); pre = substr($0, 1, RLENGTH); rest = substr($0, RLENGTH + 1)
        while ((sp = index(rest, " ")) > 0 && (substr(rest, 1, sp - 1) in mine)) { rest = substr(rest, sp + 1); sub(/^ +/, "", rest) }
        if (m != "-") rest = m " " rest
        print pre rest; done = 1; next }
      { print }' "$f" > "$tmp"; then rm -f "$tmp"; die "status-board --mark $1: rewriting $f failed"; fi
  mv "$tmp" "$f" || { rm -f "$tmp"; die "status-board --mark $1: cannot replace $f"; }
  echo "marked $1 $2 in ${loc%%	*}"; echo "path: $f"; return 0
}
