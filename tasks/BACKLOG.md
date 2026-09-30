# BACKLOG

Not yet dispatchable. Phase 2 of report 17 lives here until Phase 1 has numbers.

## HEF-4 — ledger publish: write phase and blocked reason back to the board

Phase 2 of `reports/17-multi-agent-session-orchestration.md`. `ledger publish <id>` mirrors the
entry's `phase` and `blocked_on` to the board item (a sub-state marker on the kanban heading, or a
comment on the GitHub Project item), so the board becomes the cross-machine truth. Outward write
only; `gh` detected, never installed.

## HEF-5 — blocked-escalation message to the attended session

Phase 2 of report 17. When an entry sits in a `human:*` block longer than a configured time, the
orchestrator sends one `SendMessage` to a named attended session with the text
`ledger <id> blocked_on <kind> <path>` and nothing else. Pointer only; the receiver treats it as
data. Add only if Phase 1 shows blocked entries waiting longer than the target.

## HEF-6 — ledger handoff shortcut for hand-run items

A person working an item in a `<repo>-feature` pane goes through four ledger calls to hand it to
the release queue (`run --role implement --exit 0 --usd 0`, `record --pr … --branch …`,
`advance pr`, `block --kind human:merge`). Add `ledger.sh handoff <id> --pr <url>` that does exactly
those four, reading the branch from the current checkout, with the same guards and a smoke fixture.

## HEF-7 — PR babysitter: loop on CI and review comments up to the human merge gate

Report 18 #2. After `/hef.pr`, a `--watch` mode (or `/hef.babysit <pr>`) loops with `ScheduleWakeup`
on `gh pr checks`: a red check → fetch the failed job log, `/hef.fix` on the branch, push, reply with
the commit hash; a review comment → the untrusted-input rule, pertinent → address and reply with the
hash, doubtful → ask the user; mergeable → stop and set `blocked_on: human:merge`. Never merges.
Helper `hooks/pr-watch.sh` (fetcher over `gh`; fake-`gh` smoke). Evidence: each CI failure −15 %
merge odds; reviewer abandonment 38 % of rejections (report 17 §1f).

## HEF-8 — arena: bounded read-only fan-out in /hef.plan Phase 0

Report 18 #4 (deck slide 23). `/hef.plan --arena K` sends the truth-map questions to K `repo-scout`
agents at different tiers, read-only, each returning a ≤2k-token digest; the planner merges them
into `research.md` with per-claim attribution and turns disagreements into `[NEEDS CLARIFICATION]`.
Cross-vendor explorers only when their CLIs are detected (optional-provider lane). K ≤ 3.

## HEF-9 — dependency audit in /hef.scan

Report 18 #5 (the deck's Builder role). Detect `osv-scanner`, `npm audit`, `pip-audit`,
`cargo audit`, `govulncheck`; list dependencies new in the diff and known vulnerabilities as a
`--deps` section; advisory line in `quality-before-commit.sh`. Detection lives in the
`quality-tooling` skill; nothing is installed.

## HEF-10 — board item kinds with kind-specific verifier gates

Report 18 #6 (deck slides 32–33). A heading marker the board already parses (🐞 incident,
🛡 vulnerability) becomes `kind` on the ledger entry; the verify prompt adds the kind's gate — a
regression test citing the incident id must exist and pass; a re-scan must be clean — as verdict
gates `incident` / `vulnerability`. Phase 2 of orchestrate.

## HEF-11 — stage roles in the launcher and `/hef.orchestrate --stage`

Report 18 addendum A5 (the deck as the macro layer). `session-launch.sh plan <id>`: a fresh
process that runs brainstorm → spec → plan → tasks, writes only under `.specify/`, and exits on the
first `[NEEDS CLARIFICATION]` with `block --kind human:clarify` or at `ledger advance tasks`.
`session-launch.sh deploy <id>`: HEF-7's babysitter as a headless role, one process per PR, exits
at mergeable with `block --kind human:merge`. `/hef.orchestrate --stage plan|build|deploy`, default
`build` so today's call is unchanged; per-stage tiers under `orchestrate.tiers`. Depends on HEF-7.

## HEF-12 — pane-aware block routing

Report 18 addendum A3. `orchestrate.panes` in `.claude/project-status.json` maps block kinds to
pane names (`human:clarify` → `plan`, `human:merge` → `deploy`, …); `session-start-context.sh`
appends the owner to each blocked line (`ledger: HEF-7 blocked_on human:merge → deploy`) so every
pane sees the queue and each line says whose it is — no filtering by session name, which hooks
cannot see. HEF-5's escalation message then targets the kind's pane instead of one named session.

## HEF-13 — providers registry and arena runners

Report 18 addendum A4, phase 2 of the arena; gated on HEF-8's number. A `providers` block in
`.claude/project-status.json` declares what the user has and how it is reached (`claude`, `codex`,
`gemini`, `aws` for Bedrock models the `claude` binary cannot drive); `hooks/arena-run.sh
<provider> <prompt-file>` wraps each CLI's non-interactive mode, detected with `command -v`, never
installed, never in the manifest. `/hef.plan --arena` fans out over runners instead of tiers, same
K ≤ 3 and digest cap. Runs from the pane, never from a hook or a sandboxed worker. A foreign-vendor
model reviews only as `/hef.review --second-opinion <provider>`, never as the verifier of record.

