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
