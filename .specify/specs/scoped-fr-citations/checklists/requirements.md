# Requirements Checklist: scoped-fr-citations
<!-- Auto-generated from spec.md by /hefesto:hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: qualified `<spec>/FR-NNN` counts for `<spec>` only | [completeness] spec-name charset stated | [ ] |
| CHK002 | FR-002: bare match excludes qualified tokens | [testability] `/` word-boundary trap named | [ ] |
| CHK003 | FR-003: scoped marker line | [clarity] exact marker text given | [ ] |
| CHK004 | FR-004: bare-citation hint on UNCOVERED rows | [testability] cap (3) and content stated | [ ] |
| CHK005 | FR-005: legacy mode counts bare + own-qualified | [consistency] with D2 | [ ] |
| CHK006 | FR-006: header names the mode | [testability] exact strings | [ ] |
| CHK007 | FR-007: qualified ELSEWHERE non-failing | [consistency] with bare ELSEWHERE | [ ] |
| CHK008 | FR-008: qualified UNKNOWN (missing spec / undeclared id) fails | [completeness] both cases | [ ] |
| CHK009 | FR-009: `--all` contract unchanged | [consistency] with smoke `--all` fixture | [ ] |
| CHK010 | FR-010: repo stays green | [measurability] baseline 15 shipped / 0 failing | [ ] |
| CHK011 | FR-011: docs/sdd.md | [completeness] legacy→scoped move documented | [ ] |
| CHK012 | FR-012: template + command guidance | [completeness] all five commands named | [ ] |
| CHK013 | FR-013: probe attribution | [testability] two-spec collision fixture | [ ] |
| CHK014 | FR-014: fixtures mutation-checked | [testability] one mutation per branch | [ ] |
