# Tasks: harness-review-tiers

## Phase 1: Tier 1 — 6.1.0 (additive)
- [x] T001 [FR-001] helper `req-coverage` + `implement-phase-{start,end,status}` `hooks/speckit-helper.sh`
- [x] T002 [FR-003] `hooks/implement-phase-test-guard.sh` + registration `hooks/hooks.json`
- [x] T003 [FR-006] `hooks/precompact-progress.sh`, `hooks/session-start-context.sh` + registration
- [x] T004 [FR-007] `hooks/audit-config-change.sh` + registration
- [x] T005 [FR-001] `commands/speckit.verify.md`; implement/tasks/test-specialist tell tests to cite FR ids
- [x] T006 [FR-002] `commands/hef.review.md`, `commands/hef.pr.md`; review-coordinator sequential merge + untrusted text
- [x] T007 [FR-004] quality-guardian + quality-tooling AI-defect recipes
- [x] T008 [FR-005] test-specialist mock budget
- [x] T009 [FR-007] llm-security.md refresh; untrusted-input blocks in hef.pr-summary/speckit.fix; mcp-security vetting; install.md sandbox
- [x] T010 [FR-008] docs/commands.md, docs/hooks.md, README, CLAUDE.md tier table, CHANGELOG 6.1.0, versions, smoke checks

## Phase 2: Tier 2 — 6.2.0 (additive)
- [ ] T011 [FR-009] `commands/hef.mutate.md` + quality-tooling ratchet recipe
- [ ] T012 [FR-010] complexity delta gates in `hooks/quality-before-commit.sh`; code-quality.md points at the gate
- [ ] T013 [FR-011] `commands/hef.agent.md` router
- [ ] T014 [FR-012] `owns:` in tasks template + workflow overlap check; `hooks/merge-tree-probe.sh`; review-coordinator sequential merges
- [ ] T015 [FR-013] `hooks/release.sh`, `commands/hef.release.md`, conventional-commit check in pre-commit
- [ ] T016 [FR-014] `tests/hooks.bats`, shellcheck in smoke, `evals/` suite
- [ ] T017 [FR-008] docs + CHANGELOG 6.2.0 + versions

## Phase 3: Tier 3 — 7.0.0 (breaking)
- [ ] T018 [FR-015] `hef.sync` → `hef.doctor`; `hef.pr-summary` → `hef.pr`
- [ ] T019 [FR-016] knowledge skills `user-invocable: false`
- [ ] T020 [FR-017] `reports/` MADR frontmatter + `commands/hef.adr.md`
- [ ] T021 [FR-018] `AGENTS.md` shim; doc-gardening routine in docs
- [ ] T022 [FR-019] `memory: project` on forensic-specialist and code-reviewer
- [ ] T023 [FR-008] docs + CHANGELOG 7.0.0 + versions + migration note

---
Legend: `[FR-NNN]` = functional requirement ref
