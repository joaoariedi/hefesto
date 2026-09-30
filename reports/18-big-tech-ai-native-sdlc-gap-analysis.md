---
status: accepted
date: 2026-09-28
---

# A Big-Tech AI-Native SDLC Against Hefesto: What to Borrow

The source: Eduardo Galbiati, *Inteligência Artificial na prática* (September 2026 deck, `edugalbs.com/ia/24-09-ppt.html`), the day-to-day AI-native SDLC of one engineer in a big tech that "uses AI in everything", with multi-team governance and a metrics ladder behind it. Slides 13–35 describe the operating model; slide 23 (the one the user pointed at) is the code-exploration "arena". This report reads the deck against hefesto 7.3.0 component by component, keeps what the evidence in `reports/17` supports, and proposes six enhancements in rank order. **Decision proposed:** adopt the three that close measured gaps — a fresh-context reviewer for plan mode, a PR babysitter that loops on CI and review comments up to the human gate, and delivery metrics from the ledger — and add the arena as a bounded, read-only fan-out in `/hef.plan` Phase 0. Cross-vendor models, board variants and post-deploy monitoring stay in the optional-provider lane or Phase 3.

This file does **not** restate the topology evidence (`17-multi-agent-session-orchestration.md`), the spec-first evidence (`16-…`), the quality-gate catalogue (`07-…`) or the protocol stack (`04-…`). Where the deck and a prior report agree, it says so in one line and moves on.

**Sources:** the deck (49 slides; transcribed 2026-09-28); Anthropic, *The AI-Native SDLC Playbook* (the deck's own reference, slides 16–18); McKinsey, *The State of AI* (August 2026, slide 37); the numbers already collected in report 17 §1 (cross-model review, MAST, AIDev merge data); this repository at v7.3.0.
**Decisions taken (2026-09-28, user):** accepted; build #1 (fresh-context plan review) and #3 (ledger metrics) now as one light feature; #2 (PR babysitter) next as its own spec; #4, #5, #6 on the board as backlog items HEF-8, HEF-9, HEF-10 (HEF-7 is #2).
**Codified in:** #1 and #3 shipped in 7.4.0 (`/hef.review` plan mode spawns `code-reviewer`; `ledger.sh metrics`; `/hef.status` "AI delivery") from `.specify/specs/plan-review-and-metrics/`; #2, #4, #5, #6 on `tasks/BACKLOG.md` as HEF-7..10.
**Addendum 2026-09-30** below: the deck re-read as the *macro* layer — four long-lived stage panes (Orchestrator, Plan & Design, Build & Test, Deploy) over the Shape A spine, with hefesto's commands, hooks, skills and agents as the tools each pane's headless sessions use; the arena in three phases, starting from the tier split that already runs (`opus` writes, `fable` reviews).

## 1. The deck's operating model in one table

| Deck element (slide) | What it is | Hefesto today | Gap |
|---|---|---|---|
| Layered concepts: MCP → Skill → Agent → Orchestrator → **Maestro** (13) | each layer uses the one below; Maestro = multi-AI, multi-session, multi-user | five-layer stack in `docs/architecture.md`; report 17 Phase 1 is the Orchestrator layer | Maestro = report 17 Phases 2–3 |
| One orchestrator, specialists with **their own context and model**, sized ~20k/80k/50k/250k/150k (14) | context isolation per role | `session-launch.sh` per role: tier, tools, `--max-budget-usd` | one cap for all roles; the deck sizes per role |
| **AI-Native SDLC** loop: Plan `intent.md` → Design `spec.md` → Build → Test → Deploy → Maintain → new `intent.md` (16) | each phase leaves a versioned artifact that triggers the next | `.specify/` artifacts, `hef.*` pipeline, `TaskCompleted` gate | Maintain → Plan loop does not exist (no post-deploy signal) |
| "Build is no longer the bottleneck" (17); invest in MCPs, skills from policies, harness, **hooks as deterministic gates** (18) | human-paced phases dominate | this is the constitution and the hook set | none |
| **RFC as source of truth**: meeting transcript → code exploration → refinement; nothing is built without an approved RFC (22) | | `/hef.brainstorm → /hef.spec → /hef.clarify`; spec-first routing (report 16) | no transcript intake |
| **Arena**: 5 models (Opus 5.5, Fable 5.1, GPT Astra, GPT-6 Sol, Kimi k3) explore the code in isolated sessions; an orchestrator merges into one document (23) | parallel *intelligence*, single merged artifact | `/hef.plan` Phase 0 truth map by ONE agent; `repo-scout` one-shot | no fan-out, no cross-model |
| **One AI writes, another reviews** the RFC until "ready for a third AI to implement" (24) | author ≠ reviewer, different vendors | `/hef.review` plan mode is **inline** in the authoring session | self-review — the +0 pp configuration (report 17 §1d) |
| Feature Workflow Agents: Developer, Code Review (SonarQube, rules per stack), Test Writer (fails → orchestrator → developer), **Builder** (build + library vulnerabilities) (26) | | `workflow.js` implement + three verifier lenses; `test-specialist`; `code-reviewer`; `quality-guardian`; `/hef.scan` (secrets, SQLi, XSS) | no dependency-vulnerability gate |
| **CI Pusher** (`/goal CI passing`, Jenkins MCP logs → orchestrator → developer), **PR Babysitter** (`/loop` on the PR until mergeable; answers pertinent comments with the commit hash; doubtful comment → asks the user), **Deployer**, **human gates** at merge, release PR, production (28) | the agent acts up to the gate and never past it | `/hef.pr` opens the PR and stops; `review-coordinator` "handles feedback" when asked; ledger kind `ci` exists but nothing sets or clears it | **nothing watches CI or the PR after creation** |
| **Monitor**: Datadog, 3 h of latency and status codes, Slack, "rollback or ticket?" (30) | closes the loop in production | none (deploy is human by report 17) | Phase 3 material |
| All communication bidirectional **with the orchestrator; agents never talk to each other** (31) | hub, not mesh | report 17's conclusion, verbatim | none — the deck confirms the shape |
| Vulnerability / incident **board variants**: a different origin board, the same Build & Test, an extra **check** before monitoring (32–33) | one pipeline, two entry points, one added gate | `/hef.orchestrate` reads one board; verifier chain is fixed | no item kind, no kind-specific gate |
| Local → **remote, shareable sessions** per JIRA issue; flows fire end to end; a person only approves the deploy (34–35) | | `runs[].session_id` + `claude --resume` (local continuation) | report 17 Phase 3 (routines) |
| Metrics ladder: installed → tokens/month → GitHub events → **lines accepted, deploys, TTM**; value = time saved, rework, adoption; governance = approved tools, human review on critical, continuous evaluation, **traceability** (41, 44–45) | measure, don't perceive | `evals/` (continuous evaluation); commit trailers + `runs[]` (traceability); report 17's Phase 1 metrics are *defined* but not *computed* | no metrics view |

Two things the deck confirms rather than adds: the hub topology (slide 31) and "hooks as deterministic gates" (slide 18) are hefesto's constitution. One thing today's own dogfood confirmed: the plan review of `session-orchestration` was done **inline by the session that wrote the plan** — exactly the self-review the evidence says is worth nothing — and it still took a separate `code-reviewer` run and a `quality-guardian` run to find the two real defects.

## 2. What the evidence says about each borrowing

- **Author ≠ reviewer, in a fresh context.** Cross-model review lifted a weaker author by +18.1 pp; self-review by the strongest model was +0; the "self-correction illusion" shows a fresh context framed as an external reviewer recovers most of the gain even with the same model (report 17 §1d). The deck's "Claude writes, Codex reviews" is the cross-vendor form; the fresh-context form is available in every Claude-only install today.
- **CI and the PR are where merges are lost.** Each CI failure cuts merge odds by ~15 %; reviewer abandonment is 38 % of rejected agent PRs and duplicates 23 % (report 17 §1f). A babysitter that turns a red check into a fix and a comment into a reply attacks both — and it is the one role in the deck with a stated loop discipline (`/loop` until mergeable, doubtful comment → ask). Claude Code has the primitives: `ScheduleWakeup`/`/loop`, `gh pr checks`, `gh run view --log-failed`, `gh api` for review threads.
- **Parallel exploration pays when the task decomposes; it costs 15×.** Google/MIT: up to +80.8 % on decomposable tasks; Anthropic's research system: gains "strongly linked to … independent context windows"; token cost ≈ 15× chat (report 17 §1a, §1e). Code exploration for a truth map is decomposable (by module, by question) and read-only — the case report 03 and 17 reserve parallelism for. Bound it: K ≤ 3, digests only, one merged document.
- **Metrics that are defined and never computed are perception.** The deck's ladder ends at lines accepted, deploys and time-to-market; report 17 §7 committed Phase 1 to merge rate, CI-red rate, USD per merged PR and reviewer minutes. The ledger holds every input (`runs[]`, `verdicts[]`, `pr`, `blocked_on.since`, `updated`); nothing reads them.
- **Dependency vulnerabilities are a supply-chain gate the rules already name** (`llm-security.md`: "a dependency that did not exist before the change is a review item"; 5–22 % of LLM-suggested package names do not exist). The deck's Builder makes it a role; hefesto can make it a detected tool in `/hef.scan`.
- **Post-deploy monitoring and remote sessions** are real in the deck and out of scope here: hefesto stops at the release gate by design (report 17 §6, "no shipped autonomous deployer"), and Phase 3 routines are gated on Phase 1 numbers.

## 3. Ranked proposal

| # | Enhancement | Size | Evidence line | New surface |
|---|---|---|---|---|
| 1 | **`/hef.review` plan mode dispatches a fresh `code-reviewer`** (fable) with spec + plan + constitution only, instead of reviewing inline; the inline path stays as `--inline` for a second opinion | fix | +0 pp self-review; self-correction illusion; today's dogfood | none new — a command edit + an eval (`plan-review-is-not-self-review`: `tool_used` Agent min 1) |
| 2 | **PR babysitter**: `/hef.pr --watch` (or `/hef.babysit <pr>`) — after the PR exists, loop with `ScheduleWakeup` on `gh pr checks`; red → fetch the failed job log, run `/hef.fix` on the branch, push, reply with the commit hash; review comment → untrusted-input rule, pertinent → address and reply with the hash, doubtful → `AskUserQuestion`; mergeable → stop and set `blocked_on: human:merge`; never merges. Helper `hooks/pr-watch.sh` (fetcher over `gh`: checks, failed logs, unresolved threads; fake-`gh` smoke) | light | −15 %/CI failure; 38 % abandonment; the deck's PR Babysitter | one command flag or command, one helper, ledger kinds `ci` (exists) + `review` (new) |
| 3 | **Delivery metrics from the ledger**: `ledger.sh metrics [--since d]` — dispatched, merged, merge rate, CI-red-on-first-push, USD per merged PR, median claim→PR and PR→merge hours, blocked time by kind; `/hef.status` gains an "AI delivery" section when a ledger exists | light | report 17 §7 Phase 1 criteria; deck slides 41/45 | one subcommand, one `/hef.status` section, smoke fixture |
| 4 | **Arena in `/hef.plan` Phase 0**: `--arena K` fans the truth-map questions out to K `repo-scout` agents at different tiers (`sonnet`, `opus`, `fable`), read-only, each returning a ≤2k-token digest; the planner merges them into `research.md` with per-claim attribution; disagreements become `[NEEDS CLARIFICATION]`. Cross-vendor explorers (`codex`, other CLIs) only if detected, optional-provider lane | light | +80.8 % decomposable; 15× cost bound by K and digests | a flag on `/hef.plan`, `repo-scout` unchanged |
| 5 | **Dependency audit in `/hef.scan`**: detect `osv-scanner`, `npm audit`, `pip-audit`, `cargo audit`, `govulncheck`; report new dependencies in the diff and known vulnerabilities; advisory in `quality-before-commit.sh` | fix | `llm-security.md` supply-chain rule; deck's Builder | detection in `quality-tooling`, a `/hef.scan --deps` section |
| 6 | **Board item kinds** (`incident`, `vulnerability`) via the heading marker the board already parses (🐞, 🛡): the ledger records `kind`; the verifier prompt adds the kind's gate (a regression test citing the incident id must exist and pass; a re-scan must be clean) as verdict gates `incident` / `vulnerability` | light | deck slides 32–33; report 17 §5a state machine | Phase 2 of orchestrate |

Not proposed: a Monitor role (Datadog/Slack) — Phase 3, optional MCP; remote shared sessions per issue — Phase 3 routines; per-role context *sizes* (the deck's ~20k/80k) — hefesto caps spend, not tokens, and `--max-budget-usd` per role is a one-line config change folded into #3's metrics work if wanted; a cross-vendor *reviewer* as a requirement — it is the deck's practice, but the evidence gives most of the gain to the fresh context, so #1 first and the vendor CLI as an optional lane.

## 4. Adoption

- **#1 and #3 together** are one light-path feature: a command edit, a subcommand, an eval, a status section — and they change what today's plan review and Phase 1 measurement actually are.
- **#2** is its own light/full feature with a spec; it is the largest gap and the deck's most disciplined role.
- **#4** rides on the next `/hef.plan` change; **#5** is a `/hef.fix`; **#6** waits for Phase 2 of orchestrate.


## Addendum 2026-09-30 — the deck as the macro layer: four stage panes over the Shape A spine

The deck was re-read from a saved copy (`reports/harness-software-engineering.html`, removed after
this addendum — the canonical source stays `edugalbs.com/ia/24-09-ppt.html`) with a different
question than on 2026-09-28. The first read asked *which components to borrow*; this one asks
*whether the deck's operating model is the layer above hefesto*. The user's framing: the deck is the
**macro orchestration** — four long-lived sessions, one per stage, that exchange messages and each
run headless sessions for the actual work — and hefesto's commands, hooks, skills and agents are the
**tools** those sessions use to complete their missions. That framing is right, and it changes
nothing in report 17's shape: it is a second **layout** of the attended panes over the same spine.
The rest of this addendum says exactly what holds it there, and phases the arena.

### A1. Where the deck's stack and hefesto's meet

| Deck layer (slide 13) | Deck definition | Hefesto | Status |
|---|---|---|---|
| MCP | translates an external service for the AI | none bundled (PR #51 lesson); `gh`, `git`, `jq` behind helpers | by design |
| Skill | uses 0..n MCPs; a policy made reusable | 7 skills (`quality-tooling`, `systematic-debugging`, `task-effort-estimation`, `mcp-security`, …) | shipped |
| Agent | uses 1..n skills; one role, own context | 6 agents + 25 `hef.*` commands (the verbs) + 15 hooks (the deterministic gates the deck's slide 18 asks for) | shipped |
| Orchestrator | multi-agent, multi-context; "delegates, coordinates and commits" (slide 31) | `/hef.orchestrate` + `ledger.sh` + `session-launch.sh`: claims, launches a fresh worker and a separate verifier, records verdicts — and **does not commit** (the worker does, inside its worktree; merge stays human) | shipped 7.3.0 |
| Maestro | multi-AI, multi-session | the attended panes (`claude --name`), herdr, cross-session pointers; the arena (HEF-8) is its multi-AI half | layout + backlog |
| Multi-user | several maestros | the team upgrade path (`docs/install.md` §5) and shared board/ledger/PRs; nothing else needed until two people attend the same repo | open |

The deck's one deviation from hefesto at the Orchestrator layer — the orchestrator *commits* — is
deliberate here: the session that coordinates never holds write access to the branch it coordinates,
so a hijacked board item cannot turn into a commit through the coordinator (report 17 §5e).

### A2. The four-pane layout, and what keeps it from being Shape B

The user's proposal: keep four sessions open — **Orchestrator** (project status, controls the
sessions), **Plan & Design** (an RFC becomes spec, plan, tasks and subtasks), **Build & Test**
(implement, tests, review, build), **Deploy · CI/CD** (CI, PR, deploy, environment transitions) —
each launching headless sessions with hefesto's agent context for its stage, exchanging messages,
with clarifications raised by the stage that owns them. Report 17 §4 rejected Shape B, "a live mesh
of long-lived role sessions", on four numbers: every inbound message is a full-context turn on a
growing context; five idle sessions reprocess after the 5-minute cache lapses; MAST's 37 %
inter-agent misalignment; and the reviewer inheriting its own prior reviews. The proposal is *not*
Shape B when the following holds — and each line is a structure, not advice:

| Pane (`claude --name <repo>-<pane>`) | Ledger phases it owns | Human gates it holds | Headless sessions it launches | Hefesto tools it uses | May never |
|---|---|---|---|---|---|
| 🎛 `orchestrator` | `queued` → claim; the whole board's state | `human:intake` (untrusted text named a tool or a file) | none of its own in the layout's first cut: it runs `/hef.orchestrate` for the build stage as today; with HEF-11 it dispatches per stage | `/hef.status`, `/hef.orchestrate`, `ledger.sh list|next|metrics`, `claude agents --json`, herdr `agent wait --until blocked` | edit source; merge, approve, push `main`; resolve a `human:*` block; hold a worker's transcript |
| 📐 `plan` (Plan & Design) | `intake` → `spec` → `plan` → `plan-review` → `tasks` | `human:clarify`, `human:plan-review` | with HEF-11: `session-launch.sh plan <id>` — brainstorm → spec → plan → tasks in a fresh process that **exits on the first `[NEEDS CLARIFICATION]`** with `block --kind human:clarify`; until then, by hand in the pane | `/hef.brainstorm`, `/hef.spec`, `/hef.clarify`, `/hef.plan` (arena here, A4), `/hef.review` plan mode (fresh `code-reviewer`), `/hef.tasks`, `/hef.checklist`, `/hef.analyze`, `/hef.adr` | touch source files; advance past `tasks` |
| 🔨 `build` (Build & Test) | `implement` → `verify` → `quality` → `security` → `pr` | `verdict`, `stall`, `budget`, `conflict` (a person splits, retries or re-scopes) | `session-launch.sh implement <id>` then `verify <id>` — what `/hef.orchestrate` does today | `/hef.implement` or `hefesto:workflow`, `/hef.verify`, `/hef.quality`, `/hef.mutate`, `/hef.scan`, `/hef.review` code mode, `/hef.pr` | merge; approve; push anywhere but `feature/<id>` |
| 🚀 `deploy` (Deploy · CI/CD) | `pr` → `merged` → `released` | `ci` (after the babysitter's retries), `human:merge`, tag/deploy | with HEF-7 as a headless role: `session-launch.sh deploy <id>` — the PR babysitter, one fresh process per PR, exits at mergeable with `block --kind human:merge` | `/hef.pr --watch` / `/hef.babysit`, `/hef.fix` on a red check, `/hef.release`, `/hef.doctor` | merge by itself; run on the workstation with production credentials (below) |

**The five rules.** (1) *The handoff is the ledger, not the message.* A stage ends with
`ledger advance <id> <phase>`; the next pane finds it with `ledger next`/`list --phase` or the
session-start line — nothing has to be sent for the pipeline to move. (2) *The pane never does the
stage's work in its own context.* It launches a fresh headless session per item (Shape A's worker,
now per stage) or does the human-gated step by hand, then `/clear`s — the `/hef.brainstorm`
convention, now the rule for all four panes. A pane's context is the board, the ledger and the
person; the deck sizes its Deployer + CI at ~250k tokens (slide 14) precisely because CI logs land
in it — here `gh run view --log-failed` lands in a babysitter process that exits, never in the
pane. (3) *A message is a pointer and an escalation, never a handoff.* One line, ≤ 200 characters,
an id and a kind and a path (`ledger HEF-7 blocked_on human:merge …/pull/7`), sent only when a
human has to notice — report 17 Phase 2's single message type, HEF-5. The deck's slide 31 rule
("agents never talk to each other, they always answer to the orchestrator") holds with the ledger
as the hub; the orchestrator pane is where the person reads the whole board, not a relay. (4)
*Inbound is data.* The four attended panes run `crossSessionInbound: accept` and treat every inbound
line as data; every launched session runs `refuse` (the launcher sets it, FR-009). (5) *Four gates
stay human and each has one owner pane*: clarify and plan review in `plan`, merge in `deploy`,
tag/deploy in `deploy` on the laptop.

**Cost, stated.** Four panes kept small by rule 2 are four short contexts that a pointer wakes; the
work is billed once per phase per item, as in Shape A. Four panes that skip rule 2 are Shape B with
one fewer session. The number to watch is the one report 17 §7 Phase 2 already set — ≤ 2 messages
per item, none over 200 characters — plus the panes' own `/context` size at the end of a day.

**Two hosts.** `docs/architecture.md` gives the always-on workstation GitHub access only and the
laptop the production credentials. The `deploy` pane therefore splits: CI, PR and the babysitter on
the workstation; environment transitions and the production release on the laptop. The ledger is
per checkout, so the laptop reads the release queue through `git pull` plus `ledger list --phase
merged`, and HEF-4 (board write-back) is what makes the queue visible across the two machines
without a message.

**By object or by stage.** README §5 documents the layout the user runs today — `project`,
`feature`, `chore`: one pane per *object* (the documents, one feature, `main`). The four-pane
layout is one pane per *stage*. They are alternatives over the same spine, and the choice is a
question of who attends: by object when one person runs the repository and a feature should stay in
one pane end to end; by stage when more than one person attends, when the panes sit on different
hosts, or when the deck's discipline — a stage owns its clarifications — is wanted. In the by-stage
layout a feature crosses three panes and three ledger advances; in the by-object layout it crosses
one pane and the same three advances. The ledger does not know which layout is in use, and must
not.

### A3. Clarifications come from the stage that owns the block

"Any clarification will emerge from the responsible stage" is already how the ledger is shaped:
every block kind has exactly one owner. What is missing is the pane learning *its* kinds without
reading all of them.

| Block kind | Set by | Owner pane | Cleared by |
|---|---|---|---|
| `human:intake` | orchestrator (board text named a tool or file) | `orchestrator` | a person edits the item, re-hash via `record --body-file`, `unblock` |
| `human:clarify` | plan worker or `/hef.spec` (`[NEEDS CLARIFICATION]`) | `plan` | `/hef.clarify` answers; `unblock` with the artifact evidence |
| `human:plan-review` | `/hef.plan` | `plan` | `/hef.review` writes `## Reviewed` |
| `verdict`, `stall`, `budget`, `conflict` | verifier / launcher | `build` | a person splits, re-scopes, or retries (`claim` again) |
| `ci` | babysitter after its retry budget | `build` (the fix) then `deploy` (the re-push) | `/hef.fix` on the branch, push |
| `human:merge` | `/hef.pr` / babysitter at mergeable | `deploy` | the person merges; `unblock` checks branch ancestry |

**Proposed (HEF-12):** `orchestrate.panes` in `.claude/project-status.json` maps kinds to pane
names; `session-start-context.sh` appends the owner to each blocked line (`ledger: HEF-7 blocked_on
human:merge → deploy`), so every pane sees the whole queue and each line says whose it is — no
filtering by session name, which hooks cannot see. HEF-5's escalation message then targets the
kind's pane instead of one named session. Both are fixes on existing code.

### A4. The arena, phased

Slide 23's arena is five models from three vendors exploring the code in isolated sessions, merged
by the orchestrator into one study; slide 24 is one AI writing the RFC and another reviewing it. The
user's direction: configure whatever model access the hefesto user has — Claude, Google, OpenAI,
through APIs or personal accounts; on Bedrock, the models the account exposes, user-selected — but
**abstract it now as "opus writes, fable reviews"** and keep the multi-vendor arena as the next
phase. That is three phases, and the first is not future work:

| Phase | What it is | Where it stands |
|---|---|---|
| **0 — tiers** | Author and reviewer are different *processes* at different *tiers*: `orchestrate.tiers.implement: opus`, `verify: fable`, one `--model` per launched session, reviewer rank ≥ author rank enforced by the launcher (the −8.6 pp guard); `/hef.review` plan mode spawns a fresh `code-reviewer` at fable over an opus plan. This is slide 24 in its fresh-context form — the form the evidence gives most of the gain to (report 17 §1d) | **shipped** (7.3.0, 7.4.0); a config line, not a feature |
| **1 — same-vendor arena** | HEF-8 as written: `/hef.plan --arena K` fans the truth-map questions to K ≤ 3 `repo-scout` agents at different tiers, read-only, ≤ 2k-token digests, merged into `research.md` with per-claim attribution, disagreements → `[NEEDS CLARIFICATION]`. The measurement it exists for: how many claims the plan later needed came from a disagreement | backlog, next `/hef.plan` change |
| **2 — providers** | A `providers` block in `.claude/project-status.json` declares what the user has and how it is reached: `{"claude":{"via":"claude"},"openai":{"via":"codex"},"google":{"via":"gemini"},"bedrock":{"via":"aws","models":["…"]}}`. Each `via` is a **runner** — a CLI with a non-interactive mode the launcher can hand a prompt file to and read text back (`claude -p`; Codex's and Gemini's headless modes; for Bedrock models that are not Anthropic's, `aws bedrock-runtime converse`, since the `claude` binary drives only Anthropic models there). `hooks/arena-run.sh <provider> <prompt-file>` wraps them; detected with `command -v`, never installed, never in the manifest — the optional-provider lane. The arena becomes a fan-out over runners instead of over tiers, same K, same digest cap, same merge | after Phase 1 has a number; one helper, one config block, one `/hef.plan` flag value |

Three boundaries hold across the phases. **Authentication is the CLI's, never hefesto's:** a
personal login or an API key lives in the runner's own config; hefesto reads no key, stores no key,
and `block-sensitive-files.sh` keeps it that way. **Egress happens from the pane, never from a
hook or a worker:** launched sessions carry the sandbox, and a call to a second vendor from inside
one is exactly the egress the sandbox is there to stop — the same line the report 15 addendum drew
for a context filter. **A foreign-vendor model reviews as a labelled second opinion, never as the
verifier of record:** the launcher's reviewer ≥ author guard is a rank over one vendor's tiers;
across vendors the rank is undefined, and the −8.6 pp regression is what an unranked reviewer risks.
Slide 24's Claude-writes-Codex-reviews therefore enters as `/hef.review --second-opinion <provider>`
(the `--inline` pattern: reported, attributed, not a verdict) until an independent calibration on
code review exists — the same reopening condition report 15 set for Jev.

### A5. What this adds and what it leaves as decided

Nothing in report 17's accepted shape changes: the spine is still one fresh process per phase per
item over a file ledger, the human gates are the same four, the message type is still the one
pointer. What the re-read adds is a second pane layout and three light items for the board:

- **HEF-11 — stage roles in the launcher.** `session-launch.sh plan <id>` (writes under `.specify/`
  only; exits on the first clarification or at `ledger advance tasks`) and `deploy <id>` (HEF-7's
  babysitter as a headless role); `/hef.orchestrate --stage plan|build|deploy`, default `build` so
  today's call is unchanged; per-stage tiers under `orchestrate.tiers`.
- **HEF-12 — pane-aware block routing.** `orchestrate.panes` config; the owner pane on each
  session-start blocked line; HEF-5's escalation target per kind.
- **HEF-13 — providers registry and arena runners.** Phase 2 of A4, gated on HEF-8's number.
- **README §5** gains the by-stage layout as a second table with the choice rule in A2, and `docs/install.md` §7 the two-host split of the `deploy` pane.

Not adopted, unchanged: the orchestrator committing; sessions as the handoff; a Monitor role; a
cross-vendor verifier of record.
