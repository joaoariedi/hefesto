---
status: accepted
date: 2026-07-12
---

# CLAUDE.md Authoring

How to write the file that Claude Code injects into every session: what belongs in it, what must be kept out, how large it may grow, and how to tier it across a repository. Evidence comes from Anthropic's published guidance plus four production repos whose CLAUDE.md files range from 5 to ~400 lines.

This file does **not** cover: context-window mechanics, WISC, prompt caching, or the Document & Clear pattern (see `01-context-engineering-fundamentals.md`); lifecycle hooks of any kind (see `07-quality-gates.md`); the security substance of trust boundaries — threat model, sanitization, hostile-input handling (see `06-security-devsecops-for-agents.md`); release-notes, IDEA.md, and research-doc conventions (see `08-project-organization-delivery.md`).

**Sources:** *AI Context Engineering for Secure Development* §Multi-Tier Contextual Guidance with CLAUDE.md; *Frank Repos Best Practices Analysis* §1 AI Configuration Files, §9 Recommended Enhancements
**Codified in:** `.claude/rules/agent-workflow.md` — "CLAUDE.md Template Guidance" (partial: section patterns only, not sizing or tiering)

## What CLAUDE.md Is

The CLAUDE.md file functions as the foundational system prompt injected into every Claude Code session.18 It acts as the project's permanent memory card, ensuring that the model adheres to repository-specific rules that cannot be inferred from the source code alone.10

That framing sets the editorial test for every line: **would the agent get this wrong if the line were absent?** Anything the model can deduce from reading the code is not memory-card material — it is context dilution.

## The Size Ceiling and the Monolithic Mega-Prompt

Overloading the file leads to the "Monolithic Mega-Prompt" anti-pattern, causing the agent to ignore critical instructions or experience contextual confusion.19

> Best practices dictate that the root CLAUDE.md should be strictly limited — **ideally under 100 instructions or 300 lines** — focusing purely on universal, project-wide directives.19

This is the single hardest number in the whole subject and the one most often violated. Note the tension with the empirical data below: FrankMega's ~400-line single file exceeds the ceiling. It works because it is a single-stack Rails app where nearly every rule is genuinely universal to the repo — but it is the outer bound, not a target. A polyglot repo hitting 400 lines should tier, not append.

## Progressive Disclosure via Multi-Tier Structure

To maintain high signal-to-noise ratios, configuration should employ **progressive disclosure** via a multi-tier repository structure. Domain-specific rules belong in subdirectory-level CLAUDE.md files — frontend styling rules in `src/ui/CLAUDE.md`, database schema constraints in `src/db/CLAUDE.md`. Claude dynamically loads these child configurations **only when interacting with the respective directories**, preserving the token budget while ensuring contextual relevance.10

The consequence for authoring: the root file carries only what is true everywhere. A rule that applies to one directory is a *cost* on every session that never touches that directory.

CLAUDE.md also supports **import syntax** (e.g. `@path/to/import`), enabling developers to dynamically reference external files like `package.json` without manually duplicating content.10 Prefer an import over a transcription — a transcribed dependency list is stale the moment someone runs `npm install`.

## Inclusion vs Exclusion Criteria

The curation of content requires ruthless prioritization. Information that adds minimal value, or that the model already possesses, must be excluded to prevent context dilution.

| Inclusion Criteria for Context Files | Exclusion Criteria for Context Files |
| :---- | :---- |
| Project-specific code style rules differing from language defaults (e.g., enforcing ES Modules over CommonJS).10 | Standard language conventions the foundational LLM already understands (e.g., basic Python PEP 8 syntax).10 |
| Testing instructions, preferred test runners, and specific environment variables required for successful local builds.10 | Long tutorials, historical context, or comprehensive file-by-file descriptions of the entire codebase.10 |
| Repository etiquette, including branch naming conventions and pull request formatting requirements.10 | Volatile information that changes frequently or detailed API documentation (which should be linked instead).10 |
| Bash commands required for obscure or custom build processes that the agent cannot autonomously deduce.10 | Vague, self-evident mandates such as "write clean code" or "ensure maximum security".10 |

## Emphasis Formatting

To improve adherence, instructions must be formatted for attention. Utilizing emphasis tags such as **"IMPORTANT"** or **"YOU MUST"** helps guide the model's attention toward non-negotiable constraints.10 Reserve them: if every rule is IMPORTANT, none is.

## Four Production Styles

All four repos analyzed (2026-03-30) have substantial AI context files. The common structure across all of them prioritizes: **what to run**, **where things are**, **what patterns to follow**, and **what not to do**.

| Repo | Stack | CLAUDE.md size | Approach |
|------|-------|---------------|----------|
| FrankYomik | Python + Go + Flutter | ~250 lines | Domain-first |
| FrankSherlock | Rust + React/TS (Tauri v2) | ~300 lines | Architecture-heavy |
| FrankMD | Rails 8 + Stimulus | 5 lines + ~200-line AGENTS.md | Split |
| FrankMega | Rails 8 + Stimulus | ~400 lines | Comprehensive single file |

### FrankYomik (~250 lines) — Domain-First

Structure: system overview → repo map → runtime flows → cache model → API surface → local dev → config → trust boundaries → security notes → versioning → debugging guide → editing guidance → job reliability.

Distinguishing sections:
- Opens with "what the system does" and names the 3 pipelines — orientation before detail.
- **Repo map**: every important file with a one-line purpose. Cheap, high-yield: it is precisely the knowledge an agent cannot deduce without reading everything.
- **Runtime flow narratives** walking through the Kindle and Webtoon flows step by step.
- **Cross-cutting change maps**: "If you change cache paths, update both `server/cache.go` and `server/worker/page_cache.py`." "If you change the job payload, check `server/handlers.go`, `server/worker/consumer.py`, and `client/lib/providers/jobs_provider.dart`."
- **Trust boundaries**: an explicit list of hostile input surfaces (image uploads, metadata fields, websocket clients, WebView pages, cache paths). As a *section pattern*, this is the highest-value thing in the file; for the security substance behind it, see `06-security-devsecops-for-agents.md`.
- **Job reliability**: documents retry/recovery layers across the system.

> **Codified in** `.claude/rules/agent-workflow.md` — the Cross-Cutting Change Maps and Trust Boundary Documentation templates are derived from this repo.

### FrankSherlock (~300 lines) — Architecture-Heavy

Structure: overview → repo layout → tech stack → build/test → module table → architecture principles → coding conventions → important paths → testing → migration rules → release workflow → what NOT to change.

Distinguishing sections:
- **Module table**: one-line purpose per Rust module.
- **Architecture principles as named constraints**: read-only, incremental, move-aware, resilient, local-only, multi-OS. Naming a constraint makes it citable in review.
- **Coding conventions per language**: Rust error handling (`thiserror`, never `.unwrap()`), TS naming (camelCase matching Rust's `serde(rename_all)`). Note this passes the inclusion test — it is *divergence from the language default*, not a restatement of it.
- **Database migration rules**: never edit shipped migrations, append-only ALTERs, test fresh + existing DBs.
- **"What NOT to change"**: explicit guardrails — "never remove FTS5 virtual table", "keep `csp: null` in `tauri.conf.json`".

> **Codified in** `.claude/rules/agent-workflow.md` — the "What NOT to Change" Guardrails template is derived from this repo.

### FrankMD — Split CLAUDE.md + AGENTS.md

CLAUDE.md is **5 lines** — just commands and critical gotchas. AGENTS.md (~200 lines) is the full contributor guide, marked **"tool-agnostic"**: it works for Claude, Cursor, Copilot, or human contributors.

AGENTS.md structure: overview → commands → architecture (backend + frontend + tests) → do list → don't list → PR checklist.

Distinguishing sections:
- **Do/Don't lists**, exceptionally clear and concise.
- **Config pattern warning**: "Always use `Config.new.get('key')`, never read `ENV` directly."
- **Test patterns**: "Use Mocha stubs raising `Errno::EACCES`, not `chmod`."
- **PR checklist** with concrete pass criteria (test counts, tool commands).

This is the only style that solves the multi-tool problem. If a team runs more than one coding agent, duplicating guidance per vendor file is a maintenance trap; a single AGENTS.md with a thin vendor-specific CLAUDE.md pointing at it is the cheaper shape.

### FrankMega (~400 lines) — Most Comprehensive Single File

Structure: overview → commands → architecture (DB, auth, authz, storage, jobs, real-time) → coding conventions (models, controllers, routes, views, JS, tests, migrations, jobs, security) → env vars → pre-commit checklist.

Distinguishing sections:
- **Model ordering convention**: associations → encryption → normalizations → validations → callbacks → scopes → public methods → private methods.
- **Controller template**: auth config → before_actions → actions → private methods.
- **Security section**: rate limiting (Rack::Attack), IP banning, headers (secure_headers), cookies, filename sanitization, Cloudflare proxying.
- **"Never do" list**: expose internal IDs, allow unsafe-eval in CSP, skip CSRF, use params without strong parameters.
- **9-item pre-commit checklist**: tests, rubocop, brakeman, bundler-audit, factories, controller tests, migrations, theme tokens, no hardcoded secrets. As a CLAUDE.md section this gives the agent a concrete self-verification list; the enforcement mechanism behind it belongs to `07-quality-gates.md`.

The ordering conventions are the interesting export. They are deterministic, mechanically checkable, and eliminate an entire class of AI-generated diff noise (methods landing in arbitrary places), at a cost of roughly two lines each.

## Section Patterns Worth Naming

Synthesizing across all four, the reusable inventory:

| Pattern | Origin | Why it earns its tokens |
|---|---|---|
| Repo map (file → one-line purpose) | FrankYomik | Cannot be deduced without reading every file |
| Cross-cutting change maps | FrankYomik | Prevents partial updates across services |
| Trust boundary list | FrankYomik | Tells the agent where to apply validation → `06` |
| Module table | FrankSherlock | Same as repo map, at module granularity |
| Named architecture principles | FrankSherlock | Makes constraints citable |
| "What NOT to change" guardrails | FrankSherlock | The only reliable way to protect load-bearing weirdness |
| Do/Don't lists | FrankMD | Highest instruction density per line |
| Per-language ordering conventions | FrankMega | Deterministic, kills diff noise |
| Security posture statement | FrankMega | Calibrates every downstream security decision → `06` |
| Pre-commit checklist | FrankMega | Agent-verifiable definition of done → `07` |

## Not Yet Adopted

From *Frank Repos Best Practices Analysis* §9, items under this subject the framework has not implemented:

| Enhancement | Source Repo | Priority |
|---|---|---|
| Recommend AGENTS.md for tool-agnostic contributor guides | FrankMD | Medium |
| Add model/controller ordering conventions per language | FrankMega | Medium |

The three High-Priority CLAUDE.md items from §9 — Cross-cutting change maps, "What NOT to change" guardrails, and Trust boundaries — **have** been adopted, and now live in `.claude/rules/agent-workflow.md` under "CLAUDE.md Template Guidance". This file is the evidence behind them, not a second copy of them.

Neither remaining item is captured anywhere in `.claude/rules/`. AGENTS.md is the cheaper of the two to adopt and the only one that addresses a problem the framework currently has no answer for (multi-tool teams).
