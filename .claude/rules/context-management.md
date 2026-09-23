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
| 40–60% | **Transition** | Finish the current coherent unit of work, then `/checkpoint` + `/compact` + `/clear`. Do not start a new phase here. |
| 60%+ | **Dumb Zone** | Stop. Write a progress file, `/clear`, and resume from the checkpoint. Continuing past this point costs more than the reset. |

**Cache-cost caveat.** Aggressive `/clear` cycles invalidate the prompt cache. Prefer
**one decisive reset at ~40%** over many partial compactions. Target 1–2 resets per long
session, not 5+.

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

Proactively externalize session state to prevent context degradation on long-running tasks.

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

### When to Suggest /clear
- After writing a progress file
- When conversation exceeds ~50 turns on complex implementation
- After completing a multi-step implementation phase
- When switching between unrelated tasks in the same session

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
