# Architecture

[← back to README](../README.md)


## 📁 Package Structure

The repository *is* the plugin. The manifests live in `.claude-plugin/`; the payload they point at
lives at the **repository root**.

```
hefesto/
├── .claude-plugin/
│   ├── plugin.json             # the plugin manifest — declares every component below
│   └── marketplace.json        # makes the repo installable (`claude plugin install`)
├── .mcp.json                   # GitHub MCP server, shipped by the plugin (registered in every project it is installed for)
├── agents/                     # 7 agents (5 pipeline + repo-scout and truth-scout one-shot)
├── commands/                   # 27 slash commands, all hef.*
├── hooks/                      # 16 hooks + hooks.json; helpers: release.sh, speckit-helper.sh (47 subcommands), status-board.sh, ledger.sh, session-launch.sh, pr-watch.sh, arena-run.sh, hefesto-setup.sh (the one-time lane settings), context-gauge.sh (the status-line gauge), lane-build.sh (builds with the lanes' cache), run-follow.sh (narrates a background run), lane-guard.sh (the lanes' PreToolUse guard), changelog-check.sh, merge-tree-probe.sh, spec-cite-probe.sh, run-bounded.sh, doctor-tmp.sh; sourced: board-lib.sh (board resolution and the ledger home), lane-lib.sh (the session record, the lane map), spec-root-lib.sh (one `.specify/` per app folder), plan-review-lib.sh (the plan-review round loop), launch-item.sh (session-launch.sh's item and RFC readers), board-github.sh and board-setup.sh (status-board.sh's GitHub Project board and setup modes), ledger-actions.sh, ledger-lanes.sh, ledger-lifecycle.sh, ledger-notes.sh, ledger-recipes.sh (ledger.sh's verb groups)
├── skills/                     # 7 skills, each a <name>/SKILL.md directory
├── workflows/                  # workflow.js — the deterministic task-list executor
├── tests/                      # smoke.sh (structural/regression + opt-in live tiers) and its parts smoke-*.sh (changelog-check, github-board, lane-cache, lane-grants, lifecycle, lifecycle-ops, merge, recipes, spec-roots, train); fixtures/ (the 9.2.0 launch fixture); workflow.test.js (node --test)
├── evals/                      # 15 `claude plugin eval` cases (opt-in; /hefesto:hef.doctor --eval)
├── docs/                       # this documentation
├── .claude/                    # THIS repo's own config — not plugin payload
│   ├── CLAUDE.md
│   └── rules/                  # 5 modular policy files
└── reports/                    # 18 research files: the "why" behind the rules
```

> **The payload deliberately does not live under `.claude/`.** That path is where Claude Code looks
> for *project-scope* config, which outranks both plugins and built-ins — so shipping the payload
> there meant that, while working in this repo, the commands resolved to the repo's own copies and
> behaved differently than in any real install. The framework was never dogfooded *as a plugin*, and
> three bugs shipped because of it. `tests/smoke.sh` now fails if any payload directory reappears
> under `.claude/`. See the 5.0.0 entry in `CHANGELOG.md`.

> `CLAUDE.md` and `rules/` are **not** plugin components — a plugin cannot ship them. They apply when
> this repo *is* your project, or when you copy them into `~/.claude/` yourself (see
> [Installing & Configuring](install.md)). Everything else in the tree is shipped by `plugin.json`.

---



## 🔁 Request Flow & Stack Composition

The harness composes 5 layers — **methodology** (the `hef.*` workflow: spec-driven, with a fix path and a size router), **agent runtime** (Claude Code), specialised **sub-agents**, **integrations** (MCP, hooks, rtk, security CLIs), and **models** (the `fable` / `opus` / `sonnet` / `haiku` *tiers* — aliases each environment binds to concrete models; commands, agents, and workflow spawns pin a tier, never a model ID) — with cross-cutting governance for quality, security, context, and memory. A single feature request traverses every layer:

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Developer
    participant FW as L1 · Methodology<br/>(SDD)
    participant CC as L2 · Claude Code<br/>(main agent)
    participant Sub as L2 · Sub-Agent<br/>(test-specialist)
    participant MCP as L3 · MCP / Hooks
    participant RTK as L3 · rtk proxy
    participant Mod as L4 · model tier<br/>(opus)

    Dev->>FW: /hefesto:hef.brainstorm "user auth idea"
    FW->>CC: socratic exploration
    CC->>Mod: refine concept (Q&A)
    Mod-->>CC: refined direction
    CC-->>Dev: ✓ confirmed concept
    Dev->>FW: /hefesto:hef.spec "user auth"
    FW->>CC: invoke pipeline (spec → plan → tasks)
    CC->>Mod: reason about spec
    Mod-->>CC: spec draft + plan
    CC->>Sub: dispatch (one-shot, isolated ctx)
    Sub->>RTK: rtk pytest -q
    RTK-->>Sub: compressed digest (≈10% tokens)
    Sub->>Mod: analyse failing tests
    Mod-->>Sub: fix proposal
    Sub-->>CC: digest only (200 tok vs 5 000)
    CC->>MCP: PreToolUse hook (gitleaks, sensitive-file block)
    MCP-->>CC: ✓ safe to write
    CC->>Mod: synthesise final patch
    Mod-->>CC: code + tests
    CC-->>Dev: spec + tests + commit ready
```

### What the flow reveals

- **L1 (methodology) shapes thinking, not state.** the SDD pipeline (`/hefesto:hef.brainstorm`…) defines structure but holds no conversation context.
- **Sub-agents isolate context.** Dispatched in fresh contexts and discarded — only the digest returns. Primary defence against the >40% "Dumb Zone".
- **rtk compresses CLI output (60–90%) before it reaches the main context** — the highest-leverage token optimisation in the framework.
- **Hooks enforce the gates deterministically** (gitleaks on commit, the sensitive-file and destructive-command blocks, the TaskCompleted test gate); the security boundary itself is OS sandboxing (`/sandbox`), which a string-matching hook cannot be.
- **Models are stateless** — every layer above exists to give them the right context and route their output safely.

### Currently In Use vs Available

| Component | Status | Notes |
|-----------|--------|-------|
| SDD pipeline | ✅ active | Full pipeline incl. `/hefesto:hef.brainstorm` → `spec` → `plan` → `review` → `tasks` → `implement` → `verify` |
| OpenSpec | ⚪ not adopted | Alternative spec workflow |
| Superpowers | ⚪ pattern reference | Skill-pack architecture is the influence |
| Claude Code | ✅ primary runtime | Session model per profile; each command pins a tier |
| Codex · Opencode · Cursor · Aider | ⚪ alternatives | Alternative runtimes — the methodology layer would still apply; the Codex and Gemini CLIs are also usable as arena providers |
| Foreign providers (`codex`, `gemini`, `claude`, `aws`) | ⚙️ opt-in | Declared under `providers` in `.claude/project-status.json`; run read-only by `hooks/arena-run.sh` as `/hefesto:hef.plan --arena --via` readers and the `/hefesto:hef.review --second-opinion` source; never the gate; `aws` refused for the arena |
| MCP: github | ⚙️ plugin-shipped | Root `.mcp.json`, registered in every project the plugin is installed for; needs `GITHUB_TOKEN` exported |
| MCP: Semgrep, Snyk, SonarQube | ⚪ optional | Add only when CLI scans aren't enough |
| **rtk** | ✅ available (auto-detected per machine) | 60–90% token reduction on common dev commands |
| Fabric | ⚪ pattern reference | Reusable prompt-pattern library |
| gitleaks · semgrep · trivy · ruff · gosec | ✅ via Bash | Quality / security CLIs |
| `fable` / `opus` / `sonnet` / `haiku` tiers | ✅ aliases | Cheap generation, expensive judgment — the policy in `.claude/CLAUDE.md`; `claude-bedrock()` rebinds them |
| GPT · Gemini · Qwen · Llama | ⚪ alternatives | Foundation models from other providers |

---



## 🧵 Multi-session orchestration

`/hefesto:hef.orchestrate` reads the board (a `tasks/` kanban or a GitHub Project, declared in
`.claude/project-status.json`), registers the item in the **ledger** — one JSON file per item at
`~/.cache/hefesto/ledger/<repo key>/<id>.json` (the key: 32 hex of the sha256 of the board's git common
dir, so every worktree agrees), outside every sandbox and never committed (since 9.0) — and
`hooks/session-launch.sh` starts a fresh headless worker (`env HEFESTO_WORKER=1 claude -p …`) in
`.claude/worktrees/<id>` with a tier, a budget cap and a tool allowlist per role (`plan` /
`implement` / `verify` / `deploy`). A **separate verifier** that never sees the author's transcript
judges the result; its tier must rank at least the author's. With `orchestrate.lane_mode: "interactive"`
(per stage or for all) no background worker starts: the stage lane does the work in its own conversation,
between `session-launch.sh --prepare` (the claim, the worktree, the prompt) and `--finish` (the same
transcription a worker's outcome gets). With `spec_roots` declared, the launcher makes the worktree and
starts the session in the item's app folder, with its own `.specify/`. No worker writes the ledger; a
person's decisions reach it through `ledger.sh` in the orchestrator lane.
Planning can run from an **RFC** per item (`rfc:` on the item, under `orchestrate.rfc_dir`): the plan role
hands it to the planner as data and pins its sha256; with `orchestrate.plan_review: "human"` every plan
waits on `human:plan-approval`, which only a named person clears, and an RFC that moves after approval
blocks the build until the plan is re-aligned and approved again. Lanes open with plain `claude --name <repo>-<lane>` after a one-time
`hooks/hefesto-setup.sh`, which writes the lane permissions into `.claude/settings.local.json` (a plugin
cannot ship them): the helper allowlist, the person's clears in `ask`, the sandbox forced on
(`enabled` and `failIfUnavailable`) with `api.github.com` denied to it and Edit denied on
`~/.cache/hefesto/{ledger,approvals,sessions}`; outside the sandbox only hefesto's helpers
(`session-launch.sh`, `ledger.sh`, `pr-watch.sh`, `status-board.sh`), `gh`, and each `--unsandboxed-command`
the person names; `autoAllowBashIfSandboxed: false` only with `--strict`; the trusted folder, the gauge; with
`--lanes`, `crossSessionInbound: "accept"` and the lanes' build cache in `allowWrite`. The orchestrator lane is the one place a
person decides — every blocked entry becomes a form whose command it then runs behind its dialog — and it
reaches the stage lanes with one-line cross-session doorbells; a lane reads its work from the ledger, never
from the message, and launched workers cannot message at all.
Blocks (`human:*`, `verdict`, `stall`, `budget`, `conflict`, `ci`) are announced at session start to
the pane that owns them (`orchestrate.panes`); opt-in `orchestrate.publish` writes each item's state
onto the board and `escalate_after_hours` sends one pointer for a stale human block. `/hefesto:hef.babysit`
(`hooks/pr-watch.sh`) keeps a PR moving to the merge gate; `/hefesto:hef.status` reports AI-delivery metrics
from the ledger. A `branches` block names the integration branch (PR base, verifier diff base,
`human:merge` check), the protected heads, and the promotion chain whose last branch is `released`.
An **external board** (`ledger.sh board`) is a board repository that feeds several code repos: each
code repo points at it with `board`, the board lists them in `repos`, the ledger is central (keyed by the
board repo's git common dir, every entry tagged with its `repo`), `claim` allows one planner,
`orchestrate.max_builders` builders and one deployer per repo at a time (verify is exempt), and every
session runs in its entry's repo.
**No worker ever merges.** By default the person merges on GitHub — the merge is the human gate; with
`orchestrate.merge_by: "lane"` the deployer lane merges an action the person approved with **Merge** in the
orchestrator's form. See README §5,
[install §7](install.md) and `reports/17`.

## 🖥️ Reference Deployment

This is the topology I run the framework on. The framework itself is host-agnostic — this section just documents one tested setup with explicit trust boundaries.

### 🔀 Two-Machine Topology

| Role | OS | Production Access | Always-On | Used For |
|------|-----|-------------------|-----------|----------|
| 💻 **Primary laptop** | Manjaro Linux | ✅ Full | ❌ No | Day-to-day dev, production deploys, attended sessions |
| 🖧 **Always-on remote workstation** | Arch Linux | ❌ GitHub only | ✅ Yes | Long-running tasks, mobile resume target, off-hours work |

Both machines install the **same plugin** from the same clone, so Claude Code behaviour is identical on each: same agents, hooks, skills, workflows, MCP server. Only the machine-local settings differ — each project's `.claude/settings.local.json`, written by `hooks/hefesto-setup.sh` (the lane permissions, the sandbox, the trusted folders), and the per-host `settings.json` (env vars, hook timeouts) — which is exactly the part a plugin cannot ship.

### 🛡️ Trust Boundaries

The blast-radius asymmetry is deliberate:

- 🔐 **Production credentials live only on the laptop.** It is offline most of the time and physically attended.
- 🌐 **The always-on workstation can reach GitHub but not production.** A compromise of the higher-exposure host (always online) cannot pivot into production systems.
- 🔗 **Network is Tailscale-only.** Strict ACLs constrain which hosts can reach which services — no public IPs, no port-forwarding, no inbound exposure.
- 👁️ **Wazuh monitors the whole stack** — file-integrity monitoring, auth events, command auditing — across both machines and any production hosts.

### 🌐 Why the Topology Matters for AI Agents

Claude Code's session-portability features pair naturally with this setup:

- ▶️ Start a long-running task on the **always-on workstation** before stepping away
- 🔄 Resume from the **laptop** later via `/teleport` (see [Multi-Environment Workflows](performance.md#-multi-environment-workflows))
- 📱 Or — start on **mobile** (claude.ai/code), pull into the laptop terminal when home

Critically, the always-on workstation can **autonomously work on GitHub repos** (review PR feedback, run CI, commit fixes) without ever holding production credentials. The laptop holds the keys; the always-on host holds the time.

---

