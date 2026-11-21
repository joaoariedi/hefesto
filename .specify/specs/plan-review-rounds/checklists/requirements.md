# Requirements Checklist: plan-review-rounds
<!-- Auto-generated from spec.md by /hefesto:hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: `plan-review-round` helper — one stdout line, refusals leave the log byte-identical | [completeness] | [ ] |
| CHK002 | FR-001: every refusal path named (spec dir, findings file, symlink log, past cap) | [testability] | [ ] |
| CHK003 | FR-002: decision table approve / revise / block decision / block cap; decision outranks cap | [testability] | [ ] |
| CHK004 | FR-003: cap 1–20, source order `--cap` → open segment → config → 5 | [completeness] | [ ] |
| CHK005 | FR-004: launcher refuses an invalid `plan_review_rounds` before launch; retry keeps the segment cap | [testability] | [ ] |
| CHK006 | FR-005: "second REVISE_PLAN" gone from both prompts; `/hefesto:hef.review` is the only round recorder | [consistency] | [ ] |
| CHK007 | FR-006: reviewer brief asks for `[DECISION]` tags; command acts on `next:` line, not the bare verdict | [clarity] | [ ] |
| CHK008 | FR-006: a person's own review opens a `person review` segment | [completeness] | [ ] |
| CHK009 | FR-007: `plan-review.md` append-only format, segment header carries the cap, mid-segment cap change refused | [testability] | [ ] |
| CHK010 | FR-008: person revision/answer opens a new segment; `PR_MODE=human` override unchanged | [consistency] | [ ] |
| CHK011 | FR-009: question file = summary + round index + last findings ≤6,000 B + log path; symlink/outside-worktree skipped | [testability] | [ ] |
| CHK012 | FR-010: smoke cases (a)–(e) each paired with a mutation that turns it red | [testability] | [ ] |
| CHK013 | FR-011: docs, subcommand counts, usage text, CHANGELOG updated | [completeness] | [ ] |
