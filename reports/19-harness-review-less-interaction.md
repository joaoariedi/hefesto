---
status: accepted
date: 2026-11-22
---

# The Harness After 9.4.4: Where a Person Is Still Needed, and Where They Are Not

**The goal (owner, 2026-11-22):** a consistent harness that builds performant, reliable and secure software with as
little interaction as possible. A person decides what to build, architecture choices with a real trade-off, and
questions well-known best practices cannot answer.

**Method:** four read-only readers (prompt surface, pipeline mechanics, outside practice 2025–2026, current Claude
Code features), plus the ledger and two weeks of running the pipeline in a single lane (9.4.2 → 9.4.4, seven items).
Claims marked *reader* come from a reader's digest and were not re-checked against the code; *measured* comes from
the ledger or the run logs; *docs* comes from the current Claude Code documentation and was not tried on the
installed CLI.

**Decisions taken (2026-11-22, owner):** the order is A1, A2 and A4 first (board items HEF-57, HEF-58, HEF-59), then
B. The merge to `main` stays the owner's action for now; B5's required check is still wanted, and auto-merge to
`main` is revisited once the loops have run for a few releases and the metrics of D2 exist.

## 1. What the evidence says

**Measured.**

- 15 merged items cost $833 (about $56 each) and took 37 verify runs. Items that passed verify first time cost
  $19–$47; the three that did not (HEF-22, HEF-25, HEF-31) cost $80–$118 and took 5–6 rounds each.
- In HEF-31's five rounds, each round found blocking defects the round before had not: a signature bypass and a
  branch-name injection, then a cap bypass, then a PR swap, then a stale row after a reopen. The builder's own review
  had approved the same code with 0 blocking.
- Every verify round needed a person: the run was started from a terminal, and a FAIL waited for `unblock`. The
  seven items took roughly 60 messages of the form "script running" or "merged", and about 12 forms, of which four
  were about design or risk.
- Two HEF-55 builds ended with nothing changed because the worker could not run `awk`; every item reported some of
  gitleaks, shellcheck and `graphify update` as "not run". Two verify runs died when one tool was killed for memory.
- Tier 1 takes 9–13 minutes locally and 13–33 minutes in CI. It ran about 40 times in this stretch. `tests/smoke.sh`
  is 7,117 lines; shellcheck cannot check it.
- Plans 12–14 days old cited line numbers that had moved and a size budget (490 code lines) that was gone (500).
- One item was merged before its verify run; nothing prevented it.

**From the readers.**

- A FAIL verdict has no way back to the build stage: `unblock` clears the block, the phase stays `verify`, and the
  builder never sees the findings. The plan stage has automatic review rounds; the code stage has none. *(reader)*
- The reviewer is told to prefer fewer findings and has no lens for state and lifecycle defects. The lenses exist
  only in `workflows/workflow.js`. *(reader)*
- The review stack runs twice per item: in the builder's chain and again in the verify stage. *(reader)*
- 47 of 72 places where a command stops for a person are operational; 25 are definition, architecture or risk. *(reader)*
- A gate whose tool could not run reports PASS or SKIPPED, and only review and the kind gate are required. `hef.scan`
  reads the staged and unstaged diff, which is empty on a committed worktree. *(reader; the verify logs show the scan
  worker falling back to the branch diff by itself)*
- Plan and verify failures are retried without a cap; a killed launcher leaves its item claimed until the next
  `claim`. *(reader)*
- Four hand-kept lists name the signature flags and person-only subcommands; forge text reaches prompts through
  several wrappers of different strength; six commands and agents that read forge text lack the injection rule. *(reader)*
- About 15 KB of the 39 KB always-loaded rules is generic advice; three agents are spawned by no command; the shipped
  GitHub MCP server is used by nothing and failed to connect. *(reader; the connection failure is measured)*

**Outside practice that bears on this.**

- A separate, sceptical evaluator, with each gate's catch rate logged and a gate retired when it stops catching
  (Anthropic, *Harness design for long-running application development*, 2026-03-24).
- Review as parallel finders by lens, then a verifier that must reproduce each finding, all in one round (Anthropic,
  *Bringing Code Review to Claude Code*, 2026-03-09; Cursor, *Building a better Bugbot*, 2026-01-15). A second
  reviewer from another model tier found more planted errors than a second same-model one (arXiv 2610.01471,
  preprint, thin evidence).
- The sandbox is the boundary and a classifier is a second layer; sandboxing cut permission prompts by 84 %
  (Anthropic, *How we contain Claude*, 2026-05-25).
- Sampled tests in the loop, the full suite at the gate (Carlini, *Building a C compiler with a team of parallel
  Claudes*, 2026-02-05); CI load grows fast under agents (Anthropic, *Agentic coding is straining CI*, 2026-09-14).
- People intervene on choices, not actions: the most common agent-initiated stop is choosing between approaches
  (Anthropic, *Measuring AI agent autonomy in practice*, 2026-02-18).
- Auto-merge only behind required checks a person owns (OpenAI, *Harness engineering*, 2026-02-11; DORA 2025).
- No good source was found for evidence caching, batching decisions, or the right number of review rounds.

**Claude Code today** *(docs)*: sandboxed Bash can run with no allow rule (`autoAllowBashIfSandboxed`);
`--permission-mode auto` works in `claude -p`, configured through `--settings`, not a project file; the status line
receives context and rate-limit fields; workflows ship in a plugin and run headless; cross-session messaging exists.
The ledger, the per-repository lock and the person's gates still need custom code.

## 2. The decision contract

Only four things may produce a form:

1. **Definition:** what to build and its acceptance criteria.
2. **Architecture:** a choice between approaches with a real trade-off.
3. **Risk acceptance:** a signature (a spec deviation, a cap passed, a kind change, an exception to a gate).
4. **Irreversible or cross-boundary actions:** the merge policy for a protected branch, production.

Everything else is automated, or stops as a stall that names its fix. A stop that fits none of the four is a defect
of the harness, counted and removed.

## 3. Proposals

Each line: the change, the evidence it answers, what it should remove.

### A. Close the loops (interaction)

- **A1. A verify-fix loop.** On FAIL the item returns to the build stage with a brief made from the verdict's
  evidence; `orchestrate.verify_rounds` (default 3), then a block. Answers: FAIL is a dead end; 16 rounds on three
  items each needed a person.
- **A2. One exhaustive review.** Finders in parallel by lens (input and security, state and lifecycle, spec
  deviation, test integrity), a verifier that reproduces each finding, every blocking finding in one round, each
  lens answering "none, checked X". A second finder on another tier. Answers: one new blocker per round.
- **A3. One review stack.** The builder runs the requirement matrix and the quality tools; the fresh review and the
  scan run once, in the verify stage. Answers: the stack runs twice.
- **A4. A driver instead of prose.** A deterministic pass that launches runs, chains build → tests → verify → fix,
  reaps dead claims at its start and caps plan and verify retries. Answers: "script running"; unbounded retries;
  stranded claims.
- **A5. Defaults that settle the operational stops.** `plan_review: agent` for new configs, `--by` from git config,
  one automatic retry, the 47 operational stops reviewed one by one against the contract.

### B. Gates that are honest and can run (reliability)

- **B1. Workers that can run their tools.** Sandbox auto-allow as the boundary in place of narrow allow lists (to
  be tried on the installed CLI first); setup detects the project's test and lint commands; the launcher refuses a
  role that lacks its runner. Answers: two dead builds; "not run" in every item.
- **B2. Three states per gate row:** PASS, FAIL, UNRUN. UNRUN on the secret scan is FAIL; a denied tool is a stall
  with its fix. The scan reads `<base>...HEAD`.
- **B3. Evidence and a faster suite.** `record --tests-green <tree>` so a gate reuses a pass on the same tree;
  `smoke.sh` split into parts that run alone, with a selector by changed area; the full suite at the gate only.
- **B4. Fresh plans.** Plans cite symbols, not line numbers; size budgets are rechecked at launch; an item is planned
  when it is next, not weeks ahead.
- **B5. Merge after verify, enforced.** A required check the verify stage posts, so a merge cannot precede it.

### C. Security

- **C1. One wrapper for untrusted text,** with invisible-Unicode stripping, and validators at write time for the PR
  URL, the spec folder and branch names; one shared injection block in every command and agent that reads forge text.
- **C2. One registry** for signature flags and person-only subcommands; the four lists generated from it.
- **C3. Worker settings isolated** from the branch under review (to be verified: `--setting-sources`).
- **C4. The GitHub MCP server removed** from the plugin, or opt-in.
- **C5. Babysitter fixes counted in the ledger,** not in PR comments anyone can write.

### D. Delete and measure

- **D1. Delete:** the generic part of the rules, two of three copies of the tool matrix, the agents nothing spawns,
  the dead asks, the custom context gauge (the status line has the fields).
- **D2. Measure:** rounds to green, interventions per merged item, escaped defects, cost per merged item, each
  gate's catch rate. An eval set of 20–50 cases built from the defects verify found in HEF-22, HEF-25 and HEF-31.

## 4. Order

A1, A2 and A4 first: they remove most of the interaction measured here and are what makes the rest testable without
a person in the loop. B2 and B1 next, because A1 multiplies whatever a gate reports. C and D follow; C2 and C1 are
small and could ride with any release.

## 5. Open questions for the owner

- Auto-merge to `main`: today `merge_by: auto` refuses it. Keep the merge as the one human action per item, or allow
  it behind B5?
- The 27 frozen items: several overlap this report (the kaizen and audit items). Re-triage against section 3.
- Which model reviews: a second finder on another tier costs more per round and should cut rounds.
