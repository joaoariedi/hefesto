# shellcheck shell=bash
# plan-review-lib.sh — the plan-review round loop (HEF-21, .specify/specs/plan-review-rounds).
#
# SOURCED, never run: by speckit-helper.sh's `plan-review-round` arm (prr_main) and by session-launch.sh's `plan` arm
# (cap validation, the open segment's cap on a retry, the question-file tail). Sourced lazily inside those arms, never
# at file top, so the test mirrors with fixed sibling lists keep working.
#
# The log is <spec dir>/plan-review.md, append-only:
#   ## Segment — <first review|person revision|person answer|person review|lane review> — <YYYY-MM-DD> — cap <N>
#   ## Round <n> — <YYYY-MM-DD> — <APPROVE|REVISE_PLAN|NEEDS_DISCUSSION>
#   decision: yes|no
#   <findings verbatim>
# The round counter is the number of `## Round ` lines after the last `## Segment ` line; the cap is that line's number.
# Why a helper at all: the rule used to be prompt prose ("a second REVISE_PLAN"), which no smoke test can check
# (constitution 3). The per-round decision is made here, deterministically, and the prompts say "do what it prints".

PRR_LOG_NAME=plan-review.md

prr_die() { echo "plan-review-round: $*" >&2; exit 1; }

# The idiom of arena-run.sh:45 — every launched worker runs with HEFESTO_WORKER=1 (session-launch.sh).
prr_worker() { [ -n "${HEFESTO_WORKER:-}" ] && [ "$HEFESTO_WORKER" != 0 ]; }

# prr_next_action <verdict> <decision 0|1> <round n> <cap> <bound 0|1> → approve | revise | block decision | block cap
# A decision outranks the cap. bound=0 in a `person review` segment: the cap never binds a person's own run.
prr_next_action() {
  case "$1" in APPROVE) echo approve; return ;; NEEDS_DISCUSSION) echo "block decision"; return ;; esac
  [ "$2" = 1 ] && { echo "block decision"; return; }
  [ "$5" = 1 ] && [ "$3" -ge "$4" ] && { echo "block cap"; return; }
  echo revise
}

# An integer from 1 to 20. 0 means "never review" (that is plan_review's job); the upper bound stops a typo becoming
# an unbounded spend. A regex first: `[ "2.5" -ge 1 ]` is an error, not a no.
prr_cap_valid() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$((10#$1))" -ge 1 ] && [ "$((10#$1))" -le 20 ]; }

prr_rounds_in_segment() { [ -f "$1" ] || { echo 0; return; }; awk '/^## Segment /{n=0} /^## Round /{n++} END{print n+0}' "$1"; }
# cap and kind parse the SAME line the awk counters reset on: the last `## Segment ` line. If that line does not parse,
# both print nothing and prr_main refuses (a malformed later header must not let an earlier segment's cap pair with
# the malformed segment's rounds).
prr_last_segment() { grep '^## Segment ' "$1" 2>/dev/null | tail -1; }
prr_segment_cap()  { prr_last_segment "$1" | sed -n 's/^## Segment .* — cap \([0-9][0-9]*\)$/\1/p'; }
prr_segment_kind() { prr_last_segment "$1" | sed -n 's/^## Segment — \(.*\) — [0-9-]* — cap [0-9][0-9]*$/\1/p'; }
# exit 0 when the open segment's last round is NEEDS_DISCUSSION or carries `decision: yes`
prr_segment_blocked() {
  [ -f "$1" ] || return 1
  awk '/^## Segment /{b=0} /^## Round /{b=($NF=="NEEDS_DISCUSSION")} /^decision: yes$/{b=1} END{exit !b}' "$1" 2>/dev/null
}
prr_open_segment() { # log kind cap — appends a segment header (and the file's title when it is new)
  [ -f "$1" ] || printf '# Plan review log — %s\n<!-- appended by speckit-helper.sh plan-review-round; never edit by hand -->\n' \
    "$(basename "$(dirname "$1")")" > "$1"
  printf '\n## Segment — %s — %s — cap %s\n' "$2" "$(date +%F)" "$3" >> "$1"
}

# A person's input opens a segment (FR-008); the round counter restarts there. Idempotent for a retry after a failed
# run, which is handed the same input again: the same kind on an empty segment appends nothing; `review` is a no-op
# while a `person review` segment is open and its last round did not block.
prr_person_input() { # log kind cap
  [ "$2" = review ] && prr_worker && prr_die "--person-input review runs from a person's session, never inside a launched worker"
  if [ "$(prr_segment_kind "$1")" = "person $2" ]; then
    case "$2" in
      review) prr_segment_blocked "$1" || { echo segment; return; } ;;
      *)      [ "$(prr_rounds_in_segment "$1")" = 0 ] && { echo segment; return; } ;;
    esac
  fi
  prr_open_segment "$1" "person $2" "$3"; echo segment
}

prr_usage() { prr_die "$1 — usage: plan-review-round (--verdict APPROVE|REVISE_PLAN|NEEDS_DISCUSSION [--decision] [--findings-file f] | --person-input revision|answer|review) [--spec-dir d] [--cap N]"; }

prr_parse_args() { # sets PRR_VERDICT PRR_DEC PRR_FF PRR_PI PRR_SD PRR_CAP_FLAG; refuses before anything is touched
  PRR_VERDICT=""; PRR_DEC=0; PRR_FF=""; PRR_PI=""; PRR_SD=""; PRR_CAP_FLAG=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --decision) PRR_DEC=1; shift; continue ;;
      --verdict|--findings-file|--person-input|--spec-dir|--cap) [ $# -ge 2 ] || prr_usage "$1 needs a value" ;;
      *) prr_usage "unknown argument '$1'" ;;
    esac
    case "$1" in
      --verdict) PRR_VERDICT="$2" ;; --findings-file) PRR_FF="$2" ;; --person-input) PRR_PI="$2" ;;
      --spec-dir) PRR_SD="$2" ;; --cap) PRR_CAP_FLAG="$2" ;;
    esac
    shift 2
  done
  [ -n "$PRR_VERDICT" ] && [ -n "$PRR_PI" ] && prr_usage "--verdict and --person-input are exclusive"
  [ -z "$PRR_VERDICT" ] && [ -z "$PRR_PI" ] && prr_usage "one of --verdict or --person-input is required"
  [ -z "$PRR_VERDICT" ] || case "$PRR_VERDICT" in APPROVE|REVISE_PLAN|NEEDS_DISCUSSION) ;; *) prr_usage "--verdict '$PRR_VERDICT' is not one of APPROVE, REVISE_PLAN, NEEDS_DISCUSSION" ;; esac
  [ -z "$PRR_PI" ] || case "$PRR_PI" in revision|answer|review) ;; *) prr_usage "--person-input '$PRR_PI' is not one of revision, answer, review" ;; esac
  [ -z "$PRR_PI" ] || { [ -z "$PRR_FF" ] && [ "$PRR_DEC" = 0 ]; } || prr_usage "--findings-file and --decision go with --verdict, not --person-input"
  [ -z "$PRR_CAP_FLAG" ] || prr_cap_valid "$PRR_CAP_FLAG" || prr_die "plan_review_rounds must be an integer from 1 to 20 — got '$PRR_CAP_FLAG'"
}

# The spec dir must resolve under <spec root>/.specify/specs/ (cwd = the spec root: speckit-helper.sh cds there), so
# the absolute path a lane sends and the relative one a person types are both accepted, and nothing else is.
prr_check_spec_dir() { # sets PRR_SDR (the real path) and PRR_LOGF
  local base
  [ -n "$PRR_SD" ] || PRR_SD=".specify/specs/${BRANCH:-}"
  base="$(cd .specify/specs 2>/dev/null && pwd -P)" || prr_die "no .specify/specs/ under the spec root $PWD"
  PRR_SDR="$(cd "$PRR_SD" 2>/dev/null && pwd -P)" || prr_die "spec dir $PRR_SD does not exist"
  [ "${PRR_SDR#"$base/"}" != "$PRR_SDR" ] || prr_die "spec dir $PRR_SD resolves to $PRR_SDR, outside $base/"
  [ -f "$PRR_SDR/plan.md" ] || prr_die "spec dir $PRR_SD has no plan.md — run /hefesto:hef.plan first"
  PRR_LOGF="$PRR_SDR/$PRR_LOG_NAME"
  [ -L "$PRR_LOGF" ] && prr_die "$PRR_LOGF is a symlink — the review log is a plain file"
  [ ! -e "$PRR_LOGF" ] || [ -r "$PRR_LOGF" ] || prr_die "$PRR_LOGF is not readable"
}

# FR-003 order: explicit --cap; the open segment's cap; orchestrate.plan_review_rounds at the git top; 5.
prr_resolve_cap() { # sets PRR_CAP
  local top cf
  PRR_CAP="$PRR_CAP_FLAG"
  [ -n "$PRR_CAP" ] || PRR_CAP="$(prr_segment_cap "$PRR_LOGF")"
  if [ -z "$PRR_CAP" ]; then
    top="$(git rev-parse --show-toplevel 2>/dev/null)"; cf="${top:-.}/.claude/project-status.json"
    PRR_CAP=5
    [ ! -f "$cf" ] || PRR_CAP="$(jq -r '.orchestrate.plan_review_rounds | if . == null then "5" elif type == "number" then tostring else "not a number: " + tojson end' "$cf" 2>/dev/null)" \
      || prr_die "$cf is not valid JSON"
  fi
  prr_cap_valid "$PRR_CAP" || prr_die "plan_review_rounds must be an integer from 1 to 20 — got '$PRR_CAP'"
}

# The findings file is read into a variable and removed first, so every later refusal still consumes it (the headless
# planner has no rm). Only a regular file inside the spec dir is ever removed.
prr_consume_findings() { # sets PRR_FX
  local ff="$PRR_FF"; PRR_FX=""
  [ -n "$ff" ] || return 0
  [ -f "$ff" ] && [ ! -L "$ff" ] || prr_die "--findings-file $ff must be a regular file, not a symlink"
  [ "$(cd "$(dirname "$ff")" 2>/dev/null && pwd -P)" = "$PRR_SDR" ] || prr_die "--findings-file $ff must be inside $PRR_SD"
  PRR_FX="$(cat -- "$ff")"; rm -f -- "$ff"
  ! grep -qE '^(## (Round|Segment) |decision: )' <<<"$PRR_FX" \
    || prr_die "--findings-file $ff holds a '## Round'/'## Segment'/'decision:' line — findings cannot forge a log line"
}

prr_record_round() { # the verdict path: every refusal before the first byte is written; then append; then print
  local log="$PRR_LOGF" cap="$PRR_CAP" bound n act dec="$PRR_DEC"
  prr_worker && [ -z "$PRR_CAP_FLAG" ] && prr_die "inside a launched worker the cap is the launcher's — pass --cap; a person review runs from a person's session"
  prr_segment_blocked "$log" && prr_die "round $(prr_rounds_in_segment "$log") blocked on a decision — a person's input (revision, answer or review) reopens recording"
  [ -z "$(prr_last_segment "$log")" ] || [ -n "$(prr_segment_cap "$log")" ] \
    || prr_die "$log: the last '## Segment' line does not parse as '## Segment — <kind> — <date> — cap N' — the log was edited by hand"
  if [ -z "$(prr_segment_cap "$log")" ]; then
    [ "$(prr_rounds_in_segment "$log")" = 0 ] || prr_die "$log has rounds but no '## Segment … — cap N' header — the log was edited by hand"
    prr_open_segment "$log" "first review" "$cap"
  elif [ "$(prr_segment_kind "$log")" = "person review" ] && [ -n "$PRR_CAP_FLAG" ]; then
    prr_open_segment "$log" "lane review" "$cap"
  fi
  bound=1; [ "$(prr_segment_kind "$log")" = "person review" ] && bound=0
  [ "$bound" = 0 ] || [ "$(prr_segment_cap "$log")" = "$cap" ] \
    || prr_die "the open segment's cap is $(prr_segment_cap "$log"), not $cap — a person's input opens a new segment"
  n=$(( $(prr_rounds_in_segment "$log") + 1 ))
  [ "$bound" = 0 ] || [ "$n" -le "$cap" ] || prr_die "round $n would pass the cap $cap — the item waits on a person (human:plan-review)"
  grep -qF '[DECISION]' <<<"$PRR_FX" && dec=1
  act="$(prr_next_action "$PRR_VERDICT" "$dec" "$n" "$cap" "$bound")"
  { printf '\n## Round %s — %s — %s\ndecision: %s\n' "$n" "$(date +%F)" "$PRR_VERDICT" "$([ "$dec" = 1 ] && echo yes || echo no)"
    [ -z "$PRR_FX" ] || printf '%s\n' "$PRR_FX"; } >> "$log"
  echo "$act"
}

# speckit-helper.sh plan-review-round … (a FETCHER: one line on stdout and exit 0, or a refusal on stderr and exit 1;
# a refusal appends nothing). Example: plan-review-round --verdict REVISE_PLAN --findings-file d/.review-findings.md --cap 5 --spec-dir d
prr_main() {
  prr_parse_args "$@"
  prr_check_spec_dir
  # A segment that opens here, at most one, is appended after every check; a cap mismatch is the round's check.
  if [ -n "$PRR_CAP_FLAG" ] && [ -n "$PRR_PI" ]; then PRR_CAP="$PRR_CAP_FLAG"; else prr_resolve_cap; fi
  if [ -n "$PRR_PI" ]; then prr_person_input "$PRR_LOGF" "$PRR_PI" "$PRR_CAP"; return; fi
  prr_consume_findings
  prr_record_round
}

# FR-009: the tail of a human:plan-review question file — a round index for the open segment, the last round's
# findings, the log's path — cut to <budget> bytes so the whole file stays inside what `ledger.sh questions` shows
# (8,000 bytes, ledger-lanes.sh:114). The log is planner-written data: a symlink, or a spec dir outside the worktree,
# gets one note line instead; a missing log (a planner from before this change) gets nothing.
prr_question_tail() { # worktree spec-dir budget-bytes
  local log="$2/$PRR_LOG_NAME" real wtr idx path left
  real="$(cd "$2" 2>/dev/null && pwd -P)"; wtr="$(cd "$1" 2>/dev/null && pwd -P)"
  [[ -n "$real" && -n "$wtr" && "$real/" == "$wtr/"* ]] || { printf '\n(review log not shown: %s is outside the worktree)\n' "$2"; return 0; }
  [ -L "$log" ] && { printf '\n(review log not shown: %s is a symlink)\n' "$log"; return 0; }
  [ -f "$log" ] || return 0
  path="Full log: $log"
  left=$(( $3 - $(printf '%s' "$path" | wc -c) - 64 )); [ "$left" -gt 0 ] || left=0   # 64 B: headers + newlines
  idx="$(awk '/^## Segment /{buf=""} /^## Round /{buf=buf $0 "\n"} /^decision:/{buf=buf "  " $0 "\n"} END{printf "%s", buf}' "$log" | head -c "$left")"
  left=$(( left - $(printf '%s' "$idx" | wc -c) )); [ "$left" -gt 0 ] || left=0
  printf '\n## Review rounds\n%s\n' "$idx"
  printf '\n## Open findings (last round)\n'; awk '/^## Segment /{f=""; next} /^## Round /{f=""} {f=f $0 "\n"} END{printf "%s", f}' "$log" | head -c "$left"
  printf '\n%s\n' "$path"
}
