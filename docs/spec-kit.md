# Spec-Driven Development

[← back to README](../README.md)


## 🧬 Development Lifecycle

The framework provides three workflow paths. Choose the one that matches your task:

### ⚡ Quick Fix Path (trivial changes)

For typos, config updates, formatting fixes, and dependency bumps:

```
/speckit.fix "fix typo in error message"   → apply fix → verify → commit
```

The triviality gate ensures only genuinely trivial changes bypass the full pipeline. If your change modifies logic, APIs, or schemas, you'll be redirected to the Standard path.

### 📋 Standard SDD Path (features, refactors, bug fixes)

The full spec-driven development pipeline from idea to implementation:

```
/hef.context              → 🧭 orient (detect stack, tools, structure)
/speckit.init         → 🏗️ bootstrap (once per project)
/speckit.constitution → 📜 define principles (once per project)
/speckit.brainstorm   → 💡 Socratic design exploration (refine the idea) ← NEW
/speckit.specify      → ✍️ write spec (scenarios, requirements, criteria)
/speckit.clarify      → 🔍 resolve ambiguities (optional)
/speckit.plan         → 📐 design (affected files, data model, API contracts)
/speckit.review       → 🔎 challenge the plan (scope, architecture, tests) ← NEW
/speckit.tasks        → 📋 generate task list (phased, with dependencies)
/speckit.checklist    → ✅ pre-implementation gate (optional)
/speckit.analyze      → 🔬 consistency check (optional)
/speckit.implement    → 🧪 TDD execution (red-green cycle; the test guard is armed)
hefesto:speckit-workflow
                      → ⚡ same, as a Workflow: parallel + adversarially verified
/speckit.verify       → 🔗 traceability gate: FR → tests (mechanical) + spec-compliance review ← NEW
/hef.quality          → 🛡️ quality gate
/hef.review           → 🔍 two-stage code review ← NEW
/hef.pr               → 📝 the pull request, evidence attached ← NEW
```

**Why `/speckit.verify` exists.** `/speckit.analyze` maps requirements to *tasks* before code exists.
Nothing checked requirements against *tests* after it did — the implement report's "coverage
mapping" was prose the model wrote about its own work. `speckit-helper.sh req-coverage` now scans
the test files for each `FR-NNN` token the spec declares and fails on an uncovered requirement or an
id the spec never declared. Tests cite their requirement with a marker, a `describe` title, or a
comment; the match is lexical on purpose (zero dependencies, any language, impossible to satisfy by
accident).

Specifications live in `.specify/specs/<branch>/` and are committed to version control. A constitution in `.specify/memory/constitution.md` defines project-level governance principles that every plan is validated against.

### 🏗️ Brownfield Path (existing code)

For projects with existing code that lack formal specifications:

```
/speckit.baseline     → 📊 reverse-engineer spec from code ← NEW
/speckit.review       → 🔎 review the inferred spec/plan
/speckit.tasks        → 📋 generate tasks for enhancements
/speckit.implement    → 🧪 execute with quality gates
```

### ⚖️ The Four Balances

Every decision in the framework balances four concerns:

| Concern | How the Framework Addresses It |
|---------|-------------------------------|
| 🔒 **Security** | Hooks block sensitive files, gitleaks secrets scanning, OWASP LLM rules, forensic-specialist agent |
| ⚡ **Performance** | performance-audit skill, quality-guardian benchmarks, CI optimization (cancel-in-progress, staged-files-only lint) |
| 🏛️ **Maintainability** | SOLID principle checks, code quality limits, systematic-debugging skill, cross-cutting change maps |
| 🎯 **Efficacy** | Iron Laws prevent false completions, spec compliance gates, built-in `/verify` to drive the real app |

---

## ⚡ `speckit-workflow` — deterministic execution of a task list

For a large task list, `hefesto:speckit-workflow` executes `tasks.md` as a
deterministic Workflow instead of `/speckit.implement`: phase order is enforced in code, independent
tasks run in parallel, and every task is adversarially verified by three agents that did not write it
(one reads the test diff for a weakened assertion, one checks the requirement, one runs the task's own
test). `tasks.md` is ticked once, at the end, by a single agent. Run it **only after** the human gates —
a Workflow cannot pause to ask a question.

It refuses to fake success. A task whose implementer cannot confirm the RED→GREEN cycle is rejected; a
dead phase gate **halts** rather than passing; a run whose test command cannot be determined halts at
load and tells you to supply one. *Absence of confirmation is not confirmation.*

### Arguments (all optional)

Pass these as the Workflow's `args`. Every one has a safe default, so a normal single-repo run needs
none of them.

| Argument | Default | What it does |
|----------|---------|--------------|
| `maxConcurrency` | `4` | Caps how many agents run at once. The harness's own cap is a CPU bound that says nothing about a shared API, so a big task list could self-inflict sustained 429/529 — this bounds it. A non-positive or non-integer value is rejected (falling back to 4) rather than silently removing the cap. |
| `sequential` | `false` | `true` forces one agent at a time — the safest setting when you already know the API is hot. |
| `testCommand` | — | An explicit full-suite command for a single-repo project, when the loader cannot detect one. Without it, an undetectable command halts the run at load rather than skipping verification. |
| `repos` | — | **Monorepo support.** An array of `{ path, testCommand, testCommandStatus, lintCommand }`, one per repository the tasks touch. Each task is routed to the repo whose path prefixes its files, and the quality gate runs once per repo — so a spec in `tasks/` can drive code in `operations_api/` (pytest) and `cube_ui/` (vitest), each verified with its own command. The loader detects these automatically; pass `repos` only to override it. The **first** entry is the default for a task that declares no files. |
| `projectRoot` | detected | Overrides the repo-root the loader infers from the spec location — needed when the spec does not live inside the code repo. |

Beyond two terminal agent failures the workflow throttles itself to one agent at a time for the rest of
the run: a slow finish beats a fast failure. A task whose files span two repos is rejected with a reason
naming both — split it into one task per repo.

---



## 📦 Spec-Kit Artifacts

Each feature generates artifacts in `.specify/specs/<branch>/`:

| Artifact | Generated By | Purpose |
|----------|-------------|---------|
| `spec.md` | `/speckit.specify` or `/speckit.baseline` | User scenarios, functional requirements, success criteria |
| `plan.md` | `/speckit.plan` | Design, affected files, constitution compliance |
| `tasks.md` | `/speckit.tasks` | Phased task list with IDs and dependencies; `[P]` tasks declare `owns:` — the files they claim exclusively, which is what the workflow batches by |
| `research.md` | `/speckit.plan` | Resolved clarifications |
| `checklists/*.md` | `/speckit.checklist` | Requirement quality checklists |
| `data-model.md` | `/speckit.plan` | Schema changes (if applicable) |
| `contracts/` | `/speckit.plan` | API contracts (if applicable) |

### `.specify/` Directory Structure

```
.specify/
├── memory/
│   └── constitution.md         # project governance principles
├── templates/
│   ├── spec.md                 # specification template
│   ├── plan.md                 # plan template
│   ├── tasks.md                # task list template
│   └── checklist.md            # checklist template
└── specs/
    └── feature-name/           # one directory per feature (kebab-case)
        ├── spec.md
        ├── plan.md
        ├── tasks.md
        ├── research.md
        └── checklists/
```

---

## 📋 Task Management

The framework uses Claude Code's built-in task tracker:

| Tool | Usage |
|------|-------|
| `TaskCreate` | Mandatory for any task with >2 steps |
| `TaskUpdate` | Mark ONE task `in_progress` at a time; `completed` immediately after |
| `TaskGet` | Read full task details before starting work |
| `TaskList` | Check progress and find next available tasks |

---

