---
model: opus
description: "Read-only cross-artifact consistency analysis with coverage mapping"
---

# Analyze

Perform a read-only consistency analysis across all spec artifacts for the current branch.

## Pre-Flight

### Current branch
> The commands in this section must be run with the Bash tool; they cannot be
> pre-executed in a `!` block. A `!` block is permission-checked before the
> CLAUDE_PLUGIN_ROOT variable is substituted, so it is rejected as "Contains
> expansion". Do not write that variable with a $ and braces here: it would be
> substituted into this note and the warning would read as nonsense.

Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh branch`

### Load all artifacts
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh all-artifacts`

### Constitution
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh constitution`

### Checklists
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh checklists-content`

## Instructions

**This command is strictly read-only. Do NOT modify any files.**

Analyze all available artifacts and produce a consistency report with six detection passes:

### Pass 1: Duplication Detection
- Scan for overlapping or redundant requirements across spec.md, plan.md, tasks.md
- Flag identical or near-identical items

### Pass 2: Ambiguity Detection
- Find vague language: "should", "might", "could", "appropriate", "as needed"
- Flag requirements without measurable criteria
- Flag user scenarios with unclear preconditions or outcomes

### Pass 3: Underspecification Detection
- Find requirements referenced in tasks but not fully defined in spec
- Find design decisions in plan without corresponding requirements
- Flag missing edge cases and error handling

### Pass 4: Constitution Alignment
- Verify every constitution principle is addressed in the plan
- Flag any task or design decision that contradicts a principle
- Check that tech stack choices align with constitution

### Pass 5: Coverage Gaps
- Map every FR-NNN to at least one T-NNN task
- Map every SC-NNN to a validation method
- Flag orphaned tasks (no FR/US reference) or orphaned requirements (no task)

### Pass 6: Inconsistency Detection
- Cross-reference priorities (P1/P2/P3) between spec and tasks
- Verify task file paths match plan's affected files list
- Check that user scenario references are consistent

## Output Format

```
SPEC-KIT ANALYSIS REPORT
=========================
Branch: <branch-name>
Date: YYYY-MM-DD
Artifacts analyzed: spec.md, plan.md, tasks.md, constitution.md

## Findings

### CRITICAL
- [Inconsistency] FR-003 referenced in tasks.md but not defined in spec.md
- [Coverage Gap] SC-002 has no corresponding task

### HIGH
- [Ambiguity] US2 "When user does something" — action is vague
- [Constitution] Principle 3 not addressed in plan.md

### MEDIUM
- [Duplication] FR-001 and FR-004 describe similar behavior
- [Underspecification] Error handling for US1 not defined

### LOW
- [Style] Task T007 missing file path reference

## Coverage Mapping

| FR | Tasks | Status |
|----|-------|--------|
| FR-001 | T001, T002 | COVERED |
| FR-002 | T003 | COVERED |
| FR-003 | — | UNCOVERED |

| SC | Validation | Status |
|----|-----------|--------|
| SC-001 | T001 test | COVERED |
| SC-002 | — | UNCOVERED |

## Summary
- Total findings: N (C critical, H high, M medium, L low)
- Coverage: X/Y requirements mapped to tasks
- Recommendation: <next action>
```
