# Requirements Checklist: session-orchestration
<!-- Auto-generated from spec.md by /hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: ledger init schema and idempotence | [completeness] every field named has a writer | [ ] |
| CHK002 | FR-001: ledger key = sha1 of common-dir parent | [testability] two worktrees resolve to one dir | [ ] |
| CHK003 | FR-002: claim exclusivity and stall at attempts > 2 | [testability] second claim non-zero, third sets stall | [ ] |
| CHK004 | FR-003: phase order forward-only | [completeness] enum matches the report §5a | [ ] |
| CHK005 | FR-004: review verdict by ≠ owner | [testability] same-name verdict refused | [ ] |
| CHK006 | FR-005: block kinds enum incl. human:intake | [completeness] every kind has an unblock rule | [ ] |
| CHK007 | FR-006: unblock needs artifact evidence per kind | [testability] each kind has a fixture with and without evidence | [ ] |
| CHK008 | FR-007: next/show/list, no sentinel | [consistency] constitution 5 | [ ] |
| CHK009 | FR-008: atomic writes, bash + jq only | [consistency] constitution 4 | [ ] |
| CHK010 | FR-009: dry-run command shape | [testability] flag list assertable from stdout | [ ] |
| CHK011 | FR-010: tier ranking and model-id refusal | [testability] mutation: drop the rank check → green? must be red | [ ] |
| CHK012 | FR-011: result capture into the ledger | [completeness] over-budget and non-zero exit paths | [ ] |
| CHK013 | FR-012: verify never sees the worker transcript | [testability] forbidden flags list | [ ] |
| CHK014 | FR-013: orchestrate command, one worker per repo | [consistency] sonnet tier; never merges | [ ] |
| CHK015 | FR-014: untrusted-text rule at intake | [consistency] same rule as /hef.fix and /hef.pr | [ ] |
| CHK016 | FR-015: session-start blocked line | [testability] fixture with and without ledger dir | [ ] |
| CHK017 | FR-016: tasks/ kanban and project-status.json | [completeness] status-board parses 3 todo items | [ ] |
| CHK018 | FR-017: three evals with tool_used max 0 graders | [consistency] constitution 3 (tool-call level) | [ ] |
| CHK019 | FR-018: mutation checks for every guard | [completeness] one per guard in the list | [ ] |
| CHK020 | FR-019: docs and counts | [completeness] 25 commands, 17 hook scripts | [ ] |
