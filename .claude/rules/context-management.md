# Context Management

Strategies for managing the LLM context window across sessions and project scales.

## The "Dumb Zone" Threshold (40% Context Usage)

LLM reasoning degrades non-linearly as the context window fills with tool output, intermediate
search results, and stale turns. Beyond roughly **40% context usage** — the "Dumb Zone" —
agents increasingly hallucinate file structure, re-read files they already read, produce
generic rather than project-specific suggestions, and prematurely summarize.

**Heuristic, not a hard gate.** The agent cannot reliably measure its own token usage
mid-turn. Use the context-usage percentage shown in the Claude Code CLI header as the
signal:

| Context usage | State | Action |
|---------------|-------|--------|
| 0–40% | **Smart Zone** | Work normally. |
| 40–60% | **Transition** | Finish the current coherent unit of work, then suggest the session's own `/compact` prompt (a pipeline lane: its pane prompt in `docs/performance.md`; any other session: the general one). Do not start a new phase here. |
| 60%+ | **Dumb Zone** | Stop. Write a progress file, then suggest `/compact` naming that file as what to keep — or `/clear` and resume from the file when the conversation itself went wrong. |

**40% is the default, not a constant.** A project sets its own threshold, per lane, with
`context.compact_at` in `.claude/project-status.json` (a number, or `{"orchestrator": 40, "plan": 50,
"build": 0, "deploy": 0}`; 0 = never prompt); `hooks/context-gauge.sh` shows it in the status line, the
only place Claude Code exposes context usage.

**`/compact` over `/clear`.** `/compact` keeps the system prompt and project context cached and costs one
summary request; `/clear` rebuilds everything on the next turn. Prefer **one decisive `/compact` at a
natural break** over many partial ones, and over `/clear` — which is for switching to unrelated work, or a
conversation that went wrong. A fixed-interval `/loop` survives both, and expires 7 days after it was
started. A session on `/loop` that holds nothing beyond what is on disk (a pipeline stage lane) can be left
to Claude Code's own auto-compaction.

**Reduce the rate at which you reach 40%.** The fastest way to stay in the Smart Zone
is to emit less token output per command. Use `rtk` (CLI output compression) when it is
installed on the user's machine — see the `quality-tooling` skill for the detection pattern and
high-savings command list. RTK is optional and auto-detected; when absent, commands run
normally without modification.

The same principle applies to *input*: when a project carries a Graphify knowledge graph
(`graphify-out/graph.json` present), answer codebase questions with `graphify query` /
`explain` / `path` before reading raw files — a scoped subgraph is typically an order of
magnitude fewer tokens than the files it summarizes, with `file:line` sources to jump to
when a specific read is still needed. Graphify is optional and auto-detected via the
project's PreToolUse nudge hooks; when absent, explore normally.

## Document & Clear Pattern

Proactively externalize session state to prevent context degradation on long-running tasks. The reset
that follows is the session's own `/compact` by default; `/clear` only in the cases listed below.

### When to Checkpoint
- At the 40% context-usage signal (primary trigger — see the Dumb Zone table above)
- After completing a major task or development phase
- When context window is saturating (repeated context, slower responses, premature summarization)
- Before natural break points (waiting for user input, CI results, review feedback)
- Before starting a fundamentally different task within the same session

### What to Write

Write a progress file (`.claude/progress.md` or project-specific location) containing:

- **Current task and phase** — what was being worked on, which workflow phase
- **Key decisions made** — with rationale (why this approach, not just what)
- **Files changed** — brief descriptions of what was modified and why
- **Blockers and open questions** — anything unresolved
- **Next steps** — ordered, specific, actionable items
- **Environment state** — branch name, uncommitted changes, pending PRs

### When to suggest `/compact`, and when `/clear`
- `/compact` (the session's own prompt): after writing a progress file; after a multi-step phase; when
  the conversation exceeds ~50 turns on one piece of work; at the threshold above
- `/clear`: when switching to an unrelated task; when the conversation went wrong and a progress file
  holds what matters; or when the next phase's whole input is on disk (a design document, `research.md`)
  and a fresh context gives a tighter result

### How to Resume from a Progress File
1. Read the progress file first
2. Verify environment state (`git status`, current branch, uncommitted changes)
3. Review key files listed in progress
4. Resume from the "Next steps" section
5. Do NOT re-do work listed as completed

## Compact Context Priorities

When context is auto-compacted, prioritize keeping:
- Architectural decisions and rationale
- Key file paths and their roles
- Lessons learned and error patterns
- User preferences and feedback
- Task progress and remaining work

Drop: full code blocks, raw tool output, intermediate search results, verbose file contents.

## Context Scaling by Project Size

### Small Projects (<10 source files, single language)
- Single root-level `CLAUDE.md` is sufficient
- No subagents needed — use main conversation for everything
- Skip TaskCreate for tasks with <3 steps
- Quality checks via direct Bash commands, no quality-guardian agent needed
- Document & Clear unnecessary for typical session lengths

### Medium Projects (10-100 source files, 1-2 languages)
- Add directory-specific `CLAUDE.md` in complex subdirectories (e.g., `src/api/CLAUDE.md`)
- Use subagents (Explore) for research while implementing in main conversation
- TaskCreate recommended for all multi-step work
- Use quality-guardian agent before commits
- Document & Clear pattern for sessions exceeding ~30 turns

### Large Projects (100+ source files, monorepo or multi-service)
- Agent Teams for parallel work across services or modules
- Multiple MCP servers for different concerns (GitHub, security scanning)
- Formal specs via SDD pipeline (`/hef.init` -> specify -> plan -> tasks -> implement)
- Per-service `CLAUDE.md` files with service-specific conventions
- Document & Clear mandatory — write progress after each phase completion
- Focused subagents (test-specialist, quality-guardian) to offload from main context

### Polyglot / Multi-Service Patterns
- Separate quality tooling configurations per service directory
- Agent Teams with language-specialized teammates
- Each service may have its own `CLAUDE.md` with service-specific build commands and conventions
