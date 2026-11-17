# Plan review — round 3 (2026-11-09)
<!-- Fresh-context code-reviewer, /hefesto:hef.review plan mode, after the owner's D9 answer. Verdict: REVISE_PLAN (text only). -->

Round-2 items #1–#8 verified resolved against the cited code.

## Verdict: REVISE_PLAN — no design change

## Suggested Changes (all applied before round 4)
1. P4 / Risks / spec D9: state the worker fence as the code has it (default `allowed_tools.implement` incl. `Bash(git *)`,
   `Bash($HERE/*)`, `--permission-prompts none`, lane-guard via the main checkout's settings, the ledger); add a Risks
   row for a project that widens `allowed_tools.implement`; note a sandboxed `gh pr create` needs `api.github.com`.
2. P4 (c) / step 4 / Risks: cite `ledger.sh:590` (stall), `:614` (`human:intake` only), `:602` (merge evidence),
   `:562,570`; the guard against an infra stall over `human:clarify` is no launch/`--prepare` over a human gate
   (`ledger.sh:649-650`, `session-launch.sh:489`). Fix the `lane-guard.sh:72-73` comment (lanes only).
3. Step 6 / SC-001: an external-board fixture (two repos on github.com: `unique` hosts, per-repo lock scope).
4. spec FR-007 → `env.HEFESTO_SETUP_EXTRA.push_rewrites`; Sketch 5 `board_config_path` → `project_config`.
