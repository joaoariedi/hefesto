# DOING

Items a human is actively working on. Session-owned items stay in TODO.md; the ledger
(`hooks/ledger.sh list --active`) is the record of what a session holds.

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

In progress 2026-09-30 on `feature/stage-roles` (spec `.specify/specs/stage-roles/`), by a person in this session.
