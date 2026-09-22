---
status: accepted
date: 2026-07-12
---

# The AI Protocol Stack

This file covers the wire-level standards that let agents talk to tools, to each other, to shared memory, and to human interfaces: MCP, A2A, Akashik, and AG-UI/A2UI. It owns protocol *mechanics* — transports, message shapes, discovery, and the token economics of tool schemas.

It does **not** cover MCP's security posture (OAuth 2.1, tool poisoning, input validation, human-in-the-loop gates) — that lives in `06-security-devsecops-for-agents.md`. Agent Teams and subagent topology live in `03-agent-topology-orchestration.md`; prompt caching and context-window mechanics live in `01-context-engineering-fundamentals.md`.

**Sources:** AI Context Engineering for Secure Development §Standardizing Communication: The AI Protocol Stack (MCP, A2A, Akashik)
**Codified in:** `.claude/rules/mcp-security.md` — partially; only the server-curation prescription. The protocol mechanics below are not codified anywhere in `.claude/rules/`.

## The M×N Integration Problem

Historically, granting an AI agent access to external data or other agents required writing bespoke integration code for every interaction. This created an M×N integration problem, where M AI models required unique connectors for N data sources, leading to a combinatorial explosion of maintenance debt.[^48] To resolve this fragmentation, the industry is converging on a standardized protocol stack that mirrors the composability of TCP/IP.[^49] Each protocol occupies one layer and composes with the others, so a single agent can speak MCP downward to tools, A2A sideways to peers, and AG-UI upward to a renderer without any of those integrations knowing about each other.

> **Note:** The original report illustrated this section with figures that did not survive export (the source retains broken `![][image1]` placeholders). The M×N framing is reproduced here as prose.

## Model Context Protocol (MCP)

Anthropic introduced MCP as an open standard for secure, structured connections between AI systems and external environments. It is a universal, **JSON-RPC 2.0**-based client-server interface: a host application (the MCP Client) communicates with independent MCP Servers that expose specific capabilities, eliminating custom API plumbing.[^48]

MCP standardizes three integration vectors:[^51]

- **Resources** — read-only access to structured data: fetching configuration files, reading logs, querying a database.
- **Tools** — executable functions with defined JSON schemas that the LLM invokes to perform side-effects: committing to Git, running a bash command, triggering a build pipeline.
- **Prompts** — pre-built, parameterized prompt templates exposed by the server to standardize complex requests and enforce organizational workflows.

### Code Execution for Tool Orchestration

The significant evolution in MCP usage is the transition toward **code execution for tool orchestration**. In environments with hundreds of available tools, loading every JSON schema definition into the context window upfront consumes tens of thousands of tokens, suffocating the model before reasoning even begins.[^53]

The modern best practice: agents write and execute code (e.g., Python in a sandboxed environment) to dynamically query MCP servers, discover available tools, and execute them on demand. This programmatic tool calling also prevents the intermediate data payloads of API responses from polluting the primary reasoning context — the script handles the payload, the model sees only the result.[^53]

### Why Server Curation Matters

MCP's extensibility is unbounded, and that is the trap. Every loaded server pays a fixed context tax at session start: its tool schemas, resource listings, and prompt templates all occupy the window before the first user turn. Loading an excessive number of MCP servers destroys the context window. The research recommends granular, single-responsibility servers — a **filesystem** server for local repository access, a **github** server for version-control awareness, and a **sequential-thinking** server to force rigorous architectural logic before execution.[^55]

> **Codified in** `.claude/rules/mcp-security.md` §Server Curation — the "keep server count minimal / audit every 30 days / prefer CLI when equivalent" prescriptions are the operationalization of this token-cost argument. This section is the evidence for that rule, not a restatement of it.

## Agent2Agent (A2A) Protocol

Where MCP connects agents to tools, **A2A** — contributed by Google to the Linux Foundation — standardizes how autonomous agents communicate with *each other*.[^49] It resolves the siloization of agents built on disparate frameworks (e.g., a LangGraph agent attempting to delegate to a CrewAI agent) by establishing a common language.[^49]

**Opaque Execution.** A2A's core principle: agents collaborate securely without exposing their internal memory, proprietary reasoning logic, or underlying tool implementations.[^57] A delegating agent sees a capability contract and a result, never the callee's internals.

**Agent Cards.** Discovery works through JSON metadata documents located at standard URIs — `/.well-known/agent-card.json` — advertising an agent's identity, capabilities, endpoints, and strict authentication requirements.[^57]

**Task-centric state.** The protocol defines a robust `InvocationContext` holding all information associated with a specific request, allowing seamless data transfer between subagents via output keys in `session.state`.[^39]

**Native async.** A2A supports asynchronous execution natively: HTTP **Server-Sent Events (SSE)** for real-time streaming, and webhook-based **Push Notifications** for long-running background tasks.[^57]

## Akashik Protocol

To address shared memory across multi-agent systems, the emerging **Akashik Protocol** provides a standardized *semantic blackboard*. Instead of ad-hoc state passing:[^61]

- Agents **RECORD** findings into a shared memory layer with a mandatory *intent* declaration — specifying *why* the data was recorded, not just what it is.
- Other agents **ATTUNE** to that memory layer, receiving relevant context automatically based on their role, task, and computational budget.
- The protocol natively manages contradictions between conflicting agent outputs, rather than leaving reconciliation to whichever agent reads last.

## AG-UI / A2UI

At the presentation layer, **AG-UI** (Agent-UI) and **A2UI** handle the translation of agentic states into human-readable interfaces, standardizing how generative UI components are streamed from backend agents to frontend renderers.[^62]

## Protocol Comparison

| Protocol | Layer in the AI Stack | Primary Function & Mechanism |
| :---- | :---- | :---- |
| **MCP** | Agent ↔ Tools & Data | JSON-RPC standard for exposing external tools, resources, and pre-built prompts to an LLM securely.[^48] |
| **A2A** | Agent ↔ Agent | HTTP/SSE standard for opaque, peer-to-peer delegation, discovery via Agent Cards, and asynchronous task coordination.[^57] |
| **Akashik** | Shared Memory Layer | Semantic blackboard allowing agents to asynchronously RECORD intents and ATTUNE to relevant global states.[^61] |
| **AG-UI / A2UI** | Agent ↔ Human Interface | Event-driven streaming of dynamic, generative user interface components directly from agent outputs.[^62] |

## Not Yet Adopted

**MCP.** The framework currently configures exactly one MCP server — see the root `.mcp.json`, which registers only `github` (HTTP transport, project scope, `Bearer ${GITHUB_TOKEN}`, for the review-coordinator agent; it is shipped by the plugin's `mcpServers` key). It previously lived at `.claude/mcp.json` — a path Claude Code never reads — and was therefore inert for the framework's entire life; see `07-quality-gates.md` on silent non-loading. The research-recommended granular stack of **filesystem**, **github**, and **sequential-thinking** servers is therefore only one-third present. The absence is deliberate under the curation rule, not an oversight: filesystem access is already covered by native Read/Grep/Glob tools, and no sequential-thinking equivalent has been evaluated.

**Code execution for tool orchestration.** Not adopted. The framework pre-loads its tool schemas conventionally; no sandboxed discover-and-call-on-demand path exists.

**A2A.** Not adopted. Framework agent-to-agent coordination runs entirely through Claude Code's in-process Agent Teams (see `03-agent-topology-orchestration.md`), which is a vendor-internal mechanism, not an A2A-compliant one. No Agent Cards are published; no `/.well-known/agent-card.json` exists.

**Akashik.** Not adopted. Shared state between framework agents is passed ad hoc through the task list and messages — precisely the pattern Akashik's semantic blackboard is designed to replace. No RECORD/ATTUNE equivalent exists.

**AG-UI / A2UI.** Not adopted, and likely not applicable: the framework's surface is a terminal CLI, not a generative UI renderer.

*(Report C §9 "Recommended Enhancements" contains no items in the protocol-stack subject area — its recommendations concern CLAUDE.md structure, quality tooling, and CI, all owned by other files in this corpus.)*
