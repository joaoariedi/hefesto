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

### 🌐 Multi-Environment Workflows

- 📱 **Remote Control** — start work locally with `claude`, resume from any device via claude.ai/code
- 🚀 **Teleport** — pull cloud/web sessions into local terminal with `/teleport`
- 🔄 Sessions maintain full context across terminal, IDE, web, and mobile

---

