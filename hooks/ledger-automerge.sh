#!/bin/bash
# ledger-automerge.sh — `orchestrate.merge_by: auto` (HEF-30, spec merge-auto D1–D4b): the deploy stage merges a PR
# into the INTEGRATION branch with no form, when a person's standing grant still matches and every gate, CI and
# pinned merge check pass. SOURCED by ledger.sh behind `[ -f ] || die`; never run on its own. Uses ledger.sh's
# globals and helpers (DIR, BCTX, ID, E, GH, HERE, die, entry, write_entry, cfgp, branches_model, merge_evidence,
# gh_pr_fact, store_get/store_put/store_dir, merge_checks_get, merge_repo_ctx, check_path_plain, SCOPE_JQ_DEFS).
#
#   merge-by [--explain]                                         person | lane | auto, resolved (FR-001, FR-003)
#   merge-auto preview | grant --sha <12+ hex> --reviewed-by-human --by <name> | revoke --reviewed-by-human --by <name> | show
#   automerge <id> [--if-merged]                                 0 merged · 2 skipped (human:merge) · 3 blocked ci|conflict
#                                                                · 4 pending · 5 open (--if-merged) · 1 refused
#
# Why a grant and not the config alone: `.claude/project-status.json` is a file a lane can write (ledger-recipes.sh),
# and the deploy launcher runs this unsandboxed. So a person's grant, in the approvals store outside every sandbox,
# pins per board repo its path, origin and integration branch, plus the merge checks — "pinned at grant, compared
# at run". Config `auto` with no grant, or with any pinned value changed since, resolves to `person` (NR-003).

# macOS ships no timeout(1): the bundled run-bounded.sh stands in (arena-run.sh does the same)
AM_TIMEOUT="$(command -v timeout || command -v gtimeout || echo "$HERE/run-bounded.sh")"
AM_NAME_RE='^[A-Za-z0-9]([A-Za-z0-9._@ -]{0,62}[A-Za-z0-9._@-])?$'

am_lane_role() { # → the calling session's lane role when a lanes session asks (empty otherwise: a terminal, the launcher)
  local sid="${CLAUDE_CODE_SESSION_ID:-}" f
  valid_sid "$sid" || return 0; f=$(session_file "$sid"); [ -f "$f" ] || return 0
  [ "$(jq -r '.lanes' "$f" 2>/dev/null)" = true ] || return 0
  jq -r '.role // "unnamed"' "$f"
}
am_not_worker() { # $1 the command, for the message
  [ -z "${HEFESTO_WORKER:-}" ] || [ "$HEFESTO_WORKER" = 0 ] || die "ledger $1: never from inside a launched worker"
}

# --- record <id> --verified-head <sha> (FR-004): the head the verify launcher checked, on the current PR --------------
# Written through .prs[-1] (as pr_stamp_merged), since .pr is a projection of it: a new PR carries no verified head.
# The launcher's own record — a lane that could write it would vouch for a head the gates never saw (NR-004).
verified_head_set() { # $1 the sha; updates E (record's entry) — no PR recorded yet leaves it unchanged
  [[ "$1" =~ ^[0-9a-f]{40}$ ]] || die "ledger record $ID: --verified-head must be the full 40-hex commit the verify run checked (got '$1')"
  am_not_worker "record $ID --verified-head"
  [ -z "$(am_lane_role)" ] || die "ledger record $ID: --verified-head is the launcher's own record (session-launch.sh writes it after verify), never a lane's"
  # shellcheck disable=SC2016  # a jq program
  E=$(jq --arg v "$1" "$ENTRY_PRS"' as $l | if .pr == null then . else (.pr + {verified_head: $v}) as $p | .prs = ($l[0:-1] + [$p]) | .pr = $p end' <<<"$E") \
    && [ -n "$E" ] || die "ledger record $ID: cannot set the verified head"
}

# --- the preview a grant pins (D1, D2) ----------------------------------------------------------------------------
am_repo_names() { if is_external; then jq -r '.repos // {} | keys_unsorted[]' <<<"$BCTX"; else echo .; fi; }
am_origin_of() { # $1 repo path → "owner/repo" of its configured origin (the raw value: insteadOf is not expanded), or rc 1
  local u; u=$(git -C "$1" config --get remote.origin.url 2>/dev/null) || return 1
  u="${u#https://github.com/}"; u="${u#ssh://git@github.com/}"; u="${u#git@github.com:}"; u="${u%/}"; u="${u%.git}"
  [[ "$u" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || return 1
  tr '[:upper:]' '[:lower:]' <<<"$u"
}
am_int_ineligible() { # $1 repo path, $2 integration branch → prints why it may not take an auto-merge; empty when it may
  local blk rc bm p
  blk=$(cd "$1" && branches_block); rc=$?; [ "$rc" -ne 2 ] || { echo "its branches block is not valid JSON"; return; }
  bm=$(branches_model "$blk" 2>&1) || { echo "its branch model is invalid: $bm"; return; }
  case "$2" in main|master) echo "the integration branch is $2"; return ;; esac
  [ "$2" != "$(jq -r .final <<<"$bm")" ] || { echo "the integration branch $2 is the final environment (no branches block means trunk on main)"; return; }
  # the user-declared globs, read from the RAW block: the effective .protected always holds the integration branch
  while IFS= read -r p; do
    # shellcheck disable=SC2254  # the pattern IS a glob, on purpose (release/*)
    case "$2" in $p) echo "the integration branch $2 matches branches.protected '$p'"; return ;; esac
  done < <(jq -r '(.protected // [])[]' <<<"${blk##*"$BR_SEP"}" 2>/dev/null)
}
automerge_repo_pin() { # $1 board repo name ("." in-repo) → {name, path, origin, integration} as one line, or die naming why
  local e ctx p int o why
  if [ "$1" = . ]; then e='{}'; else e=$(jq -nc --arg r "$1" '{repo: $r}'); fi
  ctx=$(merge_repo_ctx "$e" "ledger merge-auto preview") || exit 1; IFS=$'\t' read -r p int <<<"$ctx"
  o=$(am_origin_of "$p") || die "ledger merge-auto preview: repo $1 ($p) has no GitHub origin (remote.origin.url) — auto-merge pins it"
  why=$(am_int_ineligible "$p" "$int")
  [ -z "$why" ] || die "ledger merge-auto preview: repo $1 is not eligible — $why; auto-merge only merges into an integration branch below the environments"
  jq -nc --arg n "$1" --arg p "$p" --arg o "$o" --arg i "$int" '{name: $n, path: $p, origin: $o, integration: $i}'
}
# A pinned check runs OUTSIDE the sandbox (ledger.sh is in sandbox.excludedCommands), from the main checkout every lane
# can write — so its program must never be a file a lane can write. An ALLOWLIST, because no list of writable places is
# complete (code review of HEF-30: a prefix rule over repo + temp fell to /./, /../, //, a symlinked parent and the
# caches): a bare name, found on the launcher's PATH; or an absolute path with no . / .. / empty component whose folder
# AS WRITTEN is exactly hefesto's own hooks folder or a system bin folder. Never resolved: a link a lane wrote that
# points at /usr/bin today could point into the repo by the time the check runs. A bare `npm test` or `make` still
# reads the repo's own files: pinning one is the person's informed choice — the preview says so.
AM_PROG_DIRS="/usr/bin /bin /usr/sbin /sbin /usr/local/bin /usr/local/sbin /opt/homebrew/bin /opt/local/bin"
am_argv0() { # $1 a check, substituted → its program, read exactly as automerge_run_checks reads it (read -r -a)
  local a; read -r -a a <<<"$1"; printf '%s\n' "${a[0]:-}"
}
am_check_prog_bad() { # $1 check, $2 a pin {path, integration} → why its program may not run unsandboxed; empty when it may
  local c w d t; c="${1//\{repo_path\}/$(jq -r .path <<<"$2")}"; c="${c//\{base\}/$(jq -r .integration <<<"$2")}"
  # third review: the rule must read the check as the run does — a leading blank hid the program from a cut at the
  # first blank, not from read -a; and an interpreter is one by its name wherever it lives (/bin/sh is sh)
  case "$c" in *[[:cntrl:]]*) echo "a control character (a tab, a newline)"; return 0 ;; [[:space:]]*) echo "a leading blank"; return 0 ;; esac
  w=$(am_argv0 "$c"); [ -n "$w" ] || { echo "no program"; return 0; }
  # hefesto-setup.sh cmd_ok's list plus the exec wrappers (fourth review: stdbuf and setpriv ran a repo file);
  # lowercased first, since macOS's disk is case-insensitive and /bin/SH is sh there
  case "$(printf '%s' "${w##*/}" | tr '[:upper:]' '[:lower:]')" in sh|bash|zsh|dash|ksh|fish|env|eval|exec|xargs|sudo|doas \
    |nohup|timeout|command|builtin|nice|time|setsid|script|stdbuf|setpriv|flock|chrt|taskset|ionice|unshare|nsenter|setarch \
    |systemd-run|su|runuser|chroot|bwrap|pkexec|gdb|watch|strace|ltrace|caffeinate|arch|python|python[0-9]*|perl|ruby \
    |node|deno|bun|php|lua|lua[0-9]*|luajit|tclsh|awk|gawk|mawk|sed|find|osascript|busybox|toybox)
    echo "'$w', a shell or interpreter wrapper"; return 0 ;; esac
  # slashes are quoted: lizard (the commit gate) reads a bare slash-star as a C comment and merges functions
  case "$w" in *"/"*) ;; *) return 0 ;; esac
  case "$w" in "/"*) ;; *) echo "'$w' is a relative path"; return 0 ;; esac
  case "$w/" in *"//"*|*"/./"*|*"/../"*) echo "'$w' has an empty, . or .. path component"; return 0 ;; esac
  d="${w%"/"*}"
  for t in "$HERE" $AM_PROG_DIRS; do [ "$d" != "$t" ] || return 0; done
  echo "'$w' is not in hefesto's hooks folder or a system bin folder ($AM_PROG_DIRS)"
}
am_checks_prog_ok() { # $1 checks JSON, $2 the pins (one JSON line each) → dies naming the first program it refuses
  local c p why
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    while IFS= read -r c; do
      why=$(am_check_prog_bad "$c" "$p")
      [ -z "$why" ] || die "ledger merge-auto preview: the merge check '$c' runs $why — a pinned check runs outside the sandbox, so its program is a bare name on PATH, or an absolute path in hefesto's hooks folder or a system bin folder"
    done < <(jq -r '.[]' <<<"$1")
  done <<<"$2"
}
automerge_preview() { # → {repos: {<name>: {path, origin, integration}}, checks: […]} as one line, or die
  local ch nm pin pins=""
  ch=$(merge_checks_get "ledger merge-auto preview") || exit 1
  while IFS= read -r nm; do pin=$(automerge_repo_pin "$nm") || exit 1; pins="$pins$pin"$'\n'; done < <(am_repo_names)
  am_checks_prog_ok "$ch" "$pins"   # re-run by every merge-by resolve: a grant can never pin such a check
  printf '%s' "$pins" | jq -sc --argjson ch "$ch" '{repos: (map({(.name): {path, origin, integration}}) | add // {}), checks: $ch}'
}
am_sha() { jq -cS . <<<"$1" | hef_sha256; }

# --- merge-by (FR-001, FR-003): validate, then honour auto only when the grant equals a fresh preview -------------------
merge_by_resolve() { # sets MB_CONF, MB_EFF, MB_WHY; dies on a value that is not person, lane or auto
  local g p
  MB_CONF=$(cfgp -r '.orchestrate.merge_by // "person" | if type == "string" then . else tojson end'); MB_CONF="${MB_CONF:-person}"
  MB_EFF=person; MB_WHY=""
  case "$MB_CONF" in person|lane) MB_EFF="$MB_CONF"; return 0 ;; auto) ;; *) die "ledger merge-by: orchestrate.merge_by must be person, lane or auto (got '$MB_CONF')" ;; esac
  g=$(store_get merge-auto)
  [ -n "$g" ] || { MB_WHY="no grant — a person turns it on: ledger.sh merge-auto preview, then merge-auto grant"; return 0; }
  p=$(automerge_preview 2>/dev/null) || { MB_WHY="ledger.sh merge-auto preview refuses now (run it to see why)"; return 0; }
  if [ "$(jq -cS '{repos, checks}' <<<"$g" 2>/dev/null)" = "$(jq -cS . <<<"$p")" ]; then MB_EFF=auto
  else MB_WHY="the grant no longer matches: a repo path, origin, integration branch or merge check changed since it was given"; fi
}
merge_by_cmd() { # [--explain]
  local ex=0; while [ $# -gt 0 ]; do case "$1" in --explain) ex=1 ;; *) usage ;; esac; shift; done
  merge_by_resolve
  if [ "$ex" = 1 ]; then jq -nc --arg c "$MB_CONF" --arg e "$MB_EFF" --arg r "$MB_WHY" '{configured: $c, effective: $e, reason: (if $r == "" then null else $r end)}'; return 0; fi
  [ -z "$MB_WHY" ] || echo "merge_by auto behaves as person: $MB_WHY" >&2
  echo "$MB_EFF"
}

# --- merge-auto preview | grant | revoke | show (FR-002) --------------------------------------------------------------
am_person_only() { # $1 verb — a person's decision: never a worker, never a lane but the orchestrator, always a name
  local role
  am_not_worker "merge-auto $1"
  role=$(am_lane_role)
  [ -z "$role" ] || [ "$role" = orchestrator ] || die "ledger merge-auto $1: a person's decision, so it runs only in the orchestrator lane (this session is a $role lane)"
  [ "$REVIEWED" = 1 ] && [[ "$RBY" =~ $AM_NAME_RE ]] || die "ledger merge-auto $1: needs --reviewed-by-human --by <your name> — a person answers its permission prompt; never allowlist it"
}
merge_auto_cmd() {
  local verb="${1:-}" sha="" p h g; [ $# -eq 0 ] || shift
  REVIEWED=0; RBY=""
  while [ $# -gt 0 ]; do case "$1" in --sha) sha="${2:-}"; shift ;; --reviewed-by-human) REVIEWED=1 ;; --by) RBY="${2:-}"; shift ;; *) usage ;; esac; shift; done
  case "$verb" in
    preview) p=$(automerge_preview) || exit 1; jq . <<<"$p"; echo "sha256: $(am_sha "$p")"
             echo "note: these checks run outside the sandbox, in each repo's path; a bare program (npm, make) reads that repo's own files" >&2 ;;
    show) g=$(store_get merge-auto); [ -n "$g" ] || die "ledger merge-auto show: no grant — merge_by auto behaves as person"; jq . <<<"$g" ;;
    grant)
      am_person_only grant
      p=$(automerge_preview) || exit 1; h=$(am_sha "$p")
      [[ "$sha" =~ ^[0-9a-f]{12,64}$ ]] && [[ "$h" == "$sha"* ]] || die "ledger merge-auto grant: --sha '$sha' is not the preview's sha256 ($(cut -c1-12 <<<"$h")…) — show the preview again and ask"
      jq -c --arg h "$h" --arg by "$RBY" '. + {sha256: $h, by: $by, at: (now | todate)}' <<<"$p" | store_put merge-auto || exit 1
      echo "merge-auto granted by $RBY (sha256 ${h:0:12}) — merge_by auto merges green PRs into $(jq -r '[.repos[].integration] | unique | join(", ")' <<<"$p")" ;;
    revoke)
      am_person_only revoke
      if [ -f "$(store_dir)/merge-auto.json" ]; then rm -f "$(store_dir)/merge-auto.json" || die "ledger merge-auto revoke: cannot remove the grant"; echo "merge-auto revoked by $RBY"
      else echo "merge-auto: no grant to revoke"; fi ;;
    *) usage ;;
  esac
}

# --- automerge <id> (FR-005..FR-009) -------------------------------------------------------------------------------------
am_block() { # $1 kind, $2 reason, $3 exit code — the entry blocks (kept when already that kind) with an event; exits
  local e; e=$(entry "$ID") || exit 1
  # the block verb's own invariants (ledger.sh block): a decision that comes first is never replaced from here
  case "$(jq -r '.blocked_on.kind // ""' <<<"$e")" in ""|human:merge|ci|conflict) ;; *) die "ledger automerge $ID: blocked on $(jq -r .blocked_on.kind <<<"$e") — not replaced" ;; esac
  # shellcheck disable=SC2016  # a jq program
  jq --arg k "$1" --arg n "${2:0:500}" '(if (.blocked_on.kind // "") == $k then . else .blocked_on = {kind: $k, since: (now | todate), question_path: null} end)
    | .events = ((.events // []) + [{kind: "auto-merge-skipped", at: (now | todate), by: "ledger", note: $n}])' <<<"$e" | write_entry "$ID" || exit 1
  if [ "$3" = 2 ]; then echo "skipped $ID: $2"; else echo "blocked $ID $1: $2"; fi
  exit "$3"
}
am_skip() { am_block human:merge "$1" 2; }   # FR-007: the ordinary form path, never a merge
am_record_merge() { # $1 entry, $2 the PR's merge commit, $3 event kind, $4 note — the ONE evidence path (as merge_done)
  local via sha
  via=$( (cd_entry_repo "$1" && { hef_fetch_origin >/dev/null 2>&1; merge_evidence "$1" "$2" recorded; }) ) || return 1
  read -r _ sha _ <<<"$via"
  # shellcheck disable=SC2016  # a jq program
  jq --arg m "$sha" --arg k "$3" --arg n "$4" '.blocked_on = null | .pr.merge_sha = $m | del(.pr.merge_unverified)
    | .events = ((.events // []) + [{kind: $k, at: (now | todate), by: "ledger", note: $n}])' <<<"$1" \
    | pr_stamp_merged commit "$sha" false | write_entry "$ID" || exit 1
  bash "$0" advance "$ID" merged >/dev/null || die "ledger automerge $ID: the merge is stamped, but advance to merged failed (see above)"
  echo "merged $ID $sha"
}
am_pr_of() { # $1 entry → "<owner/repo> <n> <url>", or die
  local url; url=$(jq -r '.pr.url // empty' <<<"$1")
  [[ "$url" =~ ^https://github\.com/([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)/pull/([0-9]+)$ ]] || die "ledger automerge $ID: no GitHub PR is recorded (got '${url:-none}')"
  printf '%s %s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$url"
}
automerge_if_merged() { # $1 entry — a PR a person merged by hand is recorded (exit 0), else "open" (exit 5) and nothing recorded
  local r n url fact st oid bk
  read -r r n url <<<"$(am_pr_of "$1")" || exit 1; [ -n "$url" ] || exit 1
  bk=$(jq -r '.blocked_on.kind // empty' <<<"$1")
  # the kinds automerge_gate re-evaluates (third review): a hand merge while the babysitter held ci is recorded too
  [ "$(jq -r .phase <<<"$1")" = pr ] && case "$bk" in ""|human:merge|ci|conflict) true ;; *) false ;; esac || { echo "open $ID (phase $(jq -r .phase <<<"$1"), blocked on ${bk:-nothing})"; exit 5; }
  fact=$(gh_pr_fact "$url") || die "ledger automerge $ID --if-merged: gh cannot read $url — nothing recorded"
  read -r st _ oid <<<"$fact"
  [ "$st" = MERGED ] && [ "$oid" != - ] || { echo "open $ID ($r#$n is $st)"; exit 5; }
  am_record_merge "$1" "$oid" merge-recorded "$r#$n merged by hand; recorded by automerge --if-merged" || die "ledger automerge $ID --if-merged: $url is MERGED but the merge evidence is missing (see above) — nothing recorded"
  exit 0
}
automerge_skip_reason() { # $1 entry, $2 pr-watch state JSON, $3 the entry repo's pin, $4 the PR's owner/repo → why not; empty = eligible
  local g
  [ "$(tr '[:upper:]' '[:lower:]' <<<"$4")" = "$(jq -r '.origin | ascii_downcase' <<<"$3")" ] || { echo "PR repo $4 is not the pinned origin $(jq -r .origin <<<"$3")"; return; }
  [ "$(jq -r .state <<<"$2")" = OPEN ] || { echo "the PR is $(jq -r .state <<<"$2")"; return; }
  [ "$(jq -r .baseRefName <<<"$2")" = "$(jq -r .integration <<<"$3")" ] || { echo "the PR's base $(jq -r .baseRefName <<<"$2") is not the integration branch $(jq -r .integration <<<"$3")"; return; }
  for g in verify review quality scan $(jq -r '.item_kind // "" | select(. == "incident" or . == "vulnerability")' <<<"$1"); do
    [ "$(jq -r --arg g "$g" '[.verdicts[]? | select(.gate == $g)][-1].verdict // "none"' <<<"$1")" = PASS ] || { echo "gate $g is not PASS"; return; }
  done
  [ "$(jq -r .headRefOid <<<"$2")" = "$(jq -r '.pr.verified_head // ""' <<<"$1")" ] || echo "head moved since verify ($(jq -r '.pr.verified_head // "none recorded"' <<<"$1") → $(jq -r .headRefOid <<<"$2"))"
}
am_state_step() { # $1 pr-watch state JSON — returns when mergeable; else blocks conflict/ci, skips, or exits 4 (FR-009)
  local v ms ck
  v=$(jq -r '.verdict // empty' <<<"$1"); ms=$(jq -r '.mergeStateStatus // empty' <<<"$1"); ck=$(jq -r '.checks // empty' <<<"$1")
  case "$v" in
    conflict) am_block conflict "the PR conflicts with its base" 3 ;;
    pending)  echo "pending $ID — checks running; nothing recorded"; exit 4 ;;
    checks)   am_block ci "CI checks are red ($ck)" 3 ;;
    mergeable) case "$ms" in BEHIND) am_block conflict "the PR is behind its base" 3 ;; CLEAN|HAS_HOOKS) [ "$ck" = pass ] || am_block ci "checks are $ck" 3 ;;
                 *) am_skip "PR state ${ms:-unknown}" ;; esac ;;
    *) am_skip "the PR is ${v:-unreadable} (${ms:-unknown}), not mergeable" ;;
  esac
}
# A bare name is resolved BEFORE the cd into the repo: an empty or . entry in PATH must never find a file there.
# type -P gives the file on PATH (never a builtin), and a . entry yields ./x, which is not absolute — refused.
am_prog_file() { # $1 program → its absolute file, or rc 1
  local p; p=$(type -P -- "$1" 2>/dev/null)
  case "$p" in "/"*) printf '%s\n' "$p" ;; *) return 1 ;; esac
}
automerge_run_checks() { # $1 pinned path, $2 base, $3 grant → 0 all pass; else prints "<cmd>: <reason>", returns 1 (NR-005)
  local c out argv p
  out=$( (check_path_plain "$1" automerge) 2>&1 ) || { echo "$out"; return 1; }
  while IFS= read -r c; do
    jq -en --arg c "$c" "$SCOPE_JQ_DEFS"' $c | cmd_ok and merge_ok' >/dev/null 2>&1 || { echo "$c: refused by the action scope command rule (no shell, no -c, no hefesto helper)"; return 1; }
    read -r -a argv <<<"$c"
    p=$(am_prog_file "${argv[0]:-}") || { echo "$c: the program ${argv[0]:-} is not found on PATH"; return 1; }
    argv[0]="$p"
    out=$(cd "$1" && "$AM_TIMEOUT" 600 "${argv[@]}" 2>&1 </dev/null) && continue
    [ $? != 124 ] || { echo "$c: timed out after 600 s"; return 1; }   # FR-008 names a timeout on its own
    echo "$c: $(tail -1 <<<"${out:-exited non-zero}")"; return 1
  done < <(jq -r --arg rp "$1" --arg b "$2" '.checks[] | gsub("\\{repo_path\\}"; $rp) | gsub("\\{base\\}"; $b)' <<<"$3")
}
automerge_cmd() { # <id> [--if-merged] — the gate (FR-005, FR-007, FR-009), then the merge (FR-006, FR-008)
  ID="${1:-}"; [ -n "$ID" ] || usage; shift
  local ifm=0 e
  while [ $# -gt 0 ]; do case "$1" in --if-merged) ifm=1 ;; *) usage ;; esac; shift; done
  am_not_worker "automerge $ID"
  e=$(entry "$ID") || exit 1
  [ "$ifm" = 0 ] || automerge_if_merged "$e"
  automerge_gate "$e"
  automerge_merge "$e"
}
automerge_gate() { # $1 entry — returns when it may be merged, setting AM_GRANT AM_PIN AM_R AM_N AM_URL; else exits 1|2|3|4
  local bk nm st why
  bk=$(jq -r '.blocked_on.kind // empty' <<<"$1")
  # ci and conflict are the babysitter's own blocks (automerge sets them too): after its `mergeable` they are
  # re-evaluated here, every precondition below re-runs — a stale ci would otherwise cost a Retry (verify review).
  # Any other block is a decision that comes first (a person's question, a stall, a budget).
  case "$bk" in ""|human:merge|ci|conflict) ;; *) echo "skipped $ID: blocked on $bk — that decision comes first"; exit 2 ;; esac
  [ "$(jq -r .phase <<<"$1")" = pr ] || die "ledger automerge $ID: phase $(jq -r .phase <<<"$1") — only an entry at pr is merged"
  merge_by_resolve
  [ "$MB_EFF" = auto ] || am_skip "merge_by is $MB_CONF${MB_WHY:+ — $MB_WHY}"
  AM_GRANT=$(store_get merge-auto); nm=$(jq -r '.repo // "."' <<<"$1"); AM_PIN=$(jq -c --arg n "$nm" '.repos[$n] // empty' <<<"$AM_GRANT")
  [ -n "$AM_PIN" ] || am_skip "the grant pins no repo '$nm'"
  read -r AM_R AM_N AM_URL <<<"$(am_pr_of "$1")"; [ -n "${AM_URL:-}" ] || exit 1
  st=$( (cd_entry_repo "$1" && bash "$HERE/pr-watch.sh" state "$AM_URL") 2>&1 ) || die "ledger automerge $ID: pr-watch.sh state $AM_URL failed — nothing recorded: $(tail -1 <<<"$st")"
  why=$(automerge_skip_reason "$1" "$st" "$AM_PIN" "$AM_R"); [ -z "$why" ] || am_skip "$why"
  am_state_step "$st"
}
automerge_merge() { # $1 entry, after automerge_gate — the pinned checks, the one merge command, the evidence; exits 0 or 3
  local out vh fact mst oid int
  int=$(jq -r .integration <<<"$AM_PIN")
  out=$(automerge_run_checks "$(jq -r .path <<<"$AM_PIN")" "$int" "$AM_GRANT") || am_block ci "merge check failed — $out" 3
  vh=$(jq -r .pr.verified_head <<<"$1")
  out=$("$GH" pr merge "$AM_N" -R "$AM_R" --merge --match-head-commit "$vh" 2>&1 </dev/null) || am_block ci "gh pr merge refused: $(tail -1 <<<"${out:-no output}")" 3
  fact=$(gh_pr_fact "$AM_URL") || am_block ci "merged, but gh cannot read $AM_URL back — the merge is not recorded" 3
  read -r mst _ oid <<<"$fact"
  [ "$mst" = MERGED ] && [ "$oid" != - ] || am_block ci "gh pr merge returned, but $AM_URL is $mst" 3
  am_record_merge "$1" "$oid" auto-merged "auto-merged PR #$AM_N into $int (${oid:0:12})" || am_block ci "$AM_URL is merged, but the merge evidence is missing (see above)" 3
}
