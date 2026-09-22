# Hefesto v7.0

## Custom Agents

| Agent | Role | When to Use |
|-------|------|-------------|
| **test-specialist** | Testing | After implementation, comprehensive tests |
| **quality-guardian** | QA | Before any commit, PR, or merge |
| **code-reviewer** | Code review | Before PR creation, spec compliance + quality |
| **review-coordinator** | PR management | Creating PRs, managing review workflows |
| **forensic-specialist** | Security | Security audits, suspicious patterns |
| **repo-scout** | One-shot recon | A targeted question about a repo OTHER than this one; returns a citation-backed digest, not a transcript |

For general tasks, use built-in agents: `Explore` (codebase search), `Plan` (architecture), `general-purpose` (implementation).

## Task Management API
- **TaskCreate**: Use for any task with >2 steps (MANDATORY)
- **TaskUpdate**: Mark exactly ONE task "in_progress" at a time; mark "completed" immediately after
- **TaskGet**: Read full task details before starting work
- **TaskList**: Check progress and find next available tasks

## Core Rules
1. Do what has been asked; nothing more, nothing less
2. NEVER create files unless absolutely necessary for achieving the goal
3. ALWAYS prefer editing existing files over creating new ones
4. NEVER proactively create documentation files (*.md) unless explicitly requested
5. Only commit when explicitly requested by the user
6. Follow existing project patterns rather than imposing new conventions
7. Keep responses concise and focused on the task
8. Use `git -C <directory>` instead of `cd <directory> && git` to avoid zoxide conflicts
9. Version declaration is deprecated in docker compose, do not add it

## Performance & Model Selection
- **Fast Mode**: Toggle with `/fast` for faster Opus output on quick iterations, bug fixes, and exploration (uses Opus, not a smaller model)
- **Ultrathink**: Type `ultrathink` in any prompt to bump that turn to high reasoning effort (reverts after response)
- Effort levels: `max` (via `/model` only) > `high` (ultrathink keyword) > `medium` (default) > `low`
- **Model-tier routing (deliberate policy)**: aliases name tiers, not models. The rule is **cheap generation, expensive judgment** — pin `fable` only where the output is short, it gates everything downstream, and nothing later re-checks it: `speckit.brainstorm|specify|clarify|review|constitution`, `code-reviewer`, `forensic-specialist`. Everything that reads a lot to produce a draft someone reviews is `opus` (Fable costs 2x on input volume, which is where the spend goes): `speckit.plan|tasks|checklist|analyze|baseline|implement|verify|fix`, `hef.agent|quality|security-scan|mutate`, all workflow spawns. `sonnet` is mechanical: `speckit.init`, `hef.pr|review|release|doctor|adr|context`, `repo-scout` (`hef.review`/`hef.pr` only dispatch a `fable`/`opus` agent, so the command itself is mechanical). Note `/fast` is priced at Fable's rate — it buys throughput, not savings. Commands, agents, and workflow spawns pin tiers via alias frontmatter/opts
- NEVER put a concrete model ID in framework frontmatter or workflow opts — each environment binds the aliases: personal `claude` uses the built-in mappings + the Fable 5 session default; `claude-bedrock()` remaps them via `ANTHROPIC_DEFAULT_{FABLE,OPUS,SONNET,HAIKU}_MODEL` to Bedrock-available models. An alias a backend can't serve silently falls back to the session model — benign by design
- Use `haiku` for lightweight tasks (search, simple edits); `sonnet` for standard work; `opus` for complex architecture

## Multi-Environment Workflows
- **Remote Control**: Continue local sessions from any device via claude.ai/code
- **Teleport**: Pull cloud/web sessions into local terminal with `/teleport`
- Sessions maintain full context across surfaces (terminal, IDE, web, mobile)

## Tool Usage
- Use Read to understand existing code before suggesting modifications
- Use Grep to find similar implementations
- Use Glob to discover project structure
- Use Bash only for system commands and terminal operations
- Use EnterPlanMode/ExitPlanMode for complex features requiring user approval
- For spec-driven development (SDD), use `/speckit.init` to bootstrap, then: brainstorm → specify → plan → (clarify) → review → tasks → (checklist, analyze) → implement → **verify** (`/speckit.verify`: FR → tests mechanically, then spec-compliance review) → `/hef.quality` → `/hef.review` → `/hef.pr`
- For a LARGE task list, run `hefesto:speckit-workflow` instead of `/speckit.implement`: it executes tasks.md as a deterministic Workflow — phase order enforced in code, independent tasks in parallel, every task adversarially verified by agents that did not write it. It must be invoked by that full namespaced name; a bare `speckit-workflow` does not resolve. Run it only AFTER the human gates (clarify/review/checklist), which a workflow cannot perform.
- For trivial changes (typos, config), use `/speckit.fix` to bypass the full pipeline
- For brownfield projects, use `/speckit.baseline` to reverse-engineer specs from existing code

See `.claude/rules/` for detailed policies on code quality, git workflow, agent coordination, and language-specific tooling.
# graphify
- **graphify** (`.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.
