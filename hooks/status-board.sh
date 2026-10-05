#!/bin/bash
# status-board.sh — the mechanical half of /hef.status: one management brief from a per-project
# source declared in .claude/project-status.json.
#
#   source "github-project"  — a GitHub Projects board: status distribution, epics (issues whose
#                              title starts with epic_prefix) with sub-issue completion, roadmap
#                              quarter. This is batuta's scripts/project-status.sh with its three
#                              constants moved into the config.
#   source "tasks-repo"      — a kanban kept as markdown files (TODO/DOING/DONE/BACKLOG): items are
#                              headings that carry an id, sub-states are the heading's leading
#                              marker, "delivered this quarter" is the dated DONE sections inside
#                              the quarter, epics are initiative scoreboards (and, only when the
#                              project opts in, feature-directory checkboxes).
#
# FETCHER (speckit-helper.sh contract): the board on stdout at exit 0, or the reason on stderr at
# non-zero — never a sentinel a caller could mistake for an answer. `--check` prints the
# prerequisite checklist; `--detailed` unfolds epics/columns into items.
#
# Zero-install: bash, jq, git, grep/sed/awk/date; `gh` only for github-project (constitution 4).
set -uo pipefail

die() { echo "$*" >&2; exit 1; }

MODE="run"; CONFIG=""; ITEM_ID=""; MARK=""; WAS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check|-c) MODE="check" ;;
    --detailed|-d) MODE="detailed" ;;
    --item) shift; MODE="item"; ITEM_ID="${1:-}" ;;
    --item-raw) shift; MODE="item-raw"; ITEM_ID="${1:-}" ;;
    --mark) shift; MODE="mark"; ITEM_ID="${1:-}"; [ $# -gt 0 ] && shift; MARK="${1:-}" ;;
    --was) shift; WAS="${1:-}" ;;
    --item-kind) shift; MODE="item-kind"; ITEM_ID="${1:-}" ;;
    --item-repo) shift; MODE="item-repo"; ITEM_ID="${1:-}" ;;
    --config) shift; CONFIG="${1:-}" ;;
    --help|-h) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; echo "Usage: $(basename "$0") [--check | --detailed | --item <id> | --item-raw <id> | --item-kind <id> | --item-repo <id> | --mark <id> <marker|-> [--was <marker>]] [--config <path>]"; exit 0 ;;
    *) echo "unknown option: $1 (try --check, --detailed, --item <id>, --item-raw <id>, --item-kind <id>, --item-repo <id>, --mark <id> <marker>, --config <path>, or --help)" >&2; exit 2 ;;
  esac
  shift
done
case "$MODE" in item|item-raw|mark|item-kind|item-repo)
  [ -n "$ITEM_ID" ] || { echo "status-board: --$MODE needs an item id" >&2; exit 2; }
  [ "$MODE" != mark ] || [ -n "$MARK" ] || { echo "status-board: --mark needs <id> <marker> (or - for no marker)" >&2; exit 2; }
  # A marker is ONE token with no backslash: a space would stack under the next mark, a backslash or a
  # newline would split the heading and forge another item (code review 2026-10-02).
  for m in "$MARK" "$WAS"; do
    [ -z "$m" ] || [ "$m" = - ] || [[ "$m" =~ ^[^[:space:]\\]+$ ]] || { echo "status-board: invalid marker '$m' (expected one token without spaces or backslashes, or -)" >&2; exit 2; }
  done
  # the id becomes an awk regex atom and a file-name stem downstream: one shape only
  [[ "$ITEM_ID" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || { echo "status-board: invalid item id '$ITEM_ID' (expected [A-Za-z][A-Za-z0-9_-]*, e.g. HEF-12)" >&2; exit 2; } ;;
esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# external-board FR-002: which board this repo reads is ledger.sh's answer (`board`), never re-derived here.
# External, the config and `root` come from the board repo; --config still wins. In-repo, ROOT and CONFIG
# stay exactly as before. A copy of this script with no ledger.sh beside it is in-repo.
HERE="$(cd "$(dirname "$0")" && pwd)"; BCTX=""
if [ -f "$HERE/ledger.sh" ]; then BCTX="$(bash "$HERE/ledger.sh" board)" || exit 1; fi
if [ -n "$BCTX" ] && [ "$(jq -r .mode <<<"$BCTX")" = external ]; then
  ROOT="$(jq -r .board_top <<<"$BCTX")"; [ -n "$CONFIG" ] || CONFIG="$(jq -r .config <<<"$BCTX")"
fi
[ -n "$CONFIG" ] || CONFIG="$ROOT/.claude/project-status.json"

# --- config (FR-001, FR-002) -----------------------------------------------------------------
if [ ! -f "$CONFIG" ]; then
  cat >&2 <<EOF
status-board: no config at $CONFIG — create it. One of:
  {"source":"github-project","owner":"<org>","project":<number>,"roadmap":"docs/product/roadmap.md","epic_prefix":"epic("}
  {"source":"tasks-repo","root":"tasks","columns":{"todo":"TODO.md","doing":"DOING.md","done":"DONE.md","backlog":"BACKLOG.md"},
   "item_heading":"^#{2,3} ","id_pattern":"[A-Z][A-Z0-9]+(-[A-Z0-9]+){1,4}","done_section":"^## ([0-9]{4}-[0-9]{2}-[0-9]{2}) ",
   "epics":{"initiatives":"initiatives/*.md","specs":false},"states":{"📥":"intake"},"quarter_start":null,"quarter_end":null}
EOF
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  printf '  [MISSING] jq not found\n            ↳ install jq: https://jqlang.org\n' >&2; exit 1
fi
if ! jq -e . "$CONFIG" >/dev/null 2>&1; then
  printf '  [MISSING] %s is not valid JSON\n            ↳ fix the file (jq . %s shows the error)\n' "$CONFIG" "$CONFIG" >&2; exit 1
fi
cfg() { jq -r "$1" "$CONFIG"; }   # $1 = jq expression with its own default via //
SOURCE="$(cfg '.source // empty')"
case "$SOURCE" in
  github-project|tasks-repo) ;;
  *) die "status-board: \"source\" must be \"github-project\" or \"tasks-repo\" (got '${SOURCE:-<none>}') in $CONFIG" ;;
esac

# --- shared renderers ------------------------------------------------------------------------
bar() { # completed total → 10-cell bar
  local c=$1 t=$2 f=0 i s=""
  [ "$t" -gt 0 ] && f=$(( c * 10 / t ))
  for ((i=0; i<10; i++)); do if [ "$i" -lt "$f" ]; then s+="█"; else s+="░"; fi; done
  printf '%s' "$s"
}
epoch_of() { date -d "$1" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null; }
day_before() { date -d "$1 -1 day" +%Y-%m-%d 2>/dev/null || date -j -v-1d -f "%Y-%m-%d" "$1" +%Y-%m-%d 2>/dev/null; }
days_until() { echo $(( ( $(epoch_of "$1") - $(epoch_of "$(date +%Y-%m-%d)") ) / 86400 )); }
rule() { echo "═══════════════════════════════════════════════════════════════"; }

# --- preflight (FR-003): [ok]/[MISSING] in check mode; silent-unless-missing in run mode -------
fail=0
ok()   { [ "$MODE" = "check" ] && printf '  [ok]      %s\n' "$1"; return 0; }
miss() { # in run mode the checklist goes to stderr: stdout must stay empty when the answer is missing
  fail=$((fail + 1))
  if [ "$MODE" = "check" ]; then printf '  [MISSING] %s\n' "$1"; [ -n "${2:-}" ] && printf '            ↳ %s\n' "$2"
  else printf 'status-board: [MISSING] %s\n' "$1" >&2; [ -n "${2:-}" ] && printf '            ↳ %s\n' "$2" >&2; fi
  return 0
}
finish_preflight() {
  if [ "$MODE" = "check" ]; then
    echo
    if [ "$fail" -eq 0 ]; then echo "  All prerequisites met — /hef.status is ready."; exit 0
    else echo "  $fail prerequisite(s) missing — fix the items above, then re-run."; exit 1; fi
  fi
  if [ "$fail" -ne 0 ]; then
    echo "status-board: $fail prerequisite(s) missing — run: $(basename "$0") --check" >&2; exit 1
  fi
}

# =============================================================================================
# tasks-repo
# =============================================================================================
tasks_preflight() {
  [ "$MODE" = "check" ] && echo "status-board preflight — tasks-repo at $TROOT:"
  ok "jq installed"; ok "config valid ($CONFIG)"
  if [ -d "$TROOT" ]; then ok "root directory $TROOT"; else miss "root directory missing: $TROOT" "fix \"root\" in $CONFIG"; fi
  local key
  for key in todo doing backlog 'done'; do
    local f="$TROOT/${COL[$key]}"
    if [ -f "$f" ]; then ok "column $key: ${COL[$key]}"; else miss "column $key: $f" "create it or fix columns.$key in $CONFIG"; fi
  done
}

# Items: headings matching ITEM_HEADING whose text contains an id (FR-006). Prints id<TAB>marker<TAB>text.
# The marker is the heading's first token when it is neither the id nor an ordinary word (FR-007).
column_items() {
  local line id first marker
  grep -E "$ITEM_HEADING" "$1" | sed -E 's/^#+ *//' | while IFS= read -r line; do
    id="$(grep -oE "$ID_PATTERN" <<<"$line" | head -1)"
    [ -z "$id" ] && continue
    first="${line%% *}"
    if [ "$first" = "$id" ] || [[ "$first" =~ ^[A-Za-z0-9*_\`\[\(] ]]; then marker=""; else marker="$first"; fi
    printf '%s\t%s\t%s\n' "$id" "$marker" "$line"
  done
}

# One item's heading + body (FR-014 of session-orchestration): from the first column that holds a
# heading carrying the id, up to the next heading. `--item` strips HTML comments and wraps the text in
# the untrusted delimiters BEFORE any model reads it — the strip is mechanical and upstream of the
# judgement, so a hidden instruction never reaches the orchestrator (report 17 §1f). `--item-raw`
# prints the text as written; that is what the ledger hashes to detect an item edited after claim.
strip_comments() { sed -E 's/<!--[^>]*-->//g' | sed '/<!--/,/-->/d'; }   # what --item shows and --item-repo routes on
item_body() { # $1 id, $2 raw|clean
  local col f body
  for col in todo doing backlog 'done'; do
    f="$TROOT/${COL[$col]}"
    body=$(awk -v h="$ITEM_HEADING" -v id="$1" '
      BEGIN { p = 0 }
      $0 ~ h { if (p) exit; p = ($0 ~ ("(^|[^A-Z0-9-])" id "([^A-Z0-9-]|$)")) }
      p' "$f" 2>/dev/null)
    [ -n "$body" ] || continue
    if [ "$2" = raw ]; then printf '%s\n' "$body"; return 0; fi
    # A per-call nonce on both markers: a body that contains the literal closing marker cannot end
    # the block early and smuggle text out of it (quality gate 2026-09-27, advisory A1).
    local nonce; nonce="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8)"
    printf '<<<untrusted-begin %s %s\n%s\nuntrusted-end %s>>>\n' "$1" "$nonce" "$(strip_comments <<<"$body")" "$nonce"
    return 0
  done
  die "status-board --item $1: no such item in ${COL[todo]}, ${COL[doing]}, ${COL[backlog]} or ${COL[done]} under $TROOT"
}

# The board's ONE write path (ledger-surfaces FR-002): put a publish state marker first on an item's
# heading. Leading tokens that are publish markers (the default below — byte-identical to ledger.sh's
# copy, asserted by the smoke suite — merged with orchestrate.publish_markers) are replaced, never
# stacked; every other token (a kind marker such as 🐞) is kept; an item already in DONE is left alone. Same id-boundary match as item_body,
# so HEF-1 never rewrites HEF-10. One heading changes, written through a temp file in the same dir.
PUBLISH_MARKERS_DEFAULT='{"human_block":"⏸","block":"⛔","plan":"📐","build":"🔨","pr":"🔀","done":"✅"}'

# An item's KIND (item-kinds FR-001; report 18 #6): a kind glyph anywhere before the id on its heading —
# not only first, because publish puts a STATE marker in front (`## ⏸ 🐞 HEF-21`). Config `kinds` over
# the default; the two glyph sets never overlap (asserted by the smoke suite), or --mark would strip a
# kind. The first token is still what /hef.status reads as the sub-state: label kind glyphs via `states`.
# The glyph goes BEFORE the id (`## 🐞 HEF-21 — …`); one after it is title text. Variation selectors
# (U+FE0E text, U+FE0F emoji) are stripped from both the map's keys and the heading's tokens before the
# lookup — editors add or drop VS16 at will, and 🛡 / 🛡️ must be one glyph (quality gate 2026-10-02).
KINDS_DEFAULT='{"🐞":"incident","🛡":"vulnerability","🛡️":"vulnerability"}'
item_kind() { # $1 id → feature|incident|vulnerability
  local map col f line pre t k
  # Values must be one of the three kinds and keys must not be publish markers (--mark would strip them):
  # a bad override is named here, not later by `ledger init` (code review 2026-10-02).
  map=$(jq -ce --argjson d "$KINDS_DEFAULT" --argjson pm "$PUBLISH_MARKERS_DEFAULT" '
      def novs: gsub("[\ufe0e\ufe0f]"; "");
      (.kinds // {}) as $k | ((.orchestrate.publish_markers // {}) | if type == "object" then [.[]] else [] end) + [$pm[]] | map(strings | novs) as $marks
      | if ($k | type) != "object" then error("kinds must be an object")
        elif ($k | to_entries | any(.value as $v | ["feature","incident","vulnerability"] | index($v) | not)) then error("a kinds value is not feature, incident or vulnerability")
        elif ($k | keys | any(novs as $g | $marks | index($g))) then error("a kinds glyph is also a publish marker")
        else $d + $k | with_entries(.key |= novs) end' "$CONFIG" 2>/dev/null) \
    || die "status-board --item-kind: .kinds in $CONFIG must map glyphs (never a publish marker) to feature, incident or vulnerability"
  for col in todo doing backlog; do
    f="$TROOT/${COL[$col]}"
    line=$(awk -v h="$ITEM_HEADING" -v id="$1" '$0 ~ h && $0 ~ ("(^|[^A-Z0-9-])" id "([^A-Z0-9-]|$)") { print; exit }' "$f" 2>/dev/null)
    [ -n "$line" ] || continue
    pre="${line%%"$1"*}"
    set -f; for t in $pre; do
      t="${t//$'\xef\xb8\x8e'/}"; t="${t//$'\xef\xb8\x8f'/}"   # U+FE0E, U+FE0F
      k=$(jq -r --arg t "$t" '.[$t] // empty' <<<"$map")
      [ -n "$k" ] && { set +f; echo "$k"; return 0; }
    done; set +f
    echo feature; return 0
  done
  die "status-board --item-kind $1: no such item in ${COL[todo]}, ${COL[doing]} or ${COL[backlog]} under $TROOT"
}
mark_item() { # $1 id, $2 marker or "-", $3 the marker publish last wrote (stripped too: a superseded map's glyph)
  local set col f tmp
  set=$(jq -r --argjson d "$PUBLISH_MARKERS_DEFAULT" '$d + ((.orchestrate.publish_markers // {}) | if type == "object" then . else {} end) | [.[]] + [$d[]] | map(select(type == "string" and test("^[^\\s\\\\]+$"))) | unique | join(" ")' "$CONFIG" 2>/dev/null) \
    || set=$(jq -r '[.[]] | join(" ")' <<<"$PUBLISH_MARKERS_DEFAULT")
  # --was strips the marker publish last wrote — never a kind glyph, whatever a misconfigured map says
  if [ -n "${3:-}" ] && [ "$3" != - ]; then
    jq -e --arg w "$3" --argjson d "$KINDS_DEFAULT" 'def novs: gsub("[\ufe0e\ufe0f]"; ""); ($d + ((.kinds // {}) | if type == "object" then . else {} end)) | with_entries(.key |= novs) | has($w | novs)' "$CONFIG" >/dev/null 2>&1 \
      || set="$set $3"
  fi
  for col in todo doing backlog 'done'; do
    f="$TROOT/${COL[$col]}"; [ -f "$f" ] || continue
    awk -v h="$ITEM_HEADING" -v id="$1" '$0 ~ h && $0 ~ ("(^|[^A-Z0-9-])" id "([^A-Z0-9-]|$)") {found=1; exit} END {exit !found}' "$f" || continue
    # A DONE heading is a dated section the quarter count parses (^## YYYY-MM-DD); a marker in front would
    # break it — and the column already says the item is done.
    if [ "$col" = 'done' ]; then echo "$1 is in ${COL[done]} — the column says it; not marked"; return 0; fi
    # Write through a symlink to its target and keep the file's mode: a symlinked column (a specs-in-repo
    # layout) must not be replaced by a private regular file (quality gate 2026-10-02).
    f=$(readlink -f "$f") || die "status-board --mark: cannot resolve $f"
    tmp=$(mktemp "$(dirname "$f")/.mark.XXXXXX") || die "status-board --mark: cannot write next to $f"
    chmod --reference="$f" "$tmp" 2>/dev/null || chmod "$(stat -c %a "$f" 2>/dev/null || echo 644)" "$tmp"
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
    echo "marked $1 $2 in ${COL[$col]}"; return 0
  done
  die "status-board --mark $1: no such item in ${COL[todo]}, ${COL[doing]}, ${COL[backlog]} or ${COL[done]} under $TROOT"
}

# Routing (external-board FR-002, spec US2): the item's `repo: <name>` body line → "<name>\t<abs path>". It
# parses the COMMENT-STRIPPED body, the same text --item shows, so a `<!-- repo: … -->` never routes. The line
# may be indented and bulleted (`  - repo: ops`, fxcube's format) and end in CR; `**repo:**` is not a repo line.
repo_lines() { tr -d '\r' | grep -iE '^[[:space:]]*([-*][[:space:]]+)?repo:' | sed -E 's/^[[:space:]]*([-*][[:space:]]+)?[Rr][Ee][Pp][Oo]:[[:space:]]*//'; }
# A refusal echoes board text OUTSIDE the untrusted delimiters, so a name is shown only as [a-z0-9_-] (anything
# else → ?), at most 32 characters, and a list beyond 5 names as a count (code review 2026-10-05).
safe_name() { local n="${1//[^a-z0-9_-]/?}"; printf '%s' "${n:0:32}"; }
safe_list() { # newline-separated names → "a, b, c" (first 5, then "+N more")
  local n out="" i=0
  while IFS= read -r n; do i=$((i + 1)); [ "$i" -le 5 ] && out+="${out:+, }$(safe_name "$n")"; done
  [ "$i" -gt 5 ] && out+=", +$((i - 5)) more"; printf '%s' "$out"
}
item_repo() { # $1 id
  local repos all names n body
  [ -n "$BCTX" ] && [ "$(jq -r .mode <<<"$BCTX")" = external ] \
    || die "status-board --item-repo $1: the board is in-repo (no repos map) — routing applies only to an external board (docs/install.md §7 step 13)"
  repos="$(jq -c .repos <<<"$BCTX")"; all="$(jq -r 'keys_unsorted | join(", ")' <<<"$repos")"
  body="$(item_body "$1" raw)" || exit 1
  names="$(strip_comments <<<"$body" | repo_lines | tr ',`' '  ' | tr -s ' \t' '\n\n' | sed '/^$/d' | sort -u)" || true
  n="$(grep -c . <<<"$names")"
  if [ "$n" -eq 0 ]; then
    [ "$(jq 'length' <<<"$repos")" -eq 1 ] || die "status-board --item-repo $1: names no repo (add \`repo: <name>\` above any ### sub-heading; the board feeds: $all)"
    names="$(jq -r 'keys_unsorted[0]' <<<"$repos")"
  elif [ "$n" -gt 1 ]; then die "status-board --item-repo $1: targets $n repos ($(safe_list <<<"$names")) — split it into one item per repo"; fi
  jq -e --arg r "$names" 'has($r)' <<<"$repos" >/dev/null || die "status-board --item-repo $1: names repo '$(safe_name "$names")' the board does not feed ($all)"
  printf '%s\t%s\n' "$names" "$(jq -r --arg r "$names" '.[$r]' <<<"$repos")"
}

marker_summary() { # items → "label n · label n"
  local m n out=""
  while read -r n m; do
    [ -z "$m" ] && continue
    m="$(jq -r --arg m "$m" '.states[$m] // $m' "$CONFIG")"
    out+="${out:+ · }$m $n"
  done < <(cut -f2 | sed '/^$/d' | sort | uniq -c | sort -rn)
  printf '%s' "$out"
}

quarter_bounds() { # sets QS QE (FR-008): calendar quarter unless overridden
  QS="$(cfg '.quarter_start // empty')"; QE="$(cfg '.quarter_end // empty')"
  if { [ -n "$QS" ] && [ -z "$QE" ]; } || { [ -z "$QS" ] && [ -n "$QE" ]; }; then
    die "status-board: quarter_start and quarter_end must be set together in $CONFIG (got start='${QS:-}' end='${QE:-}')"
  fi
  if [ -z "$QS" ]; then
    local y m qm ny nqm
    y=$(date +%Y); m=$((10#$(date +%m))); qm=$(( (m - 1) / 3 * 3 + 1 ))
    QS="$(printf '%s-%02d-01' "$y" "$qm")"
    nqm=$((qm + 3)); ny=$y; if [ "$nqm" -gt 12 ]; then nqm=1; ny=$((y + 1)); fi
    QE="$(day_before "$(printf '%s-%02d-01' "$ny" "$nqm")")"
  fi
}

done_this_quarter() { # count DONE sections whose date capture lies in [QS, QE]
  local d n=0
  while read -r d; do
    [ -z "$d" ] && continue
    if [[ "$d" > "$QS" || "$d" == "$QS" ]] && [[ "$d" < "$QE" || "$d" == "$QE" ]]; then n=$((n + 1)); fi
  done < <(grep -E "$DONE_SECTION" "$TROOT/${COL[done]}" | sed -E 's/^[^0-9]*([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/')
  echo "$n"
}

initiative_epics() { # each file matched by epics.initiatives → one bar (FR-009)
  local glob f name ids prefix total done_ id
  glob="$(cfg '.epics.initiatives // "initiatives/*.md"')"
  mapfile -t files < <(cd "$TROOT" 2>/dev/null && compgen -G "$glob" || true)
  if [ "${#files[@]}" -eq 0 ]; then echo "    no initiatives found ($glob)"; return; fi
  for f in "${files[@]}"; do
    name="$(basename "${f%.md}")"
    ids="$(grep -oE "$ID_PATTERN" "$TROOT/$f" | sort -u)"
    if [ -z "$ids" ]; then printf '    %-28.28s %s  no ids\n' "$name" "$(bar 0 1)"; continue; fi
    prefix="$(sed -E 's/-[0-9]+$//' <<<"$ids" | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')"
    total=0; done_=0
    while read -r id; do
      [ -z "$id" ] && continue
      [ "$(sed -E 's/-[0-9]+$//' <<<"$id")" = "$prefix" ] || continue
      total=$((total + 1))
      if grep -qF -- "~~$id~~" "$TROOT/$f" || grep -wF -- "$id" "$TROOT/$f" | grep -q '✅'; then done_=$((done_ + 1)); fi
    done <<<"$ids"
    printf '    %-28.28s %s  %s/%s (%s%%)\n' "$name" "$(bar "$done_" "$total")" "$done_" "$total" "$(( total > 0 ? done_ * 100 / total : 0 ))"
  done
}

spec_epics() { # only when epics.specs is true (FR-010)
  local t name ticked open
  for t in "$TROOT"/.specify/specs/*/tasks.md; do
    [ -f "$t" ] || continue
    name="$(basename "$(dirname "$t")")"
    ticked=$(grep -cE '^\s*- \[x\]' "$t"); open=$(grep -cE '^\s*- \[[ ~]\]' "$t")
    printf '    %-28.28s %s  %s/%s (%s%%)\n' "$name" "$(bar "$ticked" $((ticked + open)))" "$ticked" $((ticked + open)) "$(( (ticked + open) > 0 ? ticked * 100 / (ticked + open) : 0 ))"
  done
}

tasks_config() { # the tasks-repo settings and the preflight, shared by the board and by --item
  declare -gA COL
  COL[todo]="$(cfg '.columns.todo // "TODO.md"')"; COL[doing]="$(cfg '.columns.doing // "DOING.md"')"
  COL[done]="$(cfg '.columns.done // "DONE.md"')"; COL[backlog]="$(cfg '.columns.backlog // "BACKLOG.md"')"
  TROOT="$ROOT/$(cfg '.root // "."')"; TROOT="${TROOT%/.}"
  ITEM_HEADING="$(cfg '.item_heading // "^#{2,3} "')"
  ID_PATTERN="$(cfg '.id_pattern // "[A-Z][A-Z0-9]+(-[A-Z0-9]+){1,4}"')"
  DONE_SECTION="$(cfg '.done_section // "^## ([0-9]{4}-[0-9]{2}-[0-9]{2}) "')"
  tasks_preflight; finish_preflight
}

source_tasks() {
  quarter_bounds
  local name key items n delivered
  name="$(cfg '.name // empty')"; [ -n "$name" ] || name="$(basename "$ROOT")"
  rule; echo "  $name — Status Board (tasks-repo: $(basename "$TROOT")/)"; rule
  printf '  Quarter : %s → %s — %s days left\n' "$QS" "$QE" "$(days_until "$QE")"
  echo
  declare -A COUNT
  for key in todo doing backlog; do
    items="$(column_items "$TROOT/${COL[$key]}")"
    n=$(printf '%s' "$items" | grep -c . || true); COUNT[$key]=$n
    printf '  %-8s %s items%s\n' "$key" "$n" "$( [ -n "$items" ] && printf ' — %s' "$(printf '%s\n' "$items" | marker_summary)")"
    if [ "$MODE" = "detailed" ] && [ -n "$items" ]; then
      printf '%s\n' "$items" | while IFS=$'\t' read -r id m text; do printf '      %-16s %-4s %s\n' "$id" "$m" "${text:0:70}"; done
    fi
  done
  delivered="$(done_this_quarter)"
  printf '  %-8s delivered this quarter: %s (dated sections in %s)\n' "done" "$delivered" "${COL[done]}"
  echo
  echo "  Epics — initiative scoreboards:"; initiative_epics
  if [ "$(cfg '.epics.specs // false')" = "true" ]; then echo "  Epics — feature directories (.specify/specs, opt-in):"; spec_epics; fi
  echo
  printf '  Bottom line: %s in doing · %s in todo · %s backlogged · %s delivered this quarter · %s days left.\n' \
    "${COUNT[doing]}" "${COUNT[todo]}" "${COUNT[backlog]}" "$delivered" "$(days_until "$QE")"
  rule
}

# =============================================================================================
# github-project — batuta's scripts/project-status.sh, parameterised (FR-004, FR-005)
# =============================================================================================
gh_preflight() {
  [ "$MODE" = "check" ] && echo "status-board preflight — GitHub Project #$PROJECT @ $OWNER:"
  ok "jq installed"; ok "config valid ($CONFIG)"
  local have_gh=0 authed=0 err
  if command -v gh >/dev/null 2>&1; then ok "gh CLI installed"; have_gh=1; else miss "gh CLI not found" "install: https://cli.github.com"; fi
  if [ $have_gh -eq 1 ]; then
    if gh auth status >/dev/null 2>&1; then ok "gh authenticated"; authed=1; else miss "gh not authenticated" "run: gh auth login"; fi
  fi
  if [ $authed -eq 1 ]; then
    if err=$(gh project view "$PROJECT" --owner "$OWNER" --format json 2>&1 >/dev/null); then ok "Project #$PROJECT readable ($OWNER)"
    elif printf '%s' "$err" | grep -qi 'read:project\|required scope\|missing.*scope'; then miss "gh token missing the 'read:project' scope" "run: gh auth refresh -s read:project"
    else miss "Project #$PROJECT not accessible to you" "need org membership / project visibility — $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-100)"; fi
    if [ -n "$GREPO" ]; then
      if gh repo view "$GREPO" --json name >/dev/null 2>&1; then ok "repo readable ($GREPO)"; else miss "repo $GREPO not accessible" "request access to the repository"; fi
    fi
  fi
  if [ -f "$ROADMAP" ]; then ok "roadmap found ($(basename "$ROADMAP"))"
  elif [ "$MODE" = "check" ] && [ -n "$ROADMAP" ]; then printf '  [warn]    roadmap not found — quarter header will be skipped\n'; fi
}

gh_epic_tasks() { # epic-number repo → its sub-issues, one per line
  local num=$1 repo=$2 o="${2%%/*}" r="${2##*/}" nodes tn tstate ttitle tassignee st mark
  nodes=$(gh api graphql -f query='
    query($o:String!,$r:String!,$n:Int!){ repository(owner:$o,name:$r){
      issue(number:$n){ subIssues(first:50){ nodes{
        number state title assignees(first:5){ nodes{ login } } } } } } }' -F o="$o" -F r="$r" -F n="$num" 2>/dev/null \
    | jq -r '(.data.repository.issue.subIssues.nodes // []) | sort_by(.number)[]
             | [ (.number|tostring), .state, (.title[0:64]), ([.assignees.nodes[].login] | map("@"+.) | join(",")) ] | @tsv')
  if [ -z "$nodes" ]; then printf '        (no sub-issues)\n'; return; fi
  while IFS=$'\t' read -r tn tstate ttitle tassignee; do
    [ -z "$tn" ] && continue
    st=$(awk -F'\t' -v r="$repo" -v n="$tn" '$1==r && $2==n{print $3; exit}' <<<"$STATUS_MAP"); [ -z "$st" ] && st="—"
    if [ "$tstate" = "CLOSED" ]; then mark="✓"; else mark="○"; fi
    [ -z "$tassignee" ] && tassignee="—"
    printf '        %s #%-4s %-13s %-15s %s\n' "$mark" "$tn" "[$st]" "$tassignee" "$ttitle"
  done <<<"$nodes"
}

source_github() {
  OWNER="$(cfg '.owner // empty')"; PROJECT="$(cfg '.project // empty')"
  [ -n "$OWNER" ] && [ -n "$PROJECT" ] || die "status-board: github-project needs \"owner\" and \"project\" in $CONFIG"
  GREPO="$(cfg '.repo // empty')"; EPIC_PREFIX="$(cfg '.epic_prefix // "epic("')"
  ROADMAP="$(cfg '.roadmap // empty')"; [ -n "$ROADMAP" ] && ROADMAP="$ROOT/$ROADMAP"
  gh_preflight; finish_preflight
  local quarter="" release="" updated="" close="" days="" board statuses total done_n backlog_n active remaining pct name
  if [ -f "$ROADMAP" ]; then
    quarter=$(grep -m1 "Currently in flight" "$ROADMAP" | sed -E 's/.*\*\* *//')
    release=$(grep -m1 "Latest released" "$ROADMAP" | sed -E 's/.*\*\* *//')
    updated=$(grep -m1 "Last updated" "$ROADMAP" | sed -E 's/.*\*\* *//')
    close=$(printf '%s' "$quarter" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
    [ -n "$close" ] && days="$(days_until "$close")"
  fi
  board=$(gh project item-list "$PROJECT" --owner "$OWNER" --format json --limit 400) || die "status-board: gh project item-list failed"
  statuses=$(printf '%s' "$board" | jq -c '[.items[] | select(.content.type=="Issue")] | group_by(.status) | map({status:(.[0].status // "—"), n:length}) | sort_by(-.n)')
  total=$(printf '%s' "$statuses" | jq '[.[].n] | add // 0')
  done_n=$(printf '%s' "$statuses" | jq '(map(select(.status=="Done"))[0].n) // 0')
  backlog_n=$(printf '%s' "$statuses" | jq '(map(select(.status=="Backlog"))[0].n) // 0')
  active=$(( total - backlog_n )); remaining=$(( active - done_n )); pct=0; [ "$active" -gt 0 ] && pct=$(( done_n * 100 / active ))
  STATUS_MAP=$(printf '%s' "$board" | jq -r '.items[] | select(.content.type=="Issue") | "\(.content.repository)\t\(.content.number)\t\(.status // "—")"')
  name="$(cfg '.name // empty')"; [ -n "$name" ] || name="$(basename "$ROOT")"
  rule; echo "  $name — Status Board (GitHub Project #$PROJECT @ $OWNER)"; rule
  [ -n "$quarter" ] && printf '  Quarter : %s%s\n' "$quarter" "$( [ -n "$days" ] && echo " — ${days} days left")"
  [ -n "$release" ] && printf '  Release : %s\n' "$release"
  [ -n "$updated" ] && printf '  Roadmap : updated %s\n' "$updated"
  echo
  printf '  Board #%s — %s tracked issues · delivered %s/%s active (%s%%, cumulative)\n' "$PROJECT" "$total" "$done_n" "$active" "$pct"
  printf '%s' "$statuses" | jq -r '.[] | "    \(.status): \(.n)"'
  echo
  echo "  Workstreams — epic completion$( [ "$MODE" = "detailed" ] && echo ' (tasks unfolded)'):"
  local num repo title label sum c t raw
  while IFS=$'\t' read -r num repo title; do
      [ -z "$num" ] && continue
      label=$(printf '%s' "$title" | sed -E 's/^[^(]*\(([^)]*)\): /\1 — /')
      # No pipeline here on purpose: a failed query must abort the board, not render "no tasks yet".
      raw=$(gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){subIssuesSummary{total completed}}}}' \
            -F o="${repo%%/*}" -F r="${repo##*/}" -F n="$num" 2>/dev/null) || die "status-board: gh api graphql failed for epic #$num ($repo) — the board would be wrong, not partial"
      sum=$(printf '%s' "$raw" | jq -r '(.data.repository.issue.subIssuesSummary // {completed:0,total:0}) | "\(.completed) \(.total)"')
      c=${sum%% *}; t=${sum##* }
      if [ "${t:-0}" = "0" ]; then printf '    #%-4s %-40.40s %s  %s\n' "$num" "$label" "$(bar 0 1)" "no tasks yet"
      else printf '    #%-4s %-40.40s %s  %s/%s (%s%%)\n' "$num" "$label" "$(bar "$c" "$t")" "$c" "$t" "$(( c * 100 / t ))"; fi
      if [ "$MODE" = "detailed" ]; then gh_epic_tasks "$num" "$repo"; echo; fi
  done < <(printf '%s' "$board" | jq -r --arg p "$EPIC_PREFIX" '[.items[] | select(.content.type=="Issue") | select(.content.title|startswith($p))] | sort_by(.content.number) | .[] | "\(.content.number)\t\(.content.repository)\t\(.content.title)"')
  echo
  printf '  Bottom line: %s of %s active tasks delivered (%s%%) · %s remaining · %s backlogged.\n' "$done_n" "$active" "$pct" "$remaining" "$backlog_n"
  [ -n "$days" ] && printf '  Quarter closes in %s days.\n' "$days"
  rule
}

case "$SOURCE" in
  tasks-repo)
    tasks_config
    case "$MODE" in item) item_body "$ITEM_ID" clean; exit $? ;; item-raw) item_body "$ITEM_ID" raw; exit $? ;; mark) mark_item "$ITEM_ID" "$MARK" "$WAS"; exit $? ;; item-kind) item_kind "$ITEM_ID"; exit $? ;; item-repo) item_repo "$ITEM_ID"; exit $? ;; esac
    source_tasks ;;
  github-project)
    case "$MODE" in item|item-raw|item-kind|item-repo) die "status-board --$MODE: unsupported for github-project in Phase 1 (tasks-repo only)" ;; mark) die "status-board --mark: a github-project board is published with ledger.sh publish (an issue comment), not by editing a file" ;; esac
    source_github ;;
esac
