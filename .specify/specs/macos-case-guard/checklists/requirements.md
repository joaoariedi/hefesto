# Requirements Checklist: macos-case-guard
<!-- Auto-generated from spec.md by /hefesto:hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: `case` inside an open `$(` fails the block | [completeness] multi-line, one-line, nested shapes named | [ ] |
| CHK002 | FR-001: `case` inside an open `$(` fails the block | [testability] failing fixture holds each shape | [ ] |
| CHK003 | FR-002: report names file, line, reason, remedy | [testability] message asserted on fixture output | [ ] |
| CHK004 | FR-003: function form / closed substitution / `$((` pass | [completeness] each shape in passing fixture | [ ] |
| CHK005 | FR-004: comments and quoted text ignored | [testability] passing fixture holds each | [ ] |
| CHK006 | FR-005: one guard function over real files and fixtures | [consistency] same code path, no copy | [ ] |
| CHK007 | FR-006: no false positives on today's tree | [testability] tier 1 green over hooks + install.sh | [ ] |
| CHK008 | FR-007: mutation of the guard caught | [testability] mutation applied (cmp) and survivors fail | [ ] |
| CHK009 | FR-008: ok line + CHANGELOG [Unreleased] | [completeness] | [ ] |
