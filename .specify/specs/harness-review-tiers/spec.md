# Spec: harness-review-tiers
<!-- Source: the 2026-09-22 harness review (research corpus + structural audit). Tier 1 = 6.1.0 (additive), Tier 2 = 6.2.0 (additive), Tier 3 = 7.0.0 (renames). -->

## Overview

Close the gaps the 2026-09 review found in the framework's own workflow: the spec→implementation
traceability chain ends in model-written prose, two of six agents are reachable by no command,
agents can weaken tests to go green, the quality gate targets the wrong defect profile for
AI-written code, and the harness itself is only structurally tested. Every change is a
**mechanism** (hook, helper, test) or the prose that explains one — never prose alone.

## User Scenarios

### US1: Requirement traceability after implementation [P1]
- **Given** a feature branch with `spec.md` declaring `FR-NNN` ids and a test suite
- **When** the developer runs `/hef.verify`
- **Then** every FR is mapped to the tests that cite it, an FR with no test or a test citing an unknown id fails the command mechanically, and `code-reviewer` stage 1 runs on the diff

### US2: Tests cannot shrink during implementation [P1]
- **Given** `/hef.implement` is active (phase marker set)
- **When** the agent edits a test file so that it has fewer assertions, overwrites a test file wholesale, or runs a test command with a snapshot-update flag
- **Then** the tool call is blocked with an explanation and a visible bypass

### US3: The review agents are one command away [P1]
- **Given** an implemented branch
- **When** the developer runs `/hef.review` or `/hef.pr`
- **Then** `code-reviewer` (two-stage) or `review-coordinator` (PR lifecycle, sequential merges, untrusted-text handling) is dispatched

### US4: Session continuity without manual ritual [P2]
- **Given** a long session that is about to compact, or a new session in a spec-driven repo
- **When** compaction fires / the session starts
- **Then** a progress checkpoint is written / the branch, spec status and open tasks are injected

### US5: The quality gate matches how AI code actually fails [P2]
- **Given** `quality-guardian` or `test-specialist` runs
- **When** the diff adds duplication, dead code, swallowed errors, or mock-only tests
- **Then** the agent reports it, with the recipes to check mechanically

### US6: Releases move as one [P2] (Tier 2)
- **Given** a release is cut
- **When** `/hef.release` runs
- **Then** every version declaration moves together, the commit message format is enforced, and the changelog is scaffolded from commits for a human to edit

### US7: The harness is tested behaviourally [P2] (Tier 2)
- **Given** a hook or prompt change
- **When** CI runs
- **Then** bats fixtures drive every hook, shellcheck lints them, and a plugin eval suite scores the prompts with/without the plugin

### US8: Lifecycle-shaped toolbox [P3] (Tier 3, 7.0)
- **Given** a user typing `/`
- **When** the command list appears
- **Then** knowledge skills are hidden, commands are named by lifecycle verb, and reports carry machine-readable decision status

## Functional Requirements

| ID | Requirement | Priority | Scenario |
|----|-------------|----------|----------|
| FR-001 | `speckit-helper.sh req-coverage` maps every `FR-NNN` in `spec.md` to test files citing it; exits non-zero on an uncovered FR or an unknown id; `/hef.verify` runs it plus `code-reviewer` stage 1 | P1 | US1 |
| FR-002 | `/hef.review` dispatches `code-reviewer`; `/hef.pr` dispatches `review-coordinator` with a sequential-merge rule | P1 | US3 |
| FR-003 | `implement-phase-test-guard.sh` blocks assertion-shrinking edits and wholesale overwrites of test files while `.specify/.implement-in-progress` exists, and blocks snapshot-update flags on test commands unconditionally (bypass visible) | P1 | US2 |
| FR-004 | `quality-guardian` and `quality-tooling` carry duplication-baseline, dead-code, error-swallowing and patch-coverage recipes | P2 | US5 |
| FR-005 | `test-specialist` carries a mock budget: named fakes at I/O boundaries only, mock-only assertions flagged | P2 | US5 |
| FR-006 | `precompact-progress.sh` writes a checkpoint on `PreCompact`; `session-start-context.sh` injects branch/spec/task state on `SessionStart` | P2 | US4 |
| FR-007 | Security refresh: `llm-security.md` covers OWASP LLM 2026 + Agentic Top 10; commands that read issue/PR/commit text treat it as delimited data; `mcp-security` gains a skill/plugin vetting checklist; `audit-config-change.sh` warns on mid-session settings changes; `/sandbox` is documented | P2 | US5 |
| FR-008 | 6.1.0 docs, version declarations, changelog, and smoke checks for every new hook, helper and command | P2 | US1 |
| FR-009 | `/hef.mutate` runs a mutation ratchet (Stryker incremental / mutmut) with a raise-only high-water mark | P2 | US7 |
| FR-010 | The aggregate complexity rules run as delta gates in `quality-before-commit.sh` when a tool is present; prose keeps only the rationale | P2 | US5 |
| FR-011 | `/hef.agent` routes by size: `task-effort-estimation` → `hef.fix` / specify-only / full pipeline | P2 | US8 |
| FR-012 | `[P]` tasks may declare `owns:` files; the workflow rejects overlapping owners; `merge-tree-probe.sh` warns on textual conflicts with the base branch after edits; `review-coordinator` merges sequentially | P2 | US6 |
| FR-013 | `/hef.release` bumps every version declaration via `hooks/release.sh`, enforces conventional commit messages in `quality-before-commit.sh`, and scaffolds the changelog entry | P2 | US6 |
| FR-014 | Hook fixtures (incl. the documented bypass forms) live in `tests/smoke.sh` — bats was rejected because it needs an install step (constitution 4); `shellcheck` runs in the smoke suite when present; `evals/` holds a `claude plugin eval` suite | P2 | US7 |
| FR-015 | 7.0: one namespace — every command is `hef.*` (`speckit.specify` → `hef.spec`, `speckit.review` merged into `hef.review` as plan mode, `hef.security-scan` → `hef.scan`, the workflow is `hefesto:workflow`); `hef.sync` → `hef.doctor` (sync + shellcheck + eval + skill-doctor); `hef.pr-summary` folds into `hef.pr` | P3 | US8 |
| FR-016 | 7.0: knowledge skills are `user-invocable: false`; action skills stay invocable | P3 | US8 |
| FR-017 | 7.0: `reports/` carry MADR `status`/`supersedes` frontmatter; `/hef.adr` creates one | P3 | US8 |
| FR-018 | 7.0: `AGENTS.md` shim at the repo root; doc-gardening routine documented | P3 | US8 |
| FR-019 | 7.0: `forensic-specialist` and `code-reviewer` declare `memory: project` | P3 | US8 |

## Success Criteria

| ID | Criterion | Validation Method |
|----|-----------|-------------------|
| SC-001 | `tests/smoke.sh` passes at every tier boundary | run it |
| SC-002 | `req-coverage` on this branch's own spec passes — the smoke checks cite the FR they cover | `hooks/speckit-helper.sh req-coverage` |
| SC-003 | Every new guard is mutation-tested: reintroduce the bug, suite goes red | documented in each smoke block |
| SC-004 | No command is renamed before 7.0; 6.1 and 6.2 install over 6.0 without settings edits | CHANGELOG entries state it |

## Clarifications
- Spec location for the framework itself is in-repo (constitution: spec dir == branch name).
- One feature branch, one commit per tier; no push or PR until asked (user constraint).
- `commands/` stays: it is supported and the smoke suite's namespacing guard targets it; new entries there, not `skills/`, until 7.0 decides otherwise.
