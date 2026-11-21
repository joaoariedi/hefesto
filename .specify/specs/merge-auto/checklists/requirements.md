# Requirements Checklist: merge-auto
<!-- Auto-generated from spec.md by /hefesto:hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: merge_by values person/lane/auto, unknown refused | [completeness] | [ ] |
| CHK002 | FR-002: merge-auto grant/revoke/show in approvals store, lanes refused | [security] | [ ] |
| CHK003 | FR-003: auto only with a grant matching the integration branch | [testability] | [ ] |
| CHK004 | FR-004: verify records .pr.verified_head | [testability] | [ ] |
| CHK005 | FR-005: automerge preconditions (base, gates, head, state, checks) | [completeness] | [ ] |
| CHK006 | FR-006: pinned merge, evidence, auto-merged event, advance merged | [testability] | [ ] |
| CHK007 | FR-007: unmet precondition → human:merge with reason | [negative case] | [ ] |
| CHK008 | FR-008: failing merge check → ci | [testability] | [ ] |
| CHK009 | FR-009: BEHIND/CONFLICTING → conflict; pending → nothing | [edge case] | [ ] |
| CHK010 | FR-010: deploy launcher calls automerge on mergeable under auto | [completeness] | [ ] |
| CHK011 | FR-011: brief reports auto-merges and fallbacks | [clarity] | [ ] |
| CHK012 | FR-012: one multi-select merge form per pass, ≤16 | [testability] | [ ] |
| CHK013 | FR-013: one train form for all repositories | [clarity] | [ ] |
| CHK014 | FR-014: decider used as --by, name question skipped | [testability] | [ ] |
| CHK015 | FR-015: setup writes decider only when absent | [edge case] | [ ] |
| CHK016 | FR-016: docs + CHANGELOG | [completeness] | [ ] |
| CHK017 | NR-001..NR-004 each covered by a smoke assertion and a mutation | [negative case] | [ ] |
