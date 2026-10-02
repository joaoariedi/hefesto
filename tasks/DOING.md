# DOING

Items a human is actively working on. Session-owned items stay in TODO.md; the ledger
(`hooks/ledger.sh list --active`) is the record of what a session holds.

## HEF-9 — dependency audit in /hef.scan

Report 18 #5 (the deck's Builder role). Detect `osv-scanner`, `npm audit`, `pip-audit`,
`cargo audit`, `govulncheck`; list dependencies new in the diff and known vulnerabilities as a
`--deps` section; advisory line in `quality-before-commit.sh`. Detection lives in the
`quality-tooling` skill; nothing is installed.

In progress 2026-10-02 on `feature/dependency-audit` (spec `.specify/specs/dependency-audit/`).
