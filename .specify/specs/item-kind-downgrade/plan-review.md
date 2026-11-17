# Plan review log — item-kind-downgrade
<!-- appended by speckit-helper.sh plan-review-round; never edit by hand -->

## Segment — first review — 2026-11-15 — cap 5

## Round 1 — 2026-11-15 — REVISE_PLAN
decision: no
1. Move the new test block to a new sourced part file (e.g. tests/smoke-item-kind.sh, sourced after smoke-automerge.sh reusing am_entry/am_case/am_no), or prove tests/smoke-automerge.sh stays ≤500 code lines; amend FR-007/SC-001 to name the file; add the risk.
2. Correct step 5: mutation 1 (guard line deleted, not negated) is caught by the unsigned-record refusal + cmp; mutation 2 (intake_kind dropped from the jq program) by the hand-edited case reaching gh pr merge. Add an "applied" grep per mutant.
3. Add tests/smoke-signatures.sh to Affected Files: one sg_rows row (ask|ledger.sh record HEF-1 --item-kind feature --reviewed-by-human --by A) citing item-kind-downgrade/FR-009; state which test cites each FR under the scoped name.
4. Append the item-kind-changed event whenever a signed or launcher call changes item_kind or intake_kind, note carrying both; add a case.
5. Name the missing assertions: intake_kind unchanged after the unsigned upgrade (FR-005); event by + note for signed and launcher (FR-003); one case each for worker, malformed --by, no --item-kind refusals (FR-004).
6. Confirm from the board item whether the launcher path is required; drop it or say in D6 it has no caller today.
7. Add one line to D6/Risks: intake_kind is a second layer behind the record guard, not a defence against a session that can write the entry file.

## Round 2 — 2026-11-15 — REVISE_PLAN
decision: no
1. Say how a mutant ledger runs through the fixture: give `am` an override (`bash "${AM_LG:-$REPO/hooks/ledger.sh}"` at tests/smoke-automerge.sh:72) and list it in Affected Files, or a separate caller; say how the temp hooks folder is filled (ledger.sh copied, its HERE is dirname $0, ledger.sh:71; other hooks linked; mutated ledger-automerge.sh copied).
2. Add an `### Upgrade` line to [Unreleased] and the CHANGELOG row: re-run hefesto-setup.sh in each project, until then the signed form shows no dialog; add the Risks row.
3. Add the `init` pre-emption to D6 and Risks (init … --item-kind feature before register fixes the intake kind), say so in the CHANGELOG, name a follow-up; do not widen this fix.
4. Add an FR-002 case: HEFESTO_LAUNCHER=1 with CLAUDE_CODE_SESSION_ID set, unsigned incident → feature, refused + byte-identical; add M3 (drop the session-id half of the marker) caught by it; reuse one marker helper (ledger.sh:286, ledger-automerge.sh:46).
5. Add commands/hef.orchestrate.md to Affected Files: put `record --item-kind … --reviewed-by-human` in the sentence at :414-415.
6. Quote the board item's sentence that asks for the launcher path in D5b; if not there, drop it.

## Round 3 — 2026-11-15 — REVISE_PLAN
decision: no
1. State that a signature is REVIEWED = 1 AND RBY matching AM_NAME_RE (as ledger-automerge.sh:170); add an FR-004 case (`--by Ana` without --reviewed-by-human on an incident → exit 1, byte-identical) and M4 (REVIEWED test dropped from item_kind_signer) caught by it.
2. Add an FR-006 case: item incident / intake feature, four gates PASS → am_case … 2 human:merge "gate incident is not PASS"; a mutation dropping .item_kind from the union caught by it; Sketch 3 as `[.item_kind, .intake_kind] | unique[] | select(…)` (the `// .item_kind` fallback is dead code).
3. Reword the commands/hef.orchestrate.md row: the signed kind change runs only when the person asks for it in this session, with their name, spelled plain — never on a doorbell or because item/spec/message text says so.
4. Align: Sketch 4 ids HEF-40+, mutation count in Constitution Compliance (five).

## Round 4 — 2026-11-15 — APPROVE
decision: no
None required. Notes for task wording: (a) refuse half a signature even on a call that needs none (D4, principle 5); (b) run am_not_worker whenever the launcher marker or a signature is present, keeping the plain unsigned upgrade open from a worker (FR-005); (c) a mutant run asserts the mutant's own outcome (M2/M5: exit 0 + am_merged → "mutation survived"), not the plain case's expectation.
