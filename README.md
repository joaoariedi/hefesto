<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/brand/hefesto-banner-dark.svg">
    <img src="docs/brand/hefesto-banner-light.svg" alt="Hefesto - spec-driven development for Claude Code" width="800">
  </picture>
  <p><strong>Spec-driven development for Claude Code: write the spec, then the plan, then the code &mdash; with quality gates enforced by hooks rather than by good intentions.</strong></p>
  <p>
    <a href="https://github.com/joaoariedi/hefesto/actions/workflows/smoke.yml"><img alt="smoke suite" src="https://github.com/joaoariedi/hefesto/actions/workflows/smoke.yml/badge.svg"></a>
    <img alt="plugin version" src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjoaoariedi%2Fhefesto%2Fmain%2F.claude-plugin%2Fplugin.json&query=%24.version&label=version&color=22d3ee">
    <img alt="Plugin for Claude Code" src="https://img.shields.io/badge/plugin_for-Claude_Code-2b2f36?logo=anthropic&logoColor=white">
    <img alt="Gates are hook-enforced" src="https://img.shields.io/badge/gates-hook--enforced-f97316">
    <img alt="License MIT" src="https://img.shields.io/badge/license-MIT-64748b">
  </p>
</div>

---

## 🎯 What it is

Claude Code will happily write code from a one-line prompt. That works until the change is big
enough that "what were we building?" stops having an obvious answer — and then it fails quietly,
by building the wrong thing well.

This framework adds the missing middle. A feature goes **idea → spec → plan → tasks → code →
verification**, with a human gate at each seam, and the pipeline refuses to skip ahead. Around that
sit six specialist agents, fourteen hooks, and a set of rules that load into every session.

The parts that matter are the ones you cannot talk your way past:

- ✅ **A `TaskCompleted` hook blocks a task from being marked done while the tests fail.** Not a
  reminder — a hook that exits non-zero and refuses.
- 🔐 **A pre-commit hook runs secrets detection and linting**, and blocks the commit if they fail.
- 🚧 **A plan-phase hook blocks edits outside `.specify/`** while a plan is being written, so the
  agent cannot start coding "just to check something."
- 🧷 **An implement-phase hook lets tests grow but never shrink** — no assertion removed, no test
  overwritten, no snapshot regenerated to get to green.
- 🔗 **`/hef.verify` maps every requirement to the tests that cite it**, mechanically, and fails
  on the one that none does.

Everything else — the agents, the skills, the research corpus — is support for that spine.

---

## 📦 Install

**Hand `SETUP.md` to an agent.** It is a runbook written for Claude Code to execute: it clones,
installs, configures the permission rule, verifies the result, and tells you what it did.

```bash
cd ~/some-project && claude
```

> Fetch https://raw.githubusercontent.com/joaoariedi/hefesto/main/SETUP.md
> and follow it to install the Hefesto on this machine.

Or do it yourself — it is three commands:

```bash
git clone https://github.com/joaoariedi/hefesto.git ~/.claude-framework
claude plugin marketplace add ~/.claude-framework
claude plugin install hefesto@hefesto
```

Then **restart Claude Code** and run `/hef.context` in any git repository. It should print a
project summary. If it prints nothing, the permission rule is missing or wrong — that is the
single most common failure, and [`docs/install.md`](docs/install.md) explains exactly why.

⚠️ **One thing the plugin cannot ship:** `rules/` and `CLAUDE.md` are not plugin components, so
installing does *not* give you the framework's global rules. Copy them yourself, and re-copy after
an upgrade — see [`docs/install.md`](docs/install.md).

---

## 🗂️ Structure

| Directory | What lives there |
|---|---|
| 🛠️ `commands/` | The 23 slash commands, all `hef.*` — namespaced, so no built-in can shadow them. |
| 🕵️ `agents/` | Six specialist subagents — testing, quality, review, security, PR coordination, recon. |
| ⚙️ `hooks/` | Fourteen hooks, `release.sh`, plus `speckit-helper.sh` (41 subcommands) that the commands call for live git data, requirement traceability, and the mutation ratchet. |
| 🧪 `evals/` | `claude plugin eval` cases — each prompt scored with and without the plugin. Opt-in; spends tokens. |
| 🧠 `skills/` | Systematic debugging, effort estimation, performance audit, plus reference skills promoted from rules (quality tooling, pipeline & MCP security, agent collaboration). |
| 🔁 `workflows/` | `workflow.js` — executes a task list as a deterministic Workflow. |
| 📏 `.claude/rules/` | The rules loaded into every session. **Not shipped by the plugin** — copy them yourself. |
| 🧪 `tests/` | `smoke.sh` — the plugin's own behavioral test suite: a structural + regression tier in CI, plus opt-in live and end-to-end tiers (`SMOKE_LIVE=1`). Every guard is mutation-tested. |
| 📚 `docs/` | Everything below. |

---

## 🚀 Using it

The pipeline is not all-or-nothing. Pick the path that matches the change.

### 🌱 1. A new project, from scratch

Full spec-driven development. Every gate, in order.

```bash
/hef.init                        # bootstrap .specify/ — once per project
/hef.constitution                # optional: project governance principles

/hef.brainstorm  <idea>          # Socratic exploration — refine before committing
/hef.spec     <feature>       # → spec: scenarios, requirements, success criteria
/hef.clarify                     # ← HUMAN GATE: answers ambiguities in the spec
/hef.plan                        # → implementation plan (writes blocked outside .specify/)
/hef.review                          # ← HUMAN GATE: plan mode — sign off on the plan
/hef.tasks                       # → phased, dependency-ordered task list
/hef.checklist                   # ← HUMAN GATE: requirement quality
/hef.analyze                     # optional: cross-artifact consistency

/hef.implement                   # TDD execution, red-green, one task at a time (tests may grow, not shrink)
/hef.verify                      # FR → tests, mechanically; then spec-compliance review of the diff
/hef.quality                         # lint, types, secrets, SOLID — before you commit
/hef.review                          # code mode — two-stage review (code-reviewer)
/hef.pr                              # the pull request, with the evidence attached (review-coordinator)
```

For a **large** task list, swap the implementation step for the workflow, which runs independent
tasks in parallel and has every task adversarially verified by agents that did not write it:

```
hefesto:workflow          # (full name required)
```

It **caps how many run at once** so a big task list does not self-inflict API rate limits
(`args.maxConcurrency`, default 4; `args.sequential` to force one at a time). It handles **monorepos**:
each task is routed to the repo that owns its files, with a separate test command and quality gate per
repo, so a spec in one directory can drive code in several. And it refuses to fake success — a run that
cannot mechanically verify a task **halts and says why** rather than reporting green.

It must be called by that full name; a bare `workflow` does not resolve. Run it only
**after** the human gates — a workflow cannot pause to ask you a question. Full argument reference:
[`docs/sdd.md`](docs/sdd.md).

### ✨ 2. A feature, in a project already set up

`.specify/` already exists. Skip the bootstrap and the constitution.

```bash
/hef.context                         # orient: stack, tools, structure, recent activity
/hef.spec  <feature>
/hef.clarify                     # ← HUMAN GATE
/hef.plan
/hef.review                          # ← HUMAN GATE (plan mode)
/hef.tasks
/hef.implement
/hef.verify                      # ← the traceability gate
/hef.quality
/hef.review                          # code mode
/hef.pr                              # → the PR, opened by review-coordinator; you merge
```

### 🔧 3. A trivial fix

A typo, a config tweak, a one-line bug. The pipeline would cost more than the change.

```bash
/hef.fix  <description>          # bypasses spec/plan/tasks entirely
/hef.quality
```

The hooks still apply. You cannot commit secrets or skip the tests just because you took the
short path.

### 🏚️ 4. Brownfield — existing code, no specs

Reverse-engineer the spec from what is already there, then proceed normally.

```bash
/hef.context                         # what is this codebase?
/hef.init
/hef.baseline  <module>          # → spec inferred from existing code
```

Read the generated spec before trusting it — it is inferred, not authoritative. Once you have
one, treat the module as scenario 2.

### 🧰 Also available, any time

| | |
|---|---|
| 🔒 `/hef.scan` | Secrets, SQLi, XSS in the staged changes. |
| 🤝 `/hef.agent <task>` | Sizes the task, picks the path (fix / light / full), then runs it with planning and tracking. |
| 🛡️ `/hef.quality` | The quality gate. Spawns `quality-guardian`. |
| 🧬 `/hef.mutate` | Mutation-tests the changed code against a raise-only score ratchet. Coverage says a line ran; this says a test would notice. |
| 🚀 `/hef.release <X.Y.Z>` | Moves every version declaration together and scaffolds the changelog entry for you to edit. |
| 🔍 `/hef.review` | Plan mode before tasks exist; code mode after (spawns `code-reviewer`). |
| 📝 `/hef.pr` | Open or update the PR. Spawns `review-coordinator`; never merges. `--summary-only` writes just the description. |
| 🩺 `/hef.doctor` | The framework's own check-up: three copies in sync, hooks linted, manifest valid; `--eval` scores its prompts. |
| 📜 `/hef.adr` | Record a decision under `reports/` with machine-readable status. |

Full reference: [`docs/commands.md`](docs/commands.md).

---

## ⚙️ What happens without you asking

The hooks ship with the plugin — you do not register them:

- ✏️ **On every edit** — formatters run; tests fire for the touched code.
- 🔐 **On every `git commit`** — secrets detection and linting must pass, the subject must be a conventional commit, and (where `lizard` is installed) no changed file may gain over-limit functions — or the commit is blocked.
- 🔀 **After edits, once a minute** — you are told if the branch's committed state would conflict with its base, or has drifted far behind it.
- ✅ **On task completion** — the task cannot be marked done while the test suite fails.
- 🚧 **During `/hef.plan`** — edits outside `.specify/` are blocked.
- 🧷 **During `/hef.implement`** — tests may grow, never shrink; snapshot regeneration is always blocked.
- 🧭 **On session start / before compaction** — context is injected, a checkpoint is written.
- 👁️ **On a settings change mid-session** — it is announced.

[`docs/hooks.md`](docs/hooks.md) explains each, and how to opt out deliberately when you must.

---

## 📚 Documentation

| | |
|---|---|
| 📦 [Installing & Configuring](docs/install.md) | Install, the permission rule, verification, updating, what the plugin cannot ship. |
| 🛠️ [Commands](docs/commands.md) | All 23, with arguments. |
| 🕵️ [Agents & Parallelism](docs/agents.md) | The six agents; when to use a subagent vs. a team vs. a workflow. |
| ⚙️ [Hooks & Quality Gates](docs/hooks.md) | Every hook, the Iron Laws, and the security posture. |
| 🧬 [Spec-Driven Development](docs/sdd.md) | The lifecycle in depth, `.specify/` artifacts, task management. |
| 🏗️ [Architecture](docs/architecture.md) | Package structure, request flow, the five-layer stack, deployment topology. |
| 🧠 [Skills](docs/skills.md) · [Rules](docs/rules.md) · [MCP](docs/mcp.md) | Component reference. |
| ⚡ [Performance & Reasoning](docs/performance.md) | Ultrathink, model selection, context management. |
| 📖 [Research Corpus](docs/research.md) | The reports the framework is built on, and acknowledgments. |

---

## 🧩 Requirements

`git`, the `claude` CLI. Optional: `rtk` (CLI output compression, auto-detected), `GITHUB_TOKEN`
(for the bundled GitHub MCP server).

## 📄 License

MIT — see [LICENSE](LICENSE).

---

**Framework Version**: 7.0.0 &nbsp;|&nbsp; **Last Updated**: 2026-09-22 &nbsp;|&nbsp; **Compatibility**: Claude Code with sub-agents, hooks, skills (`<name>/SKILL.md`), MCP, Agent Teams
