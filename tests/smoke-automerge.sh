# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
#
# merge-auto (HEF-30) smoke checks — `orchestrate.merge_by: auto`: the person's standing grant (merge-auto), its
# resolution (merge-by), the deploy-time merge (automerge), the verified head, the launcher wiring and setup's decider.
#
# SOURCED by tests/smoke.sh after the other parts, never run on its own. Self-contained: a fixture repo whose origin
# is configured as https://github.com/acme/app.git and rewritten (insteadOf) to a bare repo beside it, a named fake gh
# (FakeGhPr: one PR's JSON in a file; `pr merge` refuses a moved head like GitHub, else really merges in a second
# clone and pushes), the real ledger.sh. Every merge assertion is on the fake's invocation log, never on text.

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ sld >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-automerge.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_, sld)"
  else echo "tests/smoke-automerge.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

# --- the fixture -----------------------------------------------------------------------------------------------------
am_t="$(cd "$(mktemp -d)" && pwd -P)"; am_w="$am_t/w"; am_up="$am_t/up"
am_g() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
am_repo() { # am_repo <dir> — a clone-shaped repo whose origin is acme/app on GitHub, rewritten to the bare origin
  git init -q -b main "$1" && am_g "$1" commit -q --allow-empty -m init >/dev/null \
    && git -C "$1" remote add origin https://github.com/acme/app.git \
    && git -C "$1" config "url.$am_t/origin.git.insteadOf" https://github.com/acme/app.git && mkdir -p "$1/.claude"
}
git init -q --bare -b main "$am_t/origin.git" && am_repo "$am_w" && git -C "$am_w" push -q origin main 2>/dev/null
for am_b in dev stg; do git -C "$am_w" branch "$am_b" main && git -C "$am_w" push -q origin "$am_b" 2>/dev/null; done
for am_i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
  git -C "$am_w" checkout -q -b "feat$am_i" dev && am_g "$am_w" commit -q --allow-empty -m "feat$am_i" && git -C "$am_w" push -q origin "feat$am_i" 2>/dev/null
done; git -C "$am_w" checkout -q dev
git clone -q "$am_t/origin.git" "$am_up" 2>/dev/null
am_sha() { git -C "$am_w" rev-parse "$1"; }
mkdir -p "$am_t/bin"
# FakeGhPr: `pr view` answers from pr.json (through -q/--jq), `pr checks` from checks.json (default none), `pr merge`
# is logged; it refuses when $am_t/refuse exists or the --match-head-commit is not the head (as GitHub does), and
# otherwise merges the head branch into the base in a second clone, pushes, and marks the PR MERGED.
cat > "$am_t/bin/gh" <<EOF
#!/bin/bash
echo "\$*" >> "$am_t/gh.log"
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "pr checks") if [ -f "$am_t/checks.json" ]; then cat "$am_t/checks.json"; else echo '[]'; fi ;;
  "pr view") q=""; while [ \$# -gt 0 ]; do case "\$1" in -q|--jq) q="\$2"; shift ;; esac; shift; done
             if [ -n "\$q" ]; then jq -r "\$q" "$am_t/pr.json"; else cat "$am_t/pr.json"; fi ;;
  "pr merge") [ ! -f "$am_t/refuse" ] || { echo "GraphQL: Head branch is not up to date (mergePullRequest)" >&2; exit 1; }
              n="\$3"; want=""; while [ \$# -gt 0 ]; do [ "\$1" != --match-head-commit ] || want="\$2"; shift; done
              [ "\$want" = "\$(jq -r .headRefOid "$am_t/pr.json")" ] || { echo "Head branch was modified" >&2; exit 1; }
              b="\$(jq -r .baseRefName "$am_t/pr.json")"; h="\$(jq -r .headRefName "$am_t/pr.json")"
              git -C "$am_up" fetch -q origin && git -C "$am_up" checkout -q -B "\$b" "origin/\$b" \
                && git -C "$am_up" -c user.email=t@t -c user.name=t merge -q --no-ff -m "Merge pull request #\$n" "origin/\$h" \
                && git -C "$am_up" push -q origin "\$b" 2>/dev/null || exit 1
              m="\$(git -C "$am_up" rev-parse HEAD)"
              jq --arg m "\$m" '.state = "MERGED" | .mergeCommit = {oid: \$m}' "$am_t/pr.json" > "$am_t/pr.tmp" && mv "$am_t/pr.tmp" "$am_t/pr.json" ;;
  *) echo "FakeGhPr: unexpected gh \$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$am_t/bin/gh"
am_pr() { # am_pr <n> <branch> <head sha> [base] [mergeStateStatus] [owner/repo] → writes the fake PR (OPEN)
  jq -n --argjson n "$1" --arg b "$2" --arg h "$3" --arg base "${4:-dev}" --arg ms "${5:-CLEAN}" --arg r "${6:-acme/app}" \
    '{number: $n, url: "https://github.com/\($r)/pull/\($n)", state: "OPEN", isDraft: false, mergeable: "MERGEABLE", mergeStateStatus: $ms,
      reviewDecision: "", headRefName: $b, baseRefName: $base, headRefOid: $h, mergeCommit: null}' > "$am_t/pr.json"
}
AM_CHECK='test ! -e {repo_path}/.claude/FAILCHECK'
AM_BR='{"integration": "dev", "environments": ["dev", "stg", "main"]}'
am_cfg() { # am_cfg <merge_by> [branches JSON] [checks JSON] → the board config ('' = the default)
  local b="${2:-}" c="${3:-}"; [ -n "$b" ] || b="$AM_BR"; [ -n "$c" ] || c="$(jq -nc --arg c "$AM_CHECK" '[$c]')"
  jq -n --arg m "$1" --argjson b "$b" --argjson c "$c" '{name: "app", branches: $b, orchestrate: {merge_by: $m, merge: {checks: $c}}}' > "$am_w/.claude/project-status.json"
}
am() { (cd "$am_w" && HEFESTO_GH_BIN="$am_t/bin/gh" bash "$REPO/hooks/ledger.sh" "$@"); }   # am <ledger args…>
am_ld="$(sld "$am_w")"; mkdir -p "$am_ld"
am_entry() { # am_entry <id> <PR n> <branch> [jq filter] — at pr, the four gates PASS, verified at the branch head
  local h; h="$(am_sha "$3")"
  jq -n --arg id "$1" --arg b "$3" --argjson n "$2" --arg h "$h" '{id: $id, item_kind: "feature", phase: "pr", owner: null, branch: $b, worktree: null,
    pr: {url: "https://github.com/acme/app/pull/\($n)", number: $n, verified_head: $h}, prs: [{url: "https://github.com/acme/app/pull/\($n)", number: $n, verified_head: $h}],
    verdicts: ([("verify", "review", "quality", "scan") | {gate: ., verdict: "PASS", by: "verify-\($id)", at: "2026-11-09T00:00:00Z", evidence: null}]),
    blocked_on: null, events: [], runs: [], attempts: 0}' | jq "${4:-.}" > "$am_ld/$1.json"
}
am_grant() { # am_grant [extra env…] → the person's Turn on: the preview's sha, then grant
  local o s; o="$(am merge-auto preview 2>&1)" || { echo "$o"; return 1; }
  s="$(sed -n 's/^sha256: //p' <<<"$o")"; am merge-auto grant --sha "${s:0:12}" --reviewed-by-human --by Ana </dev/null 2>&1
}
am_ok() { local l="$1" o; shift; o="$(am "$@" 2>&1)" || { bad "$l must pass — got: $(head -c 300 <<<"$o")"; x_fail=1; }; }
am_no() { # am_no <label> <text the refusal must name> <ledger args…>
  local l="$1" need="$2" o; shift 2
  o="$(am "$@" 2>&1 </dev/null)" && { bad "$l must be refused"; x_fail=1; return; }
  grep -qF -- "$need" <<<"$o" || { bad "$l: the refusal must name '$need' — got: $(head -c 300 <<<"$o")"; x_fail=1; }
}
am_merged() { grep -q '^pr merge' "$am_t/gh.log" 2>/dev/null; }
am_case() { # am_case <label> <id> <exit> <block kind|none> <text the output names> [tried] — and no `gh pr merge` unless exit 0 (or tried)
  local l="$1" id="$2" o rc; : > "$am_t/gh.log"
  o="$(am automerge "$id" 2>&1 </dev/null)"; rc=$?
  [ "$rc" = "$3" ] || { bad "$l: automerge $id must exit $3 — got $rc: $(head -c 300 <<<"$o")"; x_fail=1; }
  [ "$(jq -r '.blocked_on.kind // "none"' "$am_ld/$id.json")" = "$4" ] || { bad "$l: $id must be blocked on $4 — got $(jq -c .blocked_on "$am_ld/$id.json")"; x_fail=1; }
  grep -qF -- "$5" <<<"$o" || { bad "$l: automerge's output must name '$5' — got: $(head -c 300 <<<"$o")"; x_fail=1; }
  [ "$3" = 0 ] || [ "${6:-}" = tried ] || ! am_merged || { bad "$l: gh pr merge must never be invoked ($(grep '^pr merge' "$am_t/gh.log"))"; x_fail=1; }
}
mkdir -p "$HOME/.cache/hefesto/sessions"
for am_r in deploy orchestrator; do
  jq -nc --arg r "$am_r" '{title: "repo-\($r)", role: $r, name: "repo-\($r)", lanes: true, worker: false}' > "$HOME/.cache/hefesto/sessions/sid-am-$am_r-0001.json"
done

# --- FR-004: record --verified-head ------------------------------------------------------------------------------------
head_ "merge-auto: record --verified-head writes through the current PR; the launcher's own record (HEF-30 FR-004)"
x_fail=0; am_cfg auto
am_entry HEF-1 7 feat1 'del(.pr.verified_head) | del(.prs[0].verified_head)'; am_h1="$(am_sha feat1)"
am_ok "record --verified-head" record HEF-1 --verified-head "$am_h1"
jq -e --arg h "$am_h1" '.pr.verified_head == $h and .prs[-1].verified_head == $h' "$am_ld/HEF-1.json" >/dev/null 2>&1 \
  || { bad "record --verified-head must set .pr.verified_head through .prs[-1] (FR-004) — got $(jq -c '{pr, prs}' "$am_ld/HEF-1.json")"; x_fail=1; }
am_ok "record --pr <the same url>" record HEF-1 --pr https://github.com/acme/app/pull/7
jq -e --arg h "$am_h1" '.pr.verified_head == $h' "$am_ld/HEF-1.json" >/dev/null 2>&1 || { bad "the verified head must survive record --pr of the same PR (FR-004)"; x_fail=1; }
am_no "a short sha as --verified-head" "40-hex" record HEF-1 --verified-head "${am_h1:0:12}"
o="$(cd "$am_w" && HEFESTO_WORKER=1 bash "$REPO/hooks/ledger.sh" record HEF-1 --verified-head "$(am_sha feat2)" 2>&1)" && { bad "--verified-head must be refused inside a launched worker (FR-004)"; x_fail=1; }
o="$(cd "$am_w" && CLAUDE_CODE_SESSION_ID=sid-am-deploy-0001 bash "$REPO/hooks/ledger.sh" record HEF-1 --verified-head "$(am_sha feat2)" 2>&1)" \
  && { bad "--verified-head must be refused from a lane session — it is the launcher's own record (FR-004, NR-004)"; x_fail=1; }
grep -qF "launcher" <<<"$o" || { bad "the lane refusal of --verified-head must name the launcher — got: $(head -c 200 <<<"$o")"; x_fail=1; }
jq -e --arg h "$am_h1" '.pr.verified_head == $h' "$am_ld/HEF-1.json" >/dev/null 2>&1 || { bad "a refused --verified-head must leave the recorded one"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "record --verified-head: through .prs[-1], survives record --pr of the same PR, 40-hex only, refused in a worker and from a lane session (HEF-30 FR-004)"

# --- FR-001, FR-002, FR-003: merge-by and merge-auto ------------------------------------------------------------------
head_ "merge-auto: merge-by resolves auto only with a matching grant; merge-auto preview/grant/revoke/show (HEF-30 FR-001..FR-003)"
x_fail=0; am_cfg auto
[ "$(am merge-by 2>/dev/null)" = person ] || { bad "merge_by auto with no grant must resolve to person (FR-003, NR-003) — got '$(am merge-by 2>&1)'"; x_fail=1; }
am merge-by 2>&1 >/dev/null | grep -qF "no grant" || { bad "merge-by must name the missing grant on stderr (FR-003)"; x_fail=1; }
jq -e '.configured == "auto" and .effective == "person" and (.reason | test("no grant"))' <<<"$(am merge-by --explain 2>/dev/null)" >/dev/null 2>&1 \
  || { bad "merge-by --explain must print {configured, effective, reason} — got $(am merge-by --explain 2>&1 | head -c 200)"; x_fail=1; }
am_cfg lane; [ "$(am merge-by 2>/dev/null)" = lane ] || { bad "merge_by lane must resolve to lane (FR-001)"; x_fail=1; }
am_cfg person; [ "$(am merge-by 2>/dev/null)" = person ] || { bad "merge_by person must resolve to person (FR-001)"; x_fail=1; }
am_cfg bogus; am_no "merge_by: bogus" "bogus" merge-by
jq '.orchestrate.merge_by = 3' "$am_w/.claude/project-status.json" > "$am_t/c.json" && mv "$am_t/c.json" "$am_w/.claude/project-status.json"
am_no "merge_by: 3 (not a string)" "must be person, lane or auto" merge-by
jq 'del(.orchestrate.merge_by)' "$am_w/.claude/project-status.json" > "$am_t/c.json" && mv "$am_t/c.json" "$am_w/.claude/project-status.json"
[ "$(am merge-by 2>/dev/null)" = person ] || { bad "an absent merge_by must resolve to person (FR-001)"; x_fail=1; }
# FR-002: the preview pins the repo's path, origin and integration branch and the checks, with its sha256
am_cfg auto; am_o="$(am merge-auto preview 2>/dev/null)"   # stdout: the JSON and its sha256 (the note is on stderr)
am merge-auto preview 2>&1 >/dev/null | grep -qF "outside the sandbox" || { bad "merge-auto preview must say the checks run outside the sandbox (NR-005)"; x_fail=1; }
{ jq -e --arg p "$am_w" --arg c "$AM_CHECK" '.repos["."] == {path: $p, origin: "acme/app", integration: "dev"} and .checks == [$c]' <<<"$(sed '/^sha256: /d' <<<"$am_o")" >/dev/null 2>&1 \
  && grep -qE '^sha256: [0-9a-f]{64}$' <<<"$am_o"; } || { bad "merge-auto preview must pin {path, origin, integration} per repo plus the checks, and print its sha256 (FR-002) — got: $(head -c 400 <<<"$am_o")"; x_fail=1; }
# D2: an integration branch that is main, the final environment, or a declared protected glob is never eligible
am_cfg auto '{"integration": "main"}'; am_no "preview with no environments (integration main)" "not eligible" merge-auto preview
am_cfg auto '{"integration": "dev", "environments": ["dev"]}'; am_no "preview where integration is the final environment" "final environment" merge-auto preview
am_cfg auto '{"integration": "dev", "environments": ["dev", "stg", "main"], "protected": ["de*"]}'; am_no "preview where integration matches a declared protected glob" "branches.protected" merge-auto preview
# NR-005 (code review): a pinned check runs outside the sandbox, so its program is never a file a lane can write —
# a relative path, a path in the repo, or one in a temp folder is refused; a bare name or an outside absolute path is not
# an allowlist, not a list of writable places (re-review: a prefix rule fell to /./, /../, // and a symlinked parent)
am_cfg auto '' '["./scripts/check.sh --base {base}"]'; am_no "a merge check run by a relative path" "relative path" merge-auto preview
am_cfg auto '' '["{repo_path}/.claude/check.sh"]'; am_no "a merge check run from inside the repo" "not in hefesto's hooks folder" merge-auto preview
am_cfg auto '' "[\"$am_t/bin/gh\"]"; am_no "a merge check run from a temp folder" "not in hefesto's hooks folder" merge-auto preview
am_cfg auto '' '["/{repo_path}/.claude/check.sh"]'; am_no "a merge check with an empty path component" "component" merge-auto preview
am_cfg auto '' '["/usr/bin/../../tmp/check.sh"]'; am_no "a merge check with a .. component" "component" merge-auto preview
am_cfg auto '' '["/./usr/bin/test -d {repo_path}"]'; am_no "a merge check with a . component" "component" merge-auto preview
ln -s "$am_w/.claude" "$am_t/linked"; am_cfg auto '' "[\"$am_t/linked/check.sh\"]"
am_no "a merge check whose folder is a link into the repo" "not in hefesto's hooks folder" merge-auto preview
# a link to a system folder is refused too: the folder is judged as written, never resolved — a lane could re-point
# the link between the check and the run
ln -s /usr/bin "$am_t/binlink"; am_cfg auto '' "[\"$am_t/binlink/test -d {repo_path}\"]"
am_no "a merge check through a link to a system bin folder" "not in hefesto's hooks folder" merge-auto preview
# one tokeniser for the rule and the run (third review: a leading blank hid the program from the rule, not from read -a)
am_cfg auto '' '[" {repo_path}/.claude/check.sh"]'; am_no "a merge check with a leading blank" "blank" merge-auto preview
am_cfg auto '' '["\t{repo_path}/.claude/check.sh"]'; am_no "a merge check with a tab" "control character" merge-auto preview
# an interpreter is refused by its name wherever it lives: /bin/sh is sh, /usr/bin/env is env
am_cfg auto '' '["/bin/sh {repo_path}/.claude/check.sh"]'; am_no "a merge check run by /bin/sh" "shell or interpreter" merge-auto preview
am_cfg auto '' '["/usr/bin/env PATH={repo_path}/.claude npm test"]'; am_no "a merge check run by /usr/bin/env" "shell or interpreter" merge-auto preview
# fourth review: exec wrappers run their argument too, and on a case-insensitive disk (macOS) /bin/SH is sh
am_cfg auto '' '["stdbuf -o0 {repo_path}/.claude/check.sh"]'; am_no "a merge check run by stdbuf" "shell or interpreter" merge-auto preview
am_cfg auto '' '["/bin/SH {repo_path}/.claude/check.sh"]'; am_no "a merge check run by /bin/SH" "shell or interpreter" merge-auto preview
am_cfg auto '' "[\"$REPO/hooks/changelog-check.sh -C {repo_path} placement --base origin/{base}\", \"test -d {repo_path}\", \"/usr/bin/test -d {repo_path}\"]"
am_ok "merge checks by bare name, in hefesto's hooks folder or a system bin folder" merge-auto preview
am_cfg auto
# SC-008: grant refused from a worker, from a lane other than the orchestrator, without a name, with a stale sha
am_s="$(am merge-auto preview 2>/dev/null | sed -n 's/^sha256: //p')"
o="$(cd "$am_w" && HEFESTO_WORKER=1 bash "$REPO/hooks/ledger.sh" merge-auto grant --sha "${am_s:0:12}" --reviewed-by-human --by Ana 2>&1)" && { bad "merge-auto grant must be refused inside a launched worker (SC-008)"; x_fail=1; }
o="$(cd "$am_w" && CLAUDE_CODE_SESSION_ID=sid-am-deploy-0001 bash "$REPO/hooks/ledger.sh" merge-auto grant --sha "${am_s:0:12}" --reviewed-by-human --by Ana 2>&1)" \
  && { bad "merge-auto grant must be refused from the deployer lane (SC-008)"; x_fail=1; }
grep -qF "orchestrator lane" <<<"$o" || { bad "the lane refusal of merge-auto grant must name the orchestrator lane — got: $(head -c 200 <<<"$o")"; x_fail=1; }
am_no "merge-auto grant without --by" "--by" merge-auto grant --sha "${am_s:0:12}" --reviewed-by-human
am_no "merge-auto grant with a sha that is not the preview's" "not the preview" merge-auto grant --sha 0123456789ab --reviewed-by-human --by Ana
am_no "merge-auto show with no grant" "no grant" merge-auto show
[ "$(am merge-by 2>/dev/null)" = person ] || { bad "a refused grant must leave merge_by auto behaving as person"; x_fail=1; }
o="$(cd "$am_w" && CLAUDE_CODE_SESSION_ID=sid-am-orchestrator-0001 bash "$REPO/hooks/ledger.sh" merge-auto grant --sha "${am_s:0:12}" --reviewed-by-human --by Ana 2>&1)" \
  || { bad "merge-auto grant from the orchestrator lane must pass — got: $(head -c 300 <<<"$o")"; x_fail=1; }
[ "$(am merge-by 2>/dev/null)" = auto ] || { bad "merge_by auto with a matching grant must resolve to auto (FR-003) — got '$(am merge-by 2>&1)'"; x_fail=1; }
jq -e '.by == "Ana" and (.sha256 | length) == 64 and .repos["."].integration == "dev"' <<<"$(am merge-auto show 2>/dev/null)" >/dev/null 2>&1 \
  || { bad "merge-auto show must print the grant (by, sha256, repos) — got $(am merge-auto show 2>&1 | head -c 200)"; x_fail=1; }
# FR-003: any pinned value that changes after the grant → person, naming the mismatch
am_cfg auto '' '["test -d {repo_path}"]'
[ "$(am merge-by 2>/dev/null)" = person ] && am merge-by 2>&1 >/dev/null | grep -qF "no longer matches" || { bad "a changed merge check after the grant must resolve to person, naming the mismatch (FR-003)"; x_fail=1; }
am_cfg auto; git -C "$am_w" remote set-url origin https://github.com/evil/app.git
[ "$(am merge-by 2>/dev/null)" = person ] || { bad "a changed origin after the grant must resolve to person (FR-003)"; x_fail=1; }
git -C "$am_w" remote set-url origin https://github.com/acme/app.git
am_cfg auto '{"integration": "stg", "environments": ["stg", "main"]}'
[ "$(am merge-by 2>/dev/null)" = person ] || { bad "a changed integration branch after the grant must resolve to person (FR-003)"; x_fail=1; }
am_cfg auto; [ "$(am merge-by 2>/dev/null)" = auto ] || { bad "restoring the pinned values must resolve to auto again"; x_fail=1; }
o="$(cd "$am_w" && CLAUDE_CODE_SESSION_ID=sid-am-deploy-0001 bash "$REPO/hooks/ledger.sh" merge-auto revoke --reviewed-by-human --by Ana 2>&1)" && { bad "merge-auto revoke must be refused from the deployer lane (FR-002)"; x_fail=1; }
am_ok "merge-auto revoke" merge-auto revoke --reviewed-by-human --by Ana
[ "$(am merge-by 2>/dev/null)" = person ] || { bad "after revoke, merge_by auto must resolve to person (FR-002)"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "merge-by: person/lane/auto, an invalid value refused naming it, auto only with a grant equal to a fresh preview (path, origin, integration, checks); merge-auto: preview pins and hashes, main/final/protected integration refused, grant refused from a worker, another lane, no name or a stale sha, show/revoke (HEF-30 FR-001 FR-002 FR-003 SC-008)"

# --- FR-005..FR-007: eligibility — every miss is human:merge, exit 2, and never a merge ---------------------------------
head_ "merge-auto: automerge skips to human:merge on any precondition that does not hold (HEF-30 FR-005 FR-007 SC-002 SC-004)"
x_fail=0; am_cfg auto; am_grant >/dev/null || { bad "the grant for the eligibility cases must pass"; x_fail=1; }
am_entry HEF-2 8 feat2; am_pr 8 feat2 "$(am_sha feat2)" stg
am_case "a PR into an environment branch (SC-002)" HEF-2 2 human:merge "is not the integration branch"
jq -e 'any(.events[]; .kind == "auto-merge-skipped" and (.note | contains("integration branch")))' "$am_ld/HEF-2.json" >/dev/null 2>&1 \
  || { bad "a skipped auto-merge must record an auto-merge-skipped event with the reason (FR-007)"; x_fail=1; }
am_entry HEF-3 9 feat3; am_pr 9 feat3 "$(am_sha feat4)"
am_case "a head that moved since verify (SC-004)" HEF-3 2 human:merge "head moved since verify"
am_entry HEF-4 10 feat4 '.verdicts[1].verdict = "SKIPPED"'; am_pr 10 feat4 "$(am_sha feat4)"
am_case "a SKIPPED review gate (SC-004)" HEF-4 2 human:merge "gate review is not PASS"
am_entry HEF-5 11 feat5 '.verdicts += [{gate: "verify", verdict: "FAIL", by: "v", at: "2026-11-09T01:00:00Z"}]'; am_pr 11 feat5 "$(am_sha feat5)"
am_case "a later FAIL after a PASS (the latest verdict counts)" HEF-5 2 human:merge "gate verify is not PASS"
am_entry HEF-6 12 feat6 '.verdicts = [.verdicts[] | select(.gate != "scan")]'; am_pr 12 feat6 "$(am_sha feat6)"
am_case "a missing scan verdict" HEF-6 2 human:merge "gate scan is not PASS"
am_entry HEF-7 13 feat7 '.item_kind = "incident"'; am_pr 13 feat7 "$(am_sha feat7)"
am_case "an incident with no incident gate" HEF-7 2 human:merge "gate incident is not PASS"
am_entry HEF-8 14 feat8 '.pr.url = "https://github.com/acme/other/pull/14" | .prs[0].url = .pr.url'; am_pr 14 feat8 "$(am_sha feat8)" dev CLEAN acme/other
am_case "a PR from another origin (SC-008)" HEF-8 2 human:merge "is not the pinned origin"
am_entry HEF-9 15 feat9 '.blocked_on = {kind: "human:intake", since: "2026-11-09T00:00:00Z", question_path: null}'; am_pr 15 feat9 "$(am_sha feat9)"
am_case "an entry blocked on human:intake" HEF-9 2 human:intake "blocked on human:intake"
am_cfg auto '' '["test -d {repo_path}"]'; am_entry HEF-10 16 feat10; am_pr 16 feat10 "$(am_sha feat10)"
am_case "a merge check changed after the grant (SC-004)" HEF-10 2 human:merge "no longer matches"
am_cfg lane; am_entry HEF-10 16 feat10
am_case "merge_by lane" HEF-10 2 human:merge "merge_by is lane"
am_cfg auto; am_ok "revoke" merge-auto revoke --reviewed-by-human --by Ana; am_entry HEF-10 16 feat10
am_case "no grant (SC-004, NR-003)" HEF-10 2 human:merge "no grant"
am_grant >/dev/null; am_entry HEF-10 16 feat10 '.phase = "verify"'
am_no "automerge on an entry not at pr" "only an entry at pr" automerge HEF-10
o="$(cd "$am_w" && HEFESTO_WORKER=1 HEFESTO_GH_BIN="$am_t/bin/gh" bash "$REPO/hooks/ledger.sh" automerge HEF-2 2>&1)" && { bad "automerge must be refused inside a launched worker"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "automerge → human:merge (exit 2, an auto-merge-skipped event, no gh pr merge) for an environment base, a moved head, a SKIPPED/FAIL/missing gate, the kind gate, another origin, a changed check, merge_by lane, no grant; a pending human:intake outranks it; refused off pr and in a worker (HEF-30 FR-005 FR-007 SC-002 SC-004 SC-008)"

# --- FR-008, FR-009: remote state and the pinned checks --------------------------------------------------------------
head_ "merge-auto: automerge blocks conflict on BEHIND/DIRTY, ci on red checks or a failing merge check, waits on pending (HEF-30 FR-008 FR-009 SC-003)"
x_fail=0; am_cfg auto; am_grant >/dev/null
am_entry HEF-11 17 feat11; am_pr 17 feat11 "$(am_sha feat11)"
touch "$am_w/.claude/FAILCHECK"
am_case "a failing merge check (SC-003)" HEF-11 3 ci "merge check failed — test ! -e $am_w/.claude/FAILCHECK"
rm -f "$am_w/.claude/FAILCHECK"
jq -e 'any(.events[]; .kind == "auto-merge-skipped" and (.note | contains("merge check failed")))' "$am_ld/HEF-11.json" >/dev/null 2>&1 || { bad "a failing check must be recorded with the command (FR-008)"; x_fail=1; }
am_entry HEF-11 17 feat11; am_pr 17 feat11 "$(am_sha feat11)" dev BEHIND
am_case "a PR behind its base (FR-009)" HEF-11 3 conflict "behind its base"
am_entry HEF-11 17 feat11; am_pr 17 feat11 "$(am_sha feat11)" dev DIRTY
am_case "a conflicting PR (FR-009)" HEF-11 3 conflict "conflicts"
am_entry HEF-11 17 feat11; am_pr 17 feat11 "$(am_sha feat11)"
printf '[{"name":"ci","bucket":"fail","link":"","workflow":"ci"}]\n' > "$am_t/checks.json"
am_case "red CI checks" HEF-11 3 ci "CI checks are red"
# the babysitter fixed CI and reported mergeable: a ci block automerge itself set is re-evaluated, never left stale
rm -f "$am_t/checks.json"
am_case "a ci-blocked entry whose checks turned green" HEF-11 0 none "merged HEF-11"
am_entry HEF-11 17 feat11; am_pr 17 feat11 "$(am_sha feat11)"; printf '[{"name":"ci","bucket":"pending","link":"","workflow":"ci"}]\n' > "$am_t/checks.json"
am_case "pending checks (FR-009)" HEF-11 4 none "pending"
jq -e '.events == [] and .phase == "pr"' "$am_ld/HEF-11.json" >/dev/null 2>&1 || { bad "pending must record nothing (FR-009) — got $(jq -c '{events, phase}' "$am_ld/HEF-11.json")"; x_fail=1; }
rm -f "$am_t/checks.json"
# NR-005 / SC-008: a check the command rule refuses never runs — the sentinel is never created
# (a program the preview admits, an argument the command rule refuses: -c — the run-time check, not the preview's)
am_cfg auto '' "[\"test -c $am_t/SENTINEL\", \"touch $am_t/SENTINEL\"]"; am_grant >/dev/null; am_entry HEF-11 17 feat11
am_case "a granted check the command rule refuses (SC-008)" HEF-11 3 ci "refused by the action scope"
[ ! -e "$am_t/SENTINEL" ] || { bad "a refused check must never run, nor any check after it (NR-005)"; x_fail=1; }
# a bare name is found on the launcher's PATH before the cd into the repo: an empty or . entry never finds a repo file
printf '#!/bin/sh\ntouch %s/BARE\n' "$am_t" > "$am_w/evilbare"; chmod +x "$am_w/evilbare"
am_cfg auto '' '["evilbare"]'; am_grant >/dev/null; am_entry HEF-11 17 feat11; : > "$am_t/gh.log"
o="$(cd "$am_w" && PATH="$PATH:.:" HEFESTO_GH_BIN="$am_t/bin/gh" bash "$REPO/hooks/ledger.sh" automerge HEF-11 2>&1)"; am_rc=$?
{ [ "$am_rc" = 3 ] && grep -qF "not found on PATH" <<<"$o" && [ ! -e "$am_t/BARE" ] && ! am_merged; } \
  || { bad "a bare check name must never resolve into the repo through PATH (NR-005) — rc $am_rc: $(head -c 300 <<<"$o")"; x_fail=1; }
rm -f "$am_w/evilbare"
am_cfg auto; am_grant >/dev/null
[ "$x_fail" -eq 0 ] && ok "automerge: a failing merge check → ci naming the command (no merge); BEHIND and DIRTY → conflict; red CI → ci; pending → exit 4, nothing recorded; a check the command rule refuses never runs (HEF-30 FR-008 FR-009 SC-003 SC-008 NR-005)"

# --- FR-006: the merge, the refusal, and a hand merge -----------------------------------------------------------------
head_ "merge-auto: automerge merges pinned to the verified head and records it; a refused merge blocks ci; --if-merged (HEF-30 FR-006 SC-001 SC-009)"
x_fail=0; am_cfg auto; am_grant >/dev/null
am_entry HEF-12 18 feat12; am_h12="$(am_sha feat12)"; am_pr 18 feat12 "$am_h12"
am_case "four PASS gates into the granted integration branch (SC-001)" HEF-12 0 none "merged HEF-12"
grep -qxF "pr merge 18 -R acme/app --merge --match-head-commit $am_h12" "$am_t/gh.log" \
  || { bad "the merge must be gh pr merge 18 -R acme/app --merge --match-head-commit <verified head> (FR-006) — log: $(tr '\n' '|' < "$am_t/gh.log")"; x_fail=1; }
am_mc="$(jq -r .mergeCommit.oid "$am_t/pr.json")"
jq -e --arg m "$am_mc" '.phase == "merged" and .blocked_on == null and .pr.merge_sha == $m and .pr.merged.via == "commit"
  and any(.events[]; .kind == "auto-merged" and (.note | contains("into dev"))) and all(.events[]; .kind != "auto-merge-skipped")' "$am_ld/HEF-12.json" >/dev/null 2>&1 \
  || { bad "a merged PR must be stamped, advanced to merged, with an auto-merged event and no human:merge ever (FR-006, SC-001) — got $(jq -c '{phase, blocked_on, pr, events}' "$am_ld/HEF-12.json" | head -c 500)"; x_fail=1; }
am_entry HEF-13 19 feat13; am_pr 19 feat13 "$(am_sha feat13)"; touch "$am_t/refuse"
am_case "GitHub refuses the merge (SC-008)" HEF-13 3 ci "gh pr merge refused" tried
jq -e '.phase == "pr" and .pr.merge_sha == null' "$am_ld/HEF-13.json" >/dev/null 2>&1 || { bad "a refused merge must record nothing as merged (FR-008)"; x_fail=1; }
grep -q '^pr merge' "$am_t/gh.log" || { bad "the refused-merge case must have tried gh pr merge"; x_fail=1; }
rm -f "$am_t/refuse"
# D4b / SC-009: --if-merged — open → exit 5, nothing recorded; merged by hand → recorded through the evidence, exit 0
am_entry HEF-14 20 feat14; am_pr 20 feat14 "$(am_sha feat14)"
o="$(am automerge HEF-14 --if-merged 2>&1)"; [ $? = 5 ] || { bad "--if-merged on an open PR must exit 5 — got: $(head -c 200 <<<"$o")"; x_fail=1; }
jq -e '.phase == "pr" and .blocked_on == null and .events == []' "$am_ld/HEF-14.json" >/dev/null 2>&1 || { bad "--if-merged on an open PR must record nothing"; x_fail=1; }
git -C "$am_up" fetch -q origin && git -C "$am_up" checkout -q -B dev origin/dev && am_g "$am_up" merge -q --no-ff -m "Merge pull request #20" origin/feat14 && git -C "$am_up" push -q origin dev 2>/dev/null
jq --arg m "$(git -C "$am_up" rev-parse HEAD)" '.state = "MERGED" | .mergeCommit = {oid: $m}' "$am_t/pr.json" > "$am_t/pr.tmp" && mv "$am_t/pr.tmp" "$am_t/pr.json"
: > "$am_t/gh.log"; o="$(am automerge HEF-14 --if-merged 2>&1)" || { bad "--if-merged on a PR merged by hand must pass — got: $(head -c 300 <<<"$o")"; x_fail=1; }
jq -e '.phase == "merged" and .blocked_on == null and any(.events[]; .kind == "merge-recorded")' "$am_ld/HEF-14.json" >/dev/null 2>&1 \
  || { bad "--if-merged must record a hand merge and advance to merged (SC-009) — got $(jq -c '{phase, blocked_on, events}' "$am_ld/HEF-14.json")"; x_fail=1; }
! am_merged || { bad "--if-merged must never run gh pr merge"; x_fail=1; }
# the same for an entry the babysitter had on ci: a hand merge is recorded, not skipped as "the PR is MERGED"
am_entry HEF-21 27 feat6 '.blocked_on = {kind: "ci", since: "2026-11-09T00:00:00Z", question_path: null}'; am_pr 27 feat6 "$(am_sha feat6)"
git -C "$am_up" fetch -q origin && git -C "$am_up" checkout -q -B dev origin/dev && am_g "$am_up" merge -q --no-ff -m "Merge pull request #27" origin/feat6 && git -C "$am_up" push -q origin dev 2>/dev/null
jq --arg m "$(git -C "$am_up" rev-parse HEAD)" '.state = "MERGED" | .mergeCommit = {oid: $m}' "$am_t/pr.json" > "$am_t/pr.tmp" && mv "$am_t/pr.tmp" "$am_t/pr.json"
o="$(am automerge HEF-21 --if-merged 2>&1)" && jq -e '.phase == "merged" and .blocked_on == null' "$am_ld/HEF-21.json" >/dev/null 2>&1 \
  || { bad "--if-merged must record a hand merge of a ci-blocked entry (SC-009) — got: $(head -c 300 <<<"$o")"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "automerge: gh pr merge <n> -R <origin> --merge --match-head-commit <verified head>, stamped, merged, auto-merged event, no block; GitHub's refusal → ci, nothing merged; --if-merged records a hand merge (exit 0) and leaves an open PR alone (exit 5) (HEF-30 FR-006 SC-001 SC-008 SC-009)"

# --- SC-008: a {repo_path} a granted command cannot carry ---------------------------------------------------------------
head_ "merge-auto: a repo path with a space is refused before any check runs (HEF-30 SC-008)"
x_fail=0; am_w2="$am_t/w sp"
am_repo "$am_w2" && git -C "$am_w2" fetch -q origin 2>/dev/null && git -C "$am_w2" checkout -q -b dev origin/dev 2>/dev/null
cp "$am_w/.claude/project-status.json" "$am_w2/.claude/project-status.json"
am2() { (cd "$am_w2" && HEFESTO_GH_BIN="$am_t/bin/gh" bash "$REPO/hooks/ledger.sh" "$@"); }
am_ld2="$(sld "$am_w2")"; mkdir -p "$am_ld2"
am_s2="$(am2 merge-auto preview 2>/dev/null | sed -n 's/^sha256: //p')"
am2 merge-auto grant --sha "${am_s2:0:12}" --reviewed-by-human --by Ana </dev/null >/dev/null 2>&1 || { bad "the grant in the spaced repo must pass"; x_fail=1; }
am_entry HEF-15 21 feat15; mv "$am_ld/HEF-15.json" "$am_ld2/HEF-15.json"; am_pr 21 feat15 "$(am_sha feat15)"
: > "$am_t/gh.log"; o="$(am2 automerge HEF-15 2>&1)"; am_rc=$?
{ [ "$am_rc" = 3 ] && grep -qF "character" <<<"$o" && [ "$(jq -r .blocked_on.kind "$am_ld2/HEF-15.json")" = ci ] && ! am_merged; } \
  || { bad "a repo path with a space must block ci before any check or merge (SC-008) — rc $am_rc: $(head -c 300 <<<"$o")"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "automerge: a pinned repo path with a space blocks ci, naming it, before any check or merge (HEF-30 SC-008)"

# --- FR-004, FR-010: the launcher — verify leaves the entry unblocked at pr under auto; deploy merges with no worker -----
head_ "merge-auto: session-launch under auto — verify records the head and sets no human:merge; deploy auto-merges before any babysitter (HEF-30 FR-004 FR-010 SC-009)"
x_fail=0; am_cfg auto; am_grant >/dev/null
am_cb="$am_t/cbin"; mkdir -p "$am_cb" "$am_t/ccfg"
# a fake claude: logs its call and prints the result the test put in result.json
printf '#!/bin/bash\necho "$*" >> %q/claude.log\ncat %q/result.json\n' "$am_t" "$am_t" > "$am_cb/claude"; chmod +x "$am_cb/claude"
aml() { (cd "$am_w" && PATH="$am_cb:$PATH" CLAUDE_CONFIG_DIR="$am_t/ccfg" HEFESTO_GH_BIN="$am_t/bin/gh" bash "${AM_SL:-$REPO/hooks/session-launch.sh}" "$@"); }
git -C "$am_w" worktree add -q "$am_w/.claude/worktrees/HEF-16" feat16 2>/dev/null
am_entry HEF-16 22 feat16 '.phase = "verify" | .verdicts = [] | .route = "fix" | del(.pr.verified_head) | del(.prs[0].verified_head)'
jq --arg wt "$am_w/.claude/worktrees/HEF-16" '.worktree = $wt' "$am_ld/HEF-16.json" > "$am_t/e.json" && mv "$am_t/e.json" "$am_ld/HEF-16.json"
printf '{"session_id":"v1","total_cost_usd":0,"structured_output":{"summary":"ok","verdicts":[%s]}}\n' \
  '{"gate":"verify","verdict":"PASS"},{"gate":"review","verdict":"PASS"},{"gate":"quality","verdict":"PASS"},{"gate":"scan","verdict":"PASS"}' > "$am_t/result.json"
o="$(aml verify HEF-16 2>&1)" || { bad "session-launch verify under auto must pass — got: $(tail -c 300 <<<"$o")"; x_fail=1; }
jq -e --arg h "$(am_sha feat16)" '.phase == "pr" and .blocked_on == null and .pr.verified_head == $h' "$am_ld/HEF-16.json" >/dev/null 2>&1 \
  || { bad "verify under resolved auto must record the verified head and leave the entry at pr unblocked (FR-004, SC-009) — got $(jq -c '{phase, blocked_on, pr}' "$am_ld/HEF-16.json")"; x_fail=1; }
am_pr 22 feat16 "$(am_sha feat16)"; : > "$am_t/gh.log"; : > "$am_t/claude.log"
o="$(aml deploy HEF-16 2>&1)" || { bad "session-launch deploy under auto must pass — got: $(tail -c 300 <<<"$o")"; x_fail=1; }
{ jq -e '.phase == "merged" and .blocked_on == null' "$am_ld/HEF-16.json" >/dev/null 2>&1 && am_merged && [ ! -s "$am_t/claude.log" ]; } \
  || { bad "deploy under auto must merge through ledger.sh automerge before any babysitter, launching no worker (FR-010) — entry $(jq -c '{phase, blocked_on}' "$am_ld/HEF-16.json"), claude calls: $(wc -l < "$am_t/claude.log")"; x_fail=1; }
# FR-001 / SC-008: an invalid merge_by stops the deploy launch, naming it — never read as person
git -C "$am_w" worktree add -q "$am_w/.claude/worktrees/HEF-17" feat3 2>/dev/null
am_cfg person; am_entry HEF-17 23 feat3
jq --arg wt "$am_w/.claude/worktrees/HEF-17" '.worktree = $wt' "$am_ld/HEF-17.json" > "$am_t/e.json" && mv "$am_t/e.json" "$am_ld/HEF-17.json"
o="$(aml deploy HEF-17 --dry-run 2>&1)" || { bad "the control: a deploy --dry-run under merge_by person must pass — got: $(tail -c 300 <<<"$o")"; x_fail=1; }
am_cfg bogus
o="$(aml deploy HEF-17 --dry-run 2>&1)" && { bad "an invalid merge_by must stop the deploy launch (FR-001, FR-010)"; x_fail=1; }
grep -qF "session-launch deploy HEF-17: ledger.sh merge-by failed" <<<"$o" || { bad "the stopped deploy launch must name ledger.sh merge-by — got: $(tail -c 300 <<<"$o")"; x_fail=1; }
# under person the verify path is as before: human:merge
am_cfg person; am_entry HEF-18 24 feat2 '.phase = "verify" | .verdicts = [] | .route = "fix"'
git -C "$am_w" worktree add -q "$am_w/.claude/worktrees/HEF-18" feat2 2>/dev/null
jq --arg wt "$am_w/.claude/worktrees/HEF-18" '.worktree = $wt' "$am_ld/HEF-18.json" > "$am_t/e.json" && mv "$am_t/e.json" "$am_ld/HEF-18.json"
aml verify HEF-18 >/dev/null 2>&1; jq -e '.phase == "pr" and .blocked_on.kind == "human:merge"' "$am_ld/HEF-18.json" >/dev/null 2>&1 \
  || { bad "verify under merge_by person must still block human:merge — got $(jq -c '{phase, blocked_on}' "$am_ld/HEF-18.json")"; x_fail=1; }
am_cfg auto
[ "$x_fail" -eq 0 ] && ok "session-launch: verify under resolved auto records .pr.verified_head and leaves the entry at pr unblocked (person still blocks human:merge); deploy runs ledger.sh automerge before any babysitter and merges with no worker; merge_by: bogus stops the launch naming merge-by (HEF-30 FR-004 FR-010 SC-009)"

# --- FR-015 / SC-005: setup writes orchestrate.decider once, never over a person's value; ask rules for the grant ------
head_ "merge-auto: hefesto-setup.sh writes orchestrate.decider from git config user.name only when absent; grant/revoke ask (HEF-30 FR-015 SC-005)"
x_fail=0; am_sp="$am_t/setup"; am_sh="$am_t/setup-home"; mkdir -p "$am_sh"
git init -q -b main "$am_sp" && am_g "$am_sp" commit -q --allow-empty -m init && mkdir -p "$am_sp/.claude"
printf '{"orchestrate":{"merge_by":"auto"}}\n' > "$am_sp/.claude/project-status.json"; git -C "$am_sp" config user.name "Ana Souza"
amu() { (cd "$am_sp" && HOME="$am_sh" CLAUDE_CONFIG_DIR='' bash "${AM_SU:-$REPO/hooks/hefesto-setup.sh}" "$@" 2>&1); }
am_o="$(amu --print)"
{ grep -qF 'decider: orchestrate.decider: "Ana Souza"' <<<"$am_o" && ! jq -e '.orchestrate | has("decider")' "$am_sp/.claude/project-status.json" >/dev/null; } \
  || { bad "setup --print must show the decider it would write and write nothing (FR-015) — got: $(tail -c 300 <<<"$am_o")"; x_fail=1; }
am_o="$(amu)"
[ "$(jq -r '.orchestrate.decider' "$am_sp/.claude/project-status.json")" = "Ana Souza" ] && [ "$(jq -r '.orchestrate.merge_by' "$am_sp/.claude/project-status.json")" = auto ] \
  || { bad "setup must write orchestrate.decider from git config user.name when it is absent, keeping the rest (FR-015, SC-005) — got $(cat "$am_sp/.claude/project-status.json"); output: $(tail -c 300 <<<"$am_o")"; x_fail=1; }
jq -e --arg h "$REPO/hooks" '(.permissions.ask | index(["Bash(\($h)/ledger.sh merge-auto grant:*)"])) and (.permissions.ask | index(["Bash(bash \($h)/ledger.sh merge-auto revoke:*)"]))
  and (.permissions.allow | index(["Bash(\($h)/ledger.sh merge-by:*)"])) and (.permissions.allow | map(select(test("merge-auto (grant|revoke)"))) | length == 0)' \
  "$am_sp/.claude/settings.local.json" >/dev/null 2>&1 || { bad "setup's ask rules must hold ledger.sh merge-auto grant/revoke in both spellings, never in allow (FR-015)"; x_fail=1; }
git -C "$am_sp" config user.name "Bob"; amu >/dev/null
[ "$(jq -r '.orchestrate.decider' "$am_sp/.claude/project-status.json")" = "Ana Souza" ] || { bad "setup must never overwrite orchestrate.decider (FR-015, SC-005)"; x_fail=1; }
amu --remove >/dev/null
[ "$(jq -r '.orchestrate.decider' "$am_sp/.claude/project-status.json")" = "Ana Souza" ] || { bad "setup --remove must leave orchestrate.decider (FR-015)"; x_fail=1; }
printf '{"orchestrate":{}}\n' > "$am_sp/.claude/project-status.json"; git -C "$am_sp" config user.name ""
am_o="$(amu)"
{ ! jq -e '.orchestrate | has("decider")' "$am_sp/.claude/project-status.json" >/dev/null && grep -qF "user.name is empty" <<<"$am_o"; } \
  || { bad "with an empty git user.name setup must write no decider and say so (US6, FR-015) — got: $(tail -c 300 <<<"$am_o")"; x_fail=1; }
# a name the ledger would refuse as --by (person_gate's rule) is never written: the decider must be usable (FR-015)
git -C "$am_sp" config user.name "Ana;rm"; am_o="$(amu)"
{ ! jq -e '.orchestrate | has("decider")' "$am_sp/.claude/project-status.json" >/dev/null && grep -qF "not a name the ledger accepts" <<<"$am_o"; } \
  || { bad "setup must not write a decider the ledger refuses as --by, and say so (FR-015) — got: $(tail -c 300 <<<"$am_o")"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "hefesto-setup.sh: --print shows the decider and writes nothing; writes orchestrate.decider from git user.name when absent, never over it, kept by --remove, none for an empty name; merge-auto grant/revoke ask in both spellings (HEF-30 FR-015 SC-005)"

# --- FR-016: the docs and the CHANGELOG describe auto, the grant, the batched form and the decider -------------------------
head_ "merge-auto: the docs describe merge_by auto, the grant, the one merge form and orchestrate.decider (HEF-30 FR-016)"
x_fail=0
for am_d in docs/quickstart.md docs/quickstart.pt-BR.md docs/install.md; do
  for am_w3 in '"merge_by": "auto"' 'merge-auto grant' 'merge-auto revoke' '"decider"' 'split on whitespace' 'sem shell'; do
    case "$am_d:$am_w3" in docs/install.md:*'"'*|docs/quickstart.md:'sem shell'|docs/quickstart.pt-BR.md:'split on whitespace'|docs/install.md:'sem shell') continue ;; esac
    grep -qF -- "$am_w3" "$REPO/$am_d" || { bad "$am_d must say: $am_w3 (merge-auto FR-016)"; x_fail=1; }
  done
done
for am_w3 in '`auto`' 'ledger.sh merge-auto preview' '`decider`' 'one merge form per pass'; do
  grep -qF -- "$am_w3" "$REPO/docs/install.md" || { bad "docs/install.md must say: $am_w3 (merge-auto FR-016)"; x_fail=1; }
done
grep -qF 'ledger.sh automerge' "$REPO/docs/architecture.md" || { bad "docs/architecture.md must name ledger.sh automerge (merge-auto FR-016)"; x_fail=1; }
am_un="$(awk '/^## \[Unreleased\]/{f=1; next} /^## \[/{f=0} f' "$REPO/CHANGELOG.md")"   # captured: `awk | grep -q` races under pipefail
grep -qF 'orchestrate.merge_by: "auto"' <<<"$am_un" \
  || { bad "CHANGELOG.md's Unreleased section must describe merge_by auto (merge-auto FR-016)"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "docs: quickstart (en, pt-BR) and install describe merge_by auto, the grant and revoke, the decider, checks run without a shell, the one merge form; architecture names ledger.sh automerge; CHANGELOG Unreleased (HEF-30 FR-016)"

git -C "$am_w" worktree prune 2>/dev/null
rm -rf -- "${am_t:?}"; rm -f "$HOME"/.cache/hefesto/sessions/sid-am-*-0001.json
