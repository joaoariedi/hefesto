---
name: "Systematic Debugging"
description: |
  Use when investigating bugs, test failures, or unexpected behavior.
  4-phase root cause investigation before attempting any fix.
  Enforces the Iron Law: no fixes without root-cause investigation first.
  Prevents shotgun debugging and cargo-cult fixes.
when_to_use: |
  "this test is failing", "why is this broken?", "debug this",
  "it worked before", "intermittent failure", "flaky test"
allowed-tools: Read, Grep, Glob, Bash
---

<!--
  Deliberately NOT `context: fork`. The other two skills fork because they produce a
  bounded report the main thread only needs the conclusion of. This one is different:
  it is a methodology the main agent must follow *through to the fix*, and the evidence
  it gathers in phases 1-3 is exactly what phase 4 edits against. Forking would discard
  that evidence at the moment it becomes useful.

  No `disallowed-tools` for the same reason — this skill ends in a fix, so it needs Edit.
  Its discipline is the Iron Law, not a tool restriction.
-->


# Systematic Debugging Skill

## Iron Law

**NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST.**

This rule is non-negotiable. Do not touch production code until you understand WHY the bug exists.

## Phase 1: Read Errors (Observe — Do Not Act)

- Read the FULL error message, stack trace, and log output
- Identify the exact file, line, and function where the error originates
- Note the error type: compilation, runtime, assertion, timeout, permission, network
- Check if the error message tells you exactly what went wrong (it usually does)
- **Do NOT touch any code yet**

## Phase 2: Reproduce (Confirm the Problem)

- Run the exact command that produces the error
- Confirm you see the SAME error output (not a different one)
- If the error is intermittent, identify the triggering conditions:
  - Specific input data? Race condition? Timing? Environment?
- Document the reproduction steps:
  ```
  1. Run: <exact command>
  2. Expected: <what should happen>
  3. Actual: <what happens instead>
  4. Error: <exact error message>
  ```
- If you cannot reproduce, gather more context before proceeding

## Phase 3: Gather Evidence (Understand Why)

- Read the code at the error location — understand the logic, not just the syntax
- Trace the data flow: what input reaches this point? What state exists?
- Check recent changes: `git log --oneline -10`, `git diff HEAD~3`
- Determine if the error is in YOUR code or a dependency
- Form a hypothesis about the root cause — write it down before acting
- Cross-reference: does this error pattern exist elsewhere in the codebase?

## Phase 4: Fix (Targeted Repair)

- Fix the ROOT CAUSE, not the symptom
- Write a test that reproduces the bug BEFORE fixing it (red → green)
- Apply the fix — change as little as possible
- Verify per the Verification Iron Law in `rules/code-quality.md` — run `/verify` to drive the real app, not just the test suite
- Confirm no regressions in the full test suite
- Apply defense-in-depth: add guards at each layer, not just the source

### Defense-in-Depth Pattern

When fixing a bug, add protection at multiple layers:
1. **Fix at source** — correct the root cause
2. **Add validation** — validate inputs at the boundary where bad data enters
3. **Add logging** — log at entry points so future issues are visible
4. Result: the bug can't recur AND won't fail silently if a similar issue arises

## Rationalization Prevention

| Thought | Why It Fails | Correct Action |
|---------|-------------|----------------|
| "I think I know what's wrong" | Assumptions cause wrong fixes and wasted time | Read the error first — Phase 1 |
| "Let me just try this quick fix" | Shotgun debugging creates new bugs | Reproduce first — Phase 2 |
| "The error message is misleading" | Error messages are usually accurate and literal | Read it literally — Phase 1 |
| "I'll fix it and see if that helps" | May mask the real issue or create a new one | Understand root cause — Phase 3 |
| "This worked in a similar case" | Different context means different root cause | Investigate THIS specific case — Phase 3 |

## Anti-Patterns to Avoid

- **Changing multiple things at once** — makes it impossible to know what fixed it
- **Modifying tests to make them pass** — the test is correct; fix the code
- **Adding try/catch to silence errors** — hides the problem instead of fixing it
- **Reverting to "known good" without understanding** — the bug will return
- **Blaming the framework or library first** — check your code before suspecting dependencies
- **Fixing the same symptom in multiple places** — find the single root cause

## Integration

- **quality-guardian**: Invokes this skill when debugging test failures during quality gates
- **code-reviewer**: References this skill when review reveals potential bugs
- **hef.implement**: Use this skill when TDD red phase reveals unexpected failures
- **Verification Iron Law** (`rules/code-quality.md`): always prove the fix with fresh evidence — `/verify` exercises the running app
