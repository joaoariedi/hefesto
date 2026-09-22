---
model: opus
description: "Route a task by size and coupling — trivial fix, light spec path, or the full pipeline — then run it with planning and task tracking"
argument-hint: "development task description"
---

# Route, then run

The pipeline is not all-or-nothing, and every independent review of spec-driven tooling reached
the same finding: ceremony that does not scale to the task is the reason teams abandon it. This
command decides the path before any work starts.

Task: **$ARGUMENTS**

## Pre-Flight

> The commands in this section must be run with the Bash tool; they cannot be
> pre-executed in a `!` block. A `!` block is permission-checked before the
> CLAUDE_PLUGIN_ROOT variable is substituted, so it is rejected as "Contains
> expansion". Do not write that variable with a $ and braces here: it would be
> substituted into this note and the warning would read as nonsense.

Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh branch`
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh check-specify-dir`
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh detect-stack`

## 1. Size it

Invoke the `task-effort-estimation` skill in **Projected** mode for the task. Read back the
complexity score and — more important — the risk flags. The bimodal trap the skill exists to
catch is the one that matters here: a small diff that reaches across boundaries is the shape of
work a naive size estimate waves through.

## 2. Route

| Signal | Path |
|---|---|
| Passes `/speckit.fix`'s triviality gate (no logic/API/schema change, <5 files, no new files) **and** no risk flag | **Fix** → `/speckit.fix` |
| Single repo, low coupling, no API or schema change, roughly ≤5 files, no risk flag | **Light** → `/speckit.specify` → `/speckit.tasks` → `/speckit.implement` → `/speckit.verify` (plan, review, and checklist skipped — say so) |
| Anything else — **or any non-local-context / high-coupling / high-volatility flag, regardless of size** | **Full** → brainstorm → specify → clarify → plan → review → tasks → checklist → implement → verify |

If `.specify/` does not exist, the Light and Full paths begin with `/speckit.init`.

## 3. Say it, then do it

One paragraph: the path, the score, the flag that decided it. Then:

- **Fix**: run `/speckit.fix` with the task text.
- **Light / Full**: use EnterPlanMode with the chosen sequence as the plan, follow
  `.claude/rules/agent-workflow.md` for quality gates, and track progress with
  TaskCreate/TaskUpdate/TaskList. The human gates (`clarify`, `review`, `checklist`) stay human —
  stop at each and wait.

When in doubt between two paths, take the heavier one and note the doubt; the cost of a quick
spec is low, the cost of an unplanned change is not.
