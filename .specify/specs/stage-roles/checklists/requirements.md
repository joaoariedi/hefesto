# Requirements Checklist: stage-roles
<!-- Auto-generated from spec.md by /hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: `next --stage deploy` admits a `human:merge` block and nothing else | [testability] | [ ] |
| CHK002 | FR-003: the hooks-dir allowlist entry is an exact prefix, no mid-pattern wildcard | [completeness] | [ ] |
| CHK003 | FR-004: the plan worker's write surface is `.specify/**` only | [testability] | [ ] |
| CHK004 | FR-008: every verdict has a transcription outcome, including `closed` | [completeness] | [ ] |
| CHK005 | FR-010: an invalid config falls back to the default map, never to a missing line | [testability] | [ ] |
| CHK006 | FR-009: the default stage keeps today's `/hef.orchestrate` behaviour byte-for-byte | [consistency] | [ ] |
