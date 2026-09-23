---
status: accepted
date: 2026-07-12
---

# Agent Topology and Orchestration

The taxonomy of agentic execution units (Skills, Subagents, Agent Teams), the four canonical multi-agent orchestration patterns, and the cognitive memory architecture that keeps distributed agents from relying on invisible state. This is the "why" layer behind the framework's agent doctrine — the architectural rationale and trade-offs, not the prescriptions.

This file does **not** cover: the protocols agents communicate over (MCP, A2A, Akashik, AG-UI) → `04-ai-protocol-stack.md`; context-window mechanics, WISC, or Document & Clear → `01-context-engineering-fundamentals.md`; retrieval strategies for the code agents read (cAST, HCAG) → `05-codebase-retrieval-at-scale.md`; lifecycle hooks → `07-quality-gates.md`.

**Sources:** *AI Context Engineering for Secure Development* §Agentic Capabilities: Skills, Subagents, and Agent Teams; §Multi-Agent Architectural Patterns and State Management
**Codified in:** `.claude/rules/agent-workflow.md` (One-Shot Subagents; Agent Teams), `.claude/rules/context-management.md`

## The Three Architectural Extensions

Modern frameworks have moved beyond monolithic agents executing solitary loops. Extensions fall into three categories, and choosing the wrong one is how projects collapse under token bloat or contextual confusion.

### Skills: Encapsulated Deterministic Workflows

Skills are markdown-defined toolsets, instructions, and workflows that Claude discovers and loads automatically or via manual invocation (e.g. `/deploy`).¹⁸ Their efficiency comes from a two-phase load: at session start the agent loads **only the names and descriptions** of available skills, keeping baseline context cost exceptionally low; the full instructional payload is fetched and injected only when the skill is dynamically invoked.¹⁰

Skills are optimal for repeatable, deterministic procedures — applying a deployment script, running a compliance audit against a known standard.

The **`disable-model-invocation: true`** frontmatter flag renders a skill invisible to the agent's automatic reasoning loop, reducing its context cost to **zero** until explicitly triggered by the human operator. This prevents the model from hallucinating unnecessary tool calls, and it is the mechanism for keeping a large skill library from taxing every session.¹⁰

### Subagents: Isolated Context Execution

Deep exploration — tracing a bug through dozens of legacy files — pollutes the orchestrator's context with irrelevant code fragments and verbose tool outputs when run inline.²⁹ Subagents resolve this by executing in a **strictly isolated context window**.¹⁰

Under a **hub-and-spoke topology**, the primary orchestrator spawns a subagent with specific tool permissions and a targeted system prompt. The subagent conducts its research or implementation in isolation and returns **only a synthesized, high-signal summary**, discarding the noisy intermediate steps.¹⁰ This prevents main-conversation bloat, improves cost efficiency, maintains focus, and reduces hallucination rates.²⁹

The canonical application is the **"Explore first, then plan, then code"** methodology: an Explore subagent operates in a strictly read-only capacity to build a comprehensive contextual map *before* any implementation code is generated.¹⁰ The read-only constraint is not incidental — it is what makes the isolation safe, since a subagent whose context is discarded must not leave mutations behind.

> **Codified in** `.claude/rules/agent-workflow.md` — the "One-Shot Subagents" section is the operational form of this finding: the digest-only output contract, the tool allowlist, the no-side-effects rule, and the `repo-scout` template all exist to preserve the isolation property described above.

### Agent Teams: Peer-to-Peer Mesh Orchestration

Where subagents operate in strict hierarchy, Agent Teams introduce a **mesh (peer-to-peer)** architecture: multiple AI instances operate concurrently with **independent context windows**, sharing a task list and communicating directly with one another without routing through a central supervisor.³⁰

This enables **"coopetition"** — an implementation agent writing code while a designated **critic agent** actively reviews and challenges the logic in real time, simulating a collaborative human engineering team.³³ The cost is real: Agent Teams exponentially increase token expenditure through inter-agent messaging overhead and the maintenance of multiple active sessions. The payoff is deep debugging, cross-layer feature development, and resolving **competing architectural hypotheses** where a single model falls victim to groupthink or confirmation bias.³¹

> **Codified in** `.claude/rules/agent-workflow.md` — the "Agent Teams" section (team workflow, composition patterns, DM-over-broadcast rule) operationalizes the cost profile above: prefer DMs precisely because inter-agent messaging is the dominant token cost.

### Comparison

| Architectural Extension | Context Topology | Primary Use Case | Token Efficiency Profile |
| :---- | :---- | :---- | :---- |
| **Skills** | Shared with main session | Reusable, repeatable deterministic workflows and reference materials.¹⁰ | Highly efficient; loaded dynamically on-demand.¹⁰ |
| **Subagents** | Isolated, Hub-and-Spoke | Deep repository research, isolated verification tasks, parallel file reading.¹⁰ | Efficient; shields main context from intermediate noise.¹⁰ |
| **Agent Teams** | Distributed, P2P Mesh | Complex parallel reasoning, adversarial code review, multi-module feature building.³⁰ | Resource intensive; requires multiple concurrent active sessions.³⁴ |

## Canonical Orchestration Patterns

Scaling from individual developer assistants to enterprise-wide autonomous systems requires distributed architecture. Modern multi-agent AI relies on patterns battle-tested in cloud-native microservices and the **"12-Factor App"** methodology: treating agents as **isolated workers with externalized state** and strict orchestration hierarchies is what makes multi-agent systems scale predictably.³⁶

The design of a multi-agent system defines its routing logic, failure domains, and state ownership. The industry has converged on four foundational patterns³⁰:

| Architectural Pattern | Structural Dynamics | Enterprise Application | Trade-offs & Considerations |
| :---- | :---- | :---- | :---- |
| **Sequential Pipeline** | A deterministic "assembly line" where the output of Agent A becomes the direct input for Agent B.³⁷ | Data transformation, CI/CD pipeline automation, and multi-stage document enrichment.³⁹ | Highly observable and reliable, but lacks dynamic flexibility if an early stage fails.³⁹ |
| **Loop (Generator-Critic)** | Agents cycle continuously. A generator produces an artifact, a critic evaluates it against a rubric, and the cycle repeats until a condition is met.³⁷ | Code quality assurance, security auditing, and iterative content refinement.³⁷ | High risk of infinite loops; requires strict timeout parameters and maximum iteration limits.⁴⁰ |
| **Hub-Spoke (Supervisor)** | A central routing agent delegates tasks to specialized workers. The hub maintains the canonical state.³⁰ | Complex feature development requiring diverse domain experts (e.g., UI, Database, Security agents).³⁰ | The hub serves as a single point of failure and a potential routing bottleneck, though worker failures remain isolated.³⁰ |
| **Mesh (Decentralized)** | Agents initiate communication autonomously based on service discovery. State ownership transfers upon handoff.³⁰ | Autonomous research and highly dynamic problem solving without a predefined workflow.³⁰ | Lowest observability; highly complex coordination overhead and challenging to debug.³⁰ |

Mapping back to the extension taxonomy: subagent dispatch is **Hub-Spoke (Supervisor)**; Agent Teams are **Mesh (Decentralized)** with a shared task list bolted on to recover some observability; the `quality-guardian` → `code-reviewer` → `review-coordinator` chain is a **Sequential Pipeline**; and an adversarial critic teammate is a **Loop (Generator-Critic)**.

### Liveness Timeouts Are Non-Negotiable

Across **all four patterns**, adopting distributed-systems practices such as explicit liveness timeouts is non-negotiable. Without **stream timeouts**, **tool-call timeouts**, and **session TTLs (Time-To-Live)**, agentic systems are vulnerable to hanging indefinitely, leading to resource leaks and severe security risks.⁴¹ The Loop (Generator-Critic) pattern is the acute case — it requires a maximum iteration limit in addition to wall-clock timeouts, or the generator and critic will refine forever.

## Cognitive Memory Architectures for Deep Agents

### The "Invisible State" Anti-Pattern

A critical vulnerability in multi-agent systems is the assumption that LLMs inherently remember data across disparate tasks. Relying on **"invisible state"** — where the orchestrator assumes the model will recall context from dozens of turns prior — is a severe anti-pattern that **guarantees failure in production**.²⁰ Memory must be explicitly modeled into cognitive layers, breaking free from the simplistic "RAG for chat history" approach.⁴²

### The Four Dimensions

A comprehensive agentic memory architecture comprises four distinct dimensions⁴⁴:

1. **Working Memory:** The immediate context window containing the current task, execution plan, short-term conversational history, and active tool outputs.⁴⁴
2. **Episodic Memory:** A chronological, verifiable log of past actions, decisions, and outcomes. Implementing episodic memory allows agents to utilize hindsight, reflecting on what failed in previous sessions to avoid repeating mistakes.⁴³
3. **Semantic (Factual) Memory:** Fact-based grounding data, often stored in vector databases for RAG. This encompasses enterprise knowledge, API documentation, environment state, and code syntax rules.⁴⁴
4. **Procedural Memory:** The implicit understanding of "how" to execute tasks, typically codified into functional tools, structured workflows, and deterministic lifecycle hooks rather than relying on the LLM's parametric knowledge.⁴⁴

The framework already externalizes three of these: `CLAUDE.md` and `.claude/rules/` are **Procedural Memory**; the persistent memory directory is **Episodic**; retrieval over the repo is **Semantic**. **Working Memory** is the only dimension the agent holds in-flight — which is precisely why subagent isolation and one-shot digests matter: they are Working Memory hygiene.

### Retain, Recall, Reflect

Advanced frameworks operationalize these memory layers using the **"Retain, Recall, Reflect"** paradigm. Agents must systematically **retain** structured memories, **recall** *just enough* context for the immediate operation to prevent token bloat, and **reflect** on outcomes to update their internal beliefs and procedural strategies over time.⁴³

The middle term is the load-bearing one. Retention is cheap and reflection is optional; **selective recall** is what separates a working agent from one drowning in its own history — and it is the discipline that the digest-only subagent contract enforces mechanically rather than trusting the model to exercise.
