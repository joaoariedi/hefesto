# Plan review — round 2 (2026-11-09)
<!-- Fresh-context code-reviewer, /hefesto:hef.review plan mode. Verdict: REVISE_PLAN (second) → human plan review. -->

Round-1 follow-up: P3, P5, P6, P7 resolved; P4 partially (see 4).

## Verdict: REVISE_PLAN

## Suggested Changes
1. Sketch 4 / step 2: collect `forge_stale_lock` for **every** repo (FR-008 has no SSH condition); apply the FR-010 write pre-check only to repos whose rewrite value is absent, so a second run with a lingering lock does not die for nothing.
2. Step 2 / Data Model: `push_rewrites` must join the `HEFESTO_SETUP_EXTRA` object rebuilt at `hooks/hefesto-setup.sh:348`, be carried forward from `$PREV` (`:205`) when the value is already present, and be read from `$CUR` before the merge on `--remove` — otherwise `--remove` after a second run unsets nothing.
3. Research Notes: state the FR-007 deviation (`HEFESTO_SETUP_EXTRA`, not the spec's `HEFESTO_SETUP_SET`, a comma list of marker words) and why.
4. P4 / Quick Start 3 / Risks: the worker's cwd (`$TOP/.claude/worktrees/$ID`, `session-launch.sh:251`) has no `settings.local.json` (git-excluded), so the `api.github.com` deny likely does NOT reach the worker and the entry is live — a sandboxed worker's PR-merge call could reach the API (`hefesto-setup.sh:174-175`). Define both live-check outcomes and what docs/Risks say for each, or revisit D9 (owner decision).
5. Risks: add "a worker sets `infra_cause` on an injected item (INJECTION_RULE, `session-launch.sh:297`), turning the would-be `human:intake` into a stall showing a fix line instead of the item" with the accepted-because reasoning.
6. Step 6: mutant wiring as three routes — setup guards via `lc_smut`-style mutants inside the real hooks folder (setup skips temp-folder roots, `hefesto-setup.sh:40-43`); library guards by sourcing the mutated lib directly; ledger/launcher via temp copies (`ledger.sh:92-96`). Replace GNU-only `touch -d '2 minutes ago'` with `touch -t 202601010000` (macOS lane).
7. P1: correct line counts (`ledger.sh` 721 code lines; `session-launch.sh` 485, NOT over 500) and give the launcher a line budget (≈ +4 net) so the commit gate's hard block at 500 is not hit by surprise.
8. Affected Files: cite FR-015/US5 on the `session-start-context.sh` row (or flag a spec FR gap); `unique` the `allowed_domains` hosts for multi-repo boards.
