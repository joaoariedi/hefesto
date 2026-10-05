# DOING

Items a human is actively working on. Session-owned items stay in TODO.md; the ledger
(`hooks/ledger.sh list --active`) is the record of what a session holds.

## HEF-15 — branch model: integration branch, protected branches, environment chain

Requested by fxcube-project (2026-10-05; fxcube `tasks/initiatives/lane-setup-v2.md` §4 G2).
`main` is hard-coded as where a change lands (`ledger.sh` unblock ancestry, the verifier's diff base,
the protected-head refusals). A `branches` block — `integration` (PR base, verifier diff base,
`human:merge` ancestry), `protected` (never a worker head, never pushed), `environments` (ordered
promotion chain; the last is the final branch `released` and the tag follow). Each promotion stays
a human merge. Unconfigured = today's trunk behaviour.

In progress 2026-10-05 on `feature/branch-model` (spec `.specify/specs/branch-model/`).

## HEF-14 — external board: one tasks repo feeding several code repos

Requested by fxcube-project (2026-10-05; fxcube `tasks/initiatives/lane-setup-v2.md` §4 G1). Two
board modes: `in-repo` (today, default) and `external` — the board is its own git repo, a code repo
points at it, and the board config maps repo names to paths. Each item names its target repo; the
planner, worker, verifier and babysitter run in that repo's worktree; an item that targets two repos
is refused with a clear message (split it). One central ledger in the board repo's git common dir,
so ownership and the one-worker-per-repo check see every repo the board feeds. `/hef.status`,
`--item`/`--item-raw`/`--item-kind`, `ledger handoff` and `publish` work against the external board,
board writes landing in the board repo. Unconfigured = today's behaviour.

In progress 2026-10-05 on `feature/external-board` (spec `.specify/specs/external-board/`).
