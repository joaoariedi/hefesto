

## 2026-10-05 — **HEF-15** — branch model: integration branch, protected branches, environment chain

Shipped in 7.9.0 (PR #94): `branches` {integration, protected, environments}, `ledger.sh branches [--configured]` / `where`, the integration-aware tools, pr-watch `push:false`. Spec `.specify/specs/branch-model/`.

Requested by fxcube-project (2026-10-05; fxcube `tasks/initiatives/lane-setup-v2.md` §4 G2).
`main` is hard-coded as where a change lands (`ledger.sh` unblock ancestry, the verifier's diff base,
the protected-head refusals). A `branches` block — `integration` (PR base, verifier diff base,
`human:merge` ancestry), `protected` (never a worker head, never pushed), `environments` (ordered
promotion chain; the last is the final branch `released` and the tag follow). Each promotion stays
a human merge. Unconfigured = today's trunk behaviour.

## 2026-10-05 — **HEF-14** — external board: one tasks repo feeding several code repos

Shipped in 7.9.0 (PR #95): `board` pointer + `repos` map, `ledger.sh board` (`hooks/board-lib.sh`), item `repo:` routing, the central ledger, per-repo `next`. Spec `.specify/specs/external-board/`.

Requested by fxcube-project (2026-10-05; fxcube `tasks/initiatives/lane-setup-v2.md` §4 G1). Two
board modes: `in-repo` (today, default) and `external` — the board is its own git repo, a code repo
points at it, and the board config maps repo names to paths. Each item names its target repo; the
planner, worker, verifier and babysitter run in that repo's worktree; an item that targets two repos
is refused with a clear message (split it). One central ledger in the board repo's git common dir,
so ownership and the one-worker-per-repo check see every repo the board feeds. `/hef.status`,
`--item`/`--item-raw`/`--item-kind`, `ledger handoff` and `publish` work against the external board,
board writes landing in the board repo. Unconfigured = today's behaviour.
