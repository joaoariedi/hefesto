# Requirements Checklist: verify-fix-loop
<!-- Auto-generated from spec.md by /hefesto:hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: FAIL below the cap → rework, not block verdict | [completeness] | [ ] |
| CHK002 | FR-001: verdicts + verified head written before the move | [testability] | [ ] |
| CHK003 | FR-002: rework's field changes and row/event shape | [testability] | [ ] |
| CHK004 | FR-003: every refusal leaves the entry byte-identical | [testability] | [ ] |
| CHK005 | FR-004: brief from a fixed template, hashed, `<!--` rewritten | [completeness] | [ ] |
| CHK006 | FR-005: verify_rounds 0–10, default 3, everything else refused | [testability] | [ ] |
| CHK007 | FR-006: cap → verdict block with a findings question file | [testability] | [ ] |
| CHK008 | FR-007: --past-cap person-only, ask rule, by recorded | [completeness] | [ ] |
| CHK009 | FR-008: hash check and delimited data in the rework prompt | [testability] | [ ] |
| CHK010 | FR-009: question field only on a rework run; launch-920 fixture unchanged | [testability] | [ ] |
| CHK011 | FR-010: route kept, pr_url check, consumed only on pr | [testability] | [ ] |
| CHK012 | FR-011: dispute / spec deviation → human:clarify question, no push | [clarity] | [ ] |
| CHK013 | FR-012: person's ruling reaches the next verify run only when answered | [testability] | [ ] |
| CHK014 | FR-013: rework rows older than the last reopen are closed | [testability] | [ ] |
| CHK015 | FR-014: orchestrator verdict row options with and without question_path | [completeness] | [ ] |
| CHK016 | FR-015: docs + CHANGELOG [Unreleased] + usage | [completeness] | [ ] |
| CHK017 | FR-016: every guard mutation-tested | [testability] | [ ] |
