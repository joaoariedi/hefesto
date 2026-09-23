---
status: accepted
date: 2026-07-12
---

# Claude Code Harness Capabilities

What the Claude Code harness natively provides — skill loading rules, invocation control, subagent forking, lifecycle hooks, and the bundled skills — and where a custom framework should lean on it instead of reimplementing it. This file exists because the framework spent three releases hand-rolling behaviour the harness ships for free, and shipped a skills layer that never loaded.

This file does **not** cover the agent-topology *theory* (Skills vs Subagents vs Teams as architectural patterns) — see `03-agent-topology-orchestration.md`; nor MCP protocol mechanics — see `04-ai-protocol-stack.md`; nor which security checks to run — see `06-security-devsecops-for-agents.md`.

**Sources:** Official Claude Code documentation, [Skills reference](https://code.claude.com/docs/en/skills), verified July 2026. Unlike the rest of this corpus, the source here is vendor documentation rather than a research report — claims are checkable against a URL, not a citation number.
**Codified in:** The `.claude/skills/` layer itself, plus `rules/agent-workflow.md`.

## The Loading Rule That Bites

A skill is **a directory containing `SKILL.md`**. Nothing else registers.

| Scope | Path |
|---|---|
| Personal | `~/.claude/skills/<skill-name>/SKILL.md` |
| Project | `.claude/skills/<skill-name>/SKILL.md` |
| Plugin | `<plugin>/skills/<skill-name>/SKILL.md` |

A bare `.claude/skills/foo.md` is **silently ignored**. There is no warning, no error, no entry in `/`. The framework shipped seven skills in this dead format — including both Iron Law skills that `code-quality.md` called "non-negotiable" and that `quality-guardian` claimed to enforce. They had never loaded. The agents referenced them in prose, so the model improvised the behaviour from surrounding text instead of executing the skill.

**The command name comes from the directory name**, not the `name:` frontmatter field (which is only a display label). Skills hot-reload on file change; creating the top-level `skills/` directory for the first time requires a restart.

> **Verification is one glance.** If a skill does not appear in the `/` menu, it is not registered. Never assume a config file is live because its contents look correct — this is the same failure mode as an MCP server declared in a location the harness does not read.

## Precedence: Your Skill Shadows the Built-In

Enterprise overrides personal overrides project, and **a skill at any level overrides a bundled skill of the same name**. A project skill named `code-review` replaces the bundled `/code-review`. If a skill and a command share a name, the skill wins.

This inverts the usual instinct. Writing a `security-review` skill does not *add* a capability — it **replaces** Claude Code's own, which is almost certainly better maintained. Naming is therefore a load-bearing decision: pick a name that collides only if you intend to override.

## Bundled Skills Worth Not Reinventing

| Skill | What it does |
|---|---|
| `/verify` | Builds and runs the app to confirm a change works — explicitly *without* falling back to tests or typechecks |
| `/run` | Launches and drives the app |
| `/run-skill-generator` | Records the project's build/launch recipe as `.claude/skills/run-<name>/`, so `/run` and `/verify` stop rediscovering it |
| `/code-review` | Diff review with effort levels, `--fix`, `--comment`, and a multi-agent cloud mode |
| `/security-review` | Full security review of pending changes on the branch |
| `/debug` | Debugging workflow |

`/verify` is the important one. A framework Iron Law that says "run proof commands" is *weaker* than a bundled skill that drives the running application — passing tests are evidence the tests pass, not evidence the change works.

**The policy still belongs to the framework; the procedure does not.** An Iron Law stated in `rules/` is always in context. A skill loads only when invoked. So the law lives in the rule, and the rule points at `/verify` for execution.

## Frontmatter Reference

| Field | Purpose |
|---|---|
| `name` | Display label in listings. **Does not set the command name** — the directory does. |
| `description` | What it does and when to use it. This is how Claude decides to auto-invoke. |
| `when_to_use` | Extra trigger phrases / example requests. |
| `argument-hint`, `arguments` | Autocomplete hint; named positional args for `$name` substitution. |
| `disable-model-invocation` | `true` = Claude never auto-loads it; manual `/name` only. Also blocks preloading into subagents. |
| `user-invocable` | `false` = hidden from the `/` menu. |
| `allowed-tools` | Tools usable **without a permission prompt** while active. Does *not* restrict the tool pool. |
| `disallowed-tools` | Tools **removed** from the pool while active. This is the real read-only enforcement. |
| `model`, `effort` | Per-skill model and reasoning-effort override. |
| `context: fork` | **Run the skill in a forked subagent context.** |
| `agent` | Which subagent type to fork into when `context: fork`. |
| `hooks` | Hooks scoped to this skill's lifecycle. |
| `paths` | Glob patterns limiting when the skill activates. |
| `shell` | `bash` (default) or `powershell`. |

> **`user-invocable: false` + `disable-model-invocation: true` makes a skill unreachable.** Neither the human nor the model can trigger it. The framework's `spec-template` skill set both, while `/speckit.specify` instructed the agent to use it.

## The Three Capabilities the Framework Should Exploit

**1. `context: fork` + `agent:` — subagent isolation as a frontmatter line.**
The framework's entire "One-Shot Subagents" doctrine (`rules/agent-workflow.md`) exists to keep a noisy operation's context out of the main session. Two frontmatter fields now do that. A read-only analysis skill can fork into `Explore` and return only its conclusion, with no separate agent file and no digest contract to maintain.

**2. `` !`command` `` — shell output injected *before* the skill loads.**
The command output replaces the placeholder in the skill body, so live state arrives as data rather than as a tool call the model must decide to make. The framework already uses this in `/context` and `/quality`; it is under-used everywhere else.

```yaml
---
name: pr-summary
context: fork
agent: Explore
allowed-tools: Bash(gh *)
---
- PR diff: !`gh pr diff`
- Changed files: !`gh pr diff --name-only`
```

**3. `hooks:` in skill and agent frontmatter — scoped lifecycle hooks.**
Hooks can be declared in a `SKILL.md` (or agent) frontmatter, travel with the component, need no `settings.json` registration, and are cleaned up when the component finishes. All hook events are supported; `Stop` becomes `SubagentStop` for subagents. Skills additionally get `once: true` (run once per session, then remove).

```yaml
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/security-check.sh"
```

> **This does NOT solve the framework's distribution friction, and an earlier draft of this file
> wrongly claimed it did.** The framework's eight hooks are *global* — `PreToolUse` on every
> `Bash`, `PostToolUse` on every `Edit|Write`. A skill-scoped hook only fires while that skill is
> active, so it cannot replace a global gate. The real fix is packaging: a
> `.claude-plugin/plugin.json` bundles **skills, commands, agents, hooks, workflows, and MCP
> servers** together, which is the only mechanism that ships a global hook without asking the
> user to hand-edit `settings.json`.

Substitutions available in a skill body: `$ARGUMENTS`, `$0`/`$1`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_EFFORT}`.

## Hook Events: The Framework Uses Four of Roughly Thirty

Registered today: `PreToolUse`, `PostToolUse`, `Notification`, `Stop`. Also available:

| Group | Events |
|---|---|
| Session | `SessionStart`, `Setup`, `SessionEnd` |
| Per-turn | `UserPromptSubmit`, `UserPromptExpansion`, `Stop`, `StopFailure`, `TeammateIdle` |
| Tool loop | `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch` |
| Subagent / task | `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted` |
| Compaction | `PreCompact`, `PostCompact` |
| File / config | `FileChanged`, `ConfigChange`, `CwdChanged`, `InstructionsLoaded`, `WorktreeCreate`, `WorktreeRemove` |

`TaskCompleted` is the notable gap: exiting 2 from it **blocks a premature completion**, which is the mechanical enforcement the Verification Iron Law currently lacks — today the law is prose the model can rationalize past.

## Parallelism: Three Primitives, None Superseding Another

| | Subagents | Agent Teams | Workflows |
|---|---|---|---|
| Communication | Report to caller only | Teammates message each other | None — a script wires stages |
| Coordination | Main agent manages | Shared task list, self-claiming | JS script holds loop and branching |
| Determinism | Model decides | Lead decides turn by turn | **Code decides** |
| Scale | A few | 3–5 | Dozens to hundreds |
| Best for | Result-only tasks | Debate, challenge, competing hypotheses | Repeatable fan-out |

> **The framework's Agent Teams documentation was built on dead API.** `TeamCreate` and
> `TeamDelete` were removed in v2.1.178, and `team_name` on the Agent tool is accepted but
> **ignored** and deprecated. Three of the seven documented steps did not exist. A team now forms
> when the first teammate spawns and is cleaned up automatically at session end.

Agent Teams remain experimental and still require `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

## Commands and Skills Have Merged

`.claude/commands/deploy.md` and `.claude/skills/deploy/SKILL.md` both produce `/deploy`. Existing `commands/` files keep working — they are not deprecated. Skills are the superset: they add a directory for supporting files (progressive disclosure via `references/`), invocation control, auto-loading by description, and everything in the frontmatter table above.

A command is the right choice when it is purely a human-triggered prompt. A skill is right when Claude should be able to *decide* to use it, when it needs supporting files, or when it needs tool/model/context control.

## Adopted in v4.4

- **`context: fork` + `agent: Explore`** on `task-effort-estimation` and `performance-audit` — both produce a bounded report the main thread needs the conclusion of, not the trawl. Deliberately **not** applied to `systematic-debugging`: that skill is a methodology the main agent follows *through to the fix*, and the evidence it gathers in phases 1–3 is what phase 4 edits against. Forking would discard the evidence at the moment it becomes useful.
- **`disallowed-tools`** on both forked skills. The framework had been declaring `allowed-tools` in the belief it restricted them. It does not — it only pre-grants permission and prevents nothing. The "read-only" skills could always have called `Write`.
- **`when_to_use`** on all three, giving the model trigger phrases rather than making it infer intent from a prose description.
- **Agent Teams rewritten** against the current API (see above).

- **Packaged as a plugin.** `.claude-plugin/plugin.json` bundles skills, commands, agents, hooks, **workflows**, and the MCP server; `.claude-plugin/marketplace.json` is what makes it *installable* (`claude plugin install` resolves only through a marketplace — without that file the sole install path is the session-scoped `--plugin-dir` flag). This is the *only* mechanism that ships global hooks without a hand-written `settings.json`.

  **`validate` is not a load test.** `claude plugin validate --strict` checks the manifest, frontmatter, and `hooks.json` against the schema, which is why it is worth running — but it verifies that declared *paths exist*, not that the runtime *loads* what they point at. Measured: a `workflows` key was absent entirely and validation still passed; and `claude plugin details` reports `Agents (0)` for a manifest whose agents load correctly in a live session. Validation raises the floor on silent non-loading; **only invoking the component proves it loaded.**
- **`TaskCompleted` gate.** `verify-before-task-complete.sh` exits 2 to block a completion while tests fail. The Verification Iron Law is now mechanical rather than prose.

## Not Yet Adopted

- **`paths:` gating.** No skill limits activation by file glob, so every description competes for attention on every turn. Low value at three skills; it matters as the count grows.
- **`/run-skill-generator`.** Would record each project's build/launch recipe so `/verify` and `/run` stop re-inferring it.
- **Workflows.** No framework command or rule uses the deterministic `Workflow` primitive. The spec-kit pipeline (specify → plan → tasks → implement) is exactly the shape a workflow encodes, and is currently executed by model discretion at every step.
