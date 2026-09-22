---
status: rejected
date: 2026-07-12
---

# Fabric: Prompt Orchestration as a Complementary Layer

Everything the corpus has to say about [danielmiessler/fabric](https://github.com/danielmiessler/fabric) (v1.4.437, 40k+ stars, Go, MIT): what it is, where it would slot into the AI Development Framework v4.4, and whether it is worth adopting. **Adoption status: evaluated, not adopted.** Nothing described here is currently wired into the framework — no rule, hook, agent, or skill invokes Fabric today, and this file describes a proposal, not the status quo.

This file does **not** cover the threats that Fabric's security artifacts address (OWASP LLM Top 10, MCP security posture, trust boundaries — see `06-security-devsecops-for-agents.md`), the hook and CI mechanisms Fabric would sit behind (see `07-quality-gates.md`), or context-engineering theory such as WISC and prompt caching (see `01-context-engineering-fundamentals.md`).

**Sources:** Fabric Integration Analysis (entire report, §4 and §8 merged)
**Codified in:** Not yet codified — Fabric is evaluated here, not adopted.

## What Fabric Is

Fabric is an open-source CLI tool that targets what its author calls AI's **integration problem**: AI capability is abundant, but weaving it into daily workflows remains friction-heavy. Fabric's answer is to organize prompts into a curated, crowdsourced, versioned library called **Patterns** and expose them as Unix-pipe-friendly commands.

The guiding philosophy: *break problems into discrete components, then apply AI to each component one at a time.*

It ships as a single Go binary with no runtime dependencies beyond an API key. Config lives at `~/.config/fabric/`.

```
stdin / URL / YouTube / clipboard
    → fabric --pattern <name> --model <model> [--strategy <strategy>]
    → stdout / file / clipboard
```

A Pattern becomes the system prompt. User text becomes the user turn. Output streams to stdout.

## Architecture

### The Pattern System (251 built-in patterns)

Each pattern is a Markdown file at `data/patterns/<name>/system.md` with a consistent structure: `# IDENTITY and PURPOSE` (assigns the model a role), `# STEPS` (ordered instructions), `# OUTPUT INSTRUCTIONS` (word counts, sections, bullet formats), and `# INPUT` (placeholder for user content).

| Category | Examples |
|----------|---------|
| **Code & Dev** | `review_code`, `explain_code`, `create_coding_feature`, `summarize_git_diff`, `write_pull-request`, `generate_code_rules` |
| **Security** | `analyze_malware`, `create_stride_threat_model`, `write_semgrep_rule`, `write_nuclei_template_rule`, `create_sigma_rules`, `analyze_incident`, `analyze_logs` |
| **Content Extraction** | `extract_wisdom`, `extract_ideas`, `extract_insights`, `extract_recommendations` |
| **Summarization** | `summarize`, `summarize_paper`, `summarize_meeting`, `summarize_lecture`, `create_micro_summary` |
| **Writing** | `write_essay`, `improve_writing`, `improve_academic_writing`, `humanize`, `fix_typos` |
| **Analysis** | `analyze_claims`, `find_logical_fallacies`, `analyze_paper`, `rate_content` |
| **Visualization** | `create_mermaid_visualization`, `create_conceptmap`, `create_excalidraw_visualization` |

**Custom patterns** are stored separately from upstream, survive `fabric --updatepatterns`, and take priority over built-in patterns with the same name.

### Multi-provider AI router

Fabric natively supports 20+ AI providers through dedicated Go plugins. Tier 1 native plugins cover OpenAI, Anthropic, Google Gemini, Ollama, Azure OpenAI, Azure Entra ID, Amazon Bedrock, Vertex AI, LM Studio, Perplexity, and Microsoft 365 Copilot; OpenAI-compatible endpoints cover Groq, Mistral, OpenRouter, Together, DeepSeek, Cerebras, Venice AI, GitHub Models, GrokAI, Novita, SiliconCloud, and more.

Model selection is per-invocation, or per-pattern via environment variables:

```bash
fabric -m claude-sonnet-4-5 -V anthropic -p summarize

export FABRIC_MODEL_PATTERN_SUMMARIZE=anthropic|claude-sonnet-4-5
```

### Reasoning strategies

A layer on top of patterns that modifies how the model reasons, applied via `--strategy <key>` alongside any pattern.

| Strategy | Key | Description |
|----------|-----|-------------|
| Chain of Thought | `cot` | Step-by-step reasoning |
| Chain of Draft | `cod` | Iterative drafting with minimal notes |
| Tree of Thought | `tot` | Multiple reasoning paths, select best |
| Atom of Thought | `aot` | Break into smallest independent sub-problems |
| Self-Refinement | `self-refine` | Answer → critique → refined answer |
| Reflexion | `reflexion` | Answer → brief critique → refined answer |

### Key integrations and the shell alias system

- **YouTube:** `fabric -y <URL>` extracts transcripts, timestamps, comments, metadata via `yt-dlp`
- **Web scraping:** `fabric -u <URL>` converts webpages to Markdown via Jina AI
- **REST API:** `fabric --serve` exposes all functionality on `:8080` with Swagger docs
- **Ollama compatibility mode:** `fabric --serve --serveOllama` — patterns appear as "models" to any Ollama client
- **Web search:** `--search` enables built-in web search for supported providers
- **Speech-to-text:** `--transcribe-file` via OpenAI Whisper API
- **Image generation:** `--image-file` for model-backed image generation

Fabric can also generate one shell alias per pattern, so `summarize` becomes equivalent to `fabric --pattern summarize` — turning 251 patterns into 251 standalone CLI commands.

## Complementarity: Fabric vs. the AI Development Framework

The two tools occupy **different layers** of the AI-assisted development stack and have minimal overlap.

| Dimension | AI Development Framework v4.3 | Fabric |
|-----------|-------------------------------|--------|
| **Execution model** | Interactive, multi-turn, agentic | Single-shot, one pattern per invocation |
| **Context** | Stateful sessions with memory, tasks, specs | Stateless (no session memory) |
| **Scope** | Full SDLC (spec → plan → implement → test → review → merge) | Individual analysis/transformation tasks |
| **AI provider** | Claude only (via Claude Code) | 20+ providers, hot-swappable |
| **Prompt management** | Rules + skills + agents (Markdown, loaded into system prompt) | Patterns (Markdown, used as system prompt) |
| **Quality enforcement** | Hooks, Iron Laws, quality gates, layered defense | None (output only) |
| **Integration style** | Deep IDE/terminal integration with file system access | Unix pipe philosophy, no file system mutation |

**Key insight:** Fabric is a prompt execution engine. The framework is an orchestration and governance layer. They are complementary, not competing.

## The Boundary Rule

This is the thesis that governs every integration below. If you take one thing from this file, take this.

**Fabric = stateless pre-processing. Claude Code = stateful development.**

```
Fabric output  ──save to file──►  .specify/ or docs/  ──read as data──►  Claude Code session
                    │                                                           │
                    │         NEVER pipe directly as instructions               │
                    └───────────────── ✕ ──────────────────────────────────────┘
```

Fabric output always flows *into* the framework as data files, never the reverse. Per the framework's LLM01 prompt-injection mitigations (see `06-security-devsecops-for-agents.md`), all external input — including Fabric output — is untrusted data. Save to files first, then reference within a session.

This boundary preserves the governance model: hooks still enforce deterministic quality gates, Iron Laws still govern verification and debugging, and quality-guardian still validates before integration. Fabric adds breadth (more patterns, more providers, more input sources) without undermining depth (statefulness, quality enforcement, governance).

## Seven Integration Areas

Each area maps to a phase of the framework's 4-phase, 18-step pipeline, or spans phases.

### 1. Knowledge extraction for context engineering (Phase 1, Steps 1–4)

Fabric's highest-value use is as a **context preparation tool** that runs *before* a Claude Code session begins, producing token-efficient artifacts the planning steps consume directly. Instead of loading raw documentation, videos, or papers into the context window, distill them first.

```bash
# Distill a 2-hour conference talk into structured notes
fabric -y "https://youtube.com/watch?v=..." -p extract_wisdom -o .specify/research/talk-notes.md

# Summarize API docs before referencing in a spec
fabric -u "https://docs.example.com/api/v2" -p summarize -o docs/api-summary.md

# Pre-analyze a research paper before /speckit.brainstorm
cat paper.pdf | fabric -p summarize_paper -o .specify/research/paper-summary.md

# Condense a reference project's README for context
fabric -u "https://github.com/some/project" -p summarize -o .specify/research/reference-project.md
```

Summaries run 10–50x smaller than raw sources, preserving context budget for implementation. This maps onto the Select and Compress phases of WISC (see `01-context-engineering-fundamentals.md`).

### 2. Spec-kit pipeline pre-processing (Phase 1)

Before entering `/speckit.brainstorm`, prepare structured inputs.

```bash
# Analyze competing design approaches
cat design-options.md | fabric -p analyze_claims -o .specify/research/approach-analysis.md

# Extract requirements from a product brief
cat product-brief.md | fabric -p extract_recommendations -o .specify/research/requirements-draft.md

# Find logical gaps in an existing proposal
cat proposal.md | fabric -p find_logical_fallacies -o .specify/research/proposal-gaps.md

# Rate existing spec quality before refinement
cat .specify/specs/feature/spec.md | fabric -p rate_content
```

These outputs feed the `.specify/specs/<branch>/research.md` artifact, giving `/speckit.specify` and `/speckit.plan` richer starting context without spending Claude Code tokens on preliminary analysis.

### 3. Security artifact generation (Phase 2, Steps 5–10)

Today the built-in `/security-review`, the `/security-scan` command, and the `forensic-specialist` agent run SAST tools (semgrep, gitleaks, gosec) and analyze results *inside* Claude Code sessions, spending context window on the analysis. Fabric can generate the security artifacts up front as files.

```bash
# Generate STRIDE threat model → input for forensic-specialist agent
cat docs/architecture.md | fabric -p create_stride_threat_model > .specify/security/threat-model.md

# Write Semgrep rules from vulnerability descriptions
echo "SQL injection via unsanitized user input in Go net/http handlers" | \
  fabric -p write_semgrep_rule -m claude-sonnet-4-5 -V anthropic > .semgrep/custom-rules/sqli-http.yaml

# Generate Nuclei scanner templates for infrastructure testing
echo "Check for exposed admin panels on port 8080" | \
  fabric -p write_nuclei_template_rule > nuclei-templates/admin-panel.yaml

# Generate Sigma detection rules from incident reports
cat incident-report.md | fabric -p create_sigma_rules > sigma-rules/incident-2026-04.yml

# Analyze a CVE advisory before feeding to forensic-specialist
fabric -u "https://advisory-url/CVE-2026-XXXX" -p analyze_threat_report > threat-summary.md

# Generate security design questions for a new feature
cat .specify/specs/feature/spec.md | fabric -p ask_secure_by_design_questions
```

The `/security-scan` command can reference Fabric-generated Semgrep rules during its SAST pass; `forensic-specialist` can consume threat models and Sigma rules as input artifacts; `quality-guardian`'s security assessment benefits from pre-generated threat context; and custom Semgrep rules augment Tier 1 pre-commit scanning. The threats these artifacts address are covered in `06-security-devsecops-for-agents.md`.

Fabric can also generate diagrams during implementation:

```bash
cat .specify/specs/feature/plan.md | fabric -p create_mermaid_visualization
cat .specify/specs/feature/spec.md | fabric -p create_conceptmap
cat docs/architecture.md | fabric -p create_excalidraw_visualization
```

### 4. Git workflow augmentation (Phase 3, Steps 11–16)

For git operations that don't warrant a full agent session.

```bash
# Quick commit message from staged changes (outside Claude Code)
git diff --staged | fabric -p summarize_git_diff

# Draft PR description for review-coordinator to refine
git log main..HEAD --oneline | fabric -p write_pull-request

# Summarize what changed in a feature branch
git diff main...HEAD | fabric -p summarize_git_changes

# Quick code review of a colleague's changes (not your own feature)
git diff main...feature-branch | fabric -p review_code

# Explain complex code to a reviewer
cat src/complex-module.go | fabric -p explain_code
```

The boundary with framework agents: Fabric handles quick drafts and standalone reviews outside a session. `review-coordinator` owns the full PR lifecycle (creation, reviewer assignment, feedback integration, merge). `code-reviewer` owns deep two-stage reviews (spec compliance + code quality). Fabric output is a starting draft those agents refine.

### 5. Retrospective support (Phase 4, Steps 17–18)

```bash
# Summarize what was learned during a sprint
cat sprint-notes.md | fabric -p extract_insights -o retrospective-insights.md

# Extract patterns from a post-mortem
cat incident-postmortem.md | fabric -p extract_recommendations -o lessons-learned.md

# Analyze logs from a production incident
cat production.log | fabric -p analyze_logs
```

### 6. Multi-model cost optimization (cross-phase)

The framework uses Claude exclusively, with haiku/sonnet/opus tiers for cost management. Fabric's provider routing lets low-stakes analysis go to cheaper or local models, reserving Claude Code for complex, stateful work.

| Task | Fabric route | Cost | Why not Claude Code |
|------|-------------|------|---------------------|
| Summarize a meeting recording | `fabric -p summarize_meeting -V google -m gemini-flash` | ~$0.001 | Stateless, no tool use needed |
| Extract ideas from a YouTube talk | `fabric -y <url> -p extract_wisdom -V ollama -m llama3` | $0.00 (local) | Privacy-sensitive, zero cost |
| Quick commit message | `fabric -p summarize_git_diff -V anthropic -m claude-haiku` | ~$0.0005 | Trivial task, sub-second |
| Threat model analysis | `fabric -p create_stride_threat_model -V anthropic -m claude-sonnet` | ~$0.01 | Needs quality but not statefulness |
| Diagram generation | `fabric -p create_mermaid_visualization -V openai -m gpt-4o-mini` | ~$0.001 | Structured output, any model works |
| Full feature implementation | **Claude Code → Opus** | Variable | Needs statefulness, tool use, quality gates |

The `--strategy` flag adds reasoning depth to compensate when a smaller model handles an analytical task:

```bash
cat architecture.md | fabric -p create_stride_threat_model --strategy tot -V ollama -m llama3
```

### 7. Custom pattern library (cross-phase)

The highest-leverage long-term integration is a set of **custom patterns that speak the framework's language**.

| Custom pattern | What it generates | Framework integration point |
|----------------|-------------------|----------------------------|
| `fw_claude_md` | CLAUDE.md skeleton with change maps, guardrails, trust boundaries, security posture | Follows the CLAUDE.md Template Guidance in `agent-workflow.md` |
| `fw_trust_boundaries` | Trust boundary documentation from architecture docs | Populates the Trust Boundary Documentation section |
| `fw_security_posture` | Security posture statement calibrated to app type | Populates the Security Posture Statement section |
| `fw_change_map` | Cross-cutting change maps from import/dependency analysis | Populates the Cross-Cutting Change Maps section |
| `fw_quality_report` | Structured quality gate report in framework format | Standardizes quality-guardian output |
| `fw_spec_review` | Spec analysis against the framework's spec template conventions | Pre-validates before `/speckit.review` |

## Integration Architecture

Both tools live in the developer's terminal, but only one of them writes to the project. Fabric (one-shot, 20+ providers) reads external sources and emits pre-processed artifacts — summaries, threat models, extractions — into `.specify/` and `docs/`. Claude Code (agentic, Claude-only, carrying the rules, agents, skills, hooks, specs, and tasks) reads those artifacts as data and owns all mutation of project files. Fabric's own config and custom patterns live outside the project, under `~/dotfiles/fabric/`, installed as a GNU Stow package alongside the framework's `~/dotfiles/claude/`:

```
~/dotfiles/
├── claude/           # AI Development Framework (existing)
│   └── .claude/
└── fabric/           # Fabric custom patterns (new)
    └── .config/fabric/patterns/
        ├── fw_claude_md/system.md
        ├── fw_trust_boundaries/system.md
        ├── fw_security_posture/system.md
        ├── fw_change_map/system.md
        ├── fw_quality_report/system.md
        └── fw_spec_review/system.md
```

## Experimental: REST API as a Hook Backend

Framework hooks execute shell scripts running deterministic tools (gitleaks, ruff, biome); they cannot invoke AI analysis without a full Claude Code session. Running `fabric --serve` as a persistent local service gives hooks an AI backend to POST to.

```bash
# In a PostToolUse hook: quick AI review of the edited file
cat "$EDITED_FILE" | curl -s -X POST http://localhost:8080/chat \
  -H "Content-Type: application/json" \
  -d '{"pattern": "review_code", "model": "ollama/codellama"}' \
  | jq -r '.choices[0].message.content'
```

`--serveOllama` mode is the interesting variant — patterns appear as Ollama-compatible "models", enabling local-only inference with zero API cost or network latency.

**Constraints:** viable only for `PostToolUse` hooks or optional pre-push checks, **not** the <5-second Tier 1 pre-commit gate (see `07-quality-gates.md` for the tiering this must respect). Ollama inference time depends on hardware — a GPU is recommended for acceptable hook latency. Hook output should be informational (exit 0), not blocking (exit 2), to avoid slowing the developer loop.

## Not Yet Adopted

The report's verdict: **adopt Fabric as an optional, complementary utility — not as a core dependency of the framework.** Nothing here is codified in `.claude/rules/`, and the risks below are the reason adoption stops at "optional."

| Risk | Mitigation |
|------|------------|
| **Prompt injection via Fabric output** | Fabric output is untrusted input per LLM01. Never pipe raw output into Claude Code as instructions. Save to files, reference as data. |
| **Pattern quality variance** | The 251 patterns vary in quality. Vet before relying on them; prefer custom patterns for framework-critical tasks. |
| **No quality enforcement** | Fabric has no hooks, Iron Laws, or quality gates. It produces text, not validated artifacts. All output must pass through the framework's quality pipeline. |
| **API key sprawl** | Multi-provider support means more keys to manage. Use `fabric --setup` carefully; never commit `~/.config/fabric/.env`. |
| **Context confusion** | Two AI tools in parallel can give conflicting advice. Keep the boundary: Fabric pre-processes, Claude Code develops. |
| **Statelessness** | No memory between invocations. Fabric cannot learn from project context, previous decisions, or accumulated specs. It always starts from zero. |

**Immediate wins (low effort, high value):** install Fabric and use `extract_wisdom` with `-y` for conference talks and tutorials; use `summarize_git_diff` for quick commit messages outside sessions; use `create_stride_threat_model` to prepare input for `forensic-specialist`; use `create_mermaid_visualization` for quick diagrams.

**Medium-term (moderate effort):** create 3–5 custom patterns aligned with framework conventions (`fw_claude_md`, `fw_trust_boundaries`, `fw_security_posture`); add Fabric as an optional dotfiles stow package; document the Fabric → Claude Code artifact flow in `agent-workflow.md`.

**Experimental (high effort, uncertain value):** the REST API hook backend; Ollama compatibility mode for local routing; pattern-based CI steps such as AI-generated changelogs via `generate_changelog`.

**Do not:** replace any framework agent, skill, or command with a Fabric equivalent — Fabric lacks the statefulness, quality enforcement, and governance the framework provides. Do not pipe Fabric output directly into Claude Code system prompts. Do not make Fabric a required dependency; it stays optional, for developers who want the extra utility belt.
