---
status: accepted
date: 2026-09-25
---

# Spec-First Versus Incremental Prompting: What the Evidence Says, and the Rung This Framework Stands On

The claim under examination: *newer models make spec-driven development unnecessary — incremental prompting gets the same results.* This report collects the measurements behind that claim and against it, separates the three things "spec-driven" can mean, compares the spec-kit pipeline with incremental prompting dimension by dimension, and records the framework's position with its own numbers. **Decision on record: the framework is spec-first with a mechanical anchor (tests are the truth; the spec is the intent contract, checked against them at implementation and after shipping), routed by task size. It is not spec-as-source, and the evidence says it should not be.**

This file does **not** restate the drift findings already codified from the 2026-09 review (`14-harness-review-2026-09.md`: aggregate rules, requirement coverage, ceremony scaling) or the routing policy (`.claude/CLAUDE.md`). It is the evidence layer for why those exist in the shape they do.

**Sources:** Scott Logic (Eberhardt, 2025-11-26 and 2025-12-15); Böckeler for martinfowler.com (2025-10); Thoughtworks Radar, techniques, *Assess* (2025-11) and the Thoughtworks insights post; Anthropic Engineering, *Effective harnesses for long-running agents* (2025-11) and *Harness design for long-running application development* (2026-03-24); He et al., *Speed at the Cost of Quality*, MSR 2026 (arXiv 2511.04427); *SpecFirst* (arXiv 2607.27167); *Don't Blame the Large Language Model* (arXiv 2607.03691); *Stop Hand-Holding Your Coding Agent* (arXiv 2607.00038); METR, 2025-07-10 study and 2026-02-24 update; Fowler et al., *Structured-Prompt-Driven Development*; `github/spec-kit/spec-driven.md`; this repository's own artifacts (`.specify/specs/harness-review-tiers/`, PR #60).
**Codified in:** `.claude/CLAUDE.md` (routing, tier policy), `/hef.agent` (size router), `/hef.verify` + `req-coverage --all` + `spec-cite-probe.sh` (the mechanical anchor), `evals/spec-first-routing` and `evals/no-ceremony-for-trivial` (both directions of the router, measured).

## The measurement behind the claim

Scott Logic rebuilt one feature it had already built once — circuits CRUD with geolocation in a go-kart PWA, roughly 700 lines — with GitHub Spec Kit (September 2025) on Copilot with Sonnet 4.5, and then the way its author normally works.

| | Spec Kit | Iterative prompting |
|---|---|---|
| Agent time | 33 min 30 s | 8 min |
| Code produced | 689 LOC | ~1,000 LOC |
| Markdown produced | **2,577 lines** (constitution 161, spec 230, plan 2,067) | 0 |
| Human review | **3.5 hours** | 15 min review + 9 min testing |

The headline "around ten times" slower is wall time, and nearly all of it is a person reading a 2,067-line plan. The author's verdict — "the fastest path is still iterative prompting and review, not industrialised specification pipelines" — came with three caveats: the tool was immature, the author might be using it wrong, and speed was never the claim. The December follow-up by the same author argues the opposite side of the same coin: "AI amplifies this tendency because it's eager to build whatever you describe", so problem articulation and requirements precision become the *first* skills, prompt engineering the least.

**What the 10× measures is artifact volume, not the spec step.** That distinction decides everything below.

## What newer models changed, measured

- **Anthropic, March 2026.** The cleanest test of "harness assumptions expire" (their own principle from November 2025). Moving from Opus 4.5 to Opus 4.6 they **removed** sprint decomposition and context resets — the model held a two-hour build coherently. They **kept the planner**: "without the planner, the generator under-scoped: given the raw prompt, it would start building without first speccing its work." The evaluator became **conditional**: "worth the cost when the task sits beyond what the current model does reliably solo." The numbers: solo agent, 20 minutes, $9, "nothing responded to input"; spec plus evaluator, 6 hours, $200, a working product. The assumption that expired was *the model cannot hold a long task*; the one that did not was *the model will decide what to build well enough on its own*.
- **MSR 2026 (He et al.).** 806 repositories that adopted Cursor against 1,380 propensity-matched controls, difference-in-differences. Velocity rose 3–5× in the first month and dissipated within two; static-analysis warnings rose **30.3 %** and cyclomatic complexity **41.6 %**, and neither came back down; the accumulated complexity then reduced later velocity. This is what "the same results" look like when quality is measured: the same features, with entropy that compounds.
- **SpecFirst (arXiv 2607.27167).** Eliciting a behavioural specification as a first-class step before synthesis raised test pass rates by **6.9–21.3 points** across four models on ProgramBench, most where documentation is ambiguous and early misreadings would propagate.
- **Harness evolution (arXiv 2607.03691).** Model held constant across 35 sequential releases of one agent harness, on 50 SWE-bench Verified tasks: quality moved anyway. Practitioners misattribute to the model what the harness did — in both directions.
- **METR.** The 2025 randomized trial found experienced open-source developers **19 % slower** with early-2025 tools; the 2026 update finds **18 % faster**, with the caveat that returning participants got 18 % and new ones 4 %, which METR itself calls weak evidence. Newer models make people faster; the trial does not test method.
- **The field's direction (arXiv 2607.00038).** Step-by-step prompting is being replaced, not by chat, but by *loop specifications*: "a bounded, reusable artifact, made of a trigger, a goal, a verification step, a stopping rule and a memory." In this framework that artifact is called a hook.

## Three things "spec-driven" means

Böckeler's ladder, from the martinfowler.com memo that examined Kiro, spec-kit, and Tessl:

1. **Spec-first** — write it, use it to drive the task, it may not outlive the feature. "Definitely valuable in many situations."
2. **Spec-anchored** — keep it and evolve the feature through it. Unproven.
3. **Spec-as-source** — the spec is the maintained artifact; code is compiled output. Unproven, with model-driven development as the cautionary parallel and non-determinism observed "even at this low abstraction level."

Thoughtworks holds the whole practice at *Assess* because the workflows "perform inconsistently based on task size and type" and "generate lengthy spec files difficult to review"; Kiro turned a minor bug into "4 user stories with a total of 16 acceptance criteria"; "I'd rather review code than all these markdown files." Spec-kit's own philosophy is the top rung — "Specifications don't serve code — code serves specifications" — and its document lists no failure modes. The critics are right about that rung, and it is the one nobody has been observed practising.

## Spec-kit steps versus incremental prompting

| Dimension | Spec-kit pipeline | Incremental prompting | Evidence |
|---|---|---|---|
| Time to first working code | Slow: every phase is generate-then-review | Minutes | Scott Logic: 33 vs 8 min agent time, 3.5 h review |
| Human review load | Dominates; grows with markdown volume | Code review only | 2,577 md lines for 689 LOC; "rather review code" |
| Under-scoping | Prevented by the planning step | Frequent: builds before speccing | Anthropic kept the planner for exactly this |
| Error propagation | A wrong early decision cascades through plan and tasks | Corrected at the next prompt | Anthropic: keep the spec high-level so detail cannot cascade |
| Quality and complexity drift | Constrained by explicit criteria and gates | Rises and stays risen | MSR 2026: +30.3 % warnings, +41.6 % complexity |
| Ambiguous requirements | Surfaced before code | Found mid-implementation, or never | SpecFirst: +6.9–21.3 points |
| Cross-session continuity | Artifacts survive compaction | Lives in chat; lost at reset | Anthropic 2025-11: feature list + progress file |
| Parallel agents | Task list with ownership makes it possible | Not possible from one conversation | 27.7 % of agent PRs conflict without it (report 14) |
| Scaling down to trivial work | Fails: sledgehammer for a nut | Ideal | Thoughtworks on Kiro; Scott Logic |
| The spec after shipping | Rots unless mechanically checked | Nothing to rot | Spec-anchored unproven — needs a check, not faith |

**Synthesis.** Spec-first wins wherever a wrong early decision costs more than the spec, and loses wherever the spec costs more than the decision. That boundary is task size and ambiguity — which is why every serious practitioner converges on the same design: a size router, high-level specs, lean artifacts, an evaluator that is conditional on difficulty, and tests as the truth. Fowler's *Structured-Prompt-Driven Development* reaches the same place from the other side: the prompt "captures the intent, and the code is the implementation of that intent", kept in sync in both directions.

## The rung this framework stands on, with its own numbers

Hefesto is spec-first with a mechanical anchor. The ratio that decides the review argument is measurable here: the harness-review program that shipped 6.1.0 through 7.0.0 was driven by **175 lines** of spec, plan, and tasks (`.specify/specs/harness-review-tiers/`) and produced a merge (PR #60) of **102 files, 13,185 insertions, 7,399 deletions**. Scott Logic's pipeline produced about 3.7 lines of markdown per line of code; this one produced roughly one per 75. What removes the cost the critics measured is not a better model: it is a 27-line spec template, a plan review merged into one command, five of the nine gates being optional per path, and `/hef.agent` deciding the path before any artifact exists.

Each finding above maps to a mechanism already in place:

| Finding | Mechanism |
|---|---|
| Under-scoping without a planner (Anthropic) | `/hef.spec` first for feature-sized work; the session-start routing line; `evals/spec-first-routing` (Δ +1.0) |
| Ceremony must scale down (Thoughtworks, Scott Logic) | `/hef.agent` fix / light / full; `/hef.fix`; `evals/no-ceremony-for-trivial` (judge 3/3 both arms) |
| Complexity drift under iteration (MSR 2026) | the lizard delta gate in `quality-before-commit.sh` |
| Evaluator conditional on difficulty (Anthropic) | adversarial verification in `hefesto:workflow`; `/hef.review` at two gates |
| Spec-anchored is unproven (Böckeler) | not trusted: `/hef.verify` at implementation, `req-coverage --all` in CI and `spec-cite-probe.sh` at the edit after shipping |
| Step-by-step prompting → loop specs (arXiv 2607.00038) | fifteen hooks with a trigger, a check, and an exit code |

**What the evidence asks for that is not yet mechanised:** an artifact budget. Nothing stops a plan from growing to 2,000 lines; the framework avoids the review-overload failure by template discipline, not by a check. Proposed, not built: an advisory in `check-plan` and `/hef.review` plan mode when spec + plan + tasks exceed a budget the constitution can set.

## Decision

Accepted 2026-09-25: the framework stays spec-first, routed by size, with tests as the source of truth and the spec checked against them mechanically before and after shipping. Spec-as-source is not a goal. The claim that newer models make the spec step unnecessary is contradicted by the one controlled removal experiment on record (Anthropic, 2026-03), by the one large-scale quality study of iterative agent coding (MSR 2026), and by the framework's own routing evals; the claim that spec-kit's *artifact volume* is unnecessary is supported by every source, and this framework was built on that reading.
