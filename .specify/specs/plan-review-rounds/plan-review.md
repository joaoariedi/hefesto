# Plan review log — plan-review-rounds
<!-- written by hand by the HEF-21 planner run; the round helper this item builds does not exist yet -->

## Round 1 — 2026-11-09 — REVISE_PLAN
decision: no
Eight plan-only changes, all applied to plan.md / spec.md in this run: link `plan-review-lib.sh` into the
`st_mutdir` (`tests/smoke.sh:2207`) and `sl_md` (`:2001`) mirrors; `--spec-dir` on `/hefesto:hef.review`
bypasses the branch-resolved pre-flight; FR-007 reconciled with FR-003 (only an explicit `--cap` mismatch is
refused); `--person-input` idempotent on an empty same-kind segment; refuse "rounds but no segment header";
question-file findings cut to a computed budget; test cases (f)–(i) added; minor sketch fixes.

## Round 2 — 2026-11-09 — REVISE_PLAN
decision: no
Open — not applied (the run stops at a second REVISE_PLAN):
1. The headless planner has no `rm` (`session-launch.sh:205`): the helper must consume `--findings-file` (read then delete, on record and on refusal) or take findings on stdin.
2. With `HEFESTO_WORKER` set and non-zero, the helper refuses `--person-input review` and any `--verdict` without `--cap`; mutation-tested.
3. Refuse a findings file holding a line matching `^## (Round|Segment) ` (or `> `-quote findings when appending), so a quoted header cannot corrupt the counter; add to case (i) with a mutation.
4. Refuse a `--verdict` when the open segment's last round blocked (`NEEDS_DISCUSSION` or `decision: yes`); only a person's input reopens recording; add to case (b) with a mutation.
5. Sketch 5: the call passes 2 args but the function reads `$3` (fails under `set -u`, `session-launch.sh:44`); build the index into a variable first, cut index and findings to the budget; make test (h)'s summary 2,000 multibyte characters.
6. Choose: `--person-input review` is a no-op while the open segment is already `person review`, and `block cap` is never printed in a `person review` segment — or state that each person round is its own segment.
7. Sketch 4: the cap block goes after `:494` (it reads `$ANSBLK$NOTEBLK`); add `false` to case (d)'s refused values (jq `//` treats it as absent).
8. Affected Files row for `tests/smoke-plan-review.sh` → "(a)–(i)"; `hef.review.md:76` → `:77`; settle FR-009 vs the US6 edge on whether a missing log gets a note or nothing.
