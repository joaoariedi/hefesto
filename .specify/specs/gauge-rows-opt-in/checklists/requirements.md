# Requirements Checklist: gauge-rows-opt-in
<!-- Auto-generated from spec.md by /hefesto:hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: rows only with `gauge_rows: true` (boolean) | [completeness] | [ ] |
| CHK002 | FR-001: the file read is `<pdir>/.claude/project-status.json` | [testability] | [ ] |
| CHK003 | FR-002: absent / non-boolean / invalid → context line only, rc 0, no stderr | [testability] | [ ] |
| CHK004 | FR-002: ledger not read when off | [completeness] | [ ] |
| CHK005 | FR-003: opted-in output byte-identical to today | [testability] | [ ] |
| CHK006 | FR-004: setup writes no `gauge_rows`, any mode | [testability] | [ ] |
| CHK007 | FR-005: every gauge doc names the key and its default | [completeness] | [ ] |
| CHK008 | FR-005: CHANGELOG `[Unreleased]` records the default change | [completeness] | [ ] |
