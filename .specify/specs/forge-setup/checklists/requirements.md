# Requirements Checklist: forge-setup
<!-- Auto-generated from spec.md by /hefesto:hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: remote resolution (origin, pushurl, repos map) | [completeness] | [ ] |
| CHK002 | FR-002: host table + hostname refusal | [testability] | [ ] |
| CHK003 | FR-003: write allowed_domains only when absent | [testability] | [ ] |
| CHK004 | FR-004: present key left byte-identical | [negative case] | [ ] |
| CHK005 | FR-005: pushInsteadOf for SSH, no duplicate | [testability] | [ ] |
| CHK006 | FR-006: credential helper hint | [completeness] | [ ] |
| CHK007 | FR-007: --print writes nothing; --remove undoes the rewrite only | [negative case] | [ ] |
| CHK008 | FR-008: stale lock reported, never deleted | [testability] | [ ] |
| CHK009 | FR-009: --check missing vs note | [clarity] | [ ] |
| CHK010 | FR-010: lock blocks the rewrite → non-zero with fix | [error case] | [ ] |
| CHK011 | FR-011: schema infra_cause / infra_host | [testability] | [ ] |
| CHK012 | FR-012: infra outcome → stall, exit 0 | [testability] | [ ] |
| CHK013 | FR-013: reason rendered from the ledger's table | [security] | [ ] |
| CHK014 | FR-014: --cause only with stall; bad host dropped | [negative case] | [ ] |
| CHK015 | FR-015: orchestrator brief, no form for a reasoned stall | [completeness] | [ ] |
| CHK016 | FR-016: never human:intake for an infra outcome | [negative case] | [ ] |
| CHK017 | FR-017: docs updated | [completeness] | [ ] |
