# Requirements Checklist: run-survival
<!-- Auto-generated from spec.md by /hefesto:hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: detach order systemd-run → setsid → attached | [completeness] | [ ] |
| CHK002 | FR-001: dry-run/prepare/finish never detach | [testability] | [ ] |
| CHK003 | FR-002: detached output only to launcher.log; claim pid = detached pid | [testability] | [ ] |
| CHK004 | FR-003: caller relays log + exit code, forwards no signal | [testability] | [ ] |
| CHK005 | FR-004: run cap counts pid-holding live owners ledger-wide | [completeness] | [ ] |
| CHK006 | FR-004: interactive claims excluded | [edge-case] | [ ] |
| CHK007 | FR-005: invalid max_concurrent_runs dies with value + range | [error-handling] | [ ] |
| CHK008 | FR-006: MemAvailable floor and PSI avg60 > 50 refuse with exit 75 | [testability] | [ ] |
| CHK009 | FR-007: missing /proc files skip with note; seam only outside lane mode | [security] | [ ] |
| CHK010 | FR-008: busy claim refusal → exit 75 | [consistency] | [ ] |
| CHK011 | FR-009: changed-files-only, ulimit -v, 3000-line skip, exit codes | [testability] | [ ] |
| CHK012 | FR-010: commit hook applies same skip and limit | [consistency] | [ ] |
| CHK013 | FR-011: quality/verify commands route through the helper | [completeness] | [ ] |
| CHK014 | FR-012: oomd note, never "systemctl disable", exit unchanged | [security] | [ ] |
| CHK015 | FR-013: orchestrate/docs/CHANGELOG updated | [completeness] | [ ] |
