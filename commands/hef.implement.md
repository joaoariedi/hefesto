---
model: opus
description: "Execute TDD implementation from spec artifacts with quality gates"
---

# Implement

Execute the implementation plan using strict TDD cycles with quality gates.

## Pre-Flight

### Current branch
> The commands in this section must be run with the Bash tool; they cannot be
> pre-executed in a `!` block. A `!` block is permission-checked before the
> CLAUDE_PLUGIN_ROOT variable is substituted, so it is rejected as "Contains
> expansion". Do not write that variable with a $ and braces here: it would be
> substituted into this note and the warning would read as nonsense.

Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh branch`

### Load artifacts
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh check-artifacts`

### Constitution
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh constitution`

### Checklists
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh checklists`

### Test framework detection
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh detect-test-framework`

### Arm the test guard
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh implement-phase-start`

> While the marker is set, `implement-phase-test-guard.sh` blocks any edit that leaves a test file
> with fewer assertions, any whole-file overwrite of an existing test, any `rm` of a test file, and
> (always) any snapshot-update flag. Tests may grow during this phase; they may not shrink. If a
> test is genuinely wrong, say so to the user instead of weakening it.

## Instructions

**Required inputs**: `tasks.md`, `plan.md`, and `spec.md` must all exist. If any are missing, tell the user which command to run first.

### Pre-Implementation Gate

1. **Checklist validation**: if checklists exist in `.specify/specs/<branch>/checklists/`, scan for unchecked items:
   - If CRITICAL unchecked items exist → **pause and ask user** whether to proceed or resolve first
   - If only MEDIUM/LOW unchecked items → warn but continue

2. **Load all artifacts**:
   - `tasks.md` — the task list to execute
   - `plan.md` — design decisions and affected files
   - `spec.md` — requirements and success criteria
   - `constitution.md` — governance principles
   - `data-model.md`, `contracts/` — if they exist

### Phase-by-Phase TDD Execution

3. **For each task in tasks.md** (in order, respecting phase boundaries):

   **a. Mark task in progress**
   - Update `tasks.md`: change `- [ ]` to `- [~]` for current task
   - Use TaskUpdate to set status `in_progress` in the Claude Code tracker

   **b. Write failing test** (Red phase)
   - Use `test-specialist` agent patterns to identify test location and conventions
   - Write a test that validates the task's acceptance criteria
   - **Cite the task's requirement id in the test** — `@pytest.mark.req("FR-003")`, a
     `describe("[FR-003] …")` title, or a `# FR-003` comment. `/hef.verify` maps requirements
     to tests by that token; an uncited test covers nothing as far as the spec is concerned
   - Test MUST fail at this point (implementation doesn't exist yet)
   - Run the test to confirm failure

   **c. Verify failure**
   - Execute the specific test
   - Confirm it fails for the expected reason (not a syntax error or import issue)
   - If it passes unexpectedly, the test isn't testing new behavior — revise it

   **d. Implement** (Green phase)
   - Write minimum code to make the failing test pass
   - Follow code quality limits from `.claude/rules/code-quality.md`:
     - Functions < 50 lines
     - Files < 500 lines
     - Cyclomatic complexity < 10
   - Follow patterns identified in `plan.md`

   **e. Verify pass**
   - Run the specific test — it must now pass
   - Run the full test suite — no regressions allowed
   - If any test fails, fix the implementation (never modify the test to make it pass)

   **f. Mark task complete**
   - Update `tasks.md`: change `- [~]` to `- [x]`
   - Use TaskUpdate to set status `completed` in the Claude Code tracker

4. **Between phases**: run quality checks using `quality-guardian` patterns:
   - Linting, type checking, formatting
   - Full test suite
   - Fix any issues before proceeding to the next phase

### Completion

5. **Final quality gate**:
   - Run all quality checks (lint, types, format, tests)
   - Verify all tasks in `tasks.md` are `[x]`
   - Verify all TaskUpdate entries are `completed`
   - Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh req-coverage` — the
     mechanical FR → test matrix. An `UNCOVERED` requirement here is an unfinished task, not a
     footnote; go back to step 3 for it
   - Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh implement-phase-end`
     (disarms the test guard; also run it if you abandon the phase early)

6. **Generate completion report** — the coverage mapping below is copied from `req-coverage`
   output, not written from memory:
   ```
   IMPLEMENTATION REPORT
   =====================
   Tasks completed: X/Y
   Tests written:   N
   Tests passing:   N/N
   Quality checks:  PASS/FAIL
   Files modified:  N
   Files created:   N

   Coverage mapping:
   FR-001 → T001, T002 → PASS
   FR-002 → T003       → PASS
   SC-001 → verified via T001

   Constitution compliance: ALL PRINCIPLES MET
   ```

7. **Suggest next steps**:
   - `/hef.verify` — requirement traceability plus spec-compliance review of the diff
   - `/hef.quality` → `/hef.review` → `/hef.pr`
