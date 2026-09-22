---
model: sonnet
description: "Two-stage code review of the current branch — spec compliance, then code quality — via the code-reviewer agent"
argument-hint: "[focus: file, module, or FR id — optional]"
---

# Review

Dispatch the `code-reviewer` agent on the current branch. Until now this agent could only be
reached by asking for it by name; the documented chain
`speckit.implement → code-reviewer → quality-guardian → review-coordinator` had no command for its
first link.

## Pre-Flight

### Branch and diff
> The commands in this section must be run with the Bash tool; they cannot be
> pre-executed in a `!` block. A `!` block is permission-checked before the
> CLAUDE_PLUGIN_ROOT variable is substituted, so it is rejected as "Contains
> expansion". Do not write that variable with a $ and braces here: it would be
> substituted into this note and the warning would read as nonsense.

Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh branch`
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh pr-files`
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh check-artifacts`

## Instructions

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
- `REQUEST_CHANGES` → the blocking list is the next task list; `/speckit.implement` or
  `/speckit.fix` depending on size.
- `NEEDS_DISCUSSION` → stop and surface the question to the user; do not guess.

If `/speckit.verify` has not run on this branch and spec artifacts exist, say so — stage 1 is
stronger with the mechanical coverage matrix in hand.
