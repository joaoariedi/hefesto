# Rules & Quality Standards

[← back to README](../README.md)

## 📏 Rules

Modular policies loaded into every session — once copied into `~/.claude/rules/` (rules are not plugin components, so installing the plugin does not ship them; see [Install](install.md)):

| Rule | Covers |
|------|--------|
| 📝 `code-quality.md` | Function/file size limits (lines of code; `workflow.js` exemption), SOLID principles, Clean Code for Agents, testing, both Iron Laws (with rationalization tables), surgical changes, security test files |
| 🔀 `git-workflow.md` | Commit format, branch naming, co-authoring, staging |
| 🔄 `agent-workflow.md` | Phases 0–4 (18 steps) development workflow + CLAUDE.md template guidance (change maps, guardrails, trust boundaries, security posture) |
| 🛡️ `llm-security.md` | OWASP LLM Top 10 (2026) + Agentic Top 10 mitigations (prompt injection / goal hijack, excessive agency / tool misuse, data leakage, supply chain, memory & context poisoning) and the defense-in-depth layers |
| 📦 `context-management.md` | The 40% "Dumb Zone" threshold, Document & Clear pattern, compact context priorities, project scaling by size |

Reference guidance that isn't needed every session now loads on demand as **skills** (see [Skills](skills.md)): `quality-tooling`, `pipeline-security`, `mcp-security`, and `agent-collaboration` — only their one-line descriptions stay resident.

---

## 📊 Quality Standards

```
Functions:   < 50 lines
Files:       ≤ 500 lines of code (comments/blank lines excluded; workflows/workflow.js exempt)
Complexity:  < 10 (cyclomatic)
SOLID:       OCP + DIP violations flagged in changed code
Iron Laws:   verification before completion + root cause before fix
```

Enforced by the `code-quality.md` rule, the `quality-guardian` agent, a complexity *delta* gate in `quality-before-commit.sh` (where `lizard` is installed), and the `TaskCompleted` hook for the verification Iron Law. Test coverage follows project-configured thresholds.

---

