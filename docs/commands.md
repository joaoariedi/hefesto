# Slash Commands

[← back to README](../README.md)

## 🛠️ Slash Commands

| Command | Args | Description |
|---------|------|-------------|
| `/hef.agent` | `<task>` | Route by size and coupling (fix / light spec path / full pipeline), then run with planning and task tracking |
| `/hef.mutate` | `[paths]` | Mutation-test the changed code; raise-only score ratchet; every survivor becomes a test |
| `/hef.release` | `<X.Y.Z> [date]` | Move every version declaration together and scaffold the CHANGELOG entry; never commits or tags |
| `/hef.context` | — | Analyze project tech stack, tools, and structure |
| `/hef.review` | `[focus]` | Two-stage review — spec compliance, then code quality (spawns code-reviewer) |
| `/hef.pr` | `[--summary-only] [--draft] [target]` | Open or update the PR via review-coordinator; never merges. `--summary-only` writes just the description (the former `/hef.pr-summary`) |
| `/hef.adr` | `<title> [--status …]` | Record a decision under `reports/` with MADR frontmatter |
| `/hef.quality` | — | Run comprehensive quality checks (spawns quality-guardian) |
| `/hef.security-scan` | — | Scan staged changes for secrets, SQLi, XSS |
| `/hef.doctor` | `[--eval]` | Framework self-check: the three copies in sync, hooks linted, manifest valid; `--eval` scores the plugin's own prompts (the former `/hef.sync`, plus the checks) |
| `/speckit.init` | — | Bootstrap `.specify/` directory in current project |
| `/speckit.constitution` | — | Create/update project governance principles |
| `/speckit.brainstorm` | `<idea>` | Socratic design exploration before specification |
| `/speckit.specify` | `<feature>` | Generate spec with scenarios, requirements, criteria |
| `/speckit.clarify` | — | Scan spec for ambiguities, ask targeted questions |
| `/speckit.plan` | — | Generate implementation plan from spec |
| `/speckit.review` | — | Read-only plan review gate (scope, architecture, tests) |
| `/speckit.tasks` | — | Generate phased task list from plan and spec |
| `/speckit.checklist` | — | Generate requirement quality checklists |
| `/speckit.analyze` | — | Read-only cross-artifact consistency analysis |
| `/speckit.implement` | — | Execute TDD implementation with quality gates (arms the test guard) |
| `/speckit.verify` | — | Post-implementation gate: mechanical FR → test matrix + spec-compliance review |
| `/speckit.baseline` | `<module>` | Reverse-engineer spec from existing code (brownfield) |
| `/speckit.fix` | `<description>` | Quick-fix bypass for trivial changes |

---

