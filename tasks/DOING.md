# DOING

Items a human is actively working on. Session-owned items stay in TODO.md; the ledger
(`hooks/ledger.sh list --active`) is the record of what a session holds.

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

In progress 2026-10-02 on `feature/ledger-surfaces` (spec `.specify/specs/ledger-surfaces/`).
## HEF-9 — dependency audit in /hef.scan

Report 18 #5 (the deck's Builder role). Detect `osv-scanner`, `npm audit`, `pip-audit`,
`cargo audit`, `govulncheck`; list dependencies new in the diff and known vulnerabilities as a
`--deps` section; advisory line in `quality-before-commit.sh`. Detection lives in the
`quality-tooling` skill; nothing is installed.

In progress 2026-10-02 on `feature/dependency-audit` (spec `.specify/specs/dependency-audit/`).
