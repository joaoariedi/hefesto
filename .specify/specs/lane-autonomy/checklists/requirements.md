# Requirements Checklist: lane-autonomy
<!-- Auto-generated from spec.md by /hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: hook probe of AskUserQuestion answers | [testability] the probe's PASS/FAIL criteria are written before it runs | [ ] |
| CHK002 | FR-002: the form as signature | [security] the forgery cases (model-written `answers`, a lane file, a doorbell) are each a test | [ ] |
| CHK003 | FR-003: decision log | [completeness] every autonomous path in FR-004/006/011 writes an event | [ ] |
| CHK004 | FR-004: autonomous recovery | [testability] the retry budget is a counter in the ledger, tested at its limit | [ ] |
| CHK005 | FR-005: decision filter | [measurability] the product-shape / no-best-practice label is visible in each remaining form | [ ] |
| CHK006 | FR-006: merges by policy | [security] each policy input (verdicts, route, head, base) has a mutant | [ ] |
| CHK007 | FR-007: the protected final branch always asks | [negative] tested with `auto_merge: green` | [ ] |
| CHK008 | FR-008: no second Irreversible form | [completeness] the merge and irreversible-scope forms name what is irreversible | [ ] |
| CHK009 | FR-009: plan_review agent default | [compatibility] an existing project's explicit `human` is kept | [ ] |
| CHK010 | FR-010: --by default | [testability] git name, then $USER, never a form | [ ] |
| CHK011 | FR-011: reversible actions unapproved | [security] the reversible/outward classification is computed by ledger.sh and tested per command class | [ ] |
| CHK012 | FR-012: digest | [completeness] the session start shows it, with no form | [ ] |
| CHK013 | FR-013: prompt metric | [measurability] the baseline method is reproducible | [ ] |
