# DOING

Items a human is actively working on. Session-owned items stay in TODO.md; the ledger
(`hooks/ledger.sh list --active`) is the record of what a session holds.

## HEF-8 — arena: bounded read-only fan-out in /hef.plan Phase 0

Report 18 #4 (deck slide 23). `/hef.plan --arena K` sends the truth-map questions to K `truth-scout`
agents (a new read-only one-shot for the current project — `repo-scout`'s contract forbids it) at different tiers, read-only, each returning a ≤2k-token digest; the planner merges them
into `research.md` with per-claim attribution and turns disagreements into `[NEEDS CLARIFICATION]`.
Cross-vendor explorers only when their CLIs are detected (optional-provider lane). K ≤ 3.

In progress 2026-09-30 on `feature/plan-arena` (spec `.specify/specs/plan-arena/`), by a person in this session.
