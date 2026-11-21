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

## Segment — person answer — 2026-11-09 — cap 5
The person answered: apply the review's changes and re-review until APPROVE (cap 5 rounds); stop only on
a product or design question. Round 2's eight changes were applied to plan.md / spec.md before round 1
of this segment. Finding 6 took the first option (a `person review` segment persists and the cap does not
bind it), plus a `lane review` segment so a lane after a person review is still bounded.

## Round 1 — 2026-11-09 — REVISE_PLAN
decision: no
1. Extend the findings forgery refusal to `^(## (Round|Segment) |decision: )` (contract row, FR-010 (i) mutation), so a findings line cannot flip `prr_segment_blocked` or leak into the FR-009 index.
2. `PRR_RULE` and `hef.review.md`: on a helper refusal naming a blocked round → outcome `blocked` / `human:plan-review` quoting it; any other refusal → `failed` with the refusal in the summary; pin in case (e).
3. Case (e) also pins `hef.review.md` for the `[DECISION]` brief sentence and `--person-input review` as the no-`--cap` first step, each with a delete-the-sentence mutation.
4. Resume prompt writes the real `--spec-dir $SPEC_DIR` into `PRR_RULE`; the `<spec dir>` placeholder stays only in the fresh prompt.

## Round 2 — 2026-11-09 — APPROVE
decision: no
Non-blocking notes, folded into plan.md / spec.md after the verdict:
1. Sketch 7: drive the fake planner with the absolute `--spec-dir` the prompt carries, so (a)–(c) exercise a lane's real input.
2. Sketch 3: state the containment check (`pwd -P` of the dir under `pwd -P` of `<spec root>/.specify/specs/`); add an absolute-path probe to (i).
3. Sketch 5: `[ -n "$SDA" ]` guard before `prr_question_tail`.
4. Sketch 2: segment cap/kind and the awk counters parse the same (last) `## Segment ` line; an unparsable last header is refused.
5. Sketch 3: show the FR-003 cap order (explicit, segment, config, 5).
6. Spec FR-001/FR-010(i): findings consumed on every refusal after the path checks; FR-005: "never `--verdict`".
7. Sketch 4: the fresh prompt's first `/hefesto:hef.review` mention carries the same flags as `PRR_RULE`.
