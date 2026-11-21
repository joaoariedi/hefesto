# Requirements Checklist: item-kind-downgrade
<!-- Auto-generated from spec.md by /hefesto:hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: init records intake_kind | [completeness] | [ ] |
| CHK002 | FR-002: unsigned downgrade refused, nothing written | [testability] | [ ] |
| CHK003 | FR-002: incident ↔ vulnerability counts as a downgrade (D2) | [clarity] | [ ] |
| CHK004 | FR-003: signed/launcher change sets both fields + event | [testability] | [ ] |
| CHK005 | FR-004: worker, bad name, no --item-kind refused | [negative-cases] | [ ] |
| CHK006 | FR-005: upgrades and no-ops stay unsigned | [completeness] | [ ] |
| CHK007 | FR-006: automerge union of kinds; legacy fallback | [testability] | [ ] |
| CHK008 | FR-007: forged downgrade gets no gh pr merge (tool-call assertion) | [testability] | [ ] |
| CHK009 | FR-008: both mutations caught | [testability] | [ ] |
| CHK010 | FR-009: ask rule + docs + CHANGELOG [Unreleased] | [completeness] | [ ] |
