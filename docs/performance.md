# Performance & Reasoning

[← back to README](../README.md)

## ⚡ Performance & Reasoning

### 🧠 Ultrathink

Type `ultrathink` in any prompt to bump that turn to **high reasoning effort**. Use it for:

- 🏗️ Complex architectural analysis or ambiguous requirements
- 🔒 Security-sensitive code reviews
- 🐛 Debugging race conditions or subtle bugs
- 🔄 Multi-file refactoring decisions

The effort boost reverts after the response — no persistent mode change needed.

### 🎛️ Model Selection

| Mode | How | Best For |
|------|-----|----------|
| 🟣 **`fable`** | Frontmatter `model: fable` | Judgment gates — short output that gates everything downstream: `hef.brainstorm\|spec\|clarify\|review\|constitution`, `code-reviewer`, `forensic-specialist` |
| 🔴 **`opus`** | Frontmatter `model: opus` | Drafts that read a lot and get reviewed: `hef.plan\|tasks\|implement\|verify\|fix\|babysit\|quality\|scan\|mutate…`, `quality-guardian`, `test-specialist`, `review-coordinator`, all workflow spawns |
| 🟡 **`sonnet`** | Frontmatter `model: sonnet` | Mechanical: `hef.init\|pr\|release\|doctor\|adr\|context\|status\|orchestrate`, `repo-scout`, `truth-scout` (the arena overrides its tier per spawn) |
| ⚡ **Fast Mode** | Toggle with `/fast` | Faster output on quick iterations; priced at Fable's rate |
| 🧠 **Ultrathink** | Add `ultrathink` to prompt | Deep reasoning on a single turn |

The rule is **cheap generation, expensive judgment** (`.claude/CLAUDE.md`). Aliases name tiers, never
model ids; each environment binds them (`claude-bedrock()` remaps them to Bedrock models). `haiku` is
available but no framework component pins it.

Effort levels: `max` (via `/model` only) > `high` (ultrathink) > `medium` (default) > `low`

### 📦 Context Management

For long-running sessions, the framework uses the **Document & Clear** pattern:

1. 💾 **Checkpoint** — write session state to a progress file (decisions, files changed, next steps)
2. 🧹 **Clear** — run `/clear` to reset the context window
3. ▶️ **Resume** — read the progress file and continue from "Next steps"

See `.claude/rules/context-management.md` (the 40 % "Dumb Zone" checkpoint threshold) for detailed guidance and project scaling strategies (small/medium/large).

### 🧾 Compact prompts per pane

`/compact` keeps whatever its instructions name and drops the rest, so each long-lived pane gets a
prompt shaped to what it **owns**. The shared truth (the board, the ledger, the PRs, the spec files)
is already on disk, so a pane keeps **pointers** — ids, paths, PR numbers, block kinds — never the
payload. Between items a pane runs `/clear`, not `/compact` (README §5: a pane never does a stage's
work in its own context). These prompts are for staying coherent *within* a stretch of work.

**General (any session)**

```text
/compact **Keep**: architectural decisions, key file paths, lessons learned, debugging insights, user preferences, task progress, error patterns and their solutions, API/config conventions discovered. **Drop**: full code blocks, raw tool output, file contents, search results, intermediate exploration steps. **Goal**: Prepare the context to keep working in the tasks in progress.
```

**🎛 Orchestrator** — the board, the queue, the human gates (`/hef.orchestrate`, `/hef.status`)

```text
/compact **Keep**: the board's state by item id (todo / owned / blocked) and which pane owns each block kind, every owned ledger entry with its session and repo, every blocked entry with its kind and the human command that clears it, decisions the user relayed and their rationale, dispatch order and why, today's spend against daily_usd_cap, routing refusals (items with no or two repo: lines) still waiting on a person, the pane names and the external-board/branch config in effect. **Drop**: item bodies (re-read with status-board.sh --item), dry-run argv lines, ledger JSON dumps, worker and verifier summaries already transcribed into the ledger, status-board output. **Goal**: Prepare the context for the next dispatch pass — what is runnable, what waits on whom.
```

**📐 Planner** — spec → plan → review → tasks (`/hef.orchestrate --stage plan`, `/hef.spec`, `/hef.plan`, `/hef.review`)

```text
/compact **Keep**: each item in the plan stage by id with its spec directory, the first missing artifact (spec / clarify / plan / review / tasks), open [NEEDS CLARIFICATION] markers and the answers already given, plan-review verdicts and the numbered changes still to apply, design decisions with their rationale, arena disagreements that became questions, constitution concerns raised. **Drop**: the text of spec.md, plan.md, research.md and tasks.md (they are on disk), truth-scout digests, file reads and grep output from exploration, reviewer reports already applied. **Goal**: Prepare the context to resume each item's plan pipeline at its first missing artifact.
```

**🔨 Builder** — implement → verify → quality → review → PR (`/hef.implement` or `hefesto:workflow`, `/hef.verify`, `/hef.quality`, `/hef.review`, `/hef.pr`)

```text
/compact **Keep**: the item id, branch, worktree and spec directory, the task ids done and open in tasks.md, each failing test by name with its first error line and the root cause found, fixes made and why, gate findings still open (blocking vs advisory) and the mutations that survived, files changed and the reason for each, conventions discovered in this codebase. **Drop**: code blocks, diffs, full test and linter output, file contents, exploration and search results, gate reports already acted on. **Goal**: Prepare the context to finish the current item through its gates to a PR — no new item before /clear.
```

**🚀 Deployer** — PRs to the merge gate, promotions, releases (`/hef.orchestrate --stage deploy`, `/hef.babysit`, `/hef.release`)

```text
/compact **Keep**: every PR being watched with its number, head sha, babysit verdict and fixes pushed (commit hashes), review threads waiting on a person, the merge queue order the user set, each merged entry's position along the environment chain (ledger.sh where), promotion PRs (push:false — watched, never fixed), the release in progress with its version and which steps are done (PR, tag, GitHub Release, deploy), CI incidents and whether they were infrastructure or code. **Drop**: CI logs (keep the failing job and its first error line), review comment bodies already answered, diffs, CHANGELOG text, gh and pr-watch JSON output. **Goal**: Prepare the context to keep every open PR moving to its merge gate and finish the release in progress.
```

### 🌐 Multi-Environment Workflows

- 📱 **Remote Control** — start work locally with `claude`, resume from any device via claude.ai/code
- 🚀 **Teleport** — pull cloud/web sessions into local terminal with `/teleport`
- 🔄 Sessions maintain full context across terminal, IDE, web, and mobile

---

