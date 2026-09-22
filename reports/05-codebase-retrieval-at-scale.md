---
status: proposed
date: 2026-07-12
---

# Codebase Retrieval at Scale

How AI systems index and retrieve from multi-million-line repositories: why syntax-agnostic text RAG fails on source code, and the two structural remedies — **cAST** for file-level chunking and **HCAG** for macro-architectural comprehension. This is the single least-adopted subject in the corpus: the framework currently has no indexed retrieval layer at all, relying instead on Claude Code's native Grep/Glob/Explore over the live filesystem.

This file does NOT cover context-window mechanics, prompt caching, or WISC (see `01-context-engineering-fundamentals.md`), subagents used for exploration (see `03-agent-topology-orchestration.md`), MCP as a retrieval transport (see `04-ai-protocol-stack.md`), or any security consideration (see `06-security-devsecops-for-agents.md`).

**Sources:** AI Context Engineering for Secure Development §Advanced Retrieval-Augmented Generation (RAG) for Large Codebases, §cAST: Structural Chunking via Abstract Syntax Trees, §HCAG: Hierarchical Code/Architecture-Guided Agent Generation
**Codified in:** Not yet codified.

## Why Standard Text RAG Fails on Code

When AI systems attempt to comprehend multi-million line enterprise repositories, traditional Retrieval-Augmented Generation (RAG) methodologies catastrophically fail. Standard text RAG relies on syntax-agnostic, fixed-size token splitting. This arbitrary slicing fractures functions, classes, and logical statements. When these broken snippets are retrieved, the LLM loses semantic dependencies, variable scopes, and return types, rendering the context useless for reliable code generation.64

The failure is structural, not a tuning problem — no chunk-size parameter rescues a splitter that does not know what a function is. Repository-scale code intelligence demands structural awareness through Abstract Syntax Trees (AST) and hierarchical summarization frameworks.

## cAST: Structural Chunking via Abstract Syntax Trees

The cAST (Chunking via Abstract Syntax Trees) algorithm represents a paradigm shift in codebase ingestion. Instead of line-count heuristics, cAST employs language parsers (such as tree-sitter) to convert source code into a hierarchical AST, explicitly capturing language constructs as distinct nodes.64

### The Algorithm

The chunking algorithm traverses this tree **top-down**:

1. **Fit check.** If a large AST node (e.g., an entire class definition) fits within the maximum character budget, it is preserved as a single, contiguous chunk, maintaining complete syntactic integrity.64
2. **Recursive split.** If the node exceeds the limit, the algorithm recursively breaks it down into smaller constituent nodes (e.g., individual methods).64
3. **Greedy "split-then-merge".** To maximize information density, cAST recombines small adjacent sibling nodes back together as long as they respect the budget limit.64

The merge step is what separates cAST from naive AST-walking: without it, a file of twenty one-line helpers yields twenty near-empty chunks.

### Guarantees

- Chunk boundaries strictly align with **complete semantic units**.
- Language constructs are **never severed mid-logic**.
- The resulting context is entirely **self-contained and language-invariant**.64

### Benchmarks

Evaluations demonstrate that cAST significantly boosts retrieval accuracy, improving **Recall@5 by 4.3 points on RepoEval** and **generation Pass@1 by 2.67 points on SWE-bench** compared to traditional splitting.64

## HCAG: Hierarchical Code/Architecture-Guided Agent Generation

While cAST solves file-level fragmentation, it does not resolve **macro-architectural blindness**. In complex, theory-driven systems (e.g., algorithmic game theory or distributed microservices), core design logic emerges from interactions distributed across multiple directories; retrieving isolated snippets fails to convey how the broader system operates.68

The HCAG (Hierarchical Code/Architecture-guided Agent Generation) framework addresses this semantic-structural gap by **reformulating RAG as a multi-resolution planning process**.68 It operates in two phases.

### Phase 1 — Offline Hierarchical Abstraction

An LLM recursively parses the repository **from the bottom up**. It reads leaf files to generate detailed semantic summaries, then moves up the directory tree, synthesizing file summaries into higher-level module and architectural summaries. When directories exceed a specific depth threshold, the system applies **"soft compression,"** generating placeholder summaries that can be expanded on-demand to save computational costs.68

### Phase 2 — Online Hierarchical Retrieval

During code generation, retrieval is executed **top-down**. The agent first queries the high-level architectural skeletons. The retrieval scoring function mathematically combines **semantic similarity with structural relevance** to the query. Once the correct overarching module is identified, the agent drills down into the specific implementation details.68

### The Architecture-Then-Module Paradigm

This paradigm ensures the LLM receives an accurate, verified blueprint of the system's cross-file dependencies **before** attempting to modify code, establishing a direct mapping pathway from abstract theory to executable modules and heavily reducing **architectural drift**.68

The two techniques are complementary, not alternatives: cAST governs what a chunk *is*, HCAG governs the *order* in which chunks are reached.

## Not Yet Adopted

Source C §9 ("Recommended Enhancements for the AI Development Framework") lists no retrieval item at any priority tier — indexed code retrieval was not on the radar of any of the surveyed repositories. Nothing in `.claude/rules/` touches AST-aware chunking or hierarchical retrieval; the only AST references there are gosec's AST-based SAST scanning in `pipeline-security.md`, which is unrelated.

The framework's current retrieval strategy is **live, unindexed, and agent-driven**: Grep/Glob over the working tree, plus the `Explore` and `repo-scout` agents (see `03-agent-topology-orchestration.md`). There is no embedding store, no chunker, and no offline abstraction pass. For the repository sizes the framework targets today, this is a defensible trade — the ingest cost of cAST/HCAG buys nothing when the whole codebase fits in the model's grep-able reach.

Adopting either technique would require capabilities the framework does not currently have:

- **cAST** needs a tree-sitter parsing layer, a vector store, and an ingestion pipeline with cache invalidation on every commit — a persistent index is a new artifact class for a framework that has so far kept all state in flat Markdown.
- **HCAG** needs Phase 1's offline abstraction pass to be re-run (or incrementally patched) as the tree changes, and a scoring function that fuses semantic similarity with structural relevance — neither is expressible in a rules file; both are code.
- Both would sit behind a retrieval tool surface (plausibly MCP — see `04-ai-protocol-stack.md`), which means an operational dependency where none exists today.

The honest position: this subject is documented here as prior art to adopt **when** a target repository outgrows native search, not as a pending action item.
