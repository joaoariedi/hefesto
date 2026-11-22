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

## Segment — person answer — 2026-11-22 — cap 5

## Round 1 — 2026-11-22 — REVISE_PLAN
decision: no
1. Gate `record --rework-consumed` and `record --rework-dispute` on the launcher marker (`HEFESTO_LAUNCHER=1`, no session id, not a worker) as `verified_head_set` does (`ledger-automerge.sh:44-49`); have `--rework-dispute` record the path and sha256 of the question the block carries (no caller-chosen file); bodies in `ledger-rework.sh` behind one-line arms in `ledger.sh`. FR-016: each flag refused from a session and a worker, removing the gate goes red.
2. Replace "the row's last dispute" with an ordered list on the row of every question the launcher blocked it with, `{path, sha256, at, dispute: true|false}` (the FR-008 worktree question `dispute: false`); an answer is a ruling only when the latest listed question before it is a dispute, paired with that question. FR-016: two disputes in one row; worktree question after a dispute.
3. Complete the contracts: the asked/dispute fields in the Data Model row, `record --rework-dispute` in API Contracts with its gate, and its call site inside the arm's helper so `session-launch.sh` stays at +4.
4. Hook-level cases beside `tests/smoke-lifecycle.sh:350-365`: `lane-guard.sh` denies plain `ledger.sh rework <id>` in every lane, admits `rework <id> --past-cap --by x` in the orchestrator lane, denies it in a stage lane; mutation reverts `:166` to `is_launcher_sub "$SUB"`.
5. `rework_route` returns non-zero when the fallback `block --kind verdict` also fails, so the call site's `|| exit 1` is live; add a mutation.
6. Wording: the `session-launch-forward.sh` Affected Files row says `<branch> <sentence>` (P11.4); Sketch 1's guard comment says `verdict` required under `--past-cap`, no block without it (FR-007).

## Round 2 — 2026-11-22 — REVISE_PLAN
decision: no
1. Add `tests/smoke-forward.sh` to Affected Files and drop "stays green unchanged": retarget the mutations at `:283`, `:287`, `:449`, `:504` (the file now holding the `--forward-consumed` call) and `:533` (still mutating the implement `blocked)` path) — or shape the edits so those patterns survive, and say which.
2. Extend the `tests/smoke.sh` row to name the assertions at `:2348`, `:3746`, `:3751`, `:3764`, `:6484`: per assertion, set `orchestrate.verify_rounds: 0` in its fixture or rewrite it to the new outcome; none may pass through the FR-013b fallback. Record them as intended assertion changes for the implement-phase test guard.
3. Make the ruling pairing ordinal (P13, Data Model, FR-010): `asked[]` entries carry `answers_before` (`.answers | length` at record time); answer i is a ruling iff the last `asked[]` entry with `answers_before ≤ i` is a dispute. State that the P9 fixture writes explicit `at` values.
4. Minor: add `FORGE_INFRA_RULE` and `KIND_RULE` to `rework_prompt`; correct P12's `:420` to `:422`; note in the line budget that `ledger.sh` (768) grows under the advisory.

## Round 3 — 2026-11-22 — REVISE_PLAN
decision: no
1. Make a ruling entry self-describing: stamp `{answer, question_path, question_sha256}` at `--rework-consumed`, or have `verify_ruling_block` emit `{row: .n, answer, asked}`. Update Sketch 6, the Data Model and P3's wording to match.
2. Settle the rework prompt in one place: a reader in `session-launch-rework.sh` that pairs each unconsumed answer with its dispute question from `asked[]`/`answers_before`, shared with `--rework-consumed`; use it in `rework_prompt` instead of plain `person_text_as_data answers`; align FR-008 and Sketch 5 with D7.
3. Close the unrecorded-block hole: on a rework run, record `--rework-asked other` for every block `ledger.sh answer` can clear (`human:plan-review` too), and/or require the answer's kind to be `human:clarify` in the ruling rule. FR-016: dispute, then a `human:plan-review` block — its answer is not a ruling.
4. `tests/smoke.sh` row: `im_vf` (`:6481`) also gives LT-4 a forge-shaped `.pr`/`.prs`, so the `:6484` block comes from the cap, not the fallback.
5. Specify `wt_on_branch_or_ask` so forward's text stays byte-identical (a format with a placeholder for the current branch, or a separate branch reader). Say the `--dry-run` skip covers the `--rework-asked other` record as well as the block.
6. Correct P8's "forward's own lines are not touched" to list what moves (`:370`, `:373`, `forward_wt_check`); put the two shared helpers in the forward file or give them neutral names; `rework_route` prints one stderr line when the summary file cannot be written.

## Round 4 — 2026-11-22 — REVISE_PLAN
decision: no
1. Add a test-file line budget: move the `rework` lane-guard cases, the `--check` ask-rule assertion and the `:166` mutation out of `tests/smoke-lifecycle.sh` (499) into the rework suite; split the rework suite into two files up front, each under 500 code lines, both run from `tests/smoke.sh` (e.g. `tests/smoke-rework.sh` move/cap/guards/classification, `tests/smoke-rework-ruling.sh` disputes/pairing/ruling block/P12); state the five `smoke-forward.sh` retargets are in place, one line each (498 today).
2. Specify `implement_block_question` in a sketch: `record --rework-asked dispute` only on a rework run with kind `human:clarify` and a question file; when the question file cannot be written the launcher exits non-zero naming the file (before the block, or block and exit non-zero) — a later answer is never paired with an earlier dispute; add the mutation to the test row.
3. Replace `hooks/rework-pairs.jq` + `jq -L` with the repo's pattern: the `def rework_pairs: …;` text in a shell variable in a small `hooks/rework-pairs.sh` sourced by `ledger-rework.sh` and `session-launch-rework.sh`, presence-checked as at `ledger.sh:110`; name every new sourced file in the `docs/hooks.md` row.

## Round 5 — 2026-11-22 — REVISE_PLAN
decision: no
1. Correct P14's harness claim and declare the edits in the `tests/smoke.sh` row: add `ledger-rework.sh` and `rework-pairs.sh` to the ledger lists at `:2783` and `:3321`; add `session-launch-rework.sh`, `rework-pairs.sh` and (where `ledger.sh` is linked) `ledger-rework.sh` to the chains at `:2064`, `:2286`, `:2530`, `:3773` — all in place. Also check the lists in `smoke-spec-roots.sh:443-450`, `smoke-run-survival.sh:410` and `smoke-forward-routing.sh:71,83`.
2. Cover the new presence checks: add `ledger-rework.sh` to the two `for` lists at `tests/smoke-lifecycle.sh:159` and `:164` (in place, stays at 499 code lines) and change that row from "not touched"; add to FR-016 a removal case for `session-launch-rework.sh` and `rework-pairs.sh` in one of the rework smoke files.
