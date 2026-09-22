---
name: "Agent Collaboration & Parallelism"
user-invocable: false
description: |
  How to parallelize work across subagents, agent teams, and workflows: one-shot
  subagent design rules and context-reduction discipline, choosing a parallelism
  primitive (subagent vs team vs workflow), and agent-team composition patterns.
  Load when deciding how to split work across multiple agents.
when_to_use: |
  "spawn subagents", "use an agent team", "parallelize this work", "one-shot recon",
  "workflow vs team vs subagent", "competing hypotheses", dispatching background agents
---

# Agent Collaboration & Parallelism

## One-Shot Subagents (Context Reduction)

A one-shot subagent is dispatched for a single discrete operation — run a test, fetch a fact from another repo, triage a log — and returns **only a digest** to the main conversation. The subagent's full working context is thrown away; the main context sees a bounded summary. Done right, this is the single highest-leverage tool for staying in the "Smart Zone" (<40% context) on long sessions.

### When to Use

- The operation will produce large tool output (test suites, log files, foreign repos)
- The main agent only needs the *conclusion*, not the transcript
- The work is read-mostly and has a clean output contract
- The same information would bloat the main context if fetched inline

### When NOT to Use

- The operation is small (a single Grep, a single file Read) — just do it inline
- You need the intermediate state later in the same session — subagent context is discarded
- You need to negotiate / iterate — subagents are one-round by design
- The task requires mutations to the current project — one-shot subagents are read-only

### Design Rules (Non-Negotiable)

1. **Narrow trigger in `description`** — specific verb + noun. "Run the failing tests and report" — not "help with testing." The description is the main agent's only signal for when to dispatch.
2. **Tool allowlist, not denylist** — set `tools:` frontmatter explicitly. Start with nothing, add only what the task needs. The default (all tools) is wrong for one-shot agents.
3. **No side effects on the current project** — one-shot agents must never `Write`, `Edit`, or `git commit` in the main repo. If a mutation is needed, return a *proposal* and let the main agent execute it.
4. **Output contract at the end of the system prompt** — a concrete template showing exactly what the agent must return. Every claim must carry a `path:line` citation. Example: the `<repo-scout-digest>` block in `.claude/agents/repo-scout.md`.
5. **Model tier matches cost** — `model: haiku` for cheap fetches, `model: sonnet` for analysis, `opus` reserved for architectural reasoning. Don't default to opus.
6. **Stop-early budget** — include a "if you're approaching your budget, return PARTIAL" instruction so the agent fails gracefully instead of truncating.
7. **Prefer `general-purpose` for truly one-off work** — only create a new agent file when the pattern will recur. Every agent file adds discoverability noise to the main agent's decision surface.

### Existing One-Shot Agents

| Agent | Purpose | Input | Digest |
|-------|---------|-------|--------|
| **repo-scout** | Answer a targeted question about a repo OTHER than the current project | repo identifier (path or URL) + question | `<repo-scout-digest>` block with answer + citations + verdict |

Add new one-shot agents to `.claude/agents/` following the `repo-scout.md` template. Reuse its output-contract discipline — that is where the context-reduction actually comes from.

### Common Anti-Patterns

- **Dumping raw tool output in the digest** — defeats the whole purpose. The digest must be distilled.
- **Wide `description`** — agents with vague descriptions get invoked accidentally, increasing cost without benefit.
- **Granting `Write`/`Edit` "just in case"** — one-shot agents are read-only. If you think you need mutation, use `general-purpose` or a team workflow instead.
- **Recursive subagents** — a one-shot agent that dispatches other agents reintroduces the context bloat it was meant to prevent.

## Choosing a Parallelism Primitive

Three exist. They are NOT interchangeable, and none supersedes the others.

| | Subagents | Agent Teams | Workflows |
|---|---|---|---|
| **Context** | Own window; result returns to caller | Own window; fully independent | Own window per agent |
| **Communication** | Report to the main agent only | Teammates message each other directly | None — the script wires stages together |
| **Coordination** | Main agent manages everything | Shared task list, self-claiming | A JS script holds the loop and branching |
| **Determinism** | Model decides | Lead decides, turn by turn | **Deterministic** — control flow is code |
| **Scale** | A few | 3–5 (start here) | Dozens to hundreds |
| **Token cost** | Lower | Higher — each teammate is a full session | Scales with agent count |
| **Best for** | Focused tasks where only the result matters | Work needing discussion, debate, challenge | Repeatable fan-out: migrations, audits, sweeps |

- **Subagent** — the default. You want an answer, not a colleague.
- **Agent Team** — when workers must *challenge each other*. The adversarial-debate pattern (5 teammates trying to disprove each other's hypotheses) beats sequential investigation because sequential work anchors on the first plausible theory.
- **Workflow** — when the orchestration itself should be repeatable and you want code, not a model, deciding what runs next.

## Agent Teams (Experimental)

Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in `settings.json` or the environment. Without it, no team is set up and Claude will not spawn teammates.

### When to Use
- **Research and review** — teammates investigate different aspects, then challenge each other
- **Debugging with competing hypotheses** — teammates test rival theories in parallel
- **New modules or features** — each teammate owns a separate piece
- **Cross-layer coordination** — frontend / backend / tests, one owner each

Not for sequential work, same-file edits, or dependency-heavy tasks — use a single session or subagents.

### Team Workflow

> **`TeamCreate` and `TeamDelete` no longer exist** (removed in v2.1.178), and the `team_name`
> parameter on the Agent tool is accepted but **ignored** and deprecated. There is no setup step
> and no cleanup step — a team forms when the first teammate spawns, and its directories are
> removed automatically when the session ends.

1. **Agent (spawn teammates)** — describe the task and the roles; name each teammate so you can address it later
2. **TaskCreate** — break work into tasks with clear ownership boundaries
3. **TaskUpdate** — assign via `owner`, or let teammates self-claim (file locking prevents races)
4. **SendMessage** — coordinate; address teammates by name
5. **SendMessage (shutdown_request)** — end a teammate's session gracefully when done

### Sizing
- **3–5 teammates** for most work. Three focused teammates beat five scattered ones.
- **5–6 tasks per teammate** — enough to keep everyone busy and let the lead reassign if one stalls.
- Token cost scales linearly with teammate count. Each is a full Claude session.

### Team Composition Patterns
| Pattern | Lead | Teammates | Use Case |
|---------|------|-----------|----------|
| **Parallel impl** | general-purpose | 2-3 general-purpose | Multi-service feature |
| **Adversarial review** | general-purpose | 3 general-purpose, one lens each (security / performance / tests) | PR review without single-reviewer tunnel vision |
| **Competing hypotheses** | general-purpose | 3-5, each defending a rival theory | Debugging an unclear root cause |
| **Full pipeline** | general-purpose | test-specialist, quality-guardian, review-coordinator | End-to-end delivery |

Reuse a **subagent definition** as a teammate role by naming its agent type when spawning — its `tools` allowlist and `model` are honored, and its body is appended to the teammate's system prompt.

> **Caveat**: the `skills` and `mcpServers` frontmatter fields of a subagent definition are **not** applied when it runs as a teammate. Teammates load skills and MCP servers from project/user settings like any session.

### Rules
- Teammates share a task list — use TaskList to check progress
- Address teammates by name; to reach everyone, send one message per recipient
- Teammates go idle between turns — this is normal; send a message to wake one
- Teammates do **not** inherit the lead's conversation history — put the context they need in the spawn prompt
- A teammate cannot approve a permission prompt on your behalf, and cannot relay a denied action to another teammate to bypass the check
- Break work so no two teammates edit the same file

### Team Quality Gates (Hooks)
- **`TeammateIdle`** — fires when a teammate is about to go idle. Exit 2 to send feedback and keep it working.
- **`TaskCreated`** — exit 2 to prevent creation and send feedback.
- **`TaskCompleted`** — exit 2 to block a premature completion. This is the mechanical enforcement point for the Verification Iron Law in a team context.
