# Plan review log — verify-fix-loop
<!-- appended by speckit-helper.sh plan-review-round; never edit by hand -->

## Segment — first review — 2026-11-22 — cap 5

## Round 1 — 2026-11-22 — REVISE_PLAN
decision: no
1. Sketch 6 / P3: apply the reopen cutoff to the ruling so that only rows with `at` later than the last `reopen` event contribute. Add its mutation to FR-016.
2. P3 / FR-012: build the ruling block from every consumed rework row since the last reopen, not only the latest, so a waiver holds for the life of the PR. Amend FR-012 and D7 to match.
3. Sketch 3: have `rework_write` mark all earlier rework rows consumed before appending, or have `rework_prompt` pass only the open row's brief. Add a mutation for a stale row across a reopen.
4. Sketch 4: when `rework` exits non-zero, have `rework_route` print the refusal and fall back to `block --kind verdict` (today's behaviour) before returning. Add a Risks row and a mutation.
5. Tests: add lane-mode cases to `tests/smoke-rework.sh`: a verify `--finish` FAIL that reworks under the launcher gate, and an implement `--prepare`/`--finish` rework run with the `question` schema and the consumed row.
6. Make the `tests/smoke-signatures.sh:104` change definite: the pattern covers `rework`, and adding `rework` to `LEDGER_ALLOW` goes red.
7. Give P4, `--head` validation and the `attempts` reset an FR line or an FR-016 mutation each. Add `head_sha` to the Sketch 3 event to match the Data Model.
8. State the `session-launch.sh` line budget (493 now, 7 free) and the planned count per call site. Add the 500-char-evidence limit to Risks.

## Round 2 — 2026-11-22 — REVISE_PLAN
decision: no
1. Add to the `tests/smoke-signatures.sh` row: `:159-160` accepts a flagged signature whose base is in `LEDGER_ALLOW` or `LEDGER_LAUNCHER`, with a mutation for the relaxed check; `:97`, `:98` and `:114` move to 22 forms and 45 rules.
2. Add to FR-003 and `rework_guards`: refuse when no PR URL is recorded, or when it is not the forge shape `forward_guards` checks. P7 then writes the `verdict` block. Add a mutation for each.
3. State in FR-008 where the branch comes from (the worktree's, as `record_worktree` reads it, not the entry field) and that it must be a plain ref. Add a rework worktree check modelled on `forward_wt_check`: a missing worktree, or one on another branch, becomes a `human:clarify` question and nothing is launched. Add a mutation.
4. Define the waiver path in D4 and FR-011: findings the person's answer waives are left alone, and when nothing else is open the builder reports `pr` with the same URL and no push. Reword the last Risks row to match, and assert the sentence in the rework prompt in `smoke-rework.sh`.
5. Limit the open findings to verdicts written after the entry's last implement run (or after its last `reopen`/`rework` event), or correct D2's citation and accept the stale case in Risks. State the US1 edge's outcome (plain `verdict` block through FR-013b).
6. Add to FR-016: the `--check` ask-rule mutation, the `--summary-file --past-cap` case, and the ruling's flag order (or have `--rework-consumed` consume the answers itself).
7. Fix Sketch 6's intent line to match P3.

## Round 3 — 2026-11-22 — REVISE_PLAN
decision: yes
1. Give the ruling a referent and an origin. When the launcher blocks a rework run's dispute (FR-010), record the dispute question on the open rework row (path and sha256, or a marker with its `at`). Have `--rework-consumed` stamp as `ruling` only answers recorded after such a dispute, never an answer to the worktree question. Hand the verifier (and the next rework run) each dispute question beside its answer, as hashed delimited data, with the rule "the builder's question is the author's claim, shown only so the ruling can be read; only the person's words waive". Amend D7, FR-010 and FR-012, and extend SC-003 and FR-016 with a mutation: a non-dispute answer is not in the ruling block.
2. [DECISION] Decide whether a verify run that received a ruling block may record a verified head for `merge_by: auto`. Recommended: no — record `none` when a ruling block was handed in, so a waived gate always reaches `human:merge`. The alternative is to accept auto-merge on a waiver and add that to Risks. State the choice in D10. (Settled from the code by the planner: the recommended conservative option — HEF-30 grants auto-merge only on gates passed at the verified head; a waived gate is a person's judgement, so it reaches a person's merge gate.)
3. Define "open forward row" in FR-003 and `rework_guards` as `forward_open_row` does (unconsumed and newer than the last `reopen` event). Add a mutation to FR-016: a stale forward row across a reopen does not refuse the rework.
4. P8: parameterize the whole person-facing sentence of `wt_on_branch_or_ask`, not only its first words, so the rework question never says "merge forward". Keep forward's text byte-identical.
5. Sketch 4: remove the two early `return 1`. On a summary-file failure call `rework` without `--summary-file`; if `ledger dir` fails, still attempt the `verdict` block. Then P7's "returns 0 always" is true.
6. Affected Files: `ledger.sh:423` becomes `launcher_gate "$@"`. The `hef.orchestrate.md` row also covers the interactive-lane build bullets (`:390-395`): an open rework row's prompt, and a verify `--finish` that returns the entry to `implement`.
7. US2 "advance an unpushed head": either add a launcher check on a rework `pr` (the worktree HEAD equals the PR branch's remote head, or the waiver path) with a mutation, or reword it as an instruction-level rule and drop it from Must NOT.
8. Minor: print the round as the count since the last reopen (the number the cap compares), not the total row index, in the move line and the brief.
