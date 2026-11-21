# Spec-Driven Development

[← back to README](../README.md)


## 🧬 Development Lifecycle

The framework provides three workflow paths. Choose the one that matches your task:

### ⚡ Quick Fix Path (trivial changes)

For typos, config updates, formatting fixes, and dependency bumps:

```
/hefesto:hef.fix "fix typo in error message"   → apply fix → verify → commit
```

The triviality gate ensures only genuinely trivial changes bypass the full pipeline. If your change modifies logic, APIs, or schemas, you'll be redirected to the Standard path.
The hooks still apply: you cannot commit secrets or skip the tests just because you took the short path.

### 📋 Standard SDD Path (features, refactors, bug fixes)

The full spec-driven development pipeline from idea to implementation:

```
/hefesto:hef.context              → 🧭 orient (detect stack, tools, structure)
/hefesto:hef.init         → 🏗️ bootstrap (once per project)
/hefesto:hef.constitution → 📜 define principles (once per project)
/hefesto:hef.brainstorm   → 💡 Socratic design exploration (refine the idea)
/hefesto:hef.spec      → ✍️ write spec (scenarios, requirements, criteria)
/hefesto:hef.clarify      → 🔍 resolve ambiguities (optional)
/hefesto:hef.plan         → 📐 design (affected files, data model, API contracts); --arena [K] [--via …] fans the truth map out to several readers
/hefesto:hef.review       → 🔎 plan mode (human gate): a fresh-context code-reviewer challenges the plan; APPROVE writes ## Reviewed
/hefesto:hef.tasks        → 📋 generate task list (phased, with dependencies)
/hefesto:hef.checklist    → ✅ pre-implementation gate (optional)
/hefesto:hef.analyze      → 🔬 consistency check (optional)
/hefesto:hef.implement    → 🧪 TDD execution (red-green cycle; the test guard is armed)
hefesto:workflow
                      → ⚡ same, as a Workflow: parallel + adversarially verified
/hefesto:hef.verify       → 🔗 traceability gate: FR → tests (mechanical) + spec-compliance review
/hefesto:hef.quality          → 🛡️ quality gate
/hefesto:hef.review       → 🔍 code mode: two-stage code review
/hefesto:hef.pr               → 📝 the pull request, evidence attached
/hefesto:hef.babysit          → 👀 watch CI and review comments up to the human merge gate (never merges)
```

To run this pipeline per board item in fresh headless sessions (plan / build / deploy stages), see
`/hefesto:hef.orchestrate` — [install §7](install.md).

**Why `/hefesto:hef.verify` exists.** `/hefesto:hef.analyze` maps requirements to *tasks* before code exists.
Nothing checked requirements against *tests* after it did — the implement report's "coverage
mapping" was prose the model wrote about its own work. `speckit-helper.sh req-coverage` now scans
the test files for each `FR-NNN` token the spec declares and fails on an uncovered requirement or an
id the spec never declared. Tests cite their requirement with a marker, a `describe` title, or a
comment; the match is lexical on purpose (zero dependencies, any language, impossible to satisfy by
accident).

**Qualified citations.** Every spec has an `FR-001`, so a bare id covers every spec that declares it. A
test cites a requirement as `<spec>/FR-NNN`, where `<spec>` is the spec's directory name under
`.specify/specs/` — that token covers the named spec only. A spec whose `spec.md` carries the line
`<!-- req-coverage: scoped -->` is *scoped*: only its qualified citations count, and an `UNCOVERED`
row that bare citations would have covered ends with `bare: <file:line> … — cite as <spec>/FR-NNN`.
The `/hefesto:hef.spec` template writes the marker, so every new spec is scoped. A spec without it is
*legacy* — the matrix header says `mode: legacy (bare ids count)` — and keeps the old behaviour: a bare
`FR-NNN` counts, and so does its own qualified form; another spec's qualified citation never does.
Specs written by `/hefesto:hef.baseline` and `/hefesto:hef.init` stay legacy until marked: a brownfield
suite already cites bare ids.

A citation of an id this spec does not declare is `ELSEWHERE` (reported, not failing) when another spec
declares it — bare, or qualified `<other>/FR-NNN` with that spec present and declaring the id. It is
`UNKNOWN` (failing) when no spec declares the bare id, or the qualified citation names a spec that does
not exist or does not declare the id — including the spec under check.

To move a legacy spec to scoped: add the marker line to its `spec.md`, qualify its tests' citations
(`FR-NNN` → `<spec>/FR-NNN`; the `bare:` hints list where), and re-run `req-coverage <spec>` until it
is green.

Every `FR-<digits>` token anywhere in a `spec.md` is read as a declaration, so an example id in a
spec's prose needs a non-digit placeholder (`FR-NNN`); otherwise it becomes a requirement no test cites.

Specifications live in `.specify/specs/<branch>/` of the spec root — the nearest folder, from where you work, that holds `.specify/`, never above the repository top — and are committed to version control. A constitution in `.specify/memory/constitution.md` defines project-level governance principles that every plan is validated against. In a repository with several apps (`spec_roots` in `.claude/project-status.json`, [install §7, item 15](install.md)), each app folder has its own `.specify/` and inherits the top constitution: `speckit-helper.sh constitution` run in an app prints the repository's constitution first, then the app's.

### 🏗️ Brownfield Path (existing code)

For projects with existing code that lack formal specifications:

```
/hefesto:hef.baseline     → 📊 reverse-engineer spec from code
/hefesto:hef.clarify      → 🔍 resolve what the inference missed (optional)
/hefesto:hef.plan         → 📐 design the enhancement or refactoring
/hefesto:hef.review plan  → 🔎 plan mode (human gate): needs plan.md; APPROVE writes ## Reviewed
/hefesto:hef.tasks        → 📋 generate tasks for enhancements
/hefesto:hef.implement    → 🧪 execute with quality gates
```

Read the generated spec before trusting it — it is inferred, not authoritative. Once you have one, treat the module
as a feature in a project already set up (the Standard path, without the bootstrap).

### 🔗 After shipping: traceability in CI

`/hefesto:hef.verify` maps every requirement to the tests that cite it — once, at implementation. The
critics of spec-driven development are right about what happens next: the code moves, the spec
does not, and within a few hotfixes the spec is documentation that still claims authority. This
framework's answer is not to call the spec the source of truth (the tests are) but to keep the
spec honest mechanically after the feature ships, in two places:

- **At the edit** — `spec-cite-probe.sh` (PostToolUse) tells you, outside an implement phase,
  when a test citing `FR-NNN` changes and which spec declares it.
- **At the PR** — the same predicate the verify gate runs, for every *shipped* spec, as a
  reusable workflow:

```yaml
# .github/workflows/traceability.yml in your repository
name: traceability
on: [pull_request]
jobs:
  req-coverage:
    uses: joaoariedi/hefesto/.github/workflows/req-coverage.yml@v9.3.0
    with:
      hefesto-ref: v9.3.0
```

The `@v9.3.0` pins only the workflow file. The helper it runs is cloned from the `hefesto-ref` input,
which defaults to `main` — pass the same tag there, or the check follows hefesto's main branch.

It runs `speckit-helper.sh req-coverage --all`: each spec whose `tasks.md` has no open task is
checked in its own mode (every `FR-NNN` cited by at least one test — qualified as `<spec>/FR-NNN` for
a scoped spec — and no test citing an undeclared id); specs still in progress are listed and skipped. Locally, `req-coverage <spec-name>` checks one shipped
spec from any branch. No install step: bash, jq, and git.

`req-coverage` checks the specs of the spec root it runs from, and the reusable workflow runs it from
the repository top. In a repository with several apps (`spec_roots`), each app's specs live in its own
`.specify/`: run `req-coverage --all` once per app folder.

### ⚖️ The Four Balances

Every decision in the framework balances four concerns:

| Concern | How the Framework Addresses It |
|---------|-------------------------------|
| 🔒 **Security** | Hooks block sensitive files, gitleaks secrets scanning, OWASP LLM rules, forensic-specialist agent |
| ⚡ **Performance** | performance-audit skill, quality-guardian benchmarks, CI optimization (cancel-in-progress, staged-files-only lint) |
| 🏛️ **Maintainability** | SOLID principle checks, code quality limits, systematic-debugging skill, cross-cutting change maps |
| 🎯 **Efficacy** | Iron Laws prevent false completions, spec compliance gates, built-in `/verify` to drive the real app |

---

## ⚡ `workflow` — deterministic execution of a task list

For a large task list, `hefesto:workflow` executes `tasks.md` as a
deterministic Workflow instead of `/hefesto:hef.implement`: phase order is enforced in code, independent
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
| `featureDir` | detected | The feature directory holding `tasks.md` (`.specify/specs/<branch>/`). `args` may also be this path as a plain string. Without it the loader takes `.specify/specs/<current branch>/`, else the only feature directory present. |
| `maxConcurrency` | `4` | Caps how many agents run at once. The harness's own cap is a CPU bound that says nothing about a shared API, so a big task list could self-inflict sustained 429/529 — this bounds it. A non-positive or non-integer value is rejected (falling back to 4) rather than silently removing the cap. |
| `sequential` | `false` | `true` forces one agent at a time — the safest setting when you already know the API is hot. |
| `testCommand` | — | An explicit full-suite command for a single-repo project, when the loader cannot detect one. Without it, an undetectable command halts the run at load rather than skipping verification. |
| `repos` | — | **Monorepo support.** An array of `{ path, testCommand, testCommandStatus, lintCommand }`, one per repository the tasks touch. Each task is routed to the repo whose path prefixes its files, and the quality gate runs once per repo — so a spec in `tasks/` can drive code in `api_service/` (pytest) and `web_app/` (vitest), each verified with its own command. The loader detects these automatically; pass `repos` only to override it. The **first** entry is the default for a task that declares no files. |
| `projectRoot` | detected | Overrides the repo-root the loader infers from the spec location — needed when the spec does not live inside the code repo. |

After two terminal agent failures the workflow throttles itself to one agent at a time for the rest of
the run: a slow finish beats a fast failure. A task whose files span two repos is rejected with a reason
naming both — split it into one task per repo.

---



## 📦 Spec Artifacts

Each feature generates artifacts in `.specify/specs/<branch>/` of its spec root:

| Artifact | Generated By | Purpose |
|----------|-------------|---------|
| `spec.md` | `/hefesto:hef.spec` or `/hefesto:hef.baseline` | User scenarios, functional requirements, success criteria |
| `plan.md` | `/hefesto:hef.plan` | Design, affected files, constitution compliance |
| `tasks.md` | `/hefesto:hef.tasks` | Phased task list with IDs and dependencies; `[P]` tasks declare `owns:` — the files they claim exclusively, which is what the workflow batches by |
| `research.md` | `/hefesto:hef.plan` | Truth Map — cited `file:line` claims about the code, resolved clarifications; with `--arena`, per-reader attribution and disagreements |
| `checklists/*.md` | `/hefesto:hef.checklist` | Requirement quality checklists |
| `data-model.md` | `/hefesto:hef.plan` | Schema changes (if applicable) |
| `contracts/` | `/hefesto:hef.plan` | API contracts (if applicable) |

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
    └── <branch>/               # named after the branch, minus any feature/ prefix
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

