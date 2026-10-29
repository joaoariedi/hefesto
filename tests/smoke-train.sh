# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
#
# lanes-parity (9.1) smoke checks, part 7 — a release train promotes several repos in order (T022: US8, FR-019;
# plan Sketch 13, Sketch 14, note 19).
#
# SOURCED by tests/smoke.sh after the other lifecycle parts, never run on its own. Self-contained: an external board
# feeding two code repos (api, ui), each with a bare origin and the branch model dev → stg → main declared on the
# board; a named fake gh (FakeGhTrain: one JSON file per PR number, the -q/--jq filter applied by jq); the real
# ledger.sh for request/approve/take/step/done, and lane-guard.sh fed a hand-written session record.

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ sld >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-train.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_, sld)"
  else echo "tests/smoke-train.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

head_ "Release train: request --train drafts one action over the repos in order; done checks each PR's base (US8)"
x_fail=0
tr_t="$(cd "$(mktemp -d)" && pwd -P)"; tr_g() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
for tr_r in api ui; do   # each repo: origin with dev, stg, main; dev one commit ahead (the promotion PR's head)
  git init -q --bare -b main "$tr_t/$tr_r.git" && git init -q -b main "$tr_t/$tr_r" && tr_g "$tr_t/$tr_r" commit -q --allow-empty -m init \
    && git -C "$tr_t/$tr_r" remote add origin "$tr_t/$tr_r.git" && git -C "$tr_t/$tr_r" branch stg && git -C "$tr_t/$tr_r" checkout -q -b dev \
    && tr_g "$tr_t/$tr_r" commit -q --allow-empty -m "$tr_r change" && git -C "$tr_t/$tr_r" push -q origin main stg dev 2>/dev/null \
    && git -C "$tr_t/$tr_r" checkout -q main
done
tr_b="$tr_t/board"; git init -q -b main "$tr_b" && tr_g "$tr_b" commit -q --allow-empty -m init; mkdir -p "$tr_b/.claude" "$tr_t/bin"
tr_bm='{"integration": "dev", "environments": ["dev", "stg", "main"]}'
jq -n --argjson bm "$tr_bm" '{name: "board", repos: {api: {path: "../api", branches: $bm}, ui: {path: "../ui", branches: $bm}},
  orchestrate: {merge_by: "lane", merge: {checks: ["changelog-check.sh -C {repo_path} placement --base origin/{base}"]},
    deploy: {trains: {app: {repos: ["api", "ui"], order: ["api", "ui"]}, stray: {repos: ["api", "web"], order: ["api", "web"]}}}}}' \
  > "$tr_b/.claude/project-status.json"
# FakeGhTrain: `pr view <n|url>` answers from $tr_t/pr-<n>.json (through -q/--jq when given), auth is fine.
cat > "$tr_t/bin/gh" <<EOF
#!/bin/bash
echo "\$*" >> "$tr_t/gh.log"
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "pr checks") echo '[]'; exit 0 ;;
  "pr view") n="\${3##*/}"; q=""; while [ \$# -gt 0 ]; do case "\$1" in -q|--jq) q="\$2"; shift ;; esac; shift; done
             [ -f "$tr_t/pr-\$n.json" ] || { echo "FakeGhTrain: no PR \$n" >&2; exit 1; }
             if [ -n "\$q" ]; then jq -r "\$q" "$tr_t/pr-\$n.json"; else cat "$tr_t/pr-\$n.json"; fi ;;
  *) echo "FakeGhTrain: unexpected gh \$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tr_t/bin/gh"
tr_pr() { # tr_pr <n> <repo> <head sha> [state] [merge commit] [head branch] [base] → writes the fake PR
  jq -n --argjson n "$1" --arg r "$2" --arg h "$3" --arg st "${4:-OPEN}" --arg mc "${5:-}" --arg hb "${6:-dev}" --arg base "${7:-stg}" \
    '{number: $n, url: "https://github.com/acme/\($r)/pull/\($n)", state: $st, isDraft: false, mergeable: "MERGEABLE", mergeStateStatus: "CLEAN",
      reviewDecision: "", headRefName: $hb, baseRefName: $base, headRefOid: $h, mergeCommit: (if $mc == "" then null else {oid: $mc} end)}' > "$tr_t/pr-$1.json"
}
tr_sha() { git -C "$tr_t/$1" rev-parse "$2"; }
tr_api="$(tr_sha api dev)"; tr_ui="$(tr_sha ui dev)"; tr_pr 5 api "$tr_api"; tr_pr 6 ui "$tr_ui"
trn() { (cd "$tr_b" && HEFESTO_GH_BIN="$tr_t/bin/gh" bash "$REPO/hooks/ledger.sh" "$@"); }   # trn <ledger args…>
tr_ld="$(sld "$tr_b")"
tr_ok() { local l="$1" o; shift; o="$(trn "$@" 2>&1)" || { bad "$l must pass — got: $(head -c 300 <<<"$o")"; x_fail=1; }; }
tr_no() { # tr_no <label> <text the refusal must name> <ledger args…>: must be refused, naming it
  local l="$1" need="$2" o; shift 2
  o="$(trn "$@" 2>&1)" && { bad "$l must be refused"; x_fail=1; return; }
  grep -qF -- "$need" <<<"$o" || { bad "$l: the refusal must name '$need' — got: $(head -c 300 <<<"$o")"; x_fail=1; }
}
[ "$(trn op new --title "promote app to stg" 2>&1)" = OP-1 ] || { bad "op new must create OP-1 on the board"; x_fail=1; }
# FR-019 errors: a missing PR, a repo not in the board, a PR for a repo outside the train, an env outside the model
tr_no "a train missing a repo's PR" "--pr ui=" request OP-1 --to repo-deployer --train app --env stg --pr api=5
tr_no "a train naming a repo the board does not feed" "web" request OP-1 --to repo-deployer --train stray --env stg --pr api=5 --pr web=7
tr_no "a --pr for a repo outside the train" "zzz" request OP-1 --to repo-deployer --train app --env stg --pr api=5 --pr ui=6 --pr zzz=8
tr_no "a repo's --pr given twice" "given twice" request OP-1 --to repo-deployer --train app --env stg --pr api=5 --pr api=7 --pr ui=6
tr_no "--merge with --train" "pass one" request OP-1 --to repo-deployer --train app --env stg --pr api=5 --pr ui=6 --merge
tr_no "an unknown train" "no such train" request OP-1 --to repo-deployer --train nope --env stg --pr api=5 --pr ui=6
tr_no "an env outside the repo's branch model" "qa" request OP-1 --to repo-deployer --train app --env qa --pr api=5 --pr ui=6
tr_pr 6 ui "$tr_ui" OPEN "" dev main   # a PR into main, asked for as a promotion to stg
tr_no "a train PR whose base is not the env" "targets 'main', not stg" request OP-1 --to repo-deployer --train app --env stg --pr api=5 --pr ui=6
tr_pr 6 ui "$tr_ui"
# {repo_path} goes into a granted pattern: a path with a space (it would split) or a * (it would widen) is refused
cp "$tr_b/.claude/project-status.json" "$tr_t/ps.json"
for tr_sp in "sp ace" "st*ar"; do
  git clone -q "$tr_t/api.git" "$tr_t/$tr_sp" 2>/dev/null; tr_pr 9 sp "$tr_api"   # a git repo, so the board resolves it
  jq --arg p "../$tr_sp" --argjson bm "$tr_bm" '.repos.sp = {path: $p, branches: $bm} | .orchestrate.deploy.trains.odd = {repos: ["api", "sp"], order: ["api", "sp"]}' \
    "$tr_t/ps.json" > "$tr_b/.claude/project-status.json"
  tr_no "a train repo at '$tr_sp'" "has a character" request OP-1 --to repo-deployer --train odd --env stg --pr api=5 --pr sp=9
done
cp "$tr_t/ps.json" "$tr_b/.claude/project-status.json"
[ -z "$(find "$tr_ld/actions" -name 'OP-1-A*.json' 2>/dev/null)" ] || { bad "a refused train request must write no action"; x_fail=1; }
# FR-019: per repo in order — state, the checks (-C {repo_path}, {base} = the env), the pinned merge — each gated by after_step
tr_ok "request OP-1 --train app" request OP-1 --to repo-deployer --train app --env stg --pr api=5 --pr ui=6
tr_ca="changelog-check.sh -C $tr_t/api placement --base origin/stg"; tr_cu="changelog-check.sh -C $tr_t/ui placement --base origin/stg"
tr_ma="gh pr merge 5 -R acme/api --merge --match-head-commit $tr_api"; tr_mu="gh pr merge 6 -R acme/ui --merge --match-head-commit $tr_ui"
jq -e --arg ca "$tr_ca" --arg cu "$tr_cu" --arg ma "$tr_ma" --arg mu "$tr_mu" --arg a "$tr_api" --arg u "$tr_ui" '.status == "pending"
  and .scope.kind == "train" and .scope.irreversible == true and .scope.heads == {"acme/api#5": $a, "acme/ui#6": $u}
  and (.scope.steps | length) == 6 and (.scope.steps[0] | startswith("api: state")) and (.scope.steps[2] | startswith("api: merge"))
  and (.scope.steps[3] | startswith("ui: state")) and (.scope.steps[5] | startswith("ui: merge"))
  and .scope.commands == [{cmd: $ca, after_step: 1}, {cmd: $ma, after_step: 2}, {cmd: $cu, after_step: 4}, {cmd: $mu, after_step: 5}]' \
  "$tr_ld/actions/OP-1-A1.json" >/dev/null 2>&1 \
  || { bad "request --train must draft api's state → check → merge, then ui's, each gated by after_step (FR-019) — got: $(jq -c .scope "$tr_ld/actions/OP-1-A1.json" 2>&1 | head -c 700)"; x_fail=1; }
tr_h="$(jq -r .sha256 "$tr_ld/actions/OP-1-A1.json" 2>/dev/null)"
tr_ok "approve OP-1-A1" approve OP-1-A1 --sha "${tr_h:0:8}" --to repo-deployer --title "$(jq -r .scope.title "$tr_ld/actions/OP-1-A1.json" 2>/dev/null)" \
  --irreversible-confirmed --reviewed-by-human --by Ana
# FR-022: a train plus a merge action on one repo is refused
jq -n '{id: "HEF-1", item_kind: "feature", repo: "api", phase: "pr", owner: null, branch: "feat",
  pr: {url: "https://github.com/acme/api/pull/9", number: 9}, prs: [{url: "https://github.com/acme/api/pull/9", number: 9}],
  blocked_on: {kind: "human:merge", since: "2026-10-27T00:00:00Z", question_path: null}, runs: [], attempts: 0}' > "$tr_ld/HEF-1.json"
tr_pr 9 api "$tr_api" OPEN "" feat dev
tr_no "a merge action on a repo an approved train holds" "OP-1-A1" request HEF-1 --to repo-deployer --merge
# note 10 (T022 verifier): take and heads fetch in EVERY repo of the train, so each placement check compares against
# the current origin/<base>, never what the clone last fetched
tr_moveup() { # tr_moveup <repo> <label>: a new commit on the repo's origin stg, from a separate clone
  local u="$tr_t/up-$1"; [ -d "$u" ] || git clone -q "$tr_t/$1.git" "$u"
  git -C "$u" fetch -q origin && git -C "$u" checkout -q -B stg origin/stg && tr_g "$u" commit -q --allow-empty -m "$2" && git -C "$u" push -q origin stg 2>/dev/null
}
tr_fresh() { # tr_fresh <verb>: each repo's origin/stg is the upstream one
  local r; for r in api ui; do
    [ "$(git -C "$tr_t/$r" rev-parse origin/stg)" = "$(git -C "$tr_t/$r.git" rev-parse stg)" ] \
      || { bad "action $1 on a train must git fetch --prune origin in $r (note 10)"; x_fail=1; }
  done
}
tr_moveup api "stg moved before take"; tr_moveup ui "stg moved before take"
# forensic review of PR B: take's fetch runs unsandboxed, so a remote.origin.uploadpack planted in a repo's
# .git/config (run locally for a path remote) must not run
printf '#!/bin/sh\ntouch %s/ESCAPED\nexit 1\n' "$tr_t" > "$tr_t/canary.sh"; chmod +x "$tr_t/canary.sh"
git -C "$tr_t/api" config remote.origin.uploadpack "$tr_t/canary.sh"
git -C "$tr_t/api" fetch -q origin >/dev/null 2>&1; [ -f "$tr_t/ESCAPED" ] || { bad "the uploadpack canary did not fire on a plain fetch — the fixture is dead"; x_fail=1; }; rm -f "$tr_t/ESCAPED"
tr_ok "take OP-1-A1" action take OP-1-A1; tr_fresh take
[ ! -f "$tr_t/ESCAPED" ] || { bad "take's git fetch ran the repository's remote.origin.uploadpack — a way out of the sandbox"; x_fail=1; }
git -C "$tr_t/api" config --unset remote.origin.uploadpack
# and the ext:: transport (what a url.*.insteadOf would rewrite origin to) and core.sshCommand never run under it
# (the repo opts ext in itself; GIT_SSH_COMMAND, which a sandbox may set, is dropped so core.sshCommand is live)
tr_x="$tr_t/xport"; git init -q "$tr_x"; git -C "$tr_x" remote add origin "ext::$tr_t/canary.sh %S"; git -C "$tr_x" config protocol.ext.allow always
git -C "$tr_x" remote add sshr "ssh://example.invalid/r.git"; git -C "$tr_x" config core.sshCommand "$tr_t/canary.sh"
git -C "$tr_x" remote add gitr "git://example.invalid/r.git"; git -C "$tr_x" config core.gitProxy "$tr_t/canary.sh"
for tr_rm in origin sshr gitr; do
  env -u GIT_SSH_COMMAND -u GIT_SSH git -C "$tr_x" fetch -q "$tr_rm" >/dev/null 2>&1
  [ -f "$tr_t/ESCAPED" ] || { bad "the $tr_rm canary did not fire on a plain fetch — the fixture is dead"; x_fail=1; }; rm -f "$tr_t/ESCAPED"
  env -u GIT_SSH_COMMAND -u GIT_SSH bash -c '. "$1/hooks/lane-lib.sh"; hef_git_neutral; git -C "$2" fetch -q "$3"' _ "$REPO" "$tr_x" "$tr_rm" >/dev/null 2>&1
  [ ! -f "$tr_t/ESCAPED" ] || { bad "hef_git_neutral must stop a fetch of '$tr_rm' running a program from .git/config"; x_fail=1; rm -f "$tr_t/ESCAPED"; }
done
# every fetch a hook runs passes --upload-pack (hef_fetch_origin, or the launcher's GIT_FETCH_SAFE) — the launcher
# fetches in the lane's repo at every pass (code review of PR B) — except /hef.doctor's, in the plugin's own clone;
# and the launcher, which does not source lane-lib.sh, pins the same keys as HEF_GIT_NEUTRAL
tr_safe="$(sed -n 's/^GIT_FETCH_SAFE=(\([^)]*\)).*$/\1/p' "$REPO/hooks/session-launch.sh")"   # the launcher's fetch words, expanded
[ -n "$tr_safe" ] || { bad "session-launch.sh must define GIT_FETCH_SAFE, the words of its fetches"; x_fail=1; }
tr_bare="$(for tr_f in "$REPO"/hooks/*.sh; do [ "${tr_f##*/}" = speckit-helper.sh ] && continue
  sed -E "s/\"\\\$\{GIT_FETCH_SAFE\[@\]\}\"/$tr_safe/g" "$tr_f" | sed -E 's/"[^"]*"//g; s/#.*$//' | grep -nE '(^|[^A-Za-z_-])git( -C +[^ ]*)?( -c +[^ ]*)* fetch' | grep -v -- '--upload-pack=git-upload-pack' | sed "s|^|${tr_f##*/}:|"; done)"
[ -z "$tr_bare" ] || { bad "a hook runs git fetch without --upload-pack=git-upload-pack: $tr_bare"; x_fail=1; }
tr_nl="$(sed -n 's/^HEF_GIT_NEUTRAL="\(.*\)"$/\1/p' "$REPO/hooks/lane-lib.sh")"
grep -qF "for kv in $tr_nl; do" "$REPO/hooks/session-launch.sh" || { bad "session-launch.sh must pin the same git keys as lane-lib.sh's HEF_GIT_NEUTRAL ($tr_nl)"; x_fail=1; }
tr_moveup api "stg moved before heads"; tr_moveup ui "stg moved before heads"
tr_ok "heads OP-1-A1" action heads OP-1-A1; tr_fresh heads
mkdir -p "$HOME/.cache/hefesto/sessions"
jq -nc --arg l "$tr_ld" '{title: "repo-deployer", role: "deploy", name: "repo-deployer", lanes: true, worker: false,
  ledger: $l, excluded: ["gh *", "changelog-check.sh *"]}' > "$HOME/.cache/hefesto/sessions/sid-tr-deployer-0001.json"
tr_gd() { # tr_gd <command> → allow | deny | none
  local o; o="$(jq -nc --arg c "$1" --arg d "$tr_b" '{tool_name: "Bash", tool_input: {command: $c}, session_id: "sid-tr-deployer-0001", cwd: $d}' \
    | bash "$REPO/hooks/lane-guard.sh" 2>/dev/null)"
  [ -n "$o" ] || { echo none; return; }; jq -r '.hookSpecificOutput.permissionDecision // "none"' <<<"$o" 2>/dev/null || echo none
}
printf 'mergeable\n' > "$tr_t/ev.md"
# Sketch 13/14: the second repo's merge is denied until the first repo's steps are recorded — steps go in order
[ "$(tr_gd "$tr_mu")" != allow ] || { bad "ui's merge must not be granted before any step is recorded"; x_fail=1; }
tr_no "recording ui's check before api's steps" "in order" action step OP-1-A1 5 --evidence-file "$tr_t/ev.md"
[ "$(tr_gd "$tr_mu")" != allow ] || { bad "ui's merge must stay denied while api's steps are unrecorded (FR-019)"; x_fail=1; }
for tr_n in 1 2; do tr_ok "step $tr_n" action step OP-1-A1 "$tr_n" --evidence-file "$tr_t/ev.md"; done
[ "$(tr_gd "$tr_ma")" = allow ] || { bad "api's merge must be granted once api's state and check are recorded"; x_fail=1; }
[ "$(tr_gd "$tr_mu")" != allow ] || { bad "ui's merge must stay denied until ui's own steps are recorded"; x_fail=1; }
for tr_n in 3 4 5; do tr_ok "step $tr_n" action step OP-1-A1 "$tr_n" --evidence-file "$tr_t/ev.md"; done
[ "$(tr_gd "$tr_mu")" = allow ] || { bad "ui's merge must be granted once every earlier step is recorded"; x_fail=1; }
tr_ok "step 6" action step OP-1-A1 6 --evidence-file "$tr_t/ev.md"
# done: per head, in its repo, MERGED + head == pinned + the merge commit in the PR's BASE (stg), not integration
tr_up() { # tr_up <repo> <into branch> → merges origin/dev into that branch upstream, prints the merge commit
  local u="$tr_t/up-$1"; [ -d "$u" ] || git clone -q "$tr_t/$1.git" "$u"
  git -C "$u" fetch -q origin && git -C "$u" checkout -q -B "$2" "origin/$2" && tr_g "$u" merge -q --no-ff -m "Merge pull request" origin/dev \
    && git -C "$u" push -q origin "$2" 2>/dev/null && git -C "$u" rev-parse HEAD
}
tr_pr 5 api "$tr_api" MERGED "$(tr_up api stg)"; tr_pr 6 ui "$tr_ui" MERGED "$(tr_up ui main)"
tr_no "done while ui's merge commit is only in main" "base stg" action "done" OP-1-A1 --evidence-file "$tr_t/ev.md"
jq -e '.status == "taken"' "$tr_ld/actions/OP-1-A1.json" >/dev/null 2>&1 || { bad "a refused train done must leave the action taken"; x_fail=1; }
tr_pr 6 ui "$(tr_sha api main)" MERGED "$(tr_up ui stg)"
tr_no "done when a PR merged another head than the pinned one" "acme/ui#6" action "done" OP-1-A1 --evidence-file "$tr_t/ev.md"
tr_pr 6 ui "$tr_ui" MERGED "$(git -C "$tr_t/up-ui" rev-parse stg)"
tr_o="$(cd "$tr_b" && HEFESTO_GH_BIN="$tr_t/bin/no-gh" bash "$REPO/hooks/ledger.sh" action "done" OP-1-A1 --evidence-file "$tr_t/ev.md" 2>&1)" \
  && { bad "a train's done must fail closed without gh (note 19)"; x_fail=1; }
grep -qF "gh is not installed" <<<"$tr_o" || { bad "the no-gh refusal must name gh — got: $(head -c 300 <<<"$tr_o")"; x_fail=1; }
git -C "$tr_t/api" config remote.origin.uploadpack "$tr_t/canary.sh"   # done's per-repo fetch, too
tr_ok "done once both merge commits are in stg" action "done" OP-1-A1 --evidence-file "$tr_t/ev.md"
[ ! -f "$tr_t/ESCAPED" ] || { bad "a train done's git fetch ran the repository's remote.origin.uploadpack"; x_fail=1; }
git -C "$tr_t/api" config --unset remote.origin.uploadpack
jq -e '.status == "done"' "$tr_ld/actions/OP-1-A1.json" >/dev/null 2>&1 || { bad "the train action must be done"; x_fail=1; }
jq -e '.phase == "queued"' "$tr_ld/OP-1.json" >/dev/null 2>&1 || { bad "a train's done must move no phase — got: $(jq -c .phase "$tr_ld/OP-1.json")"; x_fail=1; }
jq -e '.phase == "pr"' "$tr_ld/HEF-1.json" >/dev/null 2>&1 || { bad "a train's done must move no item's phase"; x_fail=1; }
rm -rf -- "${tr_t:?}"; rm -f "$HOME"/.cache/hefesto/sessions/sid-tr-*-0001.json
[ "$x_fail" -eq 0 ] && ok "request --train drafts per repo, in order, state → checks ({repo_path}, {base}) → the pinned merge, each gated by after_step; a missing PR, a repo outside the board or the train, an unknown env are refused; steps record in order, so the next repo's merge waits; a train plus a merge on one repo is refused; done checks every head in its own repo (MERGED, pinned head, merge commit in the PR's base), fails closed without gh, and moves no phase (US8 FR-019)"
