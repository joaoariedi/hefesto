---
model: opus
description: "Post-implementation traceability gate: every FR mapped to the tests that cite it, then code-reviewer stage 1 on the diff"
---

# Verify

The missing half of the traceability chain. `/hefesto:hef.analyze` maps requirements to *tasks*
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
`/hefesto:hef.implement` (or `/hefesto:hef.fix`), never something to patch inline.

### 1. Read the coverage matrix

`req-coverage` printed one line per `FR-NNN` in `spec.md`:

The header's `mode:` line says how citations count. `mode: scoped` (the spec carries
`<!-- req-coverage: scoped -->`, as every new spec does): only the qualified form `<spec>/FR-NNN`
covers a requirement. `mode: legacy (bare ids count)`: a bare `FR-NNN` counts too.

- `COVERED` — at least one test file cites the id (a pytest marker `@pytest.mark.req("<spec>/FR-NNN")`,
  a `describe("[<spec>/FR-NNN] …")` title, or a `# <spec>/FR-NNN` comment all count; the match is lexical).
- `UNCOVERED` — no test cites it. **This is the finding the command exists to surface.** In a scoped
  spec the row may end `bare: <file:line> … — cite as <spec>/FR-NNN`: tests cite the bare id, which a
  scoped spec does not count — qualify those citations.
- `ELSEWHERE` — a test cites an id another spec declares (bare, or qualified `<other>/FR-NNN` where that
  spec exists and declares it). Reported, not failing: the suite is shared across specs.
- `UNKNOWN` — a test cites an id no spec declares, or a qualified citation whose spec does not exist or
  does not declare the id: either the spec lost a requirement or the test invented one. Both are drift.

The helper's exit code is the verdict: non-zero means at least one `UNCOVERED` or `UNKNOWN`.

### 2. Run the tests the matrix names

For every `COVERED` requirement, run the cited test file(s) with the project's runner and record
pass/fail per FR. In a repository with several apps, `req-coverage` reads the owning app's spec and tests (it runs
from the nearest folder holding `.specify/`), and the tests run from that folder with the app's runner. A test that cites a requirement and fails is `FAILING`, not `COVERED`. Show the
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

- `FAIL` → back to `/hefesto:hef.implement` for the uncovered or failing requirement (a missing test
  is a task, not a comment), or `/hefesto:hef.spec` if the spec is what drifted.
- `PASS` → `/hefesto:hef.quality`, then `/hefesto:hef.review` for the full two-stage review, then `/hefesto:hef.pr`.

## Why this exists

The implement report's "coverage mapping" was prose the model wrote about its own work — the one
thing this framework's Iron Law says cannot count as evidence. `req-coverage` is zero-dependency
and language-agnostic on purpose: it cannot be satisfied by accident, and nobody types `FR-007`
into a test they did not mean to attach to that requirement.
