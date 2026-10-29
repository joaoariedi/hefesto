# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
#
# lanes-parity (9.1) smoke checks, part 5 — a deploy recipe drafted into one lane action (T020: US7, FR-014, FR-017,
# FR-018, NR-003; plan Sketch 7).
#
# SOURCED by tests/smoke.sh after the other lifecycle parts, never run on its own. Self-contained: its own fixture
# repo with a `.claude/project-status.json`, the real ledger.sh for request/approve/take/step, and lane-guard.sh fed
# a hand-written session record, as session-start-context.sh writes it.

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ sld >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-recipes.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_, sld)"
  else echo "tests/smoke-recipes.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

head_ "Recipes: request --recipe drafts one action; expects stop the run; a later edit changes nothing (US7)"
x_fail=0
rcp_t="$(cd "$(mktemp -d)" && pwd -P)"; git -C "$rcp_t" init -q -b main . \
  && git -C "$rcp_t" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
rcp() { (cd "$rcp_t" && bash "$REPO/hooks/ledger.sh" "$@"); }   # rcp <ledger args…>
rcp_ld="$(sld "$rcp_t")"; rcp_ssh="/usr/bin/ssh deploy@stg-host"
rcp_cfg() { # rcp_cfg <the stg deploy command> → writes the project config with every recipe this section uses
  mkdir -p "$rcp_t/.claude"
  jq -n --arg d "$1" --arg s "$rcp_ssh" '{name: "app", orchestrate: {deploy: {recipes: {
    stg: {steps: [{title: "deploy", commands: [$d], stop_checks: ["the deploy exits non-zero → stop"]},
                  {title: "version", commands: ["/usr/bin/curl -fsS https://stg-host/api/version/"], expect: "{version}"}]},
    prod: {steps: [{title: "deploy", commands: ["\($s) ./deploy.sh {version}"]}]},
    badph: {steps: [{title: "deploy", commands: ["\($s) ./deploy.sh {branch}"]}]},
    empty: {steps: [{title: "deploy", commands: ["\($s) ./deploy.sh {version}"]}, {title: "migrate", commands: []}]},
    wrapped: {steps: [{title: "deploy", commands: ["bash -c ./deploy.sh"]}]},
    needsha: {steps: [{title: "deploy", commands: ["\($s) ./deploy.sh {sha}"]}]}}}}}' > "$rcp_t/.claude/project-status.json"
}
rcp_cfg "$rcp_ssh ./deploy.sh {version} {sha} {env}"
[ "$(rcp op new --title "deploy stg" 2>&1)" = OP-1 ] || { bad "op new must create OP-1"; x_fail=1; }
mkdir -p "$rcp_ld"; jq -n '{id: "HEF-1", item_kind: "feature", phase: "implement", owner: null, blocked_on: null}' > "$rcp_ld/HEF-1.json"
rcp_refused() { # rcp_refused <text the refusal must name> <ledger request args…>: refused, and no action written
  local need="$1" o; shift
  o="$(rcp request "$@" 2>&1)" && { bad "request $* must be refused (FR-018)"; x_fail=1; }
  grep -qF -- "$need" <<<"$o" || { bad "the refusal of request $* must name '$need' — got: $(head -c 300 <<<"$o")"; x_fail=1; }
  [ -z "$(find "$rcp_ld/actions" -name '*-A*.json' 2>/dev/null)" ] || { bad "a refused request $* must write no action"; x_fail=1; }
}
# FR-018: each refusal names the offender; an unknown env lists the configured ones
rcp_refused 'nope' OP-1 --to repo-deployer --recipe nope --version 1.2.3
rcp_refused 'badph, empty, needsha, prod, stg, wrapped' OP-1 --to repo-deployer --recipe nope --version 1.2.3
rcp_refused '{branch}' OP-1 --to repo-deployer --recipe badph --version 1.2.3
rcp_refused "empty step" OP-1 --to repo-deployer --recipe empty --version 1.2.3
rcp_refused "migrate" OP-1 --to repo-deployer --recipe empty --version 1.2.3
rcp_refused 'bash -c ./deploy.sh' OP-1 --to repo-deployer --recipe wrapped --version 1.2.3
rcp_refused '--version' OP-1 --to repo-deployer --recipe stg
rcp_refused '--version' OP-1 --to repo-deployer --recipe stg --version '1.2.3; rm -rf x'
rcp_refused '--sha' OP-1 --to repo-deployer --recipe needsha --version 1.2.3
rcp_refused '--sha' OP-1 --to repo-deployer --recipe stg --version 1.2.3 --sha 'zz top'
rcp_refused 'an op' HEF-1 --to repo-deployer --recipe stg --version 1.2.3 --sha abcdef1
rcp_refused 'not both' OP-1 --to repo-deployer --recipe stg --version 1.2.3 --scope-file "$rcp_t/.claude/project-status.json"
# FR-014: the placeholders substituted, every command verbatim in the scope, kind recipe, expects one per step
rcp_req() { rcp request OP-1 --to repo-deployer --recipe stg --version 1.2.3 --sha abcdef1 2>&1; }
rcp_o="$(rcp_req)" || { bad "a valid recipe request must pass — got: $(head -c 300 <<<"$rcp_o")"; x_fail=1; }
jq -e --arg s "$rcp_ssh" '.status == "pending" and .to == "repo-deployer" and .scope.kind == "recipe" and .scope.title == "deploy stg 1.2.3"
  and .scope.commands == [{cmd: "\($s) ./deploy.sh 1.2.3 abcdef1 stg", after_step: null}, {cmd: "/usr/bin/curl -fsS https://stg-host/api/version/", after_step: 1}]
  and .scope.expects == [null, "1.2.3"] and (.scope.steps | length) == 2 and (.scope.steps[1] | contains("1.2.3"))
  and .scope.stop_checks == ["the deploy exits non-zero → stop"] and .scope.heads == {}' "$rcp_ld/actions/OP-1-A1.json" >/dev/null 2>&1 \
  || { bad "request --recipe must draft the substituted scope (FR-014) — got: $(jq -c .scope "$rcp_ld/actions/OP-1-A1.json" 2>&1 | head -c 500)"; x_fail=1; }
rcp_go() { # rcp_go <aid>: approve (the person) and take (the deployer)
  local h; h="$(jq -r .sha256 "$rcp_ld/actions/$1.json")"
  rcp approve "$1" --sha "${h:0:8}" --to repo-deployer --title "deploy stg 1.2.3" --reviewed-by-human --by Ana </dev/null >/dev/null 2>&1 \
    || { bad "approve $1 must pass"; x_fail=1; }
  rcp action take "$1" >/dev/null 2>&1 || { bad "action take $1 must pass"; x_fail=1; }
}
rcp_hash="$(jq -r .sha256 "$rcp_ld/actions/OP-1-A1.json")"
rcp approve OP-1-A1 --sha "${rcp_hash:0:8}" --to repo-deployer --title "deploy stg 1.2.3" --reviewed-by-human --by Ana </dev/null >/dev/null 2>&1 \
  || { bad "approve OP-1-A1 must pass"; x_fail=1; }
# NR-003: the recipe edited after approve changes nothing — take still matches, the scope keeps the approved command,
# and lane-guard grants only that command; the edited one is denied.
rcp_cfg "$rcp_ssh ./evil.sh {version}"
rcp action take OP-1-A1 >/dev/null 2>&1 || { bad "take must pass after the recipe was edited: the action carries the approved scope (NR-003)"; x_fail=1; }
jq -e --arg s "$rcp_ssh" --arg h "$rcp_hash" '.scope.commands[0].cmd == "\($s) ./deploy.sh 1.2.3 abcdef1 stg" and .sha256 == $h' "$rcp_ld/actions/OP-1-A1.json" >/dev/null 2>&1 \
  || { bad "an edit to the recipe must not change the approved action (NR-003) — got: $(jq -c .scope.commands "$rcp_ld/actions/OP-1-A1.json" | head -c 300)"; x_fail=1; }
mkdir -p "$HOME/.cache/hefesto/sessions"
jq -nc --arg l "$rcp_ld" --arg s "$rcp_ssh *" '{title: "repo-deployer", role: "deploy", name: "repo-deployer", lanes: true, worker: false,
  ledger: $l, excluded: ["gh *", $s, "/usr/bin/curl *"]}' > "$HOME/.cache/hefesto/sessions/sid-rcp-deployer-0001.json"
rcp_gd() { # rcp_gd <command> → allow | deny | none
  local o; o="$(jq -nc --arg c "$1" --arg d "$rcp_t" '{tool_name: "Bash", tool_input: {command: $c}, session_id: "sid-rcp-deployer-0001", cwd: $d}' \
    | bash "$REPO/hooks/lane-guard.sh" 2>/dev/null)"
  [ -n "$o" ] || { echo none; return; }; jq -r '.hookSpecificOutput.permissionDecision // "none"' <<<"$o" 2>/dev/null || echo none
}
[ "$(rcp_gd "$rcp_ssh ./deploy.sh 1.2.3 abcdef1 stg")" = allow ] || { bad "lane-guard must grant the approved recipe command"; x_fail=1; }
[ "$(rcp_gd "$rcp_ssh ./evil.sh 1.2.3")" = deny ] || { bad "lane-guard must deny the command an edit added to the recipe after approve (NR-003)"; x_fail=1; }
# FR-017: step 2's command (the version check) waits for step 1, so it cannot run before the deploy it checks
[ "$(rcp_gd "/usr/bin/curl -fsS https://stg-host/api/version/")" = deny ] || { bad "a recipe's step-2 command must not be granted before step 1 is recorded (FR-017)"; x_fail=1; }
# FR-017: a step with no expect records as before; a version check whose evidence differs stops the run, both values kept
printf 'deployed\n' > "$rcp_t/ev1.md"; printf 'version: 1.2.2\n' > "$rcp_t/ev2.md"; printf '  1.2.3  \r\n' > "$rcp_t/ev3.md"
rcp action step OP-1-A1 1 --evidence-file "$rcp_t/ev1.md" >/dev/null 2>&1 || { bad "step 1 (no expect) must be recorded"; x_fail=1; }
[ "$(rcp_gd "/usr/bin/curl -fsS https://stg-host/api/version/")" = allow ] || { bad "a recipe's step-2 command must be granted once step 1 is recorded"; x_fail=1; }
rcp_o="$(rcp action step OP-1-A1 2 --evidence-file "$rcp_t/ev2.md" 2>&1)" && { bad "a version step whose evidence differs must fail (FR-017)"; x_fail=1; }
{ grep -qF '1.2.3' <<<"$rcp_o" && grep -qF 'version: 1.2.2' <<<"$rcp_o"; } || { bad "the mismatch must print both values — got: $(head -c 300 <<<"$rcp_o")"; x_fail=1; }
jq -e '.status == "stopped" and .outcome.step == 2 and (.outcome.reason | contains("1.2.3") and contains("version: 1.2.2"))' "$rcp_ld/actions/OP-1-A1.json" >/dev/null 2>&1 \
  || { bad "a version mismatch must stop the action at its step with both values (FR-017) — got: $(jq -c '{status, outcome}' "$rcp_ld/actions/OP-1-A1.json" | head -c 300)"; x_fail=1; }
jq -e '.consumed_at != null' "$HOME/.cache/hefesto/approvals/$(basename "$rcp_ld")/OP-1-A1.json" >/dev/null 2>&1 \
  || { bad "the auto-stop must use the approval up, as action stop does"; x_fail=1; }
[ "$(rcp_gd "$rcp_ssh ./deploy.sh 1.2.3 abcdef1 stg")" = deny ] || { bad "a stopped recipe action must grant nothing more"; x_fail=1; }
# the matching version is recorded (whitespace and a CR around the line are ignored), and the action stays taken
rcp_cfg "$rcp_ssh ./deploy.sh {version} {sha} {env}"; rcp_o="$(rcp_req)" || { bad "the second request must pass — got: $rcp_o"; x_fail=1; }
rcp_go OP-1-A2
rcp_o="$(rcp action step OP-1-A2 2 --evidence-file "$rcp_t/ev3.md" 2>&1)" && { bad "a recipe's step 2 recorded before step 1 must be refused (FR-017)"; x_fail=1; }
grep -qF 'in order' <<<"$rcp_o" || { bad "the out-of-order refusal must say steps go in order — got: $(head -c 300 <<<"$rcp_o")"; x_fail=1; }
# an out-of-order version step with the WRONG version is refused for its order, not a stop that uses the approval
rcp_o="$(rcp action step OP-1-A2 2 --evidence-file "$rcp_t/ev2.md" 2>&1)" && { bad "an out-of-order mismatching step must be refused"; x_fail=1; }
grep -qF 'in order' <<<"$rcp_o" && jq -e '.status == "taken"' "$rcp_ld/actions/OP-1-A2.json" >/dev/null 2>&1 \
  || { bad "an out-of-order mismatching step must be refused for its order, the action left taken — got: $(head -c 300 <<<"$rcp_o")"; x_fail=1; }
rcp action step OP-1-A2 1 --evidence-file "$rcp_t/ev1.md" >/dev/null 2>&1 || { bad "step 1 of OP-1-A2 must be recorded"; x_fail=1; }
{ rcp action step OP-1-A2 2 --evidence-file "$rcp_t/ev3.md" >/dev/null 2>&1 && jq -e '.status == "taken" and (.steps_done | length) == 2' "$rcp_ld/actions/OP-1-A2.json" >/dev/null 2>&1; } \
  || { bad "a version step whose evidence matches must be recorded (FR-017) — got: $(jq -c '{status, steps_done}' "$rcp_ld/actions/OP-1-A2.json" | head -c 300)"; x_fail=1; }
rm -rf -- "${rcp_t:?}"; rm -f "$HOME"/.cache/hefesto/sessions/sid-rcp-*-0001.json
[ "$x_fail" -eq 0 ] && ok "request --recipe drafts one substituted kind-recipe action on an op; an unknown env (listing the configured ones), placeholder, empty step, scope-check rejection, bad --version/--sha are refused naming the offender; a version step that differs stops the run with both values; a recipe edited after approve changes nothing and its new command is denied (US7 FR-014 FR-017 FR-018 NR-003)"
