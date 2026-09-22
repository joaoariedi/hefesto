# Skills

[← back to README](../README.md)

## 🧠 Skills

A skill is a **directory containing `SKILL.md`**, never a bare `.md` file — a bare `foo.md` is silently ignored and never loads. This plugin ships them at `skills/<name>/SKILL.md`; in your own project they go under `.claude/skills/<name>/SKILL.md`. Verify with the `/` menu: a skill that does not appear there is not registered.

The framework ships three **action skills** — things a person invokes — and four **knowledge skills** promoted from always-loaded rules. Since 7.0 the knowledge skills are `user-invocable: false`: Claude loads them when relevant, but they no longer appear as commands in the `/` menu, because `/quality-tooling` was never a meaningful action for a person to take. The invocable surface is the toolbox; knowledge stays knowledge.

| Skill | Purpose | Who invokes it |
|-------|---------|----------------|
| 🐛 `systematic-debugging` | 4-phase root cause investigation (read → reproduce → evidence → fix) with Iron Law | You or Claude — proactively on bugs |
| 📐 `task-effort-estimation` | Deterministic change sizing — Pfeiffer Contribution Complexity from git metadata, plus AI-native risk flags | You or Claude — on "how big is this?"; `/hef.agent` uses it to route |
| ⚡ `performance-audit` | N+1 queries, blocking I/O, memory leaks, algorithm complexity | You — explicit only |
| 🔧 `quality-tooling` | Per-language lint/format/type-check/test/security commands, AI-defect gates, mutation ratchet, RTK, Lefthook | Claude only (knowledge) |
| 🔐 `pipeline-security` | SAST/DAST/SCA/secrets/ASPM tooling by team size, budget, and pipeline tier | Claude only (knowledge) |
| 🔌 `mcp-security` | MCP server auth, tool-poisoning defense, and the skill/plugin/agent vetting checklist | Claude only (knowledge) |
| 🤝 `agent-collaboration` | Subagents vs teams vs workflows, one-shot design rules, team composition | Claude only (knowledge) |

**Deliberately NOT reimplemented.** A project skill *overrides* a bundled one of the same name, so shipping a `security-review` skill would shadow Claude Code's own — which is better. Use the built-ins:

| Instead of a custom skill | Use the built-in | Why |
|---|---|---|
| verification-before-completion | `/verify` | It builds and drives the real app rather than settling for a green typecheck. The **Iron Law** survives as a *rule* in `code-quality.md` — a rule is always in context, whereas a skill only loads when invoked. |
| security-review | `/security-review` | Full branch review. `/hef.security-scan` remains for the fast, diff-only pass. |
| context-analysis | `/hef.context` | The command already carries the methodology and injects live git data. |
| spec-template | `/speckit.specify` | The Given/When/Then patterns now live in the command itself. |

`task-effort-estimation` deliberately reports a **complexity score and risk flags, never an hour count**. Effort under AI assistance is bimodal — up to 78% of high-complexity *isolated* features land under a quarter of expected effort, while ~22% of *low*-complexity tasks needing non-local context exceed 180%. So it flags the small diff with high coupling, which is the shape of work a naive estimate waves through. Hours only appear once `.claude/effort-calibration.json` maps observed scores to real recorded durations for your project.

---

