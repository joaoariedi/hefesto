# Requirements Checklist: spend-cap-opt-in
<!-- Auto-generated from spec.md by /hefesto:hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: no cap → no `--max-budget-usd` | [testability] dry-run token absent | [ ] |
| CHK002 | FR-001: null equals missing | [completeness] | [ ] |
| CHK003 | FR-002: set cap → today's flag and daily rule | [regression] | [ ] |
| CHK004 | FR-003: no daily cap → no refusal on any path | [completeness] pre-claim + deploy babysit | [ ] |
| CHK005 | FR-004: daily-only cap refuses at spent ≥ cap | [testability] boundary at equality | [ ] |
| CHK006 | FR-005: deploy merge record passes over the cap | [regression] | [ ] |
| CHK007 | FR-006: init writes no cap keys | [testability] | [ ] |
| CHK008 | FR-007: guides say opt-in, no stated default | [consistency] SC-003 grep | [ ] |
| CHK009 | FR-008: every new test carries a mutation | [testability] | [ ] |
