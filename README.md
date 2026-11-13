<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/brand/hefesto-banner-dark.svg">
    <img src="docs/brand/hefesto-banner-light.svg" alt="Hefesto - a development harness for Claude Code" width="800">
  </picture>
  <p><strong>A development harness for Claude Code: a spec-driven workflow, specialist agents, and quality gates enforced by hooks rather than by good intentions.</strong></p>
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

Hefesto is a Claude Code plugin that adds the missing middle: a **workflow** (idea → spec → plan →
tasks → code → verification, with a human gate at each seam), **seven specialist agents** the workflow
dispatches, **sixteen hooks** that enforce the gates, **skills** the agents reason with, and a set
of **rules** that load into every session. It is one namespace of 27 `hef.*` commands; you pick the
path that fits the change, from a one-line fix to a full specification pipeline.

The parts that matter are the ones you cannot talk your way past:

- ✅ **A `TaskCompleted` hook blocks a task from being marked done while the tests fail.**
- 🔐 **A pre-commit hook runs secrets detection and linting**, and blocks the commit if they fail.
- 🧷 **An implement-phase hook lets tests grow but never shrink** — no assertion removed, no snapshot regenerated.
- 🔗 **`/hefesto:hef.verify` maps every requirement to the tests that cite it**, and fails on the one that none does.

Every hook, and how to opt out deliberately: [`docs/hooks.md`](docs/hooks.md).

---

## 📦 Install

**One command, in a normal terminal** (not inside a Claude Code session). It installs or upgrades:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/install.sh)
```

The tools it needs, the other ways to run it and the check are on your OS's page:
**[Linux](docs/install-linux.md) · [macOS](docs/install-macos.md) · [Windows (WSL)](docs/install-windows.md)**.
The reference — manual install, profiles, the sandbox, updating, and the two things the plugin cannot ship
(`rules/` and `CLAUDE.md`) — is [`docs/install.md`](docs/install.md).

---

## 🧰 Set up a project

In a terminal, in the project's main folder (a git repository with a GitHub remote):

```bash
bash ~/.claude-framework/hooks/hefesto-setup.sh            # add --lanes for four or more lanes
```

Then open `claude` there and run `/hefesto:hef.init` (the `.specify/` folder) and `/hefesto:hef.constitution`. The
[quick start](docs/quickstart.md) §4 has the details, for a project you have or a new one
([em português](docs/quickstart.pt-BR.md)).

**Or let Claude guide you.** `SETUP.md` is a runbook written for Claude Code to follow: it checks the machine, then
walks you through installing or upgrading, fixing a broken install, setting up a project's board, and opening the
sessions. In the project, start `claude` and say:

> Run `curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/SETUP.md` and follow it.

---

## 🚀 First use

In the orchestrator session (`claude --name <repo>-orchestrator`), hand it an idea:

```bash
/hefesto:hef.ship "export orders as CSV"    # brainstorm → RFC → plan → your approval → build → PR
```

Every decision comes to you as a form there; you merge the pull request on GitHub. Or run the pipeline by hand:

```bash
/hefesto:hef.spec <feature>      # → scenarios, requirements, success criteria
/hefesto:hef.plan                # → the plan (edits outside .specify/ are blocked meanwhile)
/hefesto:hef.review              # ← HUMAN GATE: plan mode, a fresh context reviews it
/hefesto:hef.tasks               # → phased task list
/hefesto:hef.implement           # TDD, one task at a time (tests may grow, not shrink)
/hefesto:hef.verify              # FR → tests, mechanically
/hefesto:hef.pr                  # the pull request; you merge
```

A trivial change takes `/hefesto:hef.fix`; existing code without specs, `/hefesto:hef.baseline`. Every path and
command: [`docs/sdd.md`](docs/sdd.md) and [`docs/commands.md`](docs/commands.md).

---

## 🧵 Two approaches

|  | **Single lane** | **Four or more lanes** |
|---|---|---|
| For | experiments, small projects, one feature at a time | a steady stream of RFCs and fixes |
| Sessions you keep open | one: the orchestrator | the orchestrator + a planner, a builder, a deployer — more builders with `orchestrate.max_builders` |
| Setup | `hefesto-setup.sh` | `hefesto-setup.sh --lanes` |
| Run it | [quick start §5](docs/quickstart.md#5-single-lane) | [quick start §6](docs/quickstart.md#6-four-lanes) |

**How to choose:** start with the single lane; the same project adds the three stage lanes later (run the setup
with `--lanes`). Either way each pull request is kept moving to the merge gate by `/hefesto:hef.babysit`, and no
session ever merges for you. The pane layouts and the ledger behind them:
[`docs/install.md`](docs/install.md) §7.

---

## 🤝 Contribute

Running the smoke suite, the commit and branch conventions, and how a change is reviewed and merged:
[`docs/contributing.md`](docs/contributing.md).

---

## 📚 Documentation

| | |
|---|---|
| 🐧 [Linux](docs/install-linux.md) · 🍎 [macOS](docs/install-macos.md) · 🪟 [Windows (WSL)](docs/install-windows.md) | Install on your OS: the tools, the command, the check. |
| 🧭 [Quick start](docs/quickstart.md) · [em português](docs/quickstart.pt-BR.md) | After the install: prepare a project, single lane or four lanes, day to day. |
| 📦 [Installing & Configuring](docs/install.md) | The reference: manual install, profiles, the sandbox, updating, the orchestrator. |
| 🛠️ [Commands](docs/commands.md) | All 27, with arguments. |
| 🕵️ [Agents & Parallelism](docs/agents.md) | The seven agents; when to use a subagent vs. a team vs. a workflow. |
| ⚙️ [Hooks & Quality Gates](docs/hooks.md) | Every hook, the Iron Laws, and the security posture. |
| 🧬 [Spec-Driven Development](docs/sdd.md) | The lifecycle in depth, `.specify/` artifacts, task management. |
| 🏗️ [Architecture](docs/architecture.md) | Package structure, `speckit-helper.sh` (48 subcommands) and the other helpers, the five-layer stack. |
| 🧠 [Skills](docs/skills.md) · [Rules](docs/rules.md) · [MCP](docs/mcp.md) | Component reference. |
| ⚡ [Performance & Reasoning](docs/performance.md) | Ultrathink, model selection, context management. |
| 📖 [Research Corpus](docs/research.md) | The reports the framework is built on, and acknowledgments. |
| 🏭 [Case Study: a Production SDLC](docs/case-study-sdlc.md) | One adopter's whole lifecycle on Hefesto, from RFC to prod. |
| 🤝 [Contributing](docs/contributing.md) | How to change hefesto itself. |

## 📄 License

MIT — see [LICENSE](LICENSE).

---

**Framework Version**: 9.4.1 &nbsp;|&nbsp; **Last Updated**: 2026-11-13 &nbsp;|&nbsp; **Compatibility**: Claude Code with sub-agents, hooks, skills (`<name>/SKILL.md`), MCP, Agent Teams
