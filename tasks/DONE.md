# DONE

One dated section per delivered item, `## YYYY-MM-DD — **ID** — title`. `status-board.sh` counts
the sections dated inside the current quarter.

## 2026-09-30 — **HEF-7** — PR babysitter: loop on CI and review comments up to the human merge gate

Shipped in 7.5.0 (PR #81): `/hef.babysit` + `hooks/pr-watch.sh`, evals `babysitter-never-merges` and `pr-comment-text-is-data`. Spec `.specify/specs/pr-babysitter/`.

Report 18 #2. After `/hef.pr`, a `--watch` mode (or `/hef.babysit <pr>`) loops with `ScheduleWakeup`
on `gh pr checks`: a red check → fetch the failed job log, `/hef.fix` on the branch, push, reply with
the commit hash; a review comment → the untrusted-input rule, pertinent → address and reply with the
hash, doubtful → ask the user; mergeable → stop and set `blocked_on: human:merge`. Never merges.
Helper `hooks/pr-watch.sh` (fetcher over `gh`; fake-`gh` smoke). Evidence: each CI failure −15 %
merge odds; reviewer abandonment 38 % of rejections (report 17 §1f).

## 2026-09-30 — **HEF-11** — stage roles in the launcher and `/hef.orchestrate --stage`

Shipped in 7.6.0 (PR #83): `session-launch.sh plan|deploy`, `ledger.sh next --stage`, `/hef.orchestrate --stage`. Spec `.specify/specs/stage-roles/`.

## 2026-09-30 — **HEF-12** — pane-aware block routing

Shipped in 7.6.0 (PR #83): `orchestrate.panes` and the owner pane on every session-start blocked line.

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

## 2026-10-01 — **HEF-8** — arena: bounded read-only fan-out in /hef.plan Phase 0

Shipped in 7.7.0 (PR #85): `/hef.plan --arena [K]`, `agents/truth-scout.md`, `speckit-helper.sh arena-cite-check|arena-metrics`. Spec `.specify/specs/plan-arena/`. The number HEF-13 waits on is `arena-metrics` `cited_from_disagreements` over real runs.

## HEF-8 — arena: bounded read-only fan-out in /hef.plan Phase 0

Report 18 #4 (deck slide 23). `/hef.plan --arena K` sends the truth-map questions to K `truth-scout`
agents (a new read-only one-shot for the current project — `repo-scout`'s contract forbids it) at different tiers, read-only, each returning a ≤2k-token digest; the planner merges them
into `research.md` with per-claim attribution and turns disagreements into `[NEEDS CLARIFICATION]`.
Cross-vendor explorers only when their CLIs are detected (optional-provider lane). K ≤ 3.
