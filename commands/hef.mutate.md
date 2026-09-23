---
model: opus
description: "Mutation-test the changed code and enforce the raise-only mutation-score ratchet"
argument-hint: "[paths or modules — default: what changed vs the base branch]"
---

# Mutate

Coverage says a line ran. A mutation score says a test would have *noticed* if the line were
wrong. This command runs the project's mutation tool over the changed code, enforces a ratchet
that can only go up, and turns every surviving mutant into the test that should have killed it.

## Pre-Flight

### Branch and changed files
> The commands in this section must be run with the Bash tool; they cannot be
> pre-executed in a `!` block. A `!` block is permission-checked before the
> CLAUDE_PLUGIN_ROOT variable is substituted, so it is rejected as "Contains
> expansion". Do not write that variable with a $ and braces here: it would be
> substituted into this note and the warning would read as nonsense.

Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh branch`
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh pr-files`
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh mutation-score`

## Instructions

### 1. Pick the tool (never install one)

| Stack | Tool | Incremental invocation |
|---|---|---|
| Python / pytest | `mutmut` (3.x) | `mutmut run --paths-to-mutate <changed dirs>` then `mutmut results` |
| JS / TS (Jest, Vitest) | Stryker | `npx stryker run --incremental --mutate "<changed globs>"` |
| Go | `gremlins` or `go-mutesting` | `gremlins unleash <changed pkgs>` |
| Rust | `cargo-mutants` | `cargo mutants --in-diff <(git diff <base>)` |

If the tool is absent, print the install command for the user and **stop** — the framework is
zero-install and does not add tooling on its own. Scope: **$ARGUMENTS** if given, otherwise the
directories owning the files from `pr-files`. Never mutate the whole repository on a PR; the full
run belongs in a nightly job.

### 2. Score

Parse the tool's summary into `killed`, `survived`, `timeout`, `no-coverage`. The score is
`killed / (killed + survived)` as an integer percent (timeouts count as killed; no-coverage
mutants are reported separately — they are the untested code, and `diff-cover` is the cheaper
gate for that).

### 3. Ratchet

Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh mutation-ratchet <score>`

The stored high-water mark lives at `.specify/mutation-score`. The rule:
- On a PR / feature branch the score must be **≥ mark − 5** (exit 0) — a small dip for a large
  change is tolerated; a collapse is not. Exit 1 means the ratchet failed: stop and go to step 4.
- On the default branch, a score **above** the mark raises it:
  run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh mutation-raise <score>`.
  Feature branches never raise it — a PR-driven ratchet causes cascading failures across
  concurrent PRs.
- The mark is committed with the code. Lowering it by hand is the same act as lowering a
  coverage threshold: say why in the commit, or don't.

### 4. Triage survivors — each one is a missing assertion

For every surviving mutant, in order of the code's importance:
1. Read the mutation (`mutmut show <id>` / the Stryker report). Ask: *what observable behaviour
   changed, and which test should have failed?*
2. Write that assertion — cite the requirement id (`# FR-NNN`) so `/hef.verify` sees it.
   Prefer strengthening an existing test over adding a near-duplicate.
3. If the mutant is **equivalent** (the change is unobservable by design), mark it so in the
   tool, with one line of reasoning. Do not weaken the code to make a mutant killable.

Re-run the scoped mutation after the new tests, and re-run the ratchet.

### 5. Report

```
MUTATION REPORT — <branch>
==========================
scope:     <dirs / globs>
mutants:   N (killed K, survived S, timeout T, no-coverage C)
score:     P%   mark: M%   floor: M-5%   → PASS | FAIL
survivors triaged: S → tests added: A, equivalent: E, remaining: R
```

`/hef.quality` reports coverage; this reports whether the tests would notice. When the two
disagree, this one is right.
