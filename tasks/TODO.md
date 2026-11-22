# TODO

Items the orchestrator may claim (`/hef.orchestrate`). One heading per item: `## <ID> — title`,
then the body a worker receives as **data** (delimited and comment-stripped by
`status-board.sh --item`). Move a heading to DOING.md by hand only when a human is working on it;
the ledger, not this file, records what a session owns.

## HEF-1 — /hef.tasks accepts the light path without plan.md

`/hef.tasks` refuses to run when `plan.md` is missing, while `/hef.agent`'s light route says to
skip the plan. Found 2026-09-25 while building `/hef.status`; a throwaway plan was written to
unblock. Make the command accept the light path: when `spec.md` exists and `plan.md` does not,
generate tasks from the spec alone and say so in the tasks.md header. Keep the full path unchanged.
Add a smoke check: a spec dir with spec.md and no plan.md must not be rejected by the pre-flight
helper the command uses.

## HEF-2 — implement-phase-test-guard false positives on heredocs

`hooks/implement-phase-test-guard.sh` blocked a Bash command that *wrote* tests because its scan of
the command text saw `rm` tokens and the word `spec` inside a heredoc, and its `basename` call
chokes on tokens beginning with `---`. Both are false positives; the Edit-tool path is unaffected.
Fix both, keep every existing guard case green, and add the two false-positive commands as
fixtures that must pass. Mutation-check: reintroduce the token scan on heredoc bodies and confirm
the new fixtures go red.

## HEF-3 — namespace FR ids per spec in req-coverage

`FR-NNN` ids collide across specs: a test citing `FR-004` counts for every spec that declares an
`FR-004`. `speckit-helper.sh req-coverage` should scope citations to the spec that declares them,
for example by accepting `FR-004` only from tests under a path the spec names or by a
`<spec>/FR-004` form. Decide the form, document it in `docs/sdd.md`, update the smoke fixture that
covers `req-coverage --all` and `ELSEWHERE`, and keep the existing specs' coverage green.

## HEF-16 — publish_commit: commit board writes in an external board repo

Deferred from HEF-14 (plan review 2026-10-05). `ledger.sh publish` on an external board marks the
heading in the board repo's file; committing it is still the person's. An opt-in
`orchestrate.publish_commit` needs five guards first:
- refuse when the column file is dirty before `--mark` (a commit would sweep a person's edits);
- refuse during a merge or rebase in the board repo;
- take the absolute path from `--mark`, and refuse a column outside the board repo;
- commit before recording `published`, so a failed commit is retried;
- state the branch expectation (a board repo may push straight to main).

## HEF-17 — /hef.implement accepts the light path (tasks.md without plan.md)

Follow-up deferred from HEF-1 (plan review 2026-11-06). `/hefesto:hef.tasks` now runs on the light
path (spec.md and no plan.md, HEF-1), but `commands/hef.implement.md` still states that `plan.md`
is required (lines 43 and 53), although its `check-artifacts` pre-flight already tolerates
`plan.md: MISSING`. Make implement accept a missing plan when `tasks.md` carries the light-path
header line HEF-1 writes: that line's consumer is this command. Keep the full path unchanged, and
add a smoke check that a spec dir with spec.md, tasks.md and no plan.md is not rejected.

## HEF-18 — documentation restructure: a short README front door, one start-here path, per-OS install pages, contributing

Requested by the owner in the orchestrator lane (2026-11-07). The 9.3.0 docs pass (PR #177) fixed command
spelling and made the quick start step-by-step, but the docs are still a reference, not a front door:
README.md is 415 lines of edge cases; install, setup and use are spread over README.md, docs/quickstart.md,
docs/install.md and SETUP.md with no single "start here"; there is no contributing guide; OS differences
are scattered sentences; the single-lane versus four-lane choice appears only as a small table.

Make the documentation easy to understand in this order: what the project is, how to install, how to set
up, how to use it, how to contribute.
- README.md becomes a short front door, under about 150 lines: what it is, install in one command, setup,
  first use, the two approaches (single lane and four or more lanes) and how to decide between them,
  contribute, and links. Details move to docs/.
- One install page per OS: Linux, macOS, and Windows via WSL (the Windows page says WSL is required and
  hands over to the Linux steps). The quick install steps live there, not repeated elsewhere.
- One contributing guide (CONTRIBUTING.md or docs/contributing.md): how to run the smoke suite, the
  commit and PR conventions this repo already uses, how a change is reviewed.
- Reconcile the overlap between docs/quickstart.md, docs/install.md and SETUP.md so each has one job and
  points to the others; keep SETUP.md working as the file Claude follows.
- Keep the Portuguese quick start in step with the English one.
Keep every command spelled `/hefesto:hef.<name>` and every statement checked against the code (the smoke
guards for doc counts and command spelling must stay green).

## HEF-19 — the spend cap defaults to open; a cap is opt-in

Requested by the owner (2026-11-07). `hooks/session-launch.sh` reads `orchestrate.usd_cap // 20` and
`orchestrate.daily_usd_cap // 100`, so a project that sets no cap is capped at 20 USD per session and
refuses a launch once today's spend plus one session cap passes 100. The owner wants the default open:
no per-session or daily limit unless the project sets one. Make a missing or null `usd_cap` mean no
`--max-budget-usd` and no daily check; a set value keeps today's behaviour. Update the orchestrate
guide text, docs/install.md, the status-board init defaults, and the smoke fixtures that cover the cap
refusal and the budget block.

## HEF-20 — a worker that cannot emit its structured outcome loses the item's block

Observed 2026-11-07 on HEF-18's plan run (session f3f1e392, 53 turns, 8.28 USD). The planner did all
its work — spec, research, plan and a saved plan-review.md committed on the item's branch, a second
REVISE_PLAN reached — then `claude -p` ended with `subtype: error_max_structured_output_retries`,
`stop_reason: tool_use`, `is_error: true`. `session-launch.sh` saw "no structured_output in the result",
exited 1, and recorded only a failed run: the entry stayed in phase `intake` with `worktree`, `spec_dir`
and `blocked_on` all null, and the orchestrator learned nothing of the review or the question. The
person had to repair the entry by hand (`ledger.sh record --worktree --branch --spec-dir`, then `block`).
Make the launcher fall back when the outcome is missing or malformed: record the worktree and branch it
created, detect the spec folder and any committed `plan-review.md` or question text on the branch, and
block the item `human:plan-review` (or `stall` when nothing usable is on disk) with a question file that
quotes the run's last `says:` lines as data. Keep the raw `result.json` beside the run for the person.
Add a smoke fixture with a fake `claude` that returns this error shape; mutation: drop the fallback → red.

## HEF-21 — the planner works through plan-review rounds on its own; a person sees design questions and the final approval

Owner decision 2026-11-07, after one session asked five "apply the review's edits and re-review once" forms.
Today `session-launch.sh` (lanes-v3 FR-014, `:495`) and the planner prompt stop at the second REVISE_PLAN and
block `human:plan-review`; every such round this session was, in the reviewer's own words, plan edits with no
product decision. Change the loop: apply each round's changes and run the fresh-context review again until
APPROVE, up to a hard cap of 5 rounds (`orchestrate.plan_review_rounds`, default 5). Stop early and block
`human:plan-review` only when a round's finding needs a product or design decision (the reviewer marks it so, or
the planner cannot decide it from the code and the item); at the cap, block with the review log and the open
findings. A person's revision request still comes back as today. Log every round in `plan-review.md` beside
the plan. Smoke: a fake reviewer returning REVISE_PLAN ×3 then APPROVE reaches tasks with no block; one
returning a design question blocks on round 1; one never approving blocks at round 5. Mutation each.

## HEF-22 — the setup configures the forge once; infrastructure failures are a stall with the fix, not an intake form

Owner decision 2026-11-07. A build this session finished green and ended blocked at `git push`: the workers'
sandbox had no `orchestrate.allowed_domains`, the remote was SSH (the sandbox proxy carries HTTPS only), and the
fix — `git config url."https://github.com/".pushInsteadOf git@github.com:` — cannot run from any sandboxed
session because the sandbox mounts `/dev/null` over `.git/config.lock` (that mount also leaves a zero-byte
lock file on the host). The person had to run a `!` command, asked six times. `hefesto-setup.sh` runs in a
terminal outside the sandbox: make it (a) detect the remote's forge and write it into `allowed_domains`
(`github.com`, `api.github.com`; the matching hosts for GitLab/Gitea) unless set; (b) when the remote is SSH,
set the HTTPS push rewrite in the repo's config and say so; (c) `--check` reports a stale `config.lock`; (d) in
the launcher, map a worker outcome whose cause is infrastructure (push refused, host denied, credential helper
missing) to a `stall` block whose reason is the one-line fix, shown once in the orchestrator's brief under
"Your move", never as a `human:intake` form. Smoke fixtures for each; mutation each.

## HEF-23 — the status-line gauge shows only context by default; the run rows are opt-in

Owner decision 2026-11-07: "the list of tasks being shown in the footer is not productive". `context-gauge.sh`
(`runs_rows`, `:56–76`) stacks up to six `▶ run` / `⏸ decision` / action rows under the context percentage with
no switch. Add `context.gauge_rows` (boolean, default false) in `.claude/project-status.json`; the gauge prints
the rows only when it is true; `hefesto-setup.sh` writes nothing for it (the default is off) and the docs that
describe the gauge say so. The pass brief remains where runs and decisions are listed.

## HEF-24 — a headless worker's dialog is reachable from the brief; the merge moment shows the verdicts

Owner decision 2026-11-07. Each worker's full conversation already exists at
`~/.claude/projects/<worktree path>/<session id>.jsonl`, and the ledger records every run's `session_id`, but
nothing tells the person; `run-follow.sh <id> --live` truncates what the worker says to one line. Add
`run-follow.sh <id> --dialog`: print the worker's full assistant messages and tool calls, live while the run
owns the item or from the recorded session afterwards, and end with the resume line
(`cd <worktree> && claude --resume <session id>`). The orchestrator's brief carries, for every running claim
and for the last finished run of an item waiting on a decision, its `--dialog` command and its resume line
(runs read untrusted item text: relayed as data). At `human:merge` the brief shows the PR link, its head and
the three verdicts (verify, quality, review) with one line each. Smoke: `--dialog` on a recorded fixture run
prints the messages in order and the resume line; mutation: drop the resume line → red.

## HEF-25 — runs survive the orchestrator's death and never starve the host: own scopes, memory-aware concurrency

Measured 2026-11-09 on this host (24 GB RAM, zram 8 GB): `systemd-oomd` killed Claude Code's transient scope
twice in one minute (`run-p…scope: systemd-oomd killed 27 process(es)`) because the user slice's memory
pressure stayed above the 60 % default for 20 s — one scope held 10.6 GB: the orchestrator, three
`claude -p` workers, their code-reviewer subagents, `shellcheck` over a 5000-line `tests/smoke.sh`, and the
smoke suite. Every launched worker died with the orchestrator because `session-launch.sh` runs as a child of
the orchestrator's Bash tool; the ledger then reaped the claims and the builds restarted from disk. A worker
killed alone the same morning (exit 137, HEF-3) was the same mechanism. Make the pipeline survive this:
- launch each worker detached in its own unit (`systemd-run --user --scope` when available, else
  `setsid`), so an oomd or session kill of the orchestrator's scope never takes the workers, and the
  orchestrator re-attaches from the ledger on its next pass (it already reads only the ledger);
- `orchestrate.max_concurrent_runs` (default 2): a launch past it is refused as busy, like the stage limits;
- before a launch, read `MemAvailable` and `/proc/pressure/memory`; refuse (as busy, retry on the next pass)
  when available memory is under `orchestrate.min_free_mb` (default 4096) or `some avg60` is over 50;
- the quality and verify steps run `shellcheck` only on the changed hunks' files under a `ulimit -v` and skip
  files over 3000 lines with a one-line note (the smoke suite's own shellcheck guard covers them);
- `hefesto-setup.sh --check` reports when `systemd-oomd` is active with the default 60 % limit on the user
  slice and prints the drop-in or `systemctl disable --now systemd-oomd` the person may choose.
Smoke: a fake `systemd-run`/`setsid` records the detach; a fixture with low MemAvailable refuses; the
concurrency cap refuses the third launch; mutation each.

## HEF-26 — the PR's head branch and the worktree's branch must agree; the babysitter must not stop on the name

Measured 2026-11-09 on PR #192: the implement worker (through `/hefesto:hef.pr` / review-coordinator) pushed the
worktree `worktree-HEF-18` as `docs/front-door`, so the ledger's `branch`, the worktree's checkout and the PR's
`headRefName` disagreed. When the PR later conflicted with main, the deploy babysitter stopped at
`pr-watch.sh resolve <n> --local` ("the local checkout is on 'worktree-HEF-18', the PR head is
'docs/front-door'") and nothing was resolved; the worktree's git dir is read-only inside every sandbox, so the
person had to switch the branch by hand. Fix both ends: (a) a launched worker pushes the branch it is on —
`/hefesto:hef.pr` and review-coordinator never rename on push when `HEFESTO_WORKER` is set (the semantic name
is the PR title's job); (b) when a PR exists, `session-launch.sh` records the PR's head ref from the forge and
`--prepare`/the deploy launch `git switch` the worktree onto that branch outside the sandbox before the
babysitter runs, or refuse with the exact command; (c) `ledger.sh branches`/`where` read the PR head, not the
worktree name. Smoke: a fixture PR whose head differs from the worktree branch is switched before babysit;
a worker push with a rename is refused; mutation each.

## HEF-27 — a permission dialog only for a person's signature; the ledger's mechanics never ask

Measured 2026-11-09 on a four-lane production board (16 days of transcripts): its settings held 408 `ask`
rules and 434 `allow` rules, in several path spellings (plugin cache per profile, the clone, `bash <path>`).
The ask set covered `ledger.sh claim`, `record`, `advance`, `handoff`, `block` and `release` — commands every
lane pass runs — beside the real signatures. Each one is a dialog; the person counted about 100 interactions
from RFC to a staging deploy where 8.0 took 3 to 5. Make the rule: a dialog exists only for the commands that
record a person's decision — `unblock --reviewed-by-human`, `unblock --merge-sha`, `approve`, `answer`,
`revise`, `record --body-file|--body-from-board`, `drop`, `fold`, `supersede`, `reopen`, `op close|drop` — and
`ledger.sh` itself refuses those from a worker or a stage lane, as today. Every other subcommand is `allow`.
Rewrite `hefesto-setup.sh`: write one canonical spelling per rule, strip the duplicates and the mechanics it or
an earlier version wrote, and let `--check` report any ask rule outside the signature set as the defect it is.
The `--prepare` path runs `claim` and `record` itself, outside the sandbox, so a lane never sees those dialogs.
Smoke: a settings file with the 408-rule shape is reduced to the signature set and one spelling; a mechanics
ask rule makes `--check` fail; mutation each.

## HEF-28 — standing read-only grants for operations work; an action only for a write

Owner decision 2026-11-09. Since 9.0 every command that leaves the sandbox needs an approved action, so one
incident on the measured board became five forms in a row — "read 2", "read 3", "proxy read", "pg alert",
"outage read" — each a scope the person approved before the deployer could run `ssh host 'systemctl status …'`.
Add grants: `ledger.sh grant new --to <lane> --hosts <h,…> --commands-file <f> --read-only` drafts a standing,
revocable grant (title, hosts, command patterns, `read_only: true`, no expiry or `--until`); the person approves
it once in the orchestrator with the hash, as an action is approved today; `lane-guard.sh` lets a command that
matches an approved grant's host and pattern run with no dialog while the grant is open; `ledger.sh grant
list|revoke` manage them; `--check` lists the open grants. The pattern set for `read_only` is a fixed allowlist
of read verbs (status, logs, journalctl, ps, df, free, cat of named paths, docker ps/logs/inspect, kubectl get,
curl -I, dig) — a pattern outside it is refused at `grant new`. Writes and irreversible steps keep the action
flow unchanged. Smoke: a granted read runs without a dialog, a write under the same grant is denied, a revoked
grant denies, a pattern with `rm`/`restart`/`apply` is refused at creation; mutation each.

## HEF-29 — doorbells are one line, machine-shaped, and coalesced; a lane never chats

Measured 2026-11-09 on the same board: 3,168 `SendMessage` calls in 16 days, up to 316 a day, 963 of them to
the orchestrator, most in free prose ("deployer-N is done: cube_ui#N is merged", "please refresh #N next", "From
the orchestrator, after your context compaction …"). Each message is a pass in the receiver and a visible turn
in its pane. Enforce the protocol the guide already states: a PreToolUse hook on `SendMessage` in a set-up
project accepts only `<sender>: <stage> pass`, `<sender>: action <aid>`, `<sender>: directive <id>`, `<sender>:
done launched|action|idle <x>` and the `<sender>: done <stage> <id>` of an interactive lane, and denies anything
else with the grammar in the reason. Coalesce: a lane rings the orchestrator at most once per pass, and not at
all when the ledger has not changed since its last ring (`ledger.sh changed-since <lane>`); the orchestrator rings
a stage once per pass. Everything a lane wants to say goes in the ledger (`note`, the outcome), where the next
pass reads it. Smoke: a prose message is denied, each grammar line is accepted, a second ring with an unchanged
ledger is suppressed; mutation each.

## HEF-30 — `merge_by: auto` for the integration branch; merges and trains batched in one form; the decider remembered

Owner decision 2026-11-09. On the measured board every PR was a `human:merge` form plus an approve dialog
(`merge_by: lane`), and a train cut asked once per repository. (a) `merge_by: auto`: when the four gates
(verify, review, quality, scan) are PASS, CI is green, `orchestrate.merge.checks` pass and the PR targets the
integration branch (`branches.integration`, never a protected or environment branch), the deployer merges it
with no form, records `merged` and says so in the brief; a red check or a conflict goes to the babysitter as
today. Promotions to environments stay human trains. (b) In `merge_by: lane` or `person`, the orchestrator asks
one multi-select form per pass listing every mergeable PR (link, head, verdicts), not one form per PR; one train
form covers all its repositories. (c) `orchestrate.decider` in `.claude/project-status.json` (written by setup
from `git config user.name`) is the `--by` name: the "which name records your decisions" question is never asked
when it is set. Smoke: a PR with four PASS gates on the integration branch merges without a block; the same PR
against an environment branch blocks `human:merge`; a failing merge check blocks `ci`; the decider is read from
config; mutation each.

## HEF-31 — a PR that conflicts with its base is merged forward by the build stage; a person sees only a judgment call

Measured 2026-11-09 on PR #192: two sibling PRs merged first, the PR became CONFLICTING, and the deploy babysitter
did exactly what it should — read the state and block the entry `conflict` — but no stage then resolves it: the
Retry form sends it back to the same babysitter, which blocks it again. The person had to be asked, and the
only tool left was a hand directive to an implement worker. Make the conflict a build-stage job: when
`pr-watch.sh state` says CONFLICTING (or `mergeStateStatus: BEHIND` with required up-to-date branches), the
entry goes to phase `implement` with a generated directive — fetch the base, merge it into the PR branch in the
worktree, resolve, run the project's test command through `lane-build.sh`, push to the same branch — and the
verifier re-runs its gates on the new head. The worker resolves mechanically where one side is unchanged or
the change is a count/version the suite computes; when both sides changed the same lines with intent, it stops
with the two hunks as a `human:clarify` question, never a guess. `merge_by: auto` (HEF-30) depends on this: a
PR that cannot be merged forward is not mergeable. Smoke: a fixture PR behind its base is merged forward and
re-verified without a form; a true two-sided edit stops with a question; mutation each.

## HEF-32 — decisions per item is a ledger metric; the status brief shows it; a rise is visible before a person feels it

Owner need 2026-11-09: "we need to be sure that only the main decision is being pushed to the user" and a way to
"see if the workflow is fluid again" after 9.4.0. Today the only way to know was a one-off script over 16 days
of transcripts (146 forms, 217 questions, 3,168 doorbells on one board). Make it a first-class number: every
form the orchestrator asks is recorded on the entry it concerns (`ledger.sh asked <id> --kind <block kind|
lifecycle|action> --questions N`, called by the orchestrator right after a form; an action approval and a
directive already leave records). `ledger.sh metrics` gains `decisions`: per item (forms, questions, approvals,
directives), the median and the worst item of the last 7 and 30 days, and the split by kind (plan approval,
merge, design question, retry, budget, intake, lifecycle). `/hefesto:hef.status` prints one line: "decisions per
item (7d): median N, worst <id> N — target ≤ 5 from RFC to the first environment", with the kinds that exceed
their share. `orchestrate.decisions_target` (default 5) turns the line red when the median passes it. Smoke: a
fixture ledger with known forms yields the exact counts; mutation: drop one kind from the split → red.

## HEF-33 — the orchestrator pass fits a context budget: summaries instead of ledger JSON, one register per new id, refusals remembered

GitHub issue #180 holds the full text (filed 2026-11-07 from a four-lane production board; registered on the owner's
decision 2026-11-09, 9.6 backlog). One orchestrator pass is 13 tool calls before any decision and every doorbell
starts a full pass; `ledger.sh list` returned 404.8 KB of JSON for ~200 entries, `list --phase queued` 37.6 KB,
`list --today` 42.3 KB for one number, `status-board.sh --detailed` 115 lines every pass; routing refusals repeat
on every pass because nothing records them. Make the pass cheap: `ledger.sh list` prints one line per entry by
default (`--json` for the full form); `list --today` prints the sum; `ledger.sh pass-state` returns the whole
pre-flight in one call (board mode, active, blocked, pending actions, next per stage, unregistered todo ids);
`register` records a routing refusal on the entry (`refused: <reason>`) and `next` skips it until the item text
changes; the guide's pre-flight shrinks to that one call plus `status-board.sh --list todo` and `ListAgents`.
Smoke: a 200-entry fixture ledger keeps the pass output under 8 KB; a refused registration is not retried.

## HEF-34 — `ledger next` never returns an entry `--prepare` refuses; refs outside the kanban columns are rejected at register

GitHub issue #181 holds the full text (filed 2026-11-07; registered 2026-11-09, 9.6 backlog). `register` accepted
`--ref initiatives/sec-posture.md#BKP-GIT-MIRROR` and `messages/po/…txt#…`; `next --stage plan` dispatched them;
`--prepare` refused ("no such item in TODO.md, DOING.md, BACKLOG.md or DONE.md"); nothing recorded the refusal, so
the same entry wedged the stage head on every pass and the person had to drop items to unwedge it. Fix: `register`
refuses a ref outside the board's column files (one line, naming the ref and the columns); `next` skips an entry whose
last run or prepare was refused (`refused_at`, cleared when the item text changes or a person `unblock`s it); the
launcher records a prepare refusal on the entry. Smoke: an out-of-column ref is refused at register; a recorded
prepare refusal is skipped by `next`; mutation each.

## HEF-35 — epics with per-repo children: the parent is never re-planned after its children shipped; repo detection reads only `repo:` lines

GitHub issue #182 holds the full text (filed 2026-11-07; registered 2026-11-09, 9.6 backlog). A parent heading
`ID` with children `ID-OPS`, `ID-UI`, `ID-FLEET` sharing its `source.ref` was dispatched to the planner after its
children were merged and released (6 minutes to conclude "nothing to plan"); and `status-board --item-repo` read
prose words (`?`, `a`, `and`, `are`, `come`) as repository names and refused the epic on every pass. Fix: an entry
whose `source.ref` is shared by child entries is a parent — `next` never dispatches it, its phase follows its
children (all merged → merged, all released → released), and `status-board --detailed` shows it as an epic with
the children's states; repo detection accepts only an explicit `repo:` line or a `repos:` list, never prose, and an
item naming several repos is registered as a parent whose children the orchestrator creates (`ID-<REPO>`) from a
form. Smoke: a parent with released children is not returned by `next`; prose never yields a repo name.

## HEF-36 — `route: action`: an item that is a host operation or physical work is drafted and closed from the orchestrator, never built

GitHub issue #183 holds the full text (filed 2026-11-07; registered 2026-11-09, 9.6 backlog). Two of the first three
items a build stage dispatched were not code: a host `rmdir` and a physical cooling fault. Each cost a builder claim,
a worktree, a `human:clarify` block, a form and a hand-written lane-action scope, and afterwards the item had no
phase to land in (the lifecycle is plan → build → PR → merge → deploy). Add `route: action` (`item_kind: operation`),
set at register from an explicit `owner: deployer` / `kind: operation` line or by a form: the orchestrator drafts the
lane action from the item (`ledger.sh request <id> --to <deployer> --from-item`), the person approves it as today,
the lane carries it out, and `action done` moves the item to a terminal `done` phase with the evidence file as its
record; `next --stage build` never returns an action-route item. Smoke: an `owner: deployer` item is never claimed
by a builder; `action done` closes it; mutation each.

## HEF-37 — an interactive implement or verify finish that blocks on a question writes the question file, like the plan finish does

GitHub issue #184 holds the full text (filed 2026-11-07; registered 2026-11-09, 9.6 backlog). Two interactive
builder finishes recorded `blocked human:clarify` with `question_path: null`; `ledger.sh questions <id>` exited 1
("no open question found … read the item's folder"); the only copy of the question was `outcome-<id>.json` in the
builder session's scratchpad, which the orchestrator had to find with `find -newermt`. The plan finish writes
`<ledger>/<id>.question-<n>.md` and sets `question_path`; the implement and verify finishes must do the same from
the outcome's `summary`/`question` field, for a `fix`-route item with no folder too. Also: `ledger.sh note <id>` is
refused for the orchestrator by the lane guard, so it cannot read a lane's note to brief the person — allow a
read-only `note --show` from the orchestrator. Smoke: an implement finish with `blocked` writes the question file
and `questions` prints it; mutation: drop the write → red.

## HEF-38 — lanes register a live session ref the orchestrator rings; a duplicate lane name is reported and resolved, not silently dead

GitHub issue #185 holds the full text (filed 2026-11-07; registered 2026-11-09, 9.6 backlog). After a restart,
`ListAgents` showed two live sessions with one builder lane name (one from before the restart) plus a stale
orchestrator from an older era; the rule "two with the same name → do not ring" made the third builder slot dead
until a person found the right terminal, and `hefesto-setup.sh --check` said `setup: ok`. Fix: a stage lane's first
pass runs `ledger.sh lane hello --name <name> --ref <ListAgents ref> --session <id>` and every pass refreshes a
heartbeat; `ledger.sh lanes --live` prints `{name: {ref, last_seen, busy}}`; the orchestrator rings `name [ref]`, the
newest live record wins, and a stale duplicate is named in the brief with its age and ref so the person closes the
right one; `--check` reports duplicates. Smoke: two records for one name → the newest is rung, the other named;
mutation each.

## HEF-39 — interactive lanes record their real cost and run the stage's tier

GitHub issue #186 holds the full text (filed 2026-11-07; registered 2026-11-09, 9.6 backlog). Every in-lane run is
recorded with `usd: 0`, so `list --today` sums to 0 after a morning of five interactive sessions, the brief's spend
line is false and the caps cannot fire; `tiers` applies to launched workers only, so the model policy (cheap
generation, expensive judgment) cannot be applied per stage in interactive mode. Fix: `--prepare` and `--finish`
read the session's cost (the session JSONL or the sessions registry) and record the delta as `usd` with
`source: session`; `--prepare` prints a `tier:` line from `orchestrate.tiers[role]` and the lane prompt says to run
`/model <tier>` before starting, or the setup emits the `claude --name … --model <alias>` lines for the lanes.
Smoke: a fixture session JSONL with known cost yields the delta; mutation: record 0 → red.

## HEF-40 — `ledger next` honours priority and lane affinity: board P-levels, column order, `owner:` lines; a next-up list

GitHub issue #187 holds the full text (filed 2026-11-07; registered 2026-11-09, 9.6 backlog). `next` handed out a
P3 host operation, a P2 physical item and a P4 fix before the release cut the handoff named first; the board's
P-levels, column order and the person's priority had no effect, and the only steering tools were `direct` and
`drop`. The build lanes are a flat list, so the fleet specialist could get an ops item. Fix: `register` reads
`priority: P<n>` or the heading's `P<n>` and the column position; `next` orders by priority, then column position,
then age; `ledger.sh prioritize <id> [--first]` pins a next-up order from the orchestrator (a form, or `/hefesto:hef.ship`);
`owner: <lane>` lines and an `orchestrate.lanes.build` map of `{name: [repos]}` give lane affinity so a lane is
offered only its repos' items. Smoke: a P1 below a P3 in the file is returned first; an item owned by one lane is
never offered to another; mutation each.

## HEF-41 — more than one planner per board; a planner lane may take a verify when planning is idle

GitHub issue #188 holds the full text (filed 2026-11-07; registered 2026-11-09, 9.6 backlog). On an external board
driving five repos with three builders, one `plan` lane serializes every plan (6–20 minutes each plus the approval
round trip) while 50 entries wait: the plan lane is the pipeline's throughput cap. Fix: `orchestrate.lanes.plan`
accepts a list and `orchestrate.max_planners` (default 1) is enforced by `claim` like builders; the orchestrator rings
each idle planner for one runnable item; with HEF-40's affinity a planner can be pinned to repos; `--stage plan`
with nothing to plan may take a `verify` for a finished build, the one stage that benefits from a different session
than the builder's. Smoke: two planner lanes plan two items at once; a third launch is refused as busy; mutation.

## HEF-42 — action scope templates for host operations and a pre-form scope lint; the lane guard honours shell quoting

GitHub issue #189 holds the full text (filed 2026-11-07; registered 2026-11-09, 9.6 backlog). Hand-written action
scopes of ~40 lines each (a remote `rmdir` of a path named `*`, an Alertmanager silence through `ssh host docker
exec …`) were approved and then stopped by the lane guard on quoting: a `find … -exec … ';'` step was refused as a
chain, parentheses inside a quoted `--title` as a subshell. Fix: `orchestrate.host_ops` templates (named host
procedures with placeholders, like deploy recipes) drafted with `ledger.sh request <id> --host-op <name>`; a scope
lint run before the form (`ledger.sh request --lint`): every step is one plain command matching a lane's unsandboxed
pattern, every step covered by `commands`, placeholders resolved; and the guard tokenizes with shell quoting rules so
a quoted `;`, `(` or `|` inside one argument is never read as a chain. Smoke: each quoting case passes the guard,
each real chain is still refused; a scope with an uncovered step fails the lint; mutation each.

## HEF-43 — tasks-repo boards close the loop: a DONE.md record on released, dropped, folded or superseded

GitHub issue #190 holds the full text (filed 2026-11-07; registered 2026-11-09, 9.6 backlog). The ledger holds the
only record of drops and releases; the board's TODO still lists them until a person writes DONE.md by hand, and the
board and the ledger drift apart within a day. Fix: `status-board.sh --publish <id>` for tasks-repo boards moves the
item's heading verbatim to the top of DONE.md's current section with a generated record line (`✅ <id> — released
<date> — <PRs> — <envs>`), or to the configured closed section with the ledger reason for dropped/folded/superseded —
a text move, never a rewrite of the item's text; the orchestrator pass runs it with `orchestrate.publish: true`;
HEF-16's `publish_commit` commits it on an external board. Smoke: a released fixture item moves to DONE.md with its
record; a dropped one carries its reason; the item text is byte-identical; mutation each.

## HEF-44 — the orchestrator files and comments on GitHub issues in repos outside the board with its own dialog, no deployer action

GitHub issue #191 holds the full text (filed 2026-11-07; registered 2026-11-09, 9.6 backlog). The person asked the
orchestrator to file issues in the framework's repository; eleven `gh issue create` calls were blocked by the lane
guard ("ask the orchestrator for an action"), the detour through a 13-step deployer action stopped at step 2 on a
quoting refusal, and the deployer lane has nothing to do with that repository. Fix: in the orchestrator lane, `gh
issue create|comment|edit` on a repository outside the board's `repos` map and `branches.protected` is allowed under
the person's own dialog (an ask rule, like the signatures), the same class as the already-allowed `gh pr create`;
`gh pr merge`, `gh release`, pushes and anything on a board repo keep the action route. Smoke: an issue write on a
foreign repo passes the guard in the orchestrator and is refused in a stage lane; a merge is refused everywhere;
mutation each.

## HEF-45 — acceptance tests from the spec with recorded red→green evidence; verify judges evidence, not citations

GitHub issue #201 holds the full text (from a workflow review, 2026-11-10). The spec's scenarios become executable
acceptance tests before implementation; each records red on the parent commit and green on the head in an
`evidence.json`; `req-coverage` counts an FR covered only with that evidence (`CITED-ONLY`, `NOT-RED` otherwise).

## HEF-46 — every fix proves red then green: the regression-test commit fails before the fix commit

GitHub issue #202 holds the full text. Bug, incident and vulnerability items on any route (including `/hefesto:hef.fix`)
land a test commit that fails, then the fix commit that makes it pass; `speckit-helper.sh red-green` checks both in a
throwaway worktree and verify fails a test that never reproduced the bug.

## HEF-47 — intake audit for issues and external PRs

GitHub issue #203 holds the full text. `/hefesto:hef.audit issue` separates observed behaviour from the reporter's
diagnosis and reproduces the failure in the sandbox before planning; `/hefesto:hef.audit pr` checks an external PR's
claims, executable bits, homoglyphs, unpinned actions, typosquats and semver; `merge_by: auto` never applies to an
external PR without an APPROVED audit.

## HEF-48 — PR bodies carry generated evidence; a merge is refused when the evidence head differs from the PR head

GitHub issue #204 holds the full text. `ledger.sh pr-evidence <id>` renders the verdicts, the head SHA and the coverage
matrix into a marked block of the PR body; the merge refuses stale evidence.

## HEF-49 — post-merge audit of the integrated branch after N merges and before every release cut

GitHub issue #205 holds the full text. Full suite on the integration head, a fresh review of `<last tag>..HEAD` for
interactions between merged items, and the security audit over the range; findings become board items; the release
cut waits for a current post-audit.

## HEF-50 — release derives its version from the changelog; tags only on green CI for the exact SHA; never moves a tag

GitHub issue #206 holds the full text.

## HEF-51 — dependency-bump fast path: one batched verification pass with a supply-chain floor

GitHub issue #207 holds the full text.

## HEF-52 — kaizen: worker-recorded pitfalls for the next worker; a retrospective that mines the ledger

GitHub issue #208 holds the full text. Measured cause: four workers rediscovered the same `HEFESTO_TRUSTED_TOP` leak
into the smoke suite, and three builds died to the same shellcheck memory spike, with no channel to tell the next one.

## HEF-53 — bounded items: done-when, verify, invariants and out-of-scope pinned before any worker starts

GitHub issue #209 holds the full text. A one-sentence item gets one bounds form (drafted, confirmed by the person); the
verifier runs `verify:`, checks `invariants:`, and fails a diff that touches `out-of-scope:`.

## HEF-54 — `record --item-kind` cannot downgrade an item's kind under merge_by auto (9.4.2)

Found by HEF-30's verify gate on 2026-11-13: the scan rated it MEDIUM and the reviewer listed it as a suggestion; it
did not block the merge. `ledger.sh record <id> --item-kind feature` (hooks/ledger.sh:697) is open to any session, so
an `incident` or `vulnerability` item can be re-labelled, and `automerge` then skips its kind gate. Done when: a kind
change from incident/vulnerability to a lighter kind is a person's signature (`--reviewed-by-human --by`) or the
launcher's, automerge reads the kind recorded at intake, and a smoke case forges the downgrade and gets no merge.

## HEF-55 — the macOS static guard refuses a `case` inside a command substitution

Found on PR #212 (HEF-22), 2026-11-15: a `case` inline in `x="$( … case … esac … )"` passed the suite's macOS
portability guard and shellcheck, then failed 187 smoke cases on macOS: /bin/bash 3.2 ends the substitution at the
case pattern's `)` ("syntax error near unexpected token `newline'"). Done when: the static guard flags a `case`
pattern inside `$(`…`)` in `hooks/*.sh` and `install.sh` (a function called from the substitution passes), with a
fixture that fails before and passes after, and a mutation of the guard caught.

## HEF-56 — follow-ups from the HEF-16 and HEF-31 reviews

Non-blocking findings the verify gates left open (2026-11-21/22). Merge-forward (HEF-31, PR #220): the
launcher still reads a stale pre-reopen forward row at `session-launch.sh:325` (reproduced with `--dry-run`),
outside `forward_open_row`; a branch name holding `<!--` makes the conflict block's reason unreadable in
`ledger.sh questions` (`ledger-lifecycle.sh:185`); a blocked forward run twice is not idempotent. Publish-commit
(HEF-16, PR #219): the `gpgsign` pin has no test or mutant (`ledger-publish.sh:78`); the rollback fails while an
`index.lock` is held (`:79`); the CHANGELOG and `docs/hooks.md:32` misdescribe the `--mark`/`--locate` mismatch
refusal; the one-minute stale-lock break could let two publishes in; no test for the "no marker" message or a failed
rollback. Done when: each is fixed or recorded as accepted, each fix with a test and a mutant caught.

## HEF-57 — a FAIL verdict goes back to the build stage with its findings (verify-fix loop)

Report 19, A1. Today a FAIL from the verify stage blocks the item on `verdict`; `unblock` clears the block, the phase
stays `verify`, and the builder never sees the findings — a person carries every round (16 rounds on HEF-22, HEF-25
and HEF-31). Wanted: on FAIL the item returns to the build stage with a brief generated from the verdicts' evidence
(as data, hashed, like the merge-forward brief), the builder fixes and hands back to verify, with no person in
between; `orchestrate.verify_rounds` (default 3) caps it, then one block a person reads. Done when: a fixture item
goes FAIL → fix → PASS with no person's command; the cap blocks with the open findings readable through
`ledger.sh questions`; a spec deviation or a finding the builder disputes becomes a person's question, not a round.

## HEF-58 — the code review finds every blocking defect in one round (finders by lens, a verifier)

Report 19, A2. In HEF-31 each of five verify rounds found blocking defects the round before had missed, and the
builder's own review approved the same code. `agents/code-reviewer.md` tells the reviewer to prefer fewer findings
and has no lens for state and lifecycle defects; the lenses exist only in `workflows/workflow.js`. Wanted: the verify
stage's review runs finders in parallel by lens (input and security, state and lifecycle, spec deviation, test
integrity), a verifier reproduces each finding before it counts, and one verdict lists every blocking finding; each
lens answers "none, checked X" when it finds nothing; one finder runs on another tier. Done when: replayed on the
commits verify rejected in HEF-22, HEF-25 and HEF-31, one round reports the defects those rounds found one by one
(an eval case per defect), and the round's cost is recorded beside it.

## HEF-59 — a deterministic driver chains build, tests, verify and fix in a single lane

Report 19, A4. In single-lane mode the chain is prose in `commands/hef.orchestrate.md`: a person started every heavy
run by hand (about 60 "script running" / "merged" messages for seven items), plan and verify failures retry without
a cap, and a killed launcher leaves its item claimed until the next `claim`. Wanted: one driver (a script, not model
prose) that launches the next run when the host has room (HEF-25's gate and cap), chains build → tier 1 → verify →
fix (HEF-57), reaps dead claims at the start of every pass, counts plan and verify attempts and stalls at 3, and
stops only at a block a person must clear. Done when: a fixture board item goes from `tasks` to `human:merge` with
no person's command; a killed run is reclaimed on the next pass; a busy host (exit 75) is retried, not dropped.
