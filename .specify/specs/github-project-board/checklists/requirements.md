# Requirements Checklist: github-project-board
<!-- Auto-generated from spec.md by /hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: `--list <column>` | [testability] draft items, PRs and unmapped repos are each a test case | [ ] |
| CHK002 | FR-002: ids `<prefix>-<number>` | [negative] an unmapped repo's id and an unknown number are refused | [ ] |
| CHK003 | FR-003: item text | [security] nonce delimiters and comment stripping are byte-checked against tasks-repo | [ ] |
| CHK004 | FR-004: kinds from labels | [completeness] the default and a configured map are both tested | [ ] |
| CHK005 | FR-005: RFC line | [security] the tasks-repo path rules are reused, not copied | [ ] |
| CHK006 | FR-006: register kind | [compatibility] tasks-repo registration is unchanged | [ ] |
| CHK007 | FR-007: author trust | [security] NONE can never be configured as trusted; an unreadable association fails closed | [ ] |
| CHK008 | FR-008: add | [error] a failure after issue creation names the URL and prints no id | [ ] |
| CHK009 | FR-009: fail closed | [testability] one mutant per gh failure path | [ ] |
| CHK010 | FR-010: publish moves Status | [negative] no field other than Status is written | [ ] |
| CHK011 | FR-011: detect and adopt | [completeness] the orchestrator text no longer says "read only" | [ ] |
| CHK012 | FR-012: docs | [completeness] scopes and the trust rule are documented | [ ] |
