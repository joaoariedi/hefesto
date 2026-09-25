# Research Corpus & Acknowledgments

[← back to README](../README.md)

## 📚 Research Corpus

`reports/` holds the research behind the framework, split into fifteen files with no overlap between them — eleven single-subject topic files, one field report, two tool evaluations, and one harness review. It is the **"why" layer**: `.claude/rules/` states *what* to do, and `reports/` records the evidence, benchmark, or threat model that produced the rule. Where a finding is already codified, the report points at the rule with a `> **Codified in**` callout instead of restating it — so no text lives in two places.

| # | Subject | Codified in |
|---|---------|-------------|
| 01 | Context engineering fundamentals — WISC, context rot, prompt caching, scaling by project size | `context-management.md` |
| 02 | CLAUDE.md authoring — tiering, inclusion/exclusion criteria, four production-repo styles | `agent-workflow.md` |
| 03 | Agent topology — Skills vs Subagents vs Teams, orchestration patterns, memory architectures | the `agent-collaboration` skill |
| 04 | AI protocol stack — MCP, A2A, Akashik, AG-UI | the `mcp-security` skill (curation only) |
| 05 | Codebase retrieval at scale — cAST, HCAG | *not yet codified* |
| 06 | Security & DevSecOps — OWASP LLM Top 10, MCP controls, Policy-as-Code | `llm-security.md`, the `mcp-security` & `pipeline-security` skills |
| 07 | Quality gates — lifecycle hooks, pre-commit/pre-push, CI/CD, testing | the `quality-tooling` skill, `code-quality.md` |
| 08 | Project organization & delivery — release notes, IDEA.md, containerization | *not yet codified* |
| 09 | Fabric — prompt orchestration, evaluated but **not adopted** | *not yet codified* |
| 10 | Deterministic effort estimation — Pfeiffer Contribution Complexity, Epoch, LOCOMO | `task-effort-estimation` skill |
| 11 | Claude Code harness capabilities — skill loading rules, invocation control, `context: fork`, bundled skills | the `.claude/skills/` layer |
| 12 | Field report — `workflow` on a real two-repo feature: multi-repo roots, 429/529 overload, transient-failure aborts | `workflows/workflow.js` (multi-repo opts, bounded retry, concurrency cap) |
| 13 | Graft — code-context graph for agents, measured against the graphify lane, evaluated but **not adopted** | *not yet codified* |
| 14 | Harness review 2026-09 — toolbox, drift, and the evidence behind each change; the `harness-review-tiers` program (6.1 → 6.2 → 7.0) | `hef.verify`, `hef.review`/`hef.pr`, the implement-phase test guard, the lifecycle hooks, `llm-security.md` |
| 15 | Jev — a hosted state-to-decision model, mapped against where the framework spends and enforces, evaluated but **not adopted** | *not yet codified* |

Files 05, 08, 09, and 13 carry no pointers because their subject is genuinely unadopted, and each says so in its own header — an unadopted idea is recorded as prior art, not smuggled in as current practice.

Every report opens with MADR frontmatter — `status: proposed | accepted | rejected | deprecated | superseded` and `date`, plus `supersedes:` when it replaces another — so an agent can tell a live decision from a dead one without inferring it from prose (a fail-open parser once misread 59 of 98 records that way). `/hef.adr` creates a new one; the smoke suite rejects a report without a valid status. Statuses today: 05 and 08 `proposed` (research not yet codified), 09, 13, and 15 `rejected` (evaluated, not adopted), the rest `accepted`.

The five original research documents that produced this corpus are no longer carried in the tree — the topic files above supersede them. They remain recoverable from git history (`git show b515e2f:reports/sources/`) if a claim ever needs tracing back to the document that made it.

---

## 🙏 Inspirations & Acknowledgments

This framework was shaped by patterns observed in several projects:

| Project | Author | Key Contributions |
|---------|--------|-------------------|
| [superpowers](https://github.com/obra/superpowers) | Jesse Vincent | Iron Laws, rationalization prevention tables, Socratic brainstorming with hard gate, verification-before-completion, systematic debugging methodology, evidence-first workflow |
| [spec-kit](https://github.com/github/spec-kit) | GitHub | Spec-driven development (SDD) pipeline — the specify → plan → tasks → implement workflow that forms the framework's core |
| [FrankYomik](https://github.com/akitaonrails/FrankYomik) | Fabio Akita | Cross-cutting change maps, trust boundary documentation, domain-first CLAUDE.md structure |
| [FrankSherlock](https://github.com/akitaonrails/FrankSherlock) | Fabio Akita | "What NOT to change" guardrails, architecture-as-constraints pattern, `_`-prefixed research directories |
| [FrankMD](https://github.com/akitaonrails/FrankMD) | Fabio Akita | AGENTS.md as tool-agnostic contributor guide, concise do/don't lists |
| [FrankMega](https://github.com/akitaonrails/FrankMega) | Fabio Akita | Lefthook parallel hooks, security-specific test files, pre-commit vs pre-push separation, staged-files-only linting |
| [speckit-agent-skills](https://github.com/dceoy/speckit-agent-skills) | dceoy | `hef.baseline` concept — reverse-engineering specs from existing code |
| [speckit-wiggum-toolkit](https://github.com/leonardoFu/speckit-wiggum-toolkit) | leonardoFu | `speckit.research` and `speckit.reflect` concepts — formalized research and retrospective phases |

---

