# Requirements Checklist: lane-build-cache
<!-- Auto-generated from spec.md by /hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: the wrapper's env | [testability] the child's environment is asserted, variable by variable | [ ] |
| CHK002 | FR-002: refuses outside the sandbox | [security] writable probe, missing probe, missing env: each a test with a mutant | [ ] |
| CHK003 | FR-003: setup | [compatibility] idempotent, --remove, a single-lane setup untouched | [ ] |
| CHK004 | FR-004: no session-wide cache variable | [security] a static check over setup's writes | [ ] |
| CHK005 | FR-005: lane-guard and request refusals | [security] grant, exclusion and request paths each a test with a mutant | [ ] |
| CHK006 | FR-006: --unsandboxed-command refusal | [negative] the wrapper and a path under the cache | [ ] |
| CHK007 | FR-007: stage text | [completeness] build and deploy text, and the --prepare prompt | [ ] |
| CHK008 | FR-008: docs | [completeness] the reason no session-wide variable is set | [ ] |
