# Requirements Checklist: monorepo-spec-roots
<!-- Auto-generated from spec.md by /hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 | FR-001: A new library, `hooks/spec-root-lib.sh`, gives `spec_root_find <path>`… | [completeness] | [ ] |
| CHK002 | FR-001: A new library, `hooks/spec-root-lib.sh`, gives `spec_root_find <path>`… | [testability] | [ ] |
| CHK003 | FR-002: `speckit-helper.sh` resolves the spec root once, from its cwd, and run… | [completeness] | [ ] |
| CHK004 | FR-002: `speckit-helper.sh` resolves the spec root once, from its cwd, and run… | [testability] | [ ] |
| CHK005 | FR-003: When an artifact is missing, the helper's message names every spec roo… | [completeness] | [ ] |
| CHK006 | FR-003: When an artifact is missing, the helper's message names every spec roo… | [testability] | [ ] |
| CHK007 | FR-004: `constitution` prints the top constitution, marked inherited, before t… | [completeness] | [ ] |
| CHK008 | FR-004: `constitution` prints the top constitution, marked inherited, before t… | [testability] | [ ] |
| CHK009 | FR-005: `implement-phase-test-guard.sh`, `plan-phase-write-block.sh`, `spec-ci… | [completeness] | [ ] |
| CHK010 | FR-005: `implement-phase-test-guard.sh`, `plan-phase-write-block.sh`, `spec-ci… | [testability] | [ ] |
| CHK011 | FR-006: `spec_roots` in `project-status.json` is validated wherever it is read… | [completeness] | [ ] |
| CHK012 | FR-006: `spec_roots` in `project-status.json` is validated wherever it is read… | [testability] | [ ] |
| CHK013 | FR-007: The ledger entry gains `spec_root` (a declared name, or null for the t… | [completeness] | [ ] |
| CHK014 | FR-007: The ledger entry gains `spec_root` (a declared name, or null for the t… | [testability] | [ ] |
| CHK015 | FR-008: An item's body may carry an `app: <name>` line, parsed like the `rfc:`… | [completeness] | [ ] |
| CHK016 | FR-008: An item's body may carry an `app: <name>` line, parsed like the `rfc:`… | [testability] | [ ] |
| CHK017 | FR-009: `session-launch.sh` (headless) starts plan, implement and verify sessi… | [completeness] | [ ] |
| CHK018 | FR-009: `session-launch.sh` (headless) starts plan, implement and verify sessi… | [testability] | [ ] |
| CHK019 | FR-010: The recorded `spec_dir` is relative to the worktree (`backend/.specify… | [completeness] | [ ] |
| CHK020 | FR-010: The recorded `spec_dir` is relative to the worktree (`backend/.specify… | [testability] | [ ] |
| CHK021 | FR-011: With no `spec_roots` key, the launcher's cwd, allowlist and prompt tex… | [completeness] | [ ] |
| CHK022 | FR-011: With no `spec_roots` key, the launcher's cwd, allowlist and prompt tex… | [testability] | [ ] |
| CHK023 | FR-012: `status-board.sh` epics walk the top spec root and every declared app,… | [completeness] | [ ] |
| CHK024 | FR-012: `status-board.sh` epics walk the top spec root and every declared app,… | [testability] | [ ] |
| CHK025 | FR-013: `/hef.quality` and `/hef.verify` text: app checks from the owning app … | [completeness] | [ ] |
| CHK026 | FR-013: `/hef.quality` and `/hef.verify` text: app checks from the owning app … | [testability] | [ ] |
| CHK027 | FR-014: `session-launch.sh --prepare` prints `app: <absolute folder>` when the… | [completeness] | [ ] |
| CHK028 | FR-014: `session-launch.sh --prepare` prints `app: <absolute folder>` when the… | [testability] | [ ] |
| CHK029 | FR-015: A cross-app path is allowed for the owning item and named in its `task… | [completeness] | [ ] |
| CHK030 | FR-015: A cross-app path is allowed for the owning item and named in its `task… | [testability] | [ ] |
| CHK031 | FR-016: `docs/` describe `spec_roots`, the `app:` line, discovery and constitu… | [completeness] | [ ] |
| CHK032 | FR-016: `docs/` describe `spec_roots`, the `app:` line, discovery and constitu… | [testability] | [ ] |
| CHK033 | FR-017: Discovery never returns a folder above the git top, even when an ances… | [completeness] | [ ] |
| CHK034 | FR-017: Discovery never returns a folder above the git top, even when an ances… | [testability] | [ ] |
| CHK035 | FR-018: A nested spec root wins over its parent (`backend/api/.specify/` beats… | [completeness] | [ ] |
| CHK036 | FR-018: A nested spec root wins over its parent (`backend/api/.specify/` beats… | [testability] | [ ] |
| CHK037 | FR-019: A symlinked `.specify` is not followed to another repository: a `.spec… | [completeness] | [ ] |
| CHK038 | FR-019: A symlinked `.specify` is not followed to another repository: a `.spec… | [testability] | [ ] |
