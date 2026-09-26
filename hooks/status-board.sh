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

MODE="run"; CONFIG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check|-c) MODE="check" ;;
    --detailed|-d) MODE="detailed" ;;
    --config) shift; CONFIG="${1:-}" ;;
    --help|-h) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; echo "Usage: $(basename "$0") [--check | --detailed] [--config <path>]"; exit 0 ;;
    *) echo "unknown option: $1 (try --check, --detailed, --config <path>, or --help)" >&2; exit 2 ;;
  esac
  shift
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
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

source_tasks() {
  declare -gA COL
  COL[todo]="$(cfg '.columns.todo // "TODO.md"')"; COL[doing]="$(cfg '.columns.doing // "DOING.md"')"
  COL[done]="$(cfg '.columns.done // "DONE.md"')"; COL[backlog]="$(cfg '.columns.backlog // "BACKLOG.md"')"
  TROOT="$ROOT/$(cfg '.root // "."')"; TROOT="${TROOT%/.}"
  ITEM_HEADING="$(cfg '.item_heading // "^#{2,3} "')"
  ID_PATTERN="$(cfg '.id_pattern // "[A-Z][A-Z0-9]+(-[A-Z0-9]+){1,4}"')"
  DONE_SECTION="$(cfg '.done_section // "^## ([0-9]{4}-[0-9]{2}-[0-9]{2}) "')"
  tasks_preflight; finish_preflight
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
  tasks-repo) source_tasks ;;
  github-project) source_github ;;
esac
