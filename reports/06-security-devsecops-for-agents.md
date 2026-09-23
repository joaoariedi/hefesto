---
status: accepted
date: 2026-07-12
---

# Security & DevSecOps for Agents

The threat model, research rationale, and empirical evidence behind the framework's security posture: the OWASP Top 10 for LLM Applications as it manifests in *agentic* systems, the MCP control surface, Policy-as-Code, AI-focused DLP, and live security telemetry fed to the agent while it codes. Most of the *mitigations* here are already codified in `.claude/rules/` — this file is the **why** layer and points to the rule that enforces each control rather than restating it.

This file does **not** cover: where in the pipeline security checks execute (pre-commit vs pre-push vs CI tiering, hook mechanics) → `07-quality-gates.md`; MCP protocol mechanics (JSON-RPC, Resources/Tools/Prompts) → `04-ai-protocol-stack.md`; generating security artifacts such as Semgrep rules, STRIDE models, or Sigma rules from prompts → `09-fabric-prompt-orchestration.md`. This file owns **which security controls exist and why**.

**Sources:** *AI Context Engineering for Secure Development* §Integrating DevSecOps and Policy-as-Code in Agentic Workflows; *Frank Repos Best Practices Analysis* §5 Security Practices, §9 Recommended Enhancements
**Codified in:** `.claude/rules/llm-security.md`, `.claude/rules/mcp-security.md`, `.claude/rules/pipeline-security.md`

## Secure MLOps: Why Traditional DevSecOps Is Insufficient

As AI coding assistants transition from generating passive boilerplate to autonomously executing infrastructure commands via MCP, the security paradigm must undergo a radical shift. The velocity of AI integration outpaces traditional DevSecOps, necessitating **"Secure MLOps"** — where security controls are embedded directly into the LLM's context window, its toolchain, and its orchestrating environment.<sup>70</sup>

The core insight: traditional SAST and SCA are insufficient because they scan code *after* it is written.<sup>80</sup> In the era of AI, **prompt engineering itself acts as a primary security control**. Guardrails that live only in a README are guardrails the agent will drift from.

## Threat Mechanisms: OWASP Top 10 for LLM Applications

Agentic systems face unique threat vectors undocumented in traditional web security frameworks. The table below preserves the **threat mechanism** — the part rules/ does not carry — alongside the mitigation strategy.

| OWASP Vulnerability | Threat Mechanism in Agentic Systems | Mitigation Strategy |
| :---- | :---- | :---- |
| **LLM01: Prompt Injection** | Attackers embed malicious instructions in external data (e.g., compromised dependencies or manipulated Git issues). When retrieved via RAG, the model executes the malicious payload.<sup>72</sup> | Strict separation of instructions from data using XML tags; deterministic output validation; human-in-the-loop approvals for sensitive actions.<sup>72</sup> |
| **LLM06: Excessive Agency** | The inherent risk of granting agents broad tool access. A hallucination or injection attack can cause an agent to delete databases or provision rogue infrastructure.<sup>72</sup> | Strict Role-Based Access Control (RBAC); applying the principle of least privilege to MCP server capabilities; sandboxing execution environments.<sup>72</sup> |
| **LLM02 & LLM07: Data Leakage & System Prompt Exfiltration** | The model unintentionally summarizing and returning sensitive internal code, proprietary IP, or hardcoded secrets found during codebase exploration.<sup>73</sup> | Implementation of AI-focused Data Loss Prevention (DLP) to proactively block PII, PCI, and source code from entering the model's embeddings or cache.<sup>76</sup> |
| **LLM03: Training Data Poisoning** | Attackers manipulate the raw data or repositories that the agent relies on for context or RAG retrieval.<sup>77</sup> | Restricting the agent's searchability to verified folders and employing Adversarial Robustness Toolboxes (ART) during pipeline construction.<sup>70</sup> |

> **Codified in** `.claude/rules/llm-security.md` — this table is the threat-model evidence behind that rule's LLM01/LLM02/LLM03/LLM06/LLM07 mitigation lists and its Defense-in-Depth layer table. Do not re-derive the mitigations here; the rule is the enforcement surface.

**Not yet codified — immutable system prompts.** Input must be sanitized before reaching the model, stripping control characters and neutralizing system-level tokens.<sup>77</sup> The system prompt must be **immutable, enforced entirely server-side**, and explicitly define role boundaries ("Decline unsafe queries," "Require citations").<sup>77</sup> Paired with this, **deterministic output validation** — enforcing strict schema parsing on the LLM's response before executing any subsequent logic — prevents malformed or malicious outputs from triggering system failures.<sup>72</sup> `llm-security.md` carries the schema-validation half of this; the server-side immutability requirement is an open gap.

## MCP Security Posture: The Controls

MCP servers act as the bridge between the agent and enterprise infrastructure, and therefore introduce massive attack surfaces if improperly configured.<sup>63</sup> Three control families are mandatory:

- **Authentication & Authorization** — OAuth 2.1 or stringent API key validation via HTTP headers; least privilege; **the LLM must never decide its own permission boundaries** — authorization is enforced server-side.<sup>63</sup>
- **Input Validation & Tool Poisoning Defense** — all tool inputs generated by the LLM are **hostile input**. Servers validate and sanitize every argument, particularly file paths, to prevent **directory traversal**. Clients must additionally be defended against **tool poisoning** — where one tool's output attempts to hijack the agent — by treating all tool annotations as untrusted.<sup>63</sup>
- **Human-in-the-Loop** — high-impact actions (modifying IAM policies, executing database migrations, sending emails) require explicit human consent before the MCP server permits execution, mitigating Excessive Agency.<sup>63</sup>

> **Codified in** `.claude/rules/mcp-security.md` — the evidence for that rule's Authentication & Authorization section, its Input Validation & Tool Poisoning Defense section, and its Human-in-the-Loop approval table.

## Policy-as-Code

If guardrails exist only as written documentation in a README, **agents will inevitably drift from them**.<sup>82</sup> Security mandates must be codified as Policy-as-Code: abstract security rules (like "prevent hardcoded secrets") transformed into **executable constraints** within the CI/CD pipeline, enforced via **Open Policy Agent (OPA)** or **Sentinel**.<sup>83</sup>

This is the structural argument for the framework's own hooks-over-rules split: a rule is guidance the agent may reason around, a hook is a boundary the agent cannot bypass. OPA/Sentinel extend that boundary from the local hook into the pipeline. **Not currently adopted by the framework** — the framework enforces policy through shell hooks, not through a policy engine with a declarative language and an audit trail. For large-scale enterprise systems the source treats immutable Policy-as-Code as non-negotiable, alongside explicit human-in-the-loop workflows for infrastructure-altering MCP calls and enterprise-grade DLP.<sup>63</sup>

## AI-Focused DLP

Standard DLP inspects egress traffic. **AI-focused DLP** proactively blocks PII, PCI, and source code from entering the model's **embeddings or cache** in the first place<sup>76</sup> — a distinct control point, because once proprietary code is embedded into a commercial LLM's vector store or prompt cache, deletion is not a meaningful remedy. This is the mitigation the source assigns to LLM02/LLM07, and it is the one control in the OWASP table with **no corresponding entry in `.claude/rules/`**. The framework currently relies on `gitleaks` at commit time (secrets in *committed* code) and `block-sensitive-files.sh` (writes to `.env`, `.key`, `.pem`), neither of which prevents proprietary source from being read into context and transmitted.

## Live Security Telemetry Injected via MCP

The highest-leverage pattern in the source, and the one that most directly changes how an agent codes.

DevSecOps platforms are increasingly leveraging MCP to inject **live security telemetry directly into the agent's context window**. Instead of an agent writing insecure code and waiting for a SAST tool to flag it during a build, an MCP-enabled AppSec server (**Snyk, SonarQube, or Semgrep**) continuously feeds vulnerability data, **taint-flow traces**, and secure coding patterns to the agent *while* it codes.<sup>85</sup>

The concrete payoff is in remediation quality. When a developer prompts the agent to "fix this vulnerability," the MCP server supplies **the full HTTP request that triggered the finding and the precise source-to-sink trace** — allowing the LLM to generate a context-aware, highly accurate patch rather than a plausible-looking guess at what the scanner meant.<sup>85</sup>

This reframes the scanner from a *gate* into a *context source*. `mcp-security.md` lists Semgrep, Snyk, and SonarQube under "Recommended Security MCP Servers" but justifies them only as "real-time SAST via MCP"; the source-to-sink-trace rationale — the actual reason the pattern beats a CI scan — is not recorded anywhere in rules/. Cost caveat stands: each MCP server adds baseline context consumption, so this is a medium/large-project control, not a default.

## Prompting for Architectural Security: ENSEMBLE vs EXAMPLE

Empirical research into LLM code generation reveals that models **struggle to identify abstract architectural violations** — such as deviations from the SOLID principles — without deliberate guidance.<sup>89</sup> Prompt templates using chain-of-thought and few-shot methodologies targeting specific design heuristics force agents to evaluate their own outputs. The finding is that the *prompt strategy must match the principle*:

| Prompt strategy | Mechanism | Best at enforcing |
| :---- | :---- | :---- |
| **ENSEMBLE** | Deliberative — multiple reasoning passes | **Open/Closed Principle (OCP)** violation *detection* |
| **EXAMPLE** | Hint-based — few-shot exemplars | **Dependency Inversion Principle (DIP)** *enforcement* |

`.claude/rules/code-quality.md` already instructs the framework to "focus on OCP and DIP violations — these cause the most maintenance burden" and assigns the check to `quality-guardian`. What it does **not** encode is *how to prompt for each*: an agent asked to find OCP violations should be given a deliberative, multi-pass prompt; an agent asked to enforce DIP should be given concrete exemplars. This is an unexploited, directly actionable finding for the `quality-guardian` and `code-reviewer` agent prompts.

## Empirical Evidence: Trust Boundaries and Security-First Architecture

### Trust Boundary Documentation (FrankYomik)

FrankYomik's CLAUDE.md explicitly enumerates every hostile input surface, so the agent knows where to apply validation without being told per-task:

- Image uploads to `POST /api/v1/jobs`
- Metadata fields (title, chapter, page_number)
- WebSocket clients and subscription lists
- Web pages in the app WebView
- Fallback image URLs from page JS
- Anything persisted under `cache/`

It also notes that the **security posture is different** for a token-gated bot versus a public web app — an explicit posture statement lets the agent calibrate how much security to apply rather than defaulting to generic paranoia or generic negligence.

> **Codified in** `.claude/rules/agent-workflow.md` — the "Trust Boundary Documentation" and "Security Posture Statement" blocks in the CLAUDE.md Template Guidance section are derived directly from this repo.

### Security-First Architecture (FrankMega)

A production reference for what "security posture: production-grade" means concretely. **Not codified in rules/** — kept here in full as the reference implementation:

- **Rate limiting**: Rack::Attack with configurable multiplier (10x dev, 1x prod)
- **IP banning**: Ban model with auto-expiry, disabled in dev
- **Headers**: secure_headers gem (CSP, HSTS, X-Frame-Options)
- **Cookies**: Secure, HttpOnly, SameSite=Lax
- **Filename sanitization**: strips control chars, Windows-unsafe chars, reserved names, truncates to 255 bytes
- **Encrypted fields**: ActiveRecord Encryption for `otp_secret`
- **Cloudflare proxying**: manually configured trusted proxy IPs

FrankMega also maintains **dedicated `*_security_test` files** for auth, input validation, and rate limiting — separate from standard tests, so a security regression produces a distinct failure signal (codified in `.claude/rules/code-quality.md`).

### Which Security Scans Run, and Where

Evidence from the Frank repos on scanner selection per ecosystem. This is the *which and why*; for where these execute in the pipeline see `07-quality-gates.md`.

| Tool | Type | Repos Using |
|------|------|-------------|
| brakeman | Rails SAST | FrankMD, FrankMega |
| bundler-audit | Ruby dependency CVE scan | FrankMD, FrankMega |
| cargo audit | Rust dependency CVE scan | FrankSherlock |
| importmap audit | JS dependency scan | FrankMD, FrankMega |
| flutter analyze | Dart static analysis | FrankYomik |
| cargo clippy -D warnings | Rust lint (warnings = errors) | FrankSherlock |

Note the Ruby ecosystem (brakeman, bundler-audit, importmap audit) is absent from `.claude/rules/pipeline-security.md`, which catalogs Python, Go, JS/TS, Java, and Rust tooling but has no Ruby section.

## Not Yet Adopted

Security items from *Frank Repos Best Practices Analysis* §9 and the DevSecOps research that the framework has not implemented:

| Enhancement | Priority | Source | Notes |
|---|---|---|---|
| **Policy-as-Code via OPA / Sentinel** | High | Report A §Policy-as-Code | Framework enforces policy via shell hooks only — no policy engine, no declarative audit trail |
| **AI-focused DLP** | High | Report A (LLM02/07) | No control prevents proprietary source entering model embeddings/cache; `gitleaks` only covers committed secrets |
| **Live security telemetry via MCP** (source-to-sink traces during coding) | High | Report A <sup>85</sup> | `mcp-security.md` lists the servers but not the taint-flow rationale or usage pattern |
| **ENSEMBLE / EXAMPLE prompt templates for SOLID** | Medium | Report A <sup>89</sup> | `quality-guardian` and `code-reviewer` prompts do not differentiate strategy by principle |
| **Immutable server-side system prompts** | Medium | Report A <sup>77</sup> | Schema validation is codified; server-side prompt immutability is not |
| **Ruby security tooling section** (brakeman, bundler-audit) | Medium | FrankMD, FrankMega | `pipeline-security.md` has no Ruby ecosystem entry |
| **Security scanning as a separate CI job** (not bundled with tests) | Medium | §5 Actionable Patterns | Clearer failure signals; pipeline placement is `07-quality-gates.md`'s subject |
| **GPG / Apple signing with graceful fallback in release CI** | Low | FrankYomik, FrankSherlock | Artifact provenance; `pipeline-security.md` Tier 3 mentions Sigstore but no signing pattern |
| **AUR auto-publish pattern** | Low | FrankSherlock | Niche distribution-channel integrity |
