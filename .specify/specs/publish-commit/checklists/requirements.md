# Requirements Checklist: publish-commit
<!-- Auto-generated from spec.md by /hefesto:hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: commit only on external + tasks-repo + both flags `true` | [completeness] | [ ] |
| CHK002 | FR-001: off/absent/string "true" byte-identical to today | [testability] | [ ] |
| CHK003 | FR-002: dirty/staged/untracked column refused before mark | [completeness] | [ ] |
| CHK004 | FR-002: other dirty paths do not block and stay untouched | [testability] | [ ] |
| CHK005 | FR-003: merge/rebase/cherry-pick/revert/detached HEAD refused | [completeness] | [ ] |
| CHK006 | FR-004: --mark reports absolute resolved path; locate writes nothing | [testability] | [ ] |
| CHK007 | FR-004: column outside board_top refused before mark | [security] | [ ] |
| CHK008 | FR-005: one pathspec path, neutral git config kept + gpgsign off, no push, no branch change | [security] | [ ] |
| CHK009 | FR-006: mark → commit → re-hash → record; rollback on failure | [testability] | [ ] |
| CHK010 | FR-007: success line names the branch, "not pushed" | [clarity] | [ ] |
| CHK011 | FR-008: docs state external-only + branch expectation + refusals | [completeness] | [ ] |
| CHK012 | FR-009: sourced helper; every refusal non-zero with evidence | [consistency] | [ ] |
