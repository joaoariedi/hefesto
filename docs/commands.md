# Slash Commands

[← back to README](../README.md)

## 🛠️ Slash Commands

| Command | Args | Description |
|---------|------|-------------|
| `/hef.agent` | `<task>` | Route by size and coupling (fix / light spec path / full pipeline), then run with planning and task tracking |
| `/hef.mutate` | `[paths]` | Mutation-test the changed code; raise-only score ratchet; every survivor becomes a test |
| `/hef.release` | `<X.Y.Z> [date]` | Move every version declaration together and scaffold the CHANGELOG entry; never commits or tags |
| `/hef.context` | — | Analyze project tech stack, tools, and structure |
| `/hef.review` | `[plan \| code] [--inline] [--second-opinion <provider>] [focus]` | Plan mode before tasks exist, code mode after — both through `code-reviewer` in a fresh context, because the session that wrote the plan never grades it (self-review measured +0 pp). On `APPROVE` in plan mode the command appends `## Reviewed`; `--inline` is a self-review second opinion that never passes the gate. `--second-opinion <provider>` also sends the same brief (plan: spec + plan + constitution; code: the spec + the diff capped at 2,000 lines / 96 KiB) to a declared provider through `hooks/arena-run.sh` and relays it as untrusted data under "Second opinion (<provider>) — not the gate" — never `## Reviewed` |
| `/hef.pr` | `[--summary-only] [--draft] [target]` | Open or update the PR via review-coordinator; never merges. `--summary-only` writes just the description (the former `/hef.pr-summary`) |
| `/hef.adr` | `<title> [--status …]` | Record a decision under `reports/` with MADR frontmatter |
| `/hef.quality` | — | Run comprehensive quality checks (spawns quality-guardian) |
| `/hef.scan` | `[--deps]` | Scan staged and unstaged changes for secrets, SQLi, XSS. `--deps` adds a `## Dependencies` section: every direct dependency the branch adds, re-versions or removes (`speckit-helper.sh deps-diff` — each new one a review item: does it exist, is it the package you meant) and the findings of whichever auditors are installed (`deps-audit`: npm audit, pip-audit, cargo-audit, govulncheck, osv-scanner; a count it cannot read is `unknown`, never clean) |
| `/hef.doctor` | `[--eval]` | Framework self-check: the running copy (per-profile cache) against the clone and upstream, rules against upstream, hooks linted, manifest valid; `--eval` scores the plugin's own prompts (the former `/hef.sync`, plus the checks) |
| `/hef.status` | `[--detailed] [--check]` | Management status brief — where we are, epic completion bars, at risk, bottom line — from the source `.claude/project-status.json` declares: a GitHub Project (`owner`, `project`, `roadmap`, `epic_prefix`) or a tasks repository (kanban files `TODO/DOING/DONE/BACKLOG`, `item_heading`, `id_pattern`, `done_section`, `epics.initiatives`, `epics.specs` opt-in, `states` map, quarter override). `--check` diagnoses prerequisites; `--detailed` unfolds items or sub-issues. Numbers come from `hooks/status-board.sh` only; a fifth section, AI delivery, appears when the repository has a ledger (`ledger.sh metrics`) |
| `/hef.orchestrate` | `[--stage plan\|build\|deploy] [--dry-run]` | Dispatch ONE board item to a fresh headless session for a stage through the ledger (`hooks/ledger.sh`, `hooks/session-launch.sh`): `plan` takes a queued item through spec → plan → fresh-context review → tasks in a session that writes only under `.specify/`; `build` (the default) launches the implement worker and then the separate verifier; `deploy` runs one `/hef.babysit --once` pass on an item whose PR exists. Reads the board `/hef.status` reads; one session per repository at a time; never merges, approves, or pushes `main`. `--dry-run` prints the launch line and claims nothing. On every exit path it then publishes the touched item's state to the board (`orchestrate.publish`) and sends each overdue `human:*` block once, as a one-line pointer, to the pane that owns it (`orchestrate.escalate_after_hours`) — both opt-in |
| `/hef.babysit` | `[<pr>] [--max-fixes N] [--once]` | Keep ONE pull request moving up to the human merge gate (`hooks/pr-watch.sh`): waits on CI inside a helper call (no model turns while it runs), turns a red check into a root-caused fix inside the PR's diff pushed with its hash on the PR, reads review comments as untrusted data (pertinent → fix and reply, doubtful → ask the person), stops at mergeable with the ledger blocked on `human:merge`; `--max-fixes` (3) bounds it through the PR's own comments, `--once` prints `babysit <n> <verdict> fixes=<k> questions=<q>` for a `/loop`; never merges, approves, force-pushes, or resolves a thread |
| `/hef.init` | — | Bootstrap `.specify/` directory in current project |
| `/hef.constitution` | — | Create/update project governance principles |
| `/hef.brainstorm` | `<idea>` | Socratic design exploration before specification |
| `/hef.spec` | `<feature>` | Generate spec with scenarios, requirements, criteria |
| `/hef.clarify` | — | Scan spec for ambiguities, ask targeted questions |
| `/hef.plan` | `[--arena [K]] [--via <provider,…>]` | Generate implementation plan from spec. `--arena [K]` (K 2..3, default 2) fans the truth-map questions out to K read-only `truth-scout` agents at `sonnet`, `opus`, `fable` in one message, verifies their citations with `speckit-helper.sh arena-cite-check`, and writes `research.md` with an `## Arena` table attributing every claim per tier, `### Disagreements` (→ `[NEEDS CLARIFICATION]` markers, resolved before Phase 1) and `### Unverified`, plus a footer `speckit-helper.sh arena-metrics` reads back. `--via <p,…>` gives up to K−1 slots to providers declared in `.claude/project-status.json` (one `truth-scout` always kept), run through `hooks/arena-run.sh --purpose arena` from an unsandboxed pane; each is cite-checked and gets its own column |
| `/hef.tasks` | — | Generate phased task list from plan and spec |
| `/hef.checklist` | — | Generate requirement quality checklists |
| `/hef.analyze` | — | Read-only cross-artifact consistency analysis |
| `/hef.implement` | — | Execute TDD implementation with quality gates (arms the test guard) |
| `/hef.verify` | — | Post-implementation gate: mechanical FR → test matrix + spec-compliance review |
| `/hef.baseline` | `<module>` | Reverse-engineer spec from existing code (brownfield) |
| `/hef.fix` | `<description>` | Quick-fix bypass for trivial changes |

---

