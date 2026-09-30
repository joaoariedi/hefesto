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
tasks → code → verification, with a human gate at each seam), **six specialist agents** the workflow
dispatches, **fifteen hooks** that enforce the gates, **skills** the agents reason with, and a set
of **rules** that load into every session. It is one namespace of 26 `hef.*` commands; you pick the
path that fits the change, from a one-line fix to a full specification pipeline.

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
> and follow it to install Hefesto on this machine.

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

**Updating** is a pull plus a per-profile refresh, then a restart. This is the message to send the
engineers on your team when a release is out — replace `X.Y.Z` and paste it:

```bash
# Hefesto X.Y.Z is out. Upgrade (about a minute):
git -C ~/.claude-framework pull --ff-only
claude plugin marketplace update hefesto                 # re-read the manifest
claude plugin update hefesto@hefesto                     # once per profile you run:
#   CLAUDE_CONFIG_DIR=~/.claude-<profile> claude plugin update hefesto@hefesto
cp ~/.claude-framework/.claude/rules/*.md ~/.claude/rules/            # rules are not plugin components
diff ~/.claude-framework/.claude/CLAUDE.md ~/.claude/CLAUDE.md        # merge by hand if you customised it
# Restart Claude Code, then run /hef.doctor — it must report RUNNING_MATCHES_CLONE at X.Y.Z.
```

Each profile runs its own cached copy of the plugin, so the pull alone changes nothing a session
sees, and `plugin update` keys off the manifest version — releases always bump it. `CHANGELOG.md`
says what each release changed.

---

## 🗂️ Structure

| Directory | What lives there |
|---|---|
| 🛠️ `commands/` | The 25 slash commands, all `hef.*` — namespaced, so no built-in can shadow them. |
| 🕵️ `agents/` | Six specialist subagents — testing, quality, review, security, PR coordination, recon. |
| ⚙️ `hooks/` | Fifteen hooks, plus the helpers the commands call: `speckit-helper.sh` (42 subcommands) for live git data, requirement traceability and the mutation ratchet; `status-board.sh` for the board; `ledger.sh` and `session-launch.sh` for the multi-session pipeline; `release.sh`. |
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

### 🧵 5. Several sessions, one board

The way the harness is meant to be run once a project is live: **one long-lived pane per
responsibility, short-lived workers for the code**, and one shared truth nobody has to repeat to
anybody. The evidence for that shape — and against a mesh of sessions that talk to each other — is
[`reports/17-multi-agent-session-orchestration.md`](reports/17-multi-agent-session-orchestration.md).

| Pane (start it with `claude --name <repo>-<role>`) | Responsibility | Runs | Owns |
|---|---|---|---|
| 📋 `<repo>-project` | the board and the documents: intake, specs, tasks, status | `/hef.status`, `/hef.brainstorm` → `/hef.spec` → `/hef.clarify` → `/hef.plan` → `/hef.review` → `/hef.tasks`, `/hef.adr`, and `/hef.orchestrate` to dispatch workers | `tasks/`, `.specify/`, `docs/`, the ledger |
| ✨ `<repo>-feature` | one feature at a time, by hand, in its own worktree | `/hef.implement` or `hefesto:workflow`, `/hef.verify`, `/hef.quality`, `/hef.review`, `/hef.pr` | one branch |
| 🔧 `<repo>-chore` | general tasks, fixes, merges, releases | `/hef.fix`, `/hef.doctor`, `/hef.release`; the merges themselves | `main` |
| 🤖 workers (headless, launched by `/hef.orchestrate`) | one board item each, then they exit | the size-routed pipeline, then a separate read-only verifier | one worktree under `.claude/worktrees/<id>` |

That is the layout **by object** — the documents, one feature, `main`. The same spine also runs
**by stage**, the layout of Galbiati's deck (`reports/18-…`, addendum A2): one pane per stage,
each launching headless sessions for its stage's work and holding that stage's human gates.

| Pane | Owns (ledger phases) | Human gates | Launches / runs |
|---|---|---|---|
| 🎛 `<repo>-orchestrator` | the board's state, `queued` → claim | `human:intake` | `/hef.status`, `/hef.orchestrate`, `ledger.sh list\|next\|metrics` |
| 📐 `<repo>-plan` | `intake` → `spec` → `plan` → `plan-review` → `tasks` | `human:clarify`, `human:plan-review` | `/hef.brainstorm` → `/hef.spec` → `/hef.clarify` → `/hef.plan` → `/hef.review` → `/hef.tasks` |
| 🔨 `<repo>-build` | `implement` → `verify` → `quality` → `security` → `pr` | `verdict`, `stall`, `budget`, `conflict` | the implement worker, then the verifier (what `/hef.orchestrate` launches today) |
| 🚀 `<repo>-deploy` | `pr` → `merged` → `released` | `ci`, `human:merge`, tag/deploy | `/hef.pr`, `/hef.babysit` (`/loop 25m /hef.babysit <n> --once` while a review is pending), `/hef.release`; the merge itself, by a person |

Choose by object when one person runs the repository and a feature should stay in one pane end to
end; by stage when more than one person attends, when the panes sit on different hosts (CI and the
PR on the workstation, the production release on the laptop), or when each stage should own its own
clarifications. Either way a pane never does a stage's work in its own context: it launches a fresh
session per item, or does the human step by hand, then `/clear`s. The ledger does not know which
layout is in use.

**The shared truth is three things, none of them a conversation:** the board (`tasks/` or the
GitHub Project), the ledger (`.git/hefesto/ledger/<id>.json` — shared by every worktree, never
committed), and the pull requests. Every pane opened in the checkout is told at start which entries
are blocked and on what (`ledger: HEF-7 blocked_on human:merge …`), so nothing has to be announced.

**A message is a pointer, never a payload.** Panes can message each other (Claude Code's
cross-session messaging; `claude agents --json` lists them by the name you gave). Keep it to one
line — an id, a phase, a path: `ledger HEF-7 pr https://…/pull/7 — merge?` — never a diff, a review
or a transcript. Each inbound message costs the receiver a full-context turn, and the ledger already
holds everything the line points at.

**Aligning a release across the panes** is a sequence the ledger makes visible, not a meeting:

1. `project` dispatches or a person in `feature` claims an item (`hooks/ledger.sh claim HEF-7
   --session <repo>-feature --role implement`) — the orchestrator then leaves it alone.
2. The PR lands the item in `pr`, blocked on `human:merge`. That block is the release queue.
3. `chore` merges (a person, with a merge commit), then `git pull --ff-only`,
   `hooks/ledger.sh unblock HEF-7`, `hooks/ledger.sh advance HEF-7 merged`, and removes the worktree.
4. When `hooks/ledger.sh list --phase merged` is the release, `chore` runs `/hef.release X.Y.Z`,
   tags, and sends `project` one line: `release X.Y.Z tagged — HEF-7 HEF-8`.
5. `project` moves the items to `DONE.md`; `/hef.status` shows the quarter delivered.

**Switching it on** (once per repository; the long form is [`docs/install.md`](docs/install.md) §7):

1. Put the board in `tasks/` — one heading per item, `## HEF-1 — title`, then the body a worker
   receives as data — and declare it in `.claude/project-status.json`:
   `{"source":"tasks-repo","root":"tasks","orchestrate":{"usd_cap":5,"daily_usd_cap":25,"tiers":{"implement":"opus","verify":"fable"}}}`
   (tiers, never model ids; the reviewer tier must rank at or above the author's).
2. Protect `main`: require a pull request before merging, administrators included. Merge with merge
   commits — the `human:merge` gate is cleared by branch ancestry, which a squash never satisfies.
3. Open the project pane **with its own sandbox off**, in the main checkout, on the host that holds
   GitHub access and nothing else: `claude --name <repo>-project --settings '{"sandbox":{"enabled":false}}'`.
   The launcher spawns `claude -p` as a child of the shell; the workers get their sandbox from the
   settings it passes them.
4. `/hef.orchestrate --dry-run` prints the exact launch line for the next item and claims nothing.
5. `/hef.orchestrate` — one item: a worker in `.claude/worktrees/<id>`, then a separate verifier,
   then a PR and an entry blocked on `human:merge`. Run it again for the next item.
6. After you merge: `git pull --ff-only`, `hooks/ledger.sh unblock <id>`,
   `hooks/ledger.sh advance <id> merged`, `git worktree remove .claude/worktrees/<id>`.

A hand-run item in `feature` goes through the same ledger steps a worker does (`run --role implement
--exit 0 --usd 0`, `record --pr … --branch …`, `advance pr`, `block --kind human:merge`); a one-call
shortcut for that is backlog item HEF-6. Two rules keep the panes honest: the `project` pane that runs
`/hef.orchestrate` has **its own sandbox off** (the workers it launches get theirs), see
[`docs/install.md`](docs/install.md) §7; and no pane ever merges, approves or pushes `main` for a
worker — branch protection on `main` is the backstop, not the prompt.

### 🧰 Also available, any time

| | |
|---|---|
| 🔒 `/hef.scan` | Secrets, SQLi, XSS in the staged changes. |
| 🤝 `/hef.agent <task>` | Sizes the task, picks the path (fix / light / full), then runs it with planning and tracking. |
| 🛡️ `/hef.quality` | The quality gate. Spawns `quality-guardian`. |
| 🧬 `/hef.mutate` | Mutation-tests the changed code against a raise-only score ratchet. Coverage says a line ran; this says a test would notice. |
| 🚀 `/hef.release <X.Y.Z>` | Moves every version declaration together and scaffolds the changelog entry for you to edit. |
| 🔍 `/hef.review` | Plan mode before tasks exist; code mode after. Both spawn `code-reviewer` in a fresh context — the session that wrote it never grades it. `--inline` for a self-review second opinion. |
| 📝 `/hef.pr` | Open or update the PR. Spawns `review-coordinator`; never merges. `--summary-only` writes just the description. |
| 🩺 `/hef.doctor` | The framework's own check-up: the running copy against the clone and upstream, rules against upstream, hooks linted, manifest valid; `--eval` scores its prompts. |
| 📊 `/hef.status` | Management status brief from the source `.claude/project-status.json` declares — a GitHub Project or a tasks repository of kanban files. `--detailed` unfolds, `--check` diagnoses. Adds an AI-delivery section (merge rate, spend per merged PR, blocked by kind) when the repository has a ledger. |
| 🧵 `/hef.orchestrate` | Dispatch ONE board item to a fresh headless worker and a separate verifier through the ledger; one worker per repository at a time; never merges, approves, or pushes `main`. `--dry-run` prints the launch line and claims nothing. Run it from a pane with its own sandbox off. |
| 👀 `/hef.babysit` | Keep ONE pull request moving up to the merge gate: waits on CI in a helper call, turns a red check into a root-caused fix inside the PR's diff with its hash on the PR, treats review comments as data (pertinent → fix, doubtful → asks you), stops at mergeable with the ledger on `human:merge`. Bounded by `--max-fixes`; `--once` for a `/loop`. Never merges. |
| 📜 `/hef.adr` | Record a decision under `reports/` with machine-readable status. |

Full reference: [`docs/commands.md`](docs/commands.md).

---

## ⚙️ What happens without you asking

The hooks ship with the plugin — you do not register them:

- ✏️ **On every edit** — formatters run; tests fire for the touched code.
- 🔐 **On every `git commit`** — secrets detection and linting must pass, the subject must be a conventional commit, and (where `lizard` is installed) no changed file may gain over-limit functions — or the commit is blocked.
- 🔀 **After edits, once a minute** — you are told if the branch's committed state would conflict with its base, or has drifted far behind it.
- 🔗 **After a test edit, outside an implement phase** — if that test cites a requirement, you are told which spec declares it, so the spec follows the test instead of rotting.
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
| 🛠️ [Commands](docs/commands.md) | All 25, with arguments. |
| 🕵️ [Agents & Parallelism](docs/agents.md) | The six agents; when to use a subagent vs. a team vs. a workflow. |
| ⚙️ [Hooks & Quality Gates](docs/hooks.md) | Every hook, the Iron Laws, and the security posture. |
| 🧬 [Spec-Driven Development](docs/sdd.md) | The lifecycle in depth, `.specify/` artifacts, task management. |
| 🏗️ [Architecture](docs/architecture.md) | Package structure, request flow, the five-layer stack, deployment topology. |
| 🧠 [Skills](docs/skills.md) · [Rules](docs/rules.md) · [MCP](docs/mcp.md) | Component reference. |
| ⚡ [Performance & Reasoning](docs/performance.md) | Ultrathink, model selection, context management. |
| 📖 [Research Corpus](docs/research.md) | The reports the framework is built on, and acknowledgments. |

---

## 🧩 Requirements

`git`, `jq` (every hook reads its event with it), and the `claude` CLI.

Optional, auto-detected, silent when absent: `gitleaks` (the secrets gate), `lizard` (the
complexity gate), `shellcheck`, `rtk` (CLI output compression), `graphify` (knowledge graph),
`GITHUB_TOKEN` (the bundled GitHub MCP server), and `bubblewrap` + `socat` for the OS sandbox that
[`docs/install.md`](docs/install.md) recommends as the boundary the hooks cannot be.

## 📄 License

MIT — see [LICENSE](LICENSE).

---

**Framework Version**: 7.4.0 &nbsp;|&nbsp; **Last Updated**: 2026-09-28 &nbsp;|&nbsp; **Compatibility**: Claude Code with sub-agents, hooks, skills (`<name>/SKILL.md`), MCP, Agent Teams
