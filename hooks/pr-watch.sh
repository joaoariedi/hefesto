#!/bin/bash
# pr-watch.sh — the mechanical half of /hef.babysit: a FETCHER over `gh` + `jq` that watches ONE
# pull request up to the human merge gate. Design and evidence: reports/18 #2 and addendum A2
# (each CI failure −15 % merge odds, reviewer abandonment 38 % — report 17 §1f); spec
# .specify/specs/pr-babysitter/.
#
#   --check                                  gh (authenticated), jq, timeout, a remote — names the first missing item
#   resolve [<pr>] [--local]                 the PR as JSON; refuses closed, head=main, head=base, wrong or stale checkout
#   checks <pr> [--wait s] [--after sha]     {"state":pass|fail|pending,…} from the check BUCKETS; --wait blocks in
#                                            `gh pr checks --watch` (no model turns while CI runs); --after waits for
#                                            the pushed sha to register a check first; --wait is the call's total budget
#   failed-log <pr> --run <id> [--tail N]    the failed job log to <git-common-dir>/hefesto/pr-watch/, path + tail
#   threads <pr>                             unresolved review threads + new issue comments, every body STRIPPED of
#                                            HTML comments and wrapped in per-call nonce delimiters (untrusted data)
#   reply <pr> --thread <id> --body-file f   post a thread reply (marker appended, gitleaks-scanned when present)
#   comment <pr> --body-file f               post an issue comment (same)
#   state <pr>                               the PR fields + verdict: mergeable|conflict|checks|review|pending|closed
#   ledger-id <pr-url>                       the ledger entry recording the PR; exit 3 = none, 1 = ledger unreadable
#   in-diff <pr> <path>…                     exit 0 only when every path is in the PR's diff and none is CI config
#   fixes <pr>                               how many fixes the babysitter already pushed (its own marker comments)
#
# What this file deliberately has NO code path for: merging, approving, enabling auto-merge, force-pushing,
# pushing main, resolving a review thread. tests/smoke.sh asserts that statically on the non-comment lines.
#
# FETCHER contract (speckit-helper.sh): the answer on stdout at exit 0; the offending value and the expected
# shape on stderr at non-zero. No exit-0 sentinel (constitution 5). Usage errors exit 2. Zero-install:
# bash, jq, git, coreutils `timeout` (or `gtimeout`); `gh` and `gitleaks` detected, never installed.
# HEFESTO_GH_BIN overrides the gh binary (the test seam, like HEFESTO_LEDGER_DIR).
set -uo pipefail

die() { echo "$*" >&2; exit 1; }
usage() { sed -n '/^#   --check/,/^#   fixes/p' "$0" | sed 's/^#   /  /' >&2; echo "usage: pr-watch.sh <subcommand> …" >&2; exit 2; }

GH="${HEFESTO_GH_BIN:-gh}"
MARKER='_hef.babysit_'
FIX_RE='^fixed in [0-9a-f]{7,40}'
CI_CONFIG_RE='^(\.github/|\.gitlab-ci\.yml$|\.circleci/|Jenkinsfile$|azure-pipelines\.yml$)'
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Every temp file or dir this run creates is listed here and removed on exit — a reply body waiting to be
# posted must not outlive the call (quality gate 2026-09-30).
PW_TMP=(); trap 'rm -rf "${PW_TMP[@]}"' EXIT
tmpf() { local t; t="$(mktemp)"; PW_TMP+=("$t"); echo "$t"; }
tmpd() { local t; t="$(mktemp -d)"; PW_TMP+=("$t"); echo "$t"; }

# --- git, with the same fallback ledger.sh carries: the eval sandbox denies the git BINARY ------------
have_git() { git rev-parse --git-dir >/dev/null 2>&1; }
git_dir() {
  local d; d=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) && [ -n "$d" ] && { echo "$d"; return 0; }
  [ -d "$PWD/.git" ] && { echo "$PWD/.git"; return 0; }
  die "pr-watch: not a git repository ($PWD)"
}
common_dir() {
  local d; d=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && [ -n "$d" ] && { echo "$d"; return 0; }
  git_dir
}
remote_ok() {
  local r; r=$(git remote 2>/dev/null) && [ -n "$r" ] && return 0
  grep -q '^\[remote "' "$(git_dir)/config" 2>/dev/null
}
current_branch() {
  local b; b=$(git branch --show-current 2>/dev/null) && [ -n "$b" ] && { echo "$b"; return 0; }
  sed -n 's#^ref: refs/heads/##p' "$(git_dir)/HEAD"
}

need() {
  command -v "$GH" >/dev/null 2>&1 || die "pr-watch: gh not found — install GitHub CLI (https://cli.github.com) or set HEFESTO_GH_BIN"
  local auth; auth=$("$GH" auth status 2>&1) || die "pr-watch: gh auth status failed — a login (gh auth login) or, under the sandbox, api.github.com not granted: $(tail -1 <<<"$auth")"
  command -v jq >/dev/null 2>&1 || die "pr-watch: jq not found — install jq: https://jqlang.org"
  TIMEOUT="$(command -v timeout || command -v gtimeout)" || die "pr-watch: timeout not found — coreutils on Linux, 'brew install coreutils' (gtimeout) on macOS"
  remote_ok || die "pr-watch: no git remote in $(git_dir)/config — add one: git remote add origin <url>"
}

# Untrusted text: strip HTML comments and wrap in per-call nonce delimiters BEFORE any model reads it —
# the status-board.sh --item rule (a hidden instruction never reaches the babysitter). The first sed
# removes any closed comment, including one containing `>` (status-board's `[^>]*` would leave it to the
# second pass, which deletes whole lines to the END of the body — code review 2026-09-30); the second
# pass still drops an UNCLOSED comment to the end, which loses text but never leaks it.
sanitise() { # $1 label; body on stdin
  local body nonce; body=$(cat)
  nonce="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8)"
  printf '<<<untrusted-begin %s %s\n%s\nuntrusted-end %s>>>\n' "$1" "$nonce" "$(sed -E 's/<!--([^-]|-[^-])*-->//g' <<<"$body" | sed '/<!--/,/-->/d')" "$nonce"
}
# Header fields (path, login) are contributor-controlled too; outside the delimiters they get a safe charset.
safe() { tr -cd 'A-Za-z0-9._/@:#-' <<<"$1" | head -c 200; }

pr_json() { # $1 pr or ""
  local out
  out=$("$GH" pr view ${1:+"$1"} --json number,url,headRefName,baseRefName,headRefOid,state,isDraft 2>&1) \
    || die "pr-watch resolve: no pull request${1:+ $1} for this branch — open one with /hef.pr ($(tail -1 <<<"$out"))"
  printf '%s' "$out"
}

# --- checks: the buckets are the answer, never the exit code (gh exits 8 while pending, 1 on a failure, and prints JSON either way)
checks_json() { # $1 pr → the raw array; "no checks reported" → []
  local err out; err="$(tmpf)"; out="$("$GH" pr checks "$1" --json name,bucket,link,workflow 2>"$err")"
  if [ -z "$out" ]; then
    if grep -qi 'no checks reported' "$err"; then out='[]'; else die "pr-watch checks $1: $(cat "$err")"; fi
  fi
  printf '%s' "$out"
}
checks_state() { # $1 waited (true|false); array on stdin. cancel counts as a failure: nothing will turn it green.
  jq -c --argjson w "$1" '{state: (if any(.[]; .bucket=="fail" or .bucket=="cancel") then "fail" elif any(.[]; .bucket=="pending") then "pending" else "pass" end),
    checks: length, waited: $w,
    failed: [.[] | select(.bucket=="fail" or .bucket=="cancel") | {name, run_id: (((.link // "") | capture("runs/(?<r>[0-9]+)").r) // null), url: .link}]}'
}
# --after: a workflow registers 10–60 s after a push; until a check exists, "no checks" would read as green.
# Prints the seconds consumed and returns 0 once the sha is the head and a check exists; returns 2 when the
# grace runs out with no check (the caller answers `pending`); dies when the head moved to another sha.
wait_after() { # $1 pr, $2 sha
  local grace step t0 oid cj n
  grace="${HEFESTO_PR_WATCH_GRACE:-90}"; [[ "$grace" =~ ^[0-9]+$ ]] || die "pr-watch checks: HEFESTO_PR_WATCH_GRACE must be seconds (got '$grace')"
  step=5; [ "$grace" -lt 5 ] && step=1; t0=$(date +%s)
  while :; do
    oid=$("$GH" pr view "$1" --json headRefOid --jq .headRefOid 2>/dev/null) || die "pr-watch checks $1: gh pr view failed while waiting for $2"
    cj=$(checks_json "$1") || exit 1; n=$(jq length <<<"$cj")
    [ "$oid" = "$2" ] && [ "$n" -gt 0 ] && { echo $(( $(date +%s) - t0 )); return 0; }
    if [ $(( $(date +%s) - t0 )) -ge "$grace" ]; then
      [ "$oid" = "$2" ] || die "pr-watch checks $1: head is $oid, expected $2 — someone else pushed; run resolve again"
      return 2
    fi
    sleep "$step"
  done
}
cmd_checks() {
  local pr="$1" w="" after="" waited=false used=0 rc; shift
  while [ $# -gt 0 ]; do case "$1" in --wait) w="${2:-}"; shift ;; --after) after="${2:-}"; shift ;; *) usage ;; esac; shift; done
  if [ -n "$after" ]; then
    used=$(wait_after "$pr" "$after"); rc=$?
    case "$rc" in
      0) ;;
      2) printf '{"state":"pending","checks":0,"waited":%s,"failed":[],"note":"no check registered for %s within %ss"}\n' \
           "$( [ -n "$w" ] && echo true || echo false )" "$after" "${HEFESTO_PR_WATCH_GRACE:-90}"; exit 0 ;;
      *) exit "$rc" ;;
    esac
  fi
  if [ -n "$w" ]; then
    [[ "$w" =~ ^[0-9]+$ ]] || die "pr-watch checks: --wait takes seconds (got '$w')"
    waited=true; w=$(( w - used ))
    # The wait is the whole point: the model spends no turns while CI runs. 124 = budget spent, just stop waiting.
    [ "$w" -gt 0 ] && "$TIMEOUT" "$w" "$GH" pr checks "$pr" --watch --fail-fast >/dev/null 2>&1
  fi
  local cj; cj=$(checks_json "$pr") || exit 1
  checks_state "$waited" <<<"$cj"
}

cmd_failed_log() {
  local pr="$1" run="" tail_n=120 dir f; shift
  while [ $# -gt 0 ]; do case "$1" in --run) run="${2:-}"; shift ;; --tail) tail_n="${2:-}"; shift ;; *) usage ;; esac; shift; done
  [ -n "$run" ] || usage
  dir="$(common_dir)/hefesto/pr-watch"; mkdir -p "$dir" || die "pr-watch failed-log: cannot create $dir"
  f="$dir/$pr-$run.log"
  "$GH" run view "$run" --log-failed > "$f" 2>"$f.err" || die "pr-watch failed-log: gh run view $run --log-failed failed: $(tail -1 "$f.err")"
  echo "$f"; tail -n "$tail_n" "$f"
}

# --- threads + issue comments, fetched once into ALL = {threads: […], issue: […]} --------------------
fetch_all() { # $1 pr
  local rv owner name q tj ic
  rv=$("$GH" repo view --json owner,name 2>&1) || die "pr-watch: gh repo view failed: $rv"
  owner=$(jq -r .owner.login <<<"$rv"); name=$(jq -r .name <<<"$rv")
  q='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){reviewThreads(first:100){pageInfo{hasNextPage} nodes{id isResolved path line comments(first:50){pageInfo{hasNextPage} nodes{author{login} body createdAt url}}}}}}}'
  tj=$("$GH" api graphql -f query="$q" -f owner="$owner" -f name="$name" -F number="$1" 2>&1) || die "pr-watch threads $1: gh api graphql failed: $tj"
  jq -e '.data.repository.pullRequest.reviewThreads.nodes' >/dev/null 2>&1 <<<"$tj" || die "pr-watch threads $1: unexpected GraphQL shape: $(head -c 200 <<<"$tj")"
  [ "$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' <<<"$tj")" = false ] \
    || die "pr-watch threads $1: more than 100 review threads — the babysitter stops here; handle the PR by hand"
  [ "$(jq -r '[.data.repository.pullRequest.reviewThreads.nodes[].comments.pageInfo.hasNextPage] | any' <<<"$tj")" = false ] \
    || die "pr-watch threads $1: a thread has more than 50 comments — handle it by hand"
  ic=$("$GH" api "repos/$owner/$name/issues/$1/comments" --paginate --slurp 2>&1) || die "pr-watch threads $1: gh api issues/$1/comments failed: $ic"
  ALL=$(jq -n --argjson t "$tj" --argjson i "$ic" '{threads: $t.data.repository.pullRequest.reviewThreads.nodes, issue: ($i | flatten)}') \
    || die "pr-watch threads $1: could not combine the thread and comment payloads"
}
cmd_threads() {
  local pr="$1" last b t
  fetch_all "$pr"
  # The babysitter's own words end with the marker: a thread it answered last is skipped; an issue comment
  # older than the babysitter's last ANSWER on the issue thread was already seen. A fix notice
  # ("fixed in … (check …)") is not an answer — it must not hide the comments that arrived before it
  # (code review 2026-09-30). Both filters are what make a pass idempotent.
  last=$(jq -r --arg m "$MARKER" --arg re "$FIX_RE" '[.issue[] | select((.body // "") | contains($m)) | select(((.body // "") | split("\n")[0] | test($re)) | not) | .created_at] | max // ""' <<<"$ALL")
  jq -r --arg m "$MARKER" '.threads[] | select(.isResolved | not) | select((.comments.nodes | length) > 0) | select((.comments.nodes | last | (.body // "") | contains($m)) | not) | @base64' <<<"$ALL" \
  | while IFS= read -r b; do
      t=$(base64 -d <<<"$b")
      printf 'thread %s %s:%s %s %s comments=%s\n' "$(safe "$(jq -r .id <<<"$t")")" "$(safe "$(jq -r '.path // "-"' <<<"$t")")" "$(safe "$(jq -r '.line // "-"' <<<"$t")")" \
        "$(safe "$(jq -r '.comments.nodes[0].author.login // "?"' <<<"$t")")" "$(safe "$(jq -r '.comments.nodes | last | .createdAt' <<<"$t")")" "$(jq -r '.comments.nodes | length' <<<"$t")"
      jq -r '.comments.nodes[] | "-- \(.author.login // "?") \(.createdAt)\n\(.body // "")"' <<<"$t" | sanitise "$pr"
    done
  jq -r --arg m "$MARKER" --arg last "$last" '.issue[] | select(((.body // "") | contains($m)) | not) | select(.created_at > $last) | @base64' <<<"$ALL" \
  | while IFS= read -r b; do
      t=$(base64 -d <<<"$b")
      printf 'comment %s %s %s\n' "$(safe "$(jq -r .html_url <<<"$t")")" "$(safe "$(jq -r '.user.login // "?"' <<<"$t")")" "$(safe "$(jq -r .created_at <<<"$t")")"
      jq -r '.body // ""' <<<"$t" | sanitise "$pr"
    done
}
cmd_fixes() {
  fetch_all "$1"
  jq -r --arg m "$MARKER" --arg re "$FIX_RE" '[.threads[].comments.nodes[].body, .issue[].body] | map((. // "") | select(contains($m)) | split("\n")[0] | select(test($re))) | length' <<<"$ALL"
}

# --- the only two write calls in the file --------------------------------------------------------------
post() { # $1 pr, $2 thread id or "", $3 body file
  [ -f "$3" ] || die "pr-watch: body file '$3' not found"
  local d url; d="$(tmpd)"; { cat "$3"; printf '\n\n%s\n' "$MARKER"; } > "$d/body.md"
  # CSA's recommendation after Comment-and-Control (report 17 §5e): scan agent-posted content before publication.
  if command -v gitleaks >/dev/null 2>&1; then
    gitleaks detect --no-git --source "$d" --no-banner >/dev/null 2>&1 || die "pr-watch: refused — gitleaks found a secret in $3; nothing posted"
  fi
  if [ -n "$2" ]; then
    # -f, never -F: -F reads @path as a file and coerces numbers, so a reply starting "@reviewer" would fail.
    url=$("$GH" api graphql -f query='mutation($t:ID!,$b:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$t,body:$b}){comment{url}}}' \
          -f t="$2" -f b="$(cat "$d/body.md")" --jq '.data.addPullRequestReviewThreadReply.comment.url' 2>&1) || die "pr-watch reply $1: gh api failed: $url"
  else
    url=$("$GH" pr comment "$1" --body-file "$d/body.md" 2>&1) || die "pr-watch comment $1: gh pr comment failed: $url"
  fi
  echo "$url"
}
cmd_post() { # $1 reply|comment, $2 pr, rest
  local kind="$1" pr="$2" thread="" body=""; shift 2
  while [ $# -gt 0 ]; do case "$1" in --thread) thread="${2:-}"; shift ;; --body-file) body="${2:-}"; shift ;; *) usage ;; esac; shift; done
  [ -n "$body" ] || usage
  [ "$kind" = reply ] && { [ -n "$thread" ] || usage; }
  [ "$kind" = comment ] && thread=""
  post "$pr" "$thread" "$body"
}

cmd_state() {
  local pr="$1" ckj ck cn view
  ckj=$(checks_json "$pr" | checks_state false) || exit 1; ck=$(jq -r .state <<<"$ckj"); cn=$(jq -r .checks <<<"$ckj")
  view=$("$GH" pr view "$pr" --json number,url,state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefName,baseRefName,headRefOid 2>&1) \
    || die "pr-watch state $pr: gh pr view failed: $(tail -1 <<<"$view")"
  jq -c --arg ck "$ck" --argjson cn "$cn" '. + {checks: $ck, verdict: (
      if .state != "OPEN" then "closed"
      elif .mergeStateStatus == "DIRTY" then "conflict"
      elif $ck == "fail" then "checks"
      elif $ck == "pending" or .mergeStateStatus == "UNKNOWN" or (.mergeStateStatus == "BLOCKED" and $cn == 0) then "pending"
      elif .isDraft then "review"
      elif .mergeStateStatus == "CLEAN" or .mergeStateStatus == "BEHIND" or .mergeStateStatus == "HAS_HOOKS" then "mergeable"
      elif .mergeStateStatus == "UNSTABLE" then "checks"
      elif .mergeStateStatus == "BLOCKED" then "review"
      else "pending" end)}' <<<"$view" || die "pr-watch state $pr: gh pr view returned something jq could not read: $(head -c 200 <<<"$view")"
}

cmd_resolve() {
  local pr="" local_=0 out state head base oid cur rc bm push p
  while [ $# -gt 0 ]; do case "$1" in --local) local_=1 ;; -*) usage ;; *) pr="$1" ;; esac; shift; done
  out=$(pr_json "$pr") || exit 1
  state=$(jq -r .state <<<"$out"); head=$(jq -r .headRefName <<<"$out"); base=$(jq -r .baseRefName <<<"$out"); oid=$(jq -r .headRefOid <<<"$out")
  [ "$state" = OPEN ] || die "pr-watch resolve: PR #$(jq -r .number <<<"$out") is $state, expected OPEN — nothing to babysit"
  case "$head" in main|master) die "pr-watch resolve: the PR's head branch is '$head' — the babysitter never works on $head" ;; esac
  [ "$head" != "$base" ] || die "pr-watch resolve: head and base are both '$head' — not a pull request the babysitter can fix"
  # branch-model FR-005: a head in the protected set (a promotion PR, e.g. stg → main) is WATCHED, never
  # fixed — push:false, and no local checkout is required because no commit will be made.
  bm=$(bash "$HERE/ledger.sh" branches) || die "pr-watch resolve: ledger.sh branches failed — fix .branches in .claude/project-status.json"
  push=true
  while IFS= read -r p; do
    # shellcheck disable=SC2254  # the pattern IS a glob, on purpose (release/*)
    case "$head" in $p) push=false ;; esac
  done < <(jq -r '.protected[]' <<<"$bm")
  out=$(jq -c --argjson push "$push" '. + {push: $push}' <<<"$out") || die "pr-watch resolve: cannot add the push flag"
  if [ "$local_" = 1 ] && [ "$push" = true ]; then
    cur=$(current_branch)
    [ "$cur" = "$head" ] || die "pr-watch resolve: the local checkout is on '${cur:-<detached>}', the PR head is '$head' — git switch $head"
    if have_git; then
      # No fetch: the transport may be closed to the sandbox. The API-supplied sha against local objects decides;
      # rc 1 = behind or diverged, rc 128 = sha absent locally — both mean the fix would land on a stale base.
      git merge-base --is-ancestor "$oid" HEAD 2>/dev/null; rc=$?
      [ "$rc" -eq 0 ] || die "pr-watch resolve: the local checkout is behind the PR head $oid (merge-base rc=$rc) — git pull --ff-only"
    else
      echo "pr-watch resolve: git unavailable — ancestry of $oid not verified" >&2
    fi
  fi
  echo "$out"
}

cmd_ledger_id() {
  local all id
  all=$(bash "$HERE/ledger.sh" list) || die "pr-watch ledger-id: ledger.sh list failed"
  id=$(jq -r --arg u "$1" '.[] | select(.pr.url == $u) | .id' <<<"$all" | head -1) || die "pr-watch ledger-id: ledger.sh list returned invalid JSON"
  [ -n "$id" ] || { echo "pr-watch ledger-id: no ledger entry records $1" >&2; exit 3; }
  echo "$id"
}

cmd_in_diff() {
  local pr="$1" out base changed bad="" p; shift
  [ $# -gt 0 ] || usage
  out=$(pr_json "$pr") || exit 1; base=$(jq -r .baseRefName <<<"$out")
  have_git || die "pr-watch in-diff: git unavailable — the diff cannot be computed"
  changed=$(git diff --name-only "origin/$base...HEAD" 2>/dev/null) || changed=$(git diff --name-only "$base...HEAD" 2>/dev/null) \
    || die "pr-watch in-diff: git diff $base...HEAD failed — is '$base' fetched?"
  for p in "$@"; do
    if [[ "$p" =~ $CI_CONFIG_RE ]]; then bad+="  $p: CI configuration is never a babysitter fix"$'\n'; continue; fi
    grep -qxF -- "$p" <<<"$changed" || bad+="  $p: not in git diff $base...HEAD (the babysitter edits only what the PR already touches)"$'\n'
  done
  [ -z "$bad" ] || { printf 'pr-watch in-diff #%s refused:\n%s' "$pr" "$bad" >&2; exit 1; }
  echo "in-diff ok: $# path(s) inside the PR's diff"
}

SUB="${1:-}"; [ -n "$SUB" ] || usage; shift
case "$SUB" in
  --check)     need; echo "pr-watch: gh authenticated · jq · $TIMEOUT · remote ok" ;;
  resolve)     need; cmd_resolve "$@" ;;
  checks)      need; [ -n "${1:-}" ] || usage; cmd_checks "$@" ;;
  failed-log)  need; [ -n "${1:-}" ] || usage; cmd_failed_log "$@" ;;
  threads)     need; [ -n "${1:-}" ] || usage; cmd_threads "$1" ;;
  fixes)       need; [ -n "${1:-}" ] || usage; cmd_fixes "$1" ;;
  reply|comment) need; [ -n "${1:-}" ] || usage; cmd_post "$SUB" "$@" ;;
  state)       need; [ -n "${1:-}" ] || usage; cmd_state "$1" ;;
  ledger-id)   need; [ -n "${1:-}" ] || usage; cmd_ledger_id "$1" ;;
  in-diff)     need; [ -n "${1:-}" ] || usage; cmd_in_diff "$@" ;;
  *) usage ;;
esac
