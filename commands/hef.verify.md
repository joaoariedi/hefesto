---
model: opus
description: "Post-implementation traceability gate: every FR mapped to the tests that cite it, then code-reviewer stage 1 on the diff"
---

# Verify

The missing half of the traceability chain. `/hef.analyze` maps requirements to *tasks*
before code exists; this command maps requirements to *tests* after it does — mechanically — and
then has `code-reviewer` check that the code behind those tests is the code the spec asked for.

## Pre-Flight

### Current branch
> The commands in this section must be run with the Bash tool; they cannot be
> pre-executed in a `!` block. A `!` block is permission-checked before the
> CLAUDE_PLUGIN_ROOT variable is substituted, so it is rejected as "Contains
> expansion". Do not write that variable with a $ and braces here: it would be
> substituted into this note and the warning would read as nonsense.

Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh branch`

### Artifacts
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh check-artifacts`

### Requirement coverage (mechanical)
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh req-coverage`

### Test framework
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh detect-test-framework`

## Instructions

**This command is read-only.** It reports; it does not fix. A finding here is input to
`/hef.implement` (or `/hef.fix`), never something to patch inline.

### 1. Read the coverage matrix

`req-coverage` printed one line per `FR-NNN` in `spec.md`:

- `COVERED` — at least one test file cites the id (a pytest marker `@pytest.mark.req("FR-003")`,
  a `describe("[FR-003] …")` title, or a `# FR-003` comment all count; the match is lexical).
- `UNCOVERED` — no test cites it. **This is the finding the command exists to surface.**
- `UNKNOWN` — a test cites an id the spec does not declare: either the spec lost a requirement or
  the test invented one. Both are drift.

The helper's exit code is the verdict: non-zero means at least one `UNCOVERED` or `UNKNOWN`.

### 2. Run the tests the matrix names

For every `COVERED` requirement, run the cited test file(s) with the project's runner and record
pass/fail per FR. A test that cites a requirement and fails is `FAILING`, not `COVERED`. Show the
runner's real output — the Verification Iron Law (`rules/code-quality.md`) applies here more than
anywhere: this report is the evidence the PR will carry.

### 3. Spec-compliance review

Use the Task tool to spawn the `code-reviewer` agent and ask for **Stage 1 only** (spec
compliance) against the branch diff: for each FR, the `file:line` that implements it, plus scope
creep (changes tracked by no requirement) and phantom completions (tasks ticked, code absent).
Pass it the coverage matrix so it does not repeat the mechanical part. Tell it to flag only gaps
that affect correctness or the stated requirements — a reviewer prompted to find gaps will report
some even when the work is sound.

### 4. Report

```
VERIFICATION REPORT — <branch>
==============================
| FR     | Tests (file:line)          | Result   | Implementation (file:line) |
|--------|----------------------------|----------|----------------------------|
| FR-001 | tests/test_auth.py:12      | PASS     | auth/service.py:40         |
| FR-002 | —                          | UNCOVERED| auth/service.py:88         |
| FR-003 | tests/test_auth.py:55      | FAILING  | —                          |

Unknown ids cited by tests: FR-009 (tests/test_auth.py:70)
Scope creep: <none / list>
Phantom completions: <none / list>

Verdict: PASS | FAIL — <n> uncovered, <n> failing, <n> unknown
```

`PASS` requires: zero `UNCOVERED`, zero `FAILING`, zero `UNKNOWN`, no phantom completions.
Scope creep is reported, not blocking — it is the reviewer's call, and the PR description's job.

### 5. Next step

- `FAIL` → back to `/hef.implement` for the uncovered or failing requirement (a missing test
  is a task, not a comment), or `/hef.spec` if the spec is what drifted.
- `PASS` → `/hef.quality`, then `/hef.review` for the full two-stage review, then `/hef.pr`.

## Why this exists

The implement report's "coverage mapping" was prose the model wrote about its own work — the one
thing this framework's Iron Law says cannot count as evidence. `req-coverage` is zero-dependency
and language-agnostic on purpose: it cannot be satisfied by accident, and nobody types `FR-007`
into a test they did not mean to attach to that requirement.
