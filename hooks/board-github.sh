# shellcheck shell=bash
# shellcheck disable=SC2034  # ghb_parse_arg sets status-board.sh's mode variables
# board-github.sh — a GitHub Project (v2) as a lane board (github-project-board). Sourced by status-board.sh,
# functions only. Every lane reads a board through status-board.sh's modes; these are the github-project
# implementations of them, with the tasks-repo output shapes.
#
# - An item is an Issue of the one configured `repo` on Project `project` of `owner`; its id is <id_prefix>-<number>.
#   Draft items, pull requests and other repos' issues are not items (FR-002).
# - The columns are options of the single-select field `status_field` (default Status), mapped by `columns`.
# - Every gh failure refuses with its cause (constitution 5, NR-001): no mode prints an empty answer for an error.
# - gh writes happen only in ghb_add (--add) and ghb_set_status (ledger.sh publish) (NR-004).

GHB_COLUMNS_DEFAULT='{"todo":"Todo","doing":"In Progress","done":"Done"}'
GHB_KINDS_DEFAULT='{"bug":"incident","incident":"incident","security":"vulnerability"}'
GHB_TRUSTED_DEFAULT='["OWNER","MEMBER","COLLABORATOR"]'

# The new option arms of status-board.sh's loop (plan R2 #5): sets the mode variables and returns how many
# arguments it consumed, 0 for an option it does not know (the loop then keeps its `exit 2`).
ghb_parse_arg() {
  case "$1" in
    --list) MODE="list"; LIST_COL="${2:-}"; return 2 ;;
    --item-url) MODE="item-url"; ITEM_ID="${2:-}"; return 2 ;;
    --item-trust) MODE="item-trust"; ITEM_ID="${2:-}"; return 2 ;;
    --as-untrusted) MODE="as-untrusted"; ITEM_ID="${2:-}"; return 2 ;;
    --set-status) MODE="set-status"; ITEM_ID="${2:-}"; SET_STATE="${3:-}"; return 3 ;;
    --note-file) NOTE_FILE="${2:-}"; return 2 ;;
    --body-file) BODY_FILE="${2:-}"; return 2 ;;
  esac
  return 0
}

# Board text shown outside the untrusted delimiters (an option name, a login) is held to a plain shape.
safe_label() { local n="${1//[^A-Za-z0-9 _.-]/?}"; printf '%s' "${n:0:40}"; }
safe_labels() { local n out="" i=0; while IFS= read -r n; do i=$((i + 1)); [ "$i" -le 8 ] && out+="${out:+, }$(safe_label "$n")"; done; printf '%s' "$out"; }

ghb_config() {
  OWNER="$(cfg '.owner // empty')"; PROJECT="$(cfg '.project // empty')"; GREPO="$(cfg '.repo // empty')"
  PREFIX="$(cfg '.id_prefix // empty')"; SFIELD="$(cfg '.status_field // "Status"')"
  [[ "$OWNER" =~ ^[A-Za-z0-9-]+$ ]] && [[ "$PROJECT" =~ ^[0-9]+$ ]] || die "status-board: a github-project board needs \"owner\" and \"project\" (a number) in $CONFIG"
  [[ "$GREPO" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || die "status-board: a github-project lane board needs \"repo\": \"<owner>/<name>\" in $CONFIG"
  [[ "$PREFIX" =~ ^[A-Z][A-Z0-9]*$ ]] || die "status-board: a github-project lane board needs \"id_prefix\" (capitals, e.g. \"BC\") in $CONFIG"
  if [ -n "$BCTX" ] && [ "$(jq -r .mode <<<"$BCTX")" = external ]; then die "status-board: a github-project board is in-repo only — an external github board is not supported"; fi
}

gql() { # $1 query, then -F vars → the response JSON; refuses on a gh failure, GraphQL errors or no data
  local out err m
  err="$(mktemp)" || die "status-board: mktemp failed"
  if ! out=$("$GH" api graphql -f query="$1" "${@:2}" 2>"$err"); then
    m="$(tail -1 "$err" | cut -c1-200)"; rm -f "$err"
    die "status-board: gh api graphql failed: $m — check gh auth status (the read:project scope)"
  fi
  rm -f "$err"
  jq -e 'has("data") and (.data != null) and ((.errors // []) | length == 0)' <<<"$out" >/dev/null 2>&1 \
    || die "status-board: gh api graphql answered without data: $(jq -c '.errors // .' <<<"$out" 2>/dev/null | cut -c1-200)"
  printf '%s' "$out"
}

gh_id_parse() { # $1 id → GQ_REPO GQ_NUM
  [[ "$1" =~ ^${PREFIX}-([1-9][0-9]{0,8})$ ]] || die "status-board: $1 is not an item of this board (its ids are $PREFIX-<issue number> in $GREPO)"
  GQ_REPO="$GREPO"; GQ_NUM="${BASH_REMATCH[1]}"
}

GQ_ISSUE='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){number title body url authorAssociation author{login} editor{login} labels(first:50){nodes{name}} projectItems(first:50){nodes{id project{number owner{... on Organization{login} ... on User{login}}}}}}}}'
gh_issue_q() { # $1 id → GQ_JSON (the issue) and GQ_ITEM (its item id on this Project), once per process
  [ "${GQ_ID:-}" = "$1" ] && return 0
  gh_id_parse "$1"
  local raw; raw="$(gql "$GQ_ISSUE" -F o="${GQ_REPO%%/*}" -F r="${GQ_REPO##*/}" -F n="$GQ_NUM")" || exit 1
  GQ_JSON="$(jq -ce '.data.repository.issue // empty' <<<"$raw")" || die "status-board $1: no issue #$GQ_NUM in $GQ_REPO"
  GQ_ITEM="$(jq -r --arg o "$OWNER" --argjson p "$PROJECT" '[.projectItems.nodes[] | select(.project.number == $p and ((.project.owner.login // "") | ascii_downcase) == ($o | ascii_downcase))] | if length == 1 then .[0].id else empty end' <<<"$GQ_JSON")"
  [ -n "$GQ_ITEM" ] || die "status-board $1: issue $GQ_REPO#$GQ_NUM is not on Project #$PROJECT ($OWNER)"
  GQ_ID="$1"
}

ghb_text() { # $1 id → '## <id> — <title>' and the body, CR stripped: the text the ledger hashes (FR-003)
  gh_issue_q "$1"
  jq -r --arg id "$1" '"## \($id) — \(.title | gsub("[\r\n]"; " "))\n\(.body // "" | gsub("\r"; ""))"' <<<"$GQ_JSON"
}

ghb_kind() { # $1 id → feature|incident|vulnerability, from the labels (FR-004)
  local map; gh_issue_q "$1"
  map="$(jq -ce --argjson d "$GHB_KINDS_DEFAULT" '(.kinds_labels // $d) | if type == "object" and all(.[]; . == "feature" or . == "incident" or . == "vulnerability") then with_entries(.key |= ascii_downcase) else error("bad") end' "$CONFIG" 2>/dev/null)" \
    || die "status-board --item-kind: kinds_labels in $CONFIG must map label names to feature, incident or vulnerability"
  jq -r --argjson m "$map" '[.labels.nodes[].name | ascii_downcase | $m[.] // empty] | if index("vulnerability") then "vulnerability" elif index("incident") then "incident" else "feature" end' <<<"$GQ_JSON"
}

ghb_url() { gh_issue_q "$1"; jq -r .url <<<"$GQ_JSON"; }

ghb_assoc_ok() { # $1 association → 0 when in the trusted set; dies on a set that names NONE
  local set; set="$(jq -c --argjson d "$GHB_TRUSTED_DEFAULT" '.orchestrate.trusted_associations // $d' "$CONFIG")"
  jq -e 'type == "array" and (index("NONE") | not)' <<<"$set" >/dev/null || die "status-board: orchestrate.trusted_associations must be a list without NONE (got $(safe_label "$set"))"
  jq -e --arg a "$1" 'index($a)' <<<"$set" >/dev/null
}

ghb_trust() { # $1 id → "trusted" (0), "untrusted: <why>" (3); any other non-zero = could not read (FR-007)
  local a au ed err
  gh_issue_q "$1"
  a="$(jq -r '.authorAssociation // "NONE"' <<<"$GQ_JSON")"; au="$(jq -r '.author.login // ""' <<<"$GQ_JSON")"; ed="$(jq -r '.editor.login // ""' <<<"$GQ_JSON")"
  ghb_assoc_ok "$a" || { echo "untrusted: author $(if [ -n "$au" ]; then safe_label "$au"; else echo '(deleted)'; fi) is $(safe_label "$a"), not in orchestrate.trusted_associations"; return 3; }
  [ -n "$ed" ] && [ "$ed" != "$au" ] || { echo trusted; return 0; }
  # GraphQL gives no editor association: an editor other than the author must be a collaborator (204; 404 = not)
  [[ "$ed" =~ ^[A-Za-z0-9-]+$ ]] || die "status-board --item-trust $1: the editor login has an unexpected shape"
  err="$(mktemp)" || die "status-board: mktemp failed"
  if "$GH" api "repos/$GREPO/collaborators/$ed" --silent >/dev/null 2>"$err"; then rm -f "$err"; echo trusted; return 0; fi
  if grep -qF '(HTTP 404)' "$err"; then rm -f "$err"; echo "untrusted: last edited by $ed, who is not a collaborator of $GREPO"; return 3; fi
  rm -f "$err"; die "status-board --item-trust $1: could not check whether $ed is a collaborator of $GREPO"
}

GHB_OWNERKIND=""
ghb_ownerkind() { # → organization|user, for the Project queries
  [ -n "$GHB_OWNERKIND" ] && return 0
  local raw t; raw="$(gql 'query($l:String!){repositoryOwner(login:$l){__typename}}' -F l="$OWNER")" || exit 1
  t="$(jq -r '.data.repositoryOwner.__typename // empty' <<<"$raw")"
  case "$t" in Organization) GHB_OWNERKIND=organization ;; User) GHB_OWNERKIND=user ;; *) die "status-board: no GitHub owner '$OWNER'" ;; esac
}

gh_project_ids() { # → PID, FID, OPTS ({name: option id}) of the Status field
  ghb_ownerkind
  local raw q="query(\$l:String!,\$p:Int!,\$f:String!){owner: $GHB_OWNERKIND(login:\$l){projectV2(number:\$p){id field(name:\$f){... on ProjectV2SingleSelectField{id options{id name}}}}}}"
  raw="$(gql "$q" -F l="$OWNER" -F p="$PROJECT" -F f="$SFIELD")" || exit 1
  PID="$(jq -r '.data.owner.projectV2.id // empty' <<<"$raw")"; [ -n "$PID" ] || die "status-board: Project #$PROJECT not found for $OWNER"
  FID="$(jq -r '.data.owner.projectV2.field.id // empty' <<<"$raw")"; [ -n "$FID" ] || die "status-board: Project #$PROJECT has no single-select field '$(safe_label "$SFIELD")' (status_field)"
  OPTS="$(jq -c '[.data.owner.projectV2.field.options[] | {(.name): .id}] | add // {}' <<<"$raw")"
}

ghb_colname() { # $1 column key → the option name it maps to; refuses an unmapped key
  local n; n="$(jq -r --arg k "$1" --argjson d "$GHB_COLUMNS_DEFAULT" '(.columns // $d)[$k] // empty' "$CONFIG")"
  [ -n "$n" ] || die "status-board: columns.$1 is not set in $CONFIG (the Status option this column is)"
  printf '%s' "$n"
}

ghb_option() { # $1 column key → the option id; refuses a name the Project does not have
  local name opt; name="$(ghb_colname "$1")" || exit 1
  opt="$(jq -r --arg n "$name" '.[$n] // empty' <<<"$OPTS")"
  [ -n "$opt" ] || die "status-board: Project #$PROJECT's $(safe_label "$SFIELD") has no '$(safe_label "$name")' option (columns.$1) — it has: $(jq -r 'keys_unsorted[]' <<<"$OPTS" | safe_labels)"
  printf '%s' "$opt"
}

ghb_list() { # $1 column key → the ids of its items, every page (FR-001)
  local name opt raw more c="" q ids=""
  name="$(ghb_colname "$1")" || exit 1
  gh_project_ids
  opt="$(jq -r --arg n "$name" '.[$n] // empty' <<<"$OPTS")"
  [ -n "$opt" ] || die "status-board --list $1: Project #$PROJECT has no '$(safe_label "$name")' option — it has: $(jq -r 'keys_unsorted[]' <<<"$OPTS" | safe_labels)"
  q="query(\$l:String!,\$p:Int!,\$f:String!,\$c:String){owner: $GHB_OWNERKIND(login:\$l){projectV2(number:\$p){items(first:100, after:\$c){pageInfo{hasNextPage endCursor} nodes{id content{__typename ... on Issue{number repository{nameWithOwner}}} fieldValueByName(name:\$f){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}}}"
  while :; do
    raw="$(gql "$q" -F l="$OWNER" -F p="$PROJECT" -F f="$SFIELD" ${c:+-F c="$c"})" || exit 1
    jq -e '.data.owner.projectV2.items.nodes | type == "array"' <<<"$raw" >/dev/null || die "status-board --list $1: the Project's item page has no nodes"
    # collected, printed only once every page is read: a later failed page must not leave a short list on stdout
    ids+="$(jq -r --arg r "$GREPO" --arg n "$name" --arg p "$PREFIX" '.data.owner.projectV2.items.nodes[] | select(.content.__typename == "Issue" and (.content.repository.nameWithOwner | ascii_downcase) == ($r | ascii_downcase) and .fieldValueByName.name == $n) | "\($p)-\(.content.number)"' <<<"$raw")"$'\n'
    more="$(jq -r '.data.owner.projectV2.items.pageInfo.hasNextPage' <<<"$raw")"; c="$(jq -r '.data.owner.projectV2.items.pageInfo.endCursor // empty' <<<"$raw")"
    [ "$more" = true ] || break
    [ -n "$c" ] || die "status-board --list $1: a page says there is more but gives no cursor"
  done
  printf '%s' "$ids" | sed '/^$/d'
}

GHB_STATES='{"plan":"doing","build":"doing","block":"doing","human_block":"doing","pr":"review","done":"done"}'
ghb_set_status() { # $1 id, $2 state key, $3 note file (optional) → the card in that state's column, then one comment (FR-010)
  local col opt err
  col="$(jq -r --arg s "$2" --argjson m "$GHB_STATES" '$m[$s] // empty' <<<"{}")"
  [ -n "$col" ] || die "status-board --set-status $1: unknown state '$(safe_label "$2")' (expected plan, build, block, human_block, pr or done)"
  [ "$col" != review ] || jq -e '.columns.review // empty' "$CONFIG" >/dev/null || col=doing   # no review column: a PR stays in doing
  gh_issue_q "$1"; gh_project_ids
  opt="$(ghb_option "$col")" || exit 1
  err="$(mktemp)" || die "status-board: mktemp failed"
  "$GH" project item-edit --id "$GQ_ITEM" --project-id "$PID" --field-id "$FID" --single-select-option-id "$opt" >/dev/null 2>"$err" \
    || { local m; m="$(tail -1 "$err" | cut -c1-200)"; rm -f "$err"; die "status-board --set-status $1: gh project item-edit failed: $m — gh auth refresh -s project"; }
  if [ -n "${3:-}" ]; then
    "$GH" issue comment "$(jq -r .url <<<"$GQ_JSON")" --body-file "$3" >/dev/null 2>"$err" \
      || { rm -f "$err"; die "status-board --set-status $1: the card moved to $col but the issue comment failed"; }
  fi
  rm -f "$err"; echo "$1 → $col"
}

ghb_add() { # one new issue in the todo column; prints its id (FR-008)
  local bf="${BODY_FILE:-}" url n id opt err tmp item lbl
  add_title_ok
  gh_project_ids; opt="$(ghb_option todo)" || exit 1          # a board that cannot take the item refuses before any write
  tmp="$(mktemp)" && err="$(mktemp)" || die "status-board: mktemp failed"
  [ -n "$bf" ] || bf="$tmp"
  if [ -n "${ADD_APP:-}" ]; then { [ "$bf" = "$tmp" ] || cat "$bf"; printf 'app: %s\n' "$ADD_APP"; } > "$tmp.app" && mv "$tmp.app" "$tmp" && bf="$tmp"; fi   # #172
  lbl="$(cfg '.incident_label // "bug"')"
  if [ "$ADD_INC" = 1 ]; then url="$("$GH" issue create -R "$GREPO" --title "$ADD_TITLE" --body-file "$bf" --label "$lbl" 2>"$err")"
  else url="$("$GH" issue create -R "$GREPO" --title "$ADD_TITLE" --body-file "$bf" 2>"$err")"; fi \
    || { local m; m="$(tail -1 "$err" | cut -c1-200)"; rm -f "$tmp" "$err"; die "status-board --add: gh issue create failed: $m"; }
  url="$(tail -1 <<<"$url")"
  [[ "$url" =~ ^https://github\.com/[A-Za-z0-9._/-]+/issues/([0-9]+)$ ]] \
    || { rm -f "$tmp" "$err"; die "status-board --add: gh issue create answered '$(safe_label "$url")', not an issue URL — check gh issue list -R $GREPO for a stray issue"; }
  ghb_fail() { rm -f "$tmp" "$err"; die "status-board --add: the issue $url exists but is not on the board: $1"; }
  [ "$(printf '%s' "${url%/issues/*}" | tr '[:upper:]' '[:lower:]')" = "https://github.com/$(printf '%s' "$GREPO" | tr '[:upper:]' '[:lower:]')" ] \
    || ghb_fail "it was created in another repo than $GREPO"
  n="${BASH_REMATCH[1]}"; id="$PREFIX-$n"
  if [ "$ADD_RFC" = 1 ]; then
    { printf 'rfc: %s/%s.md\n' "$(cfg '.orchestrate.rfc_dir // "docs/rfcs"' | sed 's:/*$::')" "$id"; [ -z "${ADD_APP:-}" ] || printf 'app: %s\n' "$ADD_APP"; } > "$tmp"
    "$GH" issue edit "$n" -R "$GREPO" --body-file "$tmp" >/dev/null 2>"$err" || ghb_fail "gh issue edit failed: $(tail -1 "$err" | cut -c1-200)"
  fi
  item="$("$GH" project item-add "$PROJECT" --owner "$OWNER" --url "$url" --format json 2>"$err" | jq -r '.id // empty')"
  [ -n "$item" ] || ghb_fail "gh project item-add failed: $(tail -1 "$err" | cut -c1-200) — gh auth refresh -s project"
  "$GH" project item-edit --id "$item" --project-id "$PID" --field-id "$FID" --single-select-option-id "$opt" >/dev/null 2>"$err" \
    || ghb_fail "its Status could not be set: $(tail -1 "$err" | cut -c1-200)"
  rm -f "$tmp" "$err"; echo "$id"
}

ghb_projects() { # $1 owner/name → [{number, title, owner}] of the Projects linked to that repo (for --detect)
  [[ "$1" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || return 1
  local raw; raw="$(gql 'query($o:String!,$r:String!){repository(owner:$o,name:$r){projectsV2(first:20){nodes{number title owner{... on Organization{login} ... on User{login}}}}}}' -F o="${1%%/*}" -F r="${1##*/}")" || return 1
  jq -ce '[.data.repository.projectsV2.nodes[] | {number, title, owner: .owner.login}]' <<<"$raw"
}

ghb_scope_check() { # --check: reads need read:project; --add and publish write, and need project (FR-012)
  if "$GH" auth status 2>&1 | grep -qF "'project'"; then ok "gh token has the project scope (--add and ledger.sh publish write to the Project)"
  elif [ "$MODE" = check ]; then printf '  [warn]    gh token lacks the project scope: --add and ledger.sh publish cannot write — gh auth refresh -s project\n'; fi
}

ghb_check_config() { # --check on a github board: the lane config and every mapped column (code review 2026-11-04)
  [ "$MODE" = check ] || return 0
  if [ -z "$(cfg '.repo // empty')" ] || [ -z "$(cfg '.id_prefix // empty')" ]; then
    printf '  [warn]    no "repo" and "id_prefix": this board serves /hefesto:hef.status only, not the lanes (docs/install.md §14)\n'; return 0
  fi
  local res st k n o
  SFIELD="$(cfg '.status_field // "Status"')"   # read here: what the subshell sets never reaches the report lines
  res="$( (ghb_config; gh_project_ids
    while IFS= read -r k; do
      n="$(ghb_colname "$k")" || exit 1
      if jq -e --arg n "$n" 'has($n)' <<<"$OPTS" >/dev/null; then printf 'ok\t%s\t%s\n' "$k" "$n"
      else printf 'miss\t%s\t%s\t%s\n' "$k" "$n" "$(jq -r 'keys_unsorted[]' <<<"$OPTS" | safe_labels)"; fi
    done < <(jq -r --argjson d "$GHB_COLUMNS_DEFAULT" '(.columns // $d) | keys_unsorted[]' "$CONFIG")) 2>&1)" || { miss "the lane config: $(tail -1 <<<"$res")"; return 0; }
  while IFS=$'\t' read -r st k n o; do
    case "$st" in
      ok) ok "column $k = '$(safe_label "$n")' is a $(safe_label "$SFIELD") option" ;;
      miss) miss "column $k = '$(safe_label "$n")' is not a $(safe_label "$SFIELD") option of Project #$PROJECT" "use one of: $o" ;;
    esac
  done <<<"$res"
}
