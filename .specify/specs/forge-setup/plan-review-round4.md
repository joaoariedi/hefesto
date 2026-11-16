# Plan review — round 4 (2026-11-09)
<!-- Fresh-context code-reviewer, /hefesto:hef.review plan mode. Verdict: REVISE_PLAN (text only). -->

Round-3 items #1–#4 verified applied against the cited code.

## Verdict: REVISE_PLAN — text only, no design change

## Suggested Changes (all applied before round 5)
1. Quick Start 3 / P4 live check: probe through allowed tools (`gh pr view <n>`, `git ls-remote https://github.com/…`),
   not `curl` (not in the default implement list; denied by permission, not sandbox); outcome 2 only on a sandbox
   violation.
2. P4 (a) / Risks: `Bash(git *)` runs shell, so the allowlist fences tools, not code; lane-guard catches commands that
   name `gh`; the ledger fences its record; branch protection is what ultimately stops a worker-driven merge — the
   docs say that.
3. Risks: drop "which no allowlist could before" — `docs/install.md:430-433` already asked for `api.github.com`; D9
   automates that step.
4. Tier-1 grep for `docs/install.md` targets new wording (the rewrite text already exists at `:432`); §8b rewritten.
5. (nit) spec Clarifications lane-guard citation → `:204-207`.
