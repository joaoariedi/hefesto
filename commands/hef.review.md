---
model: fable
description: "Review — the plan before tasks exist (read-only gate), or the code before the PR (two stages, via code-reviewer)"
argument-hint: "[plan | code] [focus: file, module, or FR id]"
---

# Review

One command, two moments. Before tasks exist it reviews the **plan** — a read-only gate between
`/hef.plan` and `/hef.tasks`. Once code exists it reviews the **code** — spec compliance, then
quality — through the `code-reviewer` agent.

## Pre-Flight

> The commands in this section must be run with the Bash tool; they cannot be
> pre-executed in a `!` block. A `!` block is permission-checked before the
> CLAUDE_PLUGIN_ROOT variable is substituted, so it is rejected as "Contains
> expansion". Do not write that variable with a $ and braces here: it would be
> substituted into this note and the warning would read as nonsense.

Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh branch`
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh check-plan-review`
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh check-artifacts`
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh pr-files`

## Mode

- `plan` or `code` in **$ARGUMENTS** forces the mode.
- Otherwise: `plan.md` exists, is **not** marked `## Reviewed`, and `tasks.md` is missing → **plan
  mode**. Anything else → **code mode**. State the mode and the reason in one line before starting.

## Plan mode — read-only

Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh spec`
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh plan`
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh constitution`

Both `spec.md` and `plan.md` must exist; if either is missing, name the command to run first
(`/hef.spec` or `/hef.plan`). Challenge the plan on six dimensions, with specific references:

1. **Scope** — too much? deferrable requirements? does every planned change map to an FR?
2. **Architecture** — aligned with existing patterns? a simpler approach? does the file list fit?
3. **Design** — data model fit, contract consistency, edge cases addressed?
4. **Tests** — every level accounted for? untestable areas needing a design change? security paths
   planned for dedicated tests?
5. **Performance** — scale for expected load? N+1, missing indexes, blocking I/O, caching?
6. **Constitution** — every principle addressed, no hand-waved justification, no conflict?

```
PLAN REVIEW — <branch>
======================
## Scope · ## Architecture · ## Design · ## Tests · ## Performance · ## Constitution
- [OK/CONCERN] <assessment with specific references>

## Verdict: APPROVE / REVISE_PLAN / NEEDS_DISCUSSION
## Suggested Changes (if REVISE_PLAN)
```

- `APPROVE` → append `## Reviewed <YYYY-MM-DD>` to `plan.md` (the one write this mode makes — it is
  how `/hef.tasks` and the next `/hef.review` know the gate passed), then `/hef.tasks`.
- `REVISE_PLAN` → the numbered changes are the next edit to `plan.md`; re-run `/hef.review plan`.
- `NEEDS_DISCUSSION` → stop and surface the question to the user.

## Code mode — via `code-reviewer`

Use the Task tool to spawn the `code-reviewer` agent with this brief, verbatim plus the pre-flight
output:

> Review the current branch against its base. Complete **both stages** (spec compliance, then code
> quality) and produce the CODE REVIEW REPORT in your documented format with a verdict.
> Focus, if given: **$ARGUMENTS**.
>
> Scope discipline: flag only findings that affect correctness, security, or the stated
> requirements. Style belongs under Nitpicks and never changes the verdict. Every finding carries
> `file:line` and the evidence — a command you ran, a test you executed — not an assertion.
>
> Do not edit files. Do not fix anything. Report.

When the agent returns, relay the report unchanged. Then:

- `APPROVE` → `/hef.quality` if not yet run, then `/hef.pr`.
- `REQUEST_CHANGES` → the blocking list is the next task list; `/hef.implement` or `/hef.fix`.
- `NEEDS_DISCUSSION` → stop and surface the question to the user; do not guess.

If `/hef.verify` has not run on this branch and spec artifacts exist, say so — stage 1 is stronger
with the mechanical coverage matrix in hand.
