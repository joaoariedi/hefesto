---
status: rejected
date: 2026-09-25
---

# Jev: a State-to-Decision Model, Evaluated Against Where the Framework Spends and Enforces

Everything checked about TypeSafe AI's **Jev** (`typesafe/jev-1.13`, launched 2026-09-15): what it is, what it measurably does, where it could slot into this framework, and why it does not. **Adoption status: evaluated 2026-09-25, not adopted.** Nothing described here is wired into the framework — no rule, hook, skill, command, or manifest entry references Jev. The decision on record is that a hosted, black-box decision classifier fits neither where the framework spends tokens (generation and long reads) nor where it enforces (deterministic, mutation-tested guards), and that the one narrow candidate — a confidence-gated pre-filter in front of the size router — saves too little to justify a provider lane.

This file does **not** cover the optional-lane doctrine itself (auto-detected, degrades silently, never in the manifest — `13-graft-code-context-graph.md` and the PR #51 lesson), the model-tier policy (`.claude/CLAUDE.md`), or the eval discipline (`evals/README.md`).

**Sources:** the vendor's model-jaggedness page (docs.typesafe.ai/model-jaggedness/jev-1.13), Simon Willison's 2026-09-21 write-up, BenchLM's independent review (2026-09-22, one live probe), TechTarget's launch coverage. No hands-on probe: the model is hosted-only and this evaluation did not open an account; the numbers below are the vendor's and the two reviewers', labelled as such.
**Codified in:** Not codified — evaluated here, not adopted. Addendum 2026-09-28 below: the first third-party numbers (GPT Researcher's context filter), one correction to this report's own argument, and the one experiment that would be worth running.

## What Jev Is

A "System One" model: it takes a text *state* (a string, an array of strings, or name–value records) plus one or more *questions*, and returns typed decisions sampled in parallel — a yes/no probability (the vendor calls it a *noul*), a probability distribution over supplied *choices*, or a *score* on a rubric of two to ten described levels. It generates no prose and gives no explanation. Weights are not published; access is TypeSafe's API or OpenRouter (beta), through a *Decisions* endpoint rather than chat completions.

| | Value | Source |
|---|---|---|
| Price | $0.042 per million input tokens; output free | vendor |
| Latency | 70–500 ms end to end (vendor); median under 1 s (independent) | vendor / BenchLM |
| Context | 64k tokens for state plus all questions; 32k for state plus the longest question | BenchLM, from vendor docs |
| Agreement with frontier-model labels | 67.8 % (GPT-5.6 Sol: 74.1 %) on the vendor's workflow set | vendor, model-labelled |
| Direct verdict on a phishing set | 62.6 % on 2,000 synthetic emails | BenchLM |
| Expected calibration error | 0.154 | BenchLM |
| Accuracy when confidence ≥ 0.9 | 89.9–99.6 %, covering 66–90 % of items | BenchLM |

The vendor's own jaggedness page lists nine failure modes, verbatim in spirit: **literal reading** (implied conditions are ignored), **unreliable arithmetic and counting**, **dates treated as text**, **no multi-hop reasoning** (one hop per question, double negatives fail), **accuracy drops with irrelevant state**, **steerable by injected instructions or misleading framing**, **confused by contradictory criteria**, **no invariants between separate answers**, and **no generation**. Its recommended practice is to keep arithmetic in code, pre-filter the state, state boundary cases explicitly, and test with adversarial content before deployment.

## Measured Against the Framework, Layer by Layer

The question is not "is Jev good" but "is there a place in this framework where a fast, cheap, explanation-free, steerable classifier is better than what runs there now". Taken in the order the tier policy ranks the spend:

| Where the framework spends or decides | What runs there today | Could Jev take it? |
|---|---|---|
| Plan, tasks, implement, verify, review drafts — where the token spend is (input volume; `opus`) | Generation over long context | **No.** Jev cannot write a sentence; the spend is generation. |
| Brainstorm, spec, clarify, plan review, the two reviewer agents (`fable`) | Short judgments that gate everything downstream and that nothing re-checks | **No.** 62–68 % raw agreement, no explanation, and an unexamined bias profile are the opposite of what a human gate needs to read. |
| PreToolUse guards: destructive commands, sensitive files, test shrinkage, snapshot flags | Deterministic string and count checks, every one mutation-tested (constitution 3) | **No, on principle.** A probabilistic gate that the vendor says "can be steered by injected instructions" is a security boundary a hostile commit message can flip. `llm-security.md`'s threat model is exactly that input. |
| `req-coverage`, `spec-cite-probe`: FR ↔ test traceability | Lexical `FR-NNN` matching — "nobody types FR-007 by accident; a hit is a claim someone made" | **No.** Semantic matching reintroduces data a model can fake (`framework-hard-won-traps`: never assert on it). |
| Verify gate, workflow verdicts | Exit codes; agents that did not write the code | **No.** The evidence-discarded family (#27, #28, #31, #32) was closed by making the unknown state explicit and letting a different mechanism contradict it — not by a fuzzier verdict. |
| `/hef.agent` size router | `task-effort-estimation` (deterministic score from VCS metadata) plus one short model turn | **Marginal.** One choice question (fix / light / full), accepted at confidence ≥ 0.9 and escalated otherwise, would cost a fraction of a cent and half a second. But the router's decisive signal is non-local-context risk — the "implied context" Jev's docs list first as a weakness — and the turn it would replace is already short. |
| Eval graders | `claude plugin eval`'s fixed grader types (`regex`, `tool_used`, `llm` judge) | **No.** Not pluggable. |
| Review-comment triage (`review-coordinator`) | The agent reads and acts on every comment | **Marginal.** Classifying comments as actionable / question / nit in parallel is Jev-shaped, but the agent still has to read the actionable ones, and the volume in a single-developer workflow does not justify a lane. |

Two framework-level facts settle the marginal rows. The framework is **zero-install and provider-agnostic** through tier aliases; a hosted third-party API that a hook calls on every edit is both an install dependency and a new **data-egress path** — repository state leaves the machine per tool call, from the one layer (hooks) that is supposed to be the boundary. And the optional-lane doctrine admits a tool only when it degrades to nothing silently; a decision the router *acts on* does not degrade, it disappears.

## What Would Reopen This

- Published weights or a local runtime, which removes both the install dependency and the egress.
- An independent calibration study on code-adjacent classification (routing, review triage) — not model-labelled agreement.
- Evidence of resistance to injected instructions, the failure mode the vendor currently documents as open.

If all three arrive, the first experiment is the one named above: thirty real task descriptions from this repository's specs scored by a choice question, compared with `/hef.agent`'s routing, with the disagreement rate and the ≥ 0.9 coverage as the two numbers that decide.

## Not Adopted

Evaluated 2026-09-25 against the framework as of 7.1.0. No change to the framework. This report exists so the next person who asks "could a decision model save us tokens" starts from the mapping above rather than from the launch coverage.

## Addendum 2026-09-28 — GPT Researcher's context filter, crossed with this report

GPT Researcher (`docs.gptr.dev/docs/gpt-researcher/gptr/context-filter`) ships Jev as the default
*context filter*: between "scrape pages" and "write the report" it scores 1,000-character chunks on the
four-level usefulness rubric and keeps those ≥ 1.5, up to ten per sub-query. Four other modes exist —
BM25 keyword, embeddings, unranked, none — and Jev falls back to keyword on any error, rate limit or
missing key: "no setting can leave a run without context". This is the vendor-recommended use this
report did not evaluate (pre-filter the state before a long read), with the first numbers from outside
the vendor: a replay of 28 tasks (20 SimpleQA, 8 open-ended), one writer and one judge (`gpt-5.4`,
self-preference acknowledged), which the page itself calls "directional evidence, not a leaderboard".

| Filter | Relevant passages | Correct (SimpleQA) | Context sent | Cost per report | Filter time |
|---|---|---|---|---|---|
| Jev | 73 % | 19/20 | 4.5k tokens | $0.115 | 1.7 s |
| BM25 keyword | 51 % | 19/20 | 6.4k | $0.116 | 0.02 s |
| Embeddings | 46 % | 18/20 | 7.6k | $0.117 | 1.0 s |
| Unranked | 33 % | 19/20 | 8.0k | $0.117 | 0.01 s |
| No filter | n/a | 20/20 | 33.4k | $0.192 | — |

What it changes and what it does not:

1. **The saving is "filter at all", not "filter with Jev".** No filter → any filter cuts the report's
   cost by ~40 %; Jev over BM25 saves one tenth of a cent and gains no correct answer. Jev's real edge
   is passage relevance (73 % vs 51 %), visible in a model-judged head-to-head on open-ended topics. In
   this framework the BM25 role is already filled, locally and zero-install, by `grep`, graphify's scoped
   subgraph, and the ≤2k-token digests that `repo-scout` and the verifier's diff-plus-spec context
   enforce. The "saves too little to justify a provider lane" verdict stands with better numbers under it.
2. **A correction to this report.** The argument that a Jev use "does not degrade, it disappears" was
   made about the size router and does not hold for a filter: GPT Researcher's fallback chain is the
   optional-provider lane done correctly (`13-graft-code-context-graph.md`). A *filter* use would be
   admissible under the lane's doctrine; the router use remains inadmissible. Admissible is not useful:
   nothing in the framework has a scrape-then-filter stage, so there is nowhere to put it today.
3. **The injection concern sharpens.** A relevance filter reads untrusted text by construction — web
   pages there, board items and PR comments here — and "steerable by injected instructions" is still the
   vendor-documented open failure mode. A passage that asks to be scored 3 is the *Comment and Control*
   class of `17-multi-agent-session-orchestration.md` §1f, moved one stage earlier. The page has no
   adversarial data. Any filter over untrusted text in this framework would need the same
   `tool_used max: 0` eval the orchestrator's board reader has.
4. **None of the three reopening conditions is met**: still hosted-only; the benchmark is web
   research, not code, 28 tasks, one judge; no injection evidence.
5. **The one experiment, now concrete.** When the arena lands (`tasks/BACKLOG.md` HEF-8) or
   `/hef.baseline` runs on a large brownfield repository, the truth map is assembled from many candidate
   excerpts — the only place a chunk filter would apply here. The comparison: ripgrep-ranked versus
   Jev-ranked excerpt selection feeding the same planner, scored on the claims the plan later needed,
   with the fallback chain in place and the sandbox's egress boundary respected (the filter would run
   from the unsandboxed pane, never from a hook). Not before the arena exists, and not adopted on the
   page's numbers alone.

Status unchanged: **rejected**, re-examined 2026-09-28 against 7.4.0.
