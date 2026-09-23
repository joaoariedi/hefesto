# Plan: harness-review-tiers

## Research Notes
- Source: `reports/14` (to be written from the 2026-09-22 review) — harness docs verified 2026-09-22
  (`code.claude.com/docs/en/{hooks,skills,sub-agents}.md`): `PreCompact`, `SessionStart`,
  `ConfigChange`, `SubagentStop` exist; `SessionStart` stdout is added to context; `PreToolUse` exit 2
  blocks; `when_to_use` is a supported skill field; `commands/` remains supported.
- Evidence behind each gate lives in the review; the constitution forbids aspirational rules, so each
  new hook header cites the study or incident that motivated it.
- Live probe 2026-09-22: `block-destructive-commands.sh` catches `git -C`, `-c`, quoted verbs, short
  flags; misses `sh -c` wrappers and absolute binaries by documented design → `/sandbox` is the
  boundary, documented, not a hook change.

## Data Model
- Phase markers: `.specify/.plan-in-progress` (existing), `.specify/.implement-in-progress` (new).
  Set/cleared by helper subcommands; the hooks only test for existence.
- Progress checkpoint: `${XDG_CACHE_HOME:-~/.cache}/hefesto/progress/<sha1(cwd)>.md` — outside the
  repo so a hook never dirties a working tree.
- Requirement ids: `FR-[0-9]+` tokens in `spec.md`; a test "cites" an FR when the token appears
  anywhere in a test file (marker, comment, or test name) — lexical on purpose: zero-dependency,
  language-agnostic, and impossible to satisfy by accident.

## API Contracts
- `speckit-helper.sh req-coverage` — PREDICATE: prints the matrix, exit 0 when every FR is covered and
  no unknown id is cited, exit 1 otherwise. Missing spec → fetcher failure (stderr, non-zero).
- `speckit-helper.sh implement-phase-{start,end,status}` — mirror the plan-phase trio.
- Hook exit codes: 2 blocks; 0 with stderr is advisory; `SessionStart` stdout is context.

## Implementation Approach
Tier 1 (6.1.0, additive): helper + hooks first (they are what the commands call), then the three
commands, then agent/skill/rule prose, then docs + version + smoke checks. Tier 2 (6.2.0): mutate,
linters-as-gates, router, parallel safety, release script, bats/eval. Tier 3 (7.0.0): renames and
invocability. Each tier is one commit; the smoke suite gates each.

Mutation discipline (constitution 3): every new smoke block is written, then the guard is broken on
purpose to see the block go red, then restored — recorded as a comment in the block.

## Constitution Compliance
- [x] 1: payload stays at the repo root; nothing new under `.claude/`
- [x] 2: new commands are `hef.*`
- [x] 3: every new guard gets a smoke block that is mutation-checked
- [x] 4: zero-install — bash + jq + git only; optional tools (jscpd, mutmut…) are recipes, detected, never required
- [x] 5: `req-coverage` fails loudly; no exit-0 sentinel

## Quick Start
1. `hooks/speckit-helper.sh implement-phase-start` is NOT used for this branch (the guard would block
   editing `tests/smoke.sh`, which is the point of the guard) — the framework edits its own tests here.
2. Work tier by tier per `tasks.md`; run `tests/smoke.sh` before each commit.

## Reviewed
2026-09-22 — self-review against the research; the human gate was the user's "implement all tiers".
