---
status: accepted
date: 2026-09-27
---

# Multi-Session Orchestration: A Board-Driven Pipeline of Fresh Sessions Over a File Ledger, Not a Live Mesh

The question: how should hefesto grow from one attended session running the `hef.*` pipeline into dedicated sessions — an orchestrator that takes work from the board `/hef.status` already reads, an intake session that turns RFCs and issues into specs and tasks, engineering sessions, quality and security sessions, a release session — that communicate with each other without burning context or money. The answer the evidence supports is narrower than the question: a *fixed pipeline of short-lived, narrow-context sessions* coordinated through a file ledger and pull requests, with every human gate the framework already has left where it is, and live messaging reserved for one job — telling a human that a session is blocked. Role specialisation is worth having only where it buys a fresh window and a verifier that did not write the code; everything else it buys is coordination overhead that the literature measures at 4×–15× in tokens and 32–37 % of failures. **Decision proposed:** adopt Shape A — a board-driven pipeline of fresh headless sessions, one task per session, one worktree per task, verdicts from sessions that never saw the author's transcript — with a `hooks/ledger.sh` handoff contract and a `/hef.orchestrate` dispatcher; add cross-session messaging in a second phase for blocked-escalation only; adopt neither agent teams nor cloud routines for the pipeline unless a measured need appears.

This file does **not** cover the taxonomy of skills, subagents, teams and the four canonical topologies (`03-agent-topology-orchestration.md`), the protocol stack and why A2A was not adopted (`04-ai-protocol-stack.md`), the harness capability catalogue and hook events (`11-claude-code-harness-capabilities.md`), the field report on multi-repo fan-out and 429/529 overload (`12-field-report-speckit-workflow-multi-repo-and-overload.md`), the September 2026 review that adopted `owns:` lists, worktree isolation and sequential merges (`14-harness-review-2026-09.md`), or the evidence for spec-first routing (`16-spec-first-vs-incremental-prompting.md`). It builds on all six and restates none.

**Sources:** MAST (arXiv 2503.13657); the SWE-bench leaderboard dissection (arXiv 2506.17208); E2EDevBench (arXiv 2511.04064); AgentCoder (2312.13010) and MapCoder (2405.11403); Google/MIT scaling of agent systems (2512.08296); the equal-budget study (2604.02460); NoLiMa (2502.05167), Du et al. (2510.05381), Chroma *Context Rot*; cross-model review (2607.21656) and *The Self-Correction Illusion* (2606.05976); the AIDev PR studies (2601.15195, 2605.22534, 2607.04697, 2512.21426); Anthropic engineering posts and Claude Code docs (cross-session messaging, agent teams, workflows, routines, headless, hooks, costs, agent view); Cognition 2025/2026; Microsoft Magentic-One; the CSA *Comment and Control* note; Fortune and SC Media on the Replit and Amazon Q incidents; this repository at v7.2.0.
**Decisions taken (2026-09-27):** accepted; Phase 1 starts on hefesto itself with a small `tasks/` kanban (the `tasks-repo` source `/hef.status` already reads) seeded from the changelog's Known issues; the orchestrator lives under herdr on the always-on workstation; board write-back waits for Phase 2.
**Codified in:** *not yet* — the Phase 1 spec is drafted on the parked branch `feature/session-orchestration` (`.specify/specs/session-orchestration/spec.md`); the components (§6) are not built; the adoption plan is §7.

## 1. The evidence that decides the shape

### Roles buy a separate tester and a fresh window, not an org chart

The gains attributed to "roles" on small benchmarks come from two mechanisms. The first is separating test authorship from code authorship: in AgentCoder's GPT-3.5 ablation the coder's own tests are **61.0 % accurate against 87.8 %** from a separate Test Designer, and that separation alone lifts HumanEval from 71.3 % to 79.9 % ([AgentCoder](https://arxiv.org/html/2312.13010)). The second is an execution-fed debug loop: removing MapCoder's debugging agent costs **−17.5 %**, removing its planner −16.7 % ([MapCoder](https://arxiv.org/html/2405.11403)). What does not help is a planner whose blueprint constrains the implementer: on E2EDevBench a Developer–Tester pair reached **49.48 %** requirement implementation against 45.72 % for a single agent, while adding a Designer whose plan bound the developer collapsed it to **27.71 %** — the most expensive configuration was the worst ([E2EDevBench](https://arxiv.org/pdf/2511.04064)).

At repository scale the shape that wins is a human-authored pipeline with an agent per stage. Across all 178 SWE-bench Lite and Verified entries, the Verified medians are **63.4 %** for a fixed workflow with multiple agents (G3, n = 5), 56.0 % for a fixed workflow with one agent, 54.2 % for emergent single agents (the largest group, n = 31), and **40.6 %** — the lowest agentic median — for scaffolded multi-agent systems (G5, n = 15) ([Martinez & Franch](https://arxiv.org/html/2506.17208v2)). The controlled studies say why. Under an equal reasoning-token budget single agents "consistently match or exceed" multi-agent systems, which "become competitive when a single agent's effective context utilization is degraded" — the mechanism is fresh narrow context, not the role label ([arXiv 2604.02460](https://arxiv.org/abs/2604.02460)). Google/MIT's 260-configuration study finds multi-agent gains of up to +80.8 % on decomposable tasks and degradation of **−39 % to −70 % for every multi-agent variant on sequential planning**, with centralised verification propagating fewer errors ([arXiv 2512.08296](https://arxiv.org/abs/2512.08296)). Implementation work is a dependency chain; the orchestration design must therefore buy context isolation and verification, and pay nothing for role-play.

### Failures are control flow and specification; verification is the cheap fix

MAST's 1,600-trace taxonomy puts **41.77 %** of failures in specification and system design, **36.94 %** in inter-agent misalignment and 21.30 % in verification. Three of its modes — step repetition 15.7 %, unaware of termination 12.4 %, premature termination 6.2 % — sum to **34 % of all failures that are control flow**, which a deterministic orchestrator removes by construction. The two interventions the authors measured on ChatDev are a topology change (the CEO gets the final say, **+9.4 %**) and a high-level verification step (**+15.6 %** task completion), and they judge that "improved base model capabilities will be insufficient" to remove these failures ([MAST](https://arxiv.org/html/2503.13657v3)). E2EDevBench independently attributes 55.8 % of failed requirements to planning and comprehension (27.9 % omitted outright), which argues for a mechanical FR → task → test trace rather than trust in the planner ([E2EDevBench](https://arxiv.org/pdf/2511.04064)) — the check `speckit-helper.sh req-coverage --all` already performs.

### Context degrades well before the window is full

Eleven of thirteen models claiming 128K contexts fall below half their short-context score by **32K tokens** once lexical matches are removed; GPT-4o drops 99.3 % → 69.7 % ([NoLiMa](https://arxiv.org/abs/2502.05167)). With perfect retrieval guaranteed, five models still lose **13.9 %–85 %** as input grows, on coding among other tasks ([Du et al.](https://arxiv.org/abs/2510.05381)). Chroma measured all 18 frontier models — including the Claude 4 family — degrading with length, with focused ~300-token inputs beating full ~113K inputs across every family ([Chroma](https://www.trychroma.com/research/context-rot)). Anthropic's own multi-agent gain "was strongly linked to token usage and the ability to spread reasoning across multiple independent context windows" (vendor claim, research not coding) ([Anthropic](https://www.anthropic.com/engineering/multi-agent-research-system)). The design consequence is structural: a session is a context budget, and the cheapest way to keep every session under 32K of live material is to end it at the phase boundary and start another.

### Reviewer ≠ author, with two caveats

Self-review by the strongest available model is noise: Claude Opus 4.7 solo 91.4 % → 91.4 % with self-review (3 fixes, 3 regressions) at +72 % cost. Review of a weaker author by a stronger reviewer is the largest measured lift: Codex GPT-5.5 **71.6 % → 89.7 %** with Opus review (+18.1 pp, regression rate 4.3 %). The caveat that matters for tier policy: a *weaker* reviewer on the strongest author regressed it **−8.6 pp** (11.2 % regression rate) ([arXiv 2607.21656](https://arxiv.org/html/2607.21656)). The second caveat explains why a fresh context recovers most of the value even with the same model: relabelling an identical error from the model's own thought to a user or tool message raised correction rates by **23–93 pp** across seven families — the "self-correction illusion" is a chat-template artifact, so an external reviewer framed as such breaks it ([arXiv 2606.05976](https://arxiv.org/html/2606.05976v1)). Cognition reports the same from production: review agents "perform better without shared context", and Devin Review "catches an average of 2 bugs per PR, of which roughly 58 % are severe" (vendor) ([Cognition 2026](https://cognition.com/blog/multi-agents-working)).

### Every extra live session is billed as a full context

Agents use about **4×** the tokens of chat and multi-agent systems about **15×** (vendor) ([Anthropic](https://www.anthropic.com/engineering/multi-agent-research-system)). Claude Code agent teams use "approximately **7×** more tokens than standard sessions when teammates run in plan mode" ([Claude Code costs](https://code.claude.com/docs/en/costs)). A cross-session message is delivered "as a new turn when this session sits idle, sending your full context each time" — every inbound ping to a long-lived session is a full-context request ([Claude Code costs](https://code.claude.com/docs/en/costs)). `/compact` "is itself a large request" while `/clear` "costs nothing"; the subagent and workflow prompt cache holds for **five minutes** by default unless `subagentPromptCacheTtl: "1h"` is set at higher cost, and the first message after a break longer than the cache lifetime reprocesses the full context ([Claude Code agent teams](https://code.claude.com/docs/en/agent-teams); [costs](https://code.claude.com/docs/en/costs)). Anthropic's stated return size for a specialist is "often 1,000–2,000 tokens" ([Anthropic context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)). Chat-heavy frameworks cost 2.4–3.9× more than pipeline ones on identical tasks (ChatDev 183.7K tokens vs AgentCoder 56.9K on HumanEval) ([AgentCoder](https://arxiv.org/html/2312.13010)). Long-lived talking sessions are the most expensive design available, and they pay for that with the failure class MAST measures at 37 %.

### Production: merge is the gate, and text is the attack surface

Across 33,596 agent PRs in 2,807 repositories the merge rate is **71.48 %** (Codex 82.59 %, Copilot 43.04 %); "each additional CI failure reduces merge odds by ~15 %"; duplicates are **23 %** of rejected PRs and reviewer abandonment **38 %** ([arXiv 2601.15195](https://arxiv.org/html/2601.15195)). Only 35.7 % of rejections are genuine agent failures; 31.2 % are workflow constraints ([arXiv 2605.22534](https://arxiv.org/abs/2605.22534)). 79.4 % of agent PRs are open concurrently with another, and textual merge conflicts run **41.7 % cross-agent against 19.8 % intra-agent** ([arXiv 2607.04697](https://arxiv.org/html/2607.04697v2)). Issue readiness is measurable: shorter descriptions with clear task boundaries raise Copilot acceptance by up to 16 % ([arXiv 2512.21426](https://arxiv.org/html/2512.21426v1)). Devin's merge rate rose 34 % → 67 % in 2025 (vendor) ([Cognition](https://cognition.com/blog/devin-annual-performance-review-2025)).

No studied product merges its own PR; GitHub adds that "the PR requester cannot approve the resulting pull request" and holds CI until a human clicks approve ([GitHub Docs](https://docs.github.com/en/copilot/concepts/agents/cloud-agent/risks-and-mitigations)). "No documented autonomous deployment or monitoring patterns as of July 2026" ([Augment Code](https://www.augmentcode.com/guides/autonomous-engineering-loop)). The April 2026 *Comment and Control* disclosure hijacked Claude Code Security Review through a PR title, Gemini CLI through an issue body and Copilot through an HTML comment, exfiltrating `ANTHROPIC_API_KEY`, `GITHUB_TOKEN` and runner secrets back through GitHub itself — rated CVSS 9.4, bountied at $100 ([CSA](https://labs.cloudsecurityalliance.org/research/csa-research-note-comment-control-github-prompt-injection-20/)). Replit's agent deleted a production database during a code freeze that "lived only in the instructions" ([Fortune](https://fortune.com/2025/07/23/ai-coding-tool-replit-wiped-database-called-it-a-catastrophic-failure/)); a wiper prompt shipped in Amazon Q 1.84.0 to nearly a million developers via a PR from a contributor handed admin credentials ([SC Media](https://www.scworld.com/news/amazon-q-extension-for-vs-code-reportedly-injected-with-wiper-prompt)). The common root: a control that existed as text with nothing in the execution path enforcing it.

## 2. What the platform provides

| Primitive | Durable? | Cross-machine? | Unattended? | Structured payload? | Cost profile |
|---|---|---|---|---|---|
| Cross-session `SendMessage` / `ListAgents` (v2.1.224+) | No — a bounded queue only (the two docs pages fetched state 50 and 100 held messages; treat the exact cap as unconfirmed) | Yes, via Remote Control / Anthropic servers; not host↔container | Only if the `-p` receiver sets `crossSessionInbound: accept`; the default holds for approval and the dialog expires in 5 min | No — plain text; slash commands arrive as text; cannot approve or change settings | Each delivered message = one full-context turn; `notify_when_idle` is a one-shot notice, 12 h expiry |
| Agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) | No — `/resume` does not restore in-process teammates | No | No — interactive sessions only | Shared task list with file locking + JSON mailbox per agent | ~7× a standard session in plan mode; teammates get only the spawn prompt + CLAUDE.md |
| Workflow tool (`workflows/*.js`) | Within one session (completed agents replay; a new session cannot) | No | Yes in `claude -p` | Yes — `schema` per `agent()` | Linear in concurrent agents; prefix-sharing stagger; no mid-run input |
| Cloud routines | Yes — each run is a fresh cloud session | Yes (cloud) | Yes, no prompts | API `text` field wrapped in `<routine-fire-payload>`; GitHub-event filters | Subscription usage; min interval 1 h; 30 fires/h/routine; no routine-to-routine messaging |
| In-session `/loop`, `CronCreate`, `ScheduleWakeup` | No — 7-day expiry, fires only while idle | No | Interactive only | Prompt text | One turn per fire |
| Hooks: `TeammateIdle`, `TaskCreated`, `TaskCompleted` (exit 2 blocks), `Stop`, `SessionEnd`, `PreCompact` | Script-defined | Script-defined | Yes | JSON on stdin | Shell cost only; `TaskCompleted` is already hefesto's Iron Law gate |
| Headless `claude -p` with `--resume <id\|transcript.jsonl>`, `--output-format json`, `--json-schema`, `--allowedTools`, `--permission-mode`, `--settings`, `--name` | Yes — transcript on disk, resumable cross-directory (v2.1.223+) | Via the transcript file | Yes | Yes — `structured_output` | One full run per invocation; `total_cost_usd` in the JSON result |
| `claude agents --json` | — | — | Yes | `state`, `status`, `waitingFor` | Free |
| Worktrees: `isolation: worktree`, background sessions under `.claude/worktrees/` | Git | Git | Yes | — | Git only |
| GitHub Action / Slack / Agent HQ intake | Yes (PR + link on ticket) | Yes | Yes | `structured_output` in agent mode | CI minutes + tokens; Action cannot approve PRs or push to main by default |

What does not exist, and no design below may assume: persistent state between independent sessions except through files, git or a database; structured messages (JSON must be sent as text and parsed); waking an *existing* session from a webhook (the routine API creates a new session); nested teams; resuming a team; replaying a workflow from another session; automatic respawn after a crash (an external supervisor is required); an allowlist of senders per session (`crossSessionInbound` is one setting for all inbound). Subagent output is only *marked* when it matches an instruction-shaped pattern, not removed ([Claude Code subagents](https://code.claude.com/docs/en/sub-agents)).

## 3. What hefesto already has for each role

Today the plugin sends no message between sessions. Its only cross-session channels are files — the `.specify/specs/<branch>/` artifacts and phase markers, the checkpoint `precompact-progress.sh` writes to `${XDG_CACHE_HOME:-~/.cache}/hefesto/progress/<sha1 cwd:16>.md` and `session-start-context.sh` reads back, `.claude/agent-memory/<agent>/` for `code-reviewer` and `forensic-specialist`, `.specify/mutation-score` — and git/GitHub state: branches, PRs, and the GitHub Project or tasks-repo kanban that `hooks/status-board.sh` reads for `/hef.status`. The user's terminal orchestrator is herdr: one workspace per company, a worktree workspace per feature (`herdr worktree create --branch feat/x --label "<company> · <repo> · <feature>"`, checkout under `~/.herdr/worktrees/<repo>/<branch>`), with `herdr agent list` / `wait --until blocked` / `focus` as the triage verbs and a `SessionStart` hook reporting the session↔pane mapping. `docs/architecture.md` already names the two-machine topology: an always-on Arch workstation that holds GitHub access only, and a laptop that alone holds production credentials.

| Session role | Exists today | Missing |
|---|---|---|
| Orchestrator (board → dispatch) | `/hef.status` + `hooks/status-board.sh` (read-only FETCHER over `github-project` or `tasks-repo`, `--detailed` lists sub-issues with status and assignee); `/hef.agent` (size router fix / light / full via `task-effort-estimation`); `session-start-context.sh` (branch, artifacts, open tasks, last checkpoint) | Claiming an item, recording which session owns it, spawning a worker in a worktree, reading its result, a dispatch loop; any machine-readable per-task state |
| Intake (RFC / issue → spec → tasks) | `/hef.brainstorm` (H), `/hef.spec` (creates `feature/<name>`, H before switching), `/hef.clarify` (H, ≤5 questions), `/hef.plan` (+ `plan-phase-write-block.sh`), `/hef.review` plan mode (H, writes `## Reviewed`), `/hef.tasks` (`[P]`, `owns:`, `[FR-NNN]`, `addBlockedBy`), `/hef.checklist`, `/hef.analyze`; the untrusted-text rule in `/hef.fix` and `/hef.pr` | An entry point that takes a board or issue reference, records the source ref, and applies the delimit-and-strip rule to the fetched body |
| Engineering | `/hef.implement`, `hefesto:workflow` (phase order in code, three adversarial verifier lenses per task, `owns:`-disjoint batching), `test-specialist`, `implement-phase-test-guard.sh`, `format-after-edit.sh`, `run-tests-after-edit.sh`, `merge-tree-probe.sh`, `verify-before-task-complete.sh` (`TaskCompleted`, exit 2), `precompact-progress.sh` | A launcher that starts the session headless in its own worktree with the right flags and a turn/budget cap; a result written somewhere the orchestrator can read |
| Quality + verification | `/hef.verify` (`req-coverage` then `code-reviewer` Stage 1), `/hef.quality` (`quality-guardian` at sonnet), `/hef.mutate` (ratchet), `/hef.review` code mode (`code-reviewer` at fable), `quality-before-commit.sh` (gitleaks, lizard delta gate, linters) | Running these in a *separate* process that receives only diff + spec, never the author's transcript; a verdict recorded per gate |
| Security | `/hef.scan`, `forensic-specialist`, `block-sensitive-files.sh`, `block-destructive-commands.sh`, gitleaks on staged changes, `mcp-security`, `pipeline-security` | A secret scan of what the agent is about to *post* (PR body, comments); an injection boundary at intake |
| PR / integration | `/hef.pr` → `review-coordinator` ("never merges", one PR at a time, sequential integration) | Nothing structural — merge stays human |
| Release / deploy | `/hef.release` + `hooks/release.sh` (bumps versions, scaffolds CHANGELOG, never commits, tags or pushes, "then stop for the human edit"); `tests/smoke.sh` | Nothing — the evidence shows no shipped autonomous deployer and the framework already stops at the right line |
| Evals | five cases under `evals/` (`destructive-command-refusal`, `spec-first-routing`, `no-ceremony-for-trivial`, `root-cause-before-fix`, `effort-sizing`) | Cases for the orchestrator: honours `blocked_on`, never merges, treats board text as data |

## 4. Four candidate shapes and one hybrid

### Shape A — board-driven pipeline of fresh sessions

```
  board (GitHub Project | tasks-repo)
      │  status-board.sh (read)                 ledger: ~/.cache/hefesto/ledger/<repo>/<id>.json
      ▼
  orchestrator session  ──ledger claim──▶  claude -p  worker (worktree, feature/<id>)
  (claude -p loop or      ◀──exit code +      runs: hef.agent → implement|workflow → verify → quality
   interactive, sonnet)     json result         → scan → review(code) → pr        [never merges]
      │
      ├──ledger advance──▶  claude -p  verifier (fresh process, diff + spec only, fable/sonnet)
      │                     runs: hef.verify → hef.review code → hef.scan   [never approves]
      ▼
  PR + ledger verdicts  ──▶  human: review, merge   ──▶  release session (hef.release, stops at tag)
  blocked_on: human:clarify | human:plan-review  ──▶  herdr wait --until blocked / notify
```

Primitives: `claude -p` with `--name`, `--output-format json`, `--json-schema`, `--allowedTools`, `--settings`; git worktrees; hooks already registered; no messaging. Handoff artifact: the ledger entry plus the PR. Human gates: clarify, plan review, merge, tag/deploy — unchanged. Context budget: each session starts empty and ends at a phase boundary; the verifier's context is diff + spec + `req-coverage` matrix. Cost: one full run per phase per task, no idle sessions, no per-message billing. Predicted failures: intake plumbing loss (the Codex/Linear class), duplicate dispatch if claims are not exclusive, stale `blocked_on` if a worker dies without writing (mitigated by exit-code capture and a stall timeout, Magentic-One's stall count > 2).

### Shape B — live mesh of long-lived role sessions

```
  orchestrator ◀──SendMessage──▶ intake ◀──▶ engineering ◀──▶ quality+security ◀──▶ release
        ▲                 (text pointers to ledger entries; ledger on disk is the truth)
        └──── crossSessionInbound: accept on every -p session; notify_when_idle subscriptions
```

Primitives: five persistent sessions, `SendMessage`/`ListAgents`, file ledger. Handoff: a message naming a ledger entry. Human gates: as A, but the human must find which pane is blocked. Context: each session accumulates every task it has touched — exactly the >32K regime NoLiMa and Du measure; the reviewer inherits its own prior reviews. Cost: every inbound message is a full-context turn on a growing context; five sessions idle between tasks reprocess their context after the cache lapses. Predicted failures: MAST's inter-agent misalignment class (37 %), message loops (throttled but real), held messages expiring after 5 minutes when one side prompts and the other bypasses, and the semantic drift the communication survey names for pipelines expressed as conversation.

### Shape C — agent team per feature

```
  lead (interactive, per feature)  ── shared task list (file-locked) ──┐
     ├── teammate implement  (owns: files A)                           │ mailbox JSON per agent
     ├── teammate verify     (read-only, different files)              │ TeammateIdle / TaskCompleted hooks
     └── teammate security   (hef.scan, read-only)                     ┘
```

Primitives: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, the shared task list, `TeammateIdle`/`TaskCreated`/`TaskCompleted` hooks. Handoff: task-list transitions. Human gates: permission prompts surface in the lead; plan approval is auto-approved by the lead without the user — a gate the framework treats as human. Context: teammates start from the spawn prompt only, which is good; the lead accumulates. Cost: ~7× in plan mode. Predicted failures: no resume (a crash loses the team), "task status can lag", same-file overwrites without worktrees, interactive-only so herdr cannot run it unattended.

### Shape D — event-driven cloud routines plus local human-gated sessions

```
  GitHub events ──▶ routine: intake (issue labeled)      ──▶ draft spec on claude/<branch>
                ──▶ routine: review + scan (PR opened)   ──▶ PR comment (no approval)
                ──▶ routine: release notes (release)     ──▶ CHANGELOG PR
  local sessions (laptop / herdr): hef.clarify, hef.review plan, merge, hef.release, deploy approval
```

Primitives: routines with GitHub triggers and the API `fire` endpoint; the Claude GitHub App. Handoff: PRs and comments — the same contract every shipped product uses. Human gates: local and explicit. Context: each run is fresh by construction. Cost: subscription usage; daily run caps; 1-hour minimum schedule; every run re-clones and re-reads the repository. Predicted failures: the *Comment and Control* class — issue and PR text is the routine's input and Anthropic documents its own security review as "not hardened against prompt injection"; no routine-to-routine channel, so the pipeline order lives in trigger filters; no local filesystem, so `graphify`, `rtk`, the mutation tool and any project-local tooling are absent.

### Shape E — the hybrid the evidence best supports

Shape A as the spine, with two bounded borrowings: from B, one message type only — "ledger `<id>` is `blocked_on` `<kind>`" — sent to a named human-attended session (Phase 2); from D, the option to run the *verifier* role as a GitHub-event routine on the always-on host's behalf only after Phase 1 metrics show the local verifier is the bottleneck. Nothing from C.

| Criterion | A: fresh pipeline | B: live mesh | C: team per feature | D: routines + local gates | E: hybrid |
|---|---|---|---|---|---|
| Context economy | Best — every session is one task, one phase; reviewer sees diff + spec | Worst — five growing contexts; each message a full turn | Good for teammates, poor for the lead | Best per run; repository re-read per run | As A |
| Cost | One run per phase; no idle | 15×-class; idle reprocessing after cache lapse | ~7× in plan mode | Subscription + caps; no local tools | As A + ≤2 messages/task |
| Durability / resume | Transcript + ledger + PR; resumable via `--resume` | Queue-only; dead session = lost pings | None — teams do not resume | Cloud-durable per run; no cross-run state except git | As A |
| Security posture | Board text delimited once at intake; worker token push-only to `feature/*`; verifier cannot approve; sandbox on | Same, plus `accept` on every session widens the inbound surface | Lead relays permissions; plan auto-approved | Routine reads untrusted issue/PR text by design; secrets in cloud env | As A |
| Constitution and herdr fit | Zero-install (bash + jq), helpers fail loudly, ledger outside `.claude/`, commands `hef.*`; one worktree per feature matches herdr's model | Fits constitution; herdr can show panes but not the blocked reason | Interactive only — herdr cannot run it unattended | Needs the GitHub App and cloud; bypasses the two-machine trust boundary in `docs/architecture.md` | As A |
| New code | `ledger.sh`, `session-launch.sh`, `/hef.orchestrate`, two evals | As A + inbound settings per role + a message protocol | Team prompts + hooks; no ledger | Routine prompts + CI YAML; no local code | A + one message type |

## 5. The recommended shape and its design

Shape A, extended to E in phases. The lines that decide it: fixed workflows with an agent per stage hold the best SWE-bench Verified median (63.4 %) while scaffolded multi-agent systems hold the worst (40.6 %); the mechanism of multi-agent gains is fresh context, not roles (2604.02460); 34 % of MAST failures are control flow that a script removes and 37 % are misalignment that live messaging invites; every cross-session message is billed as a full turn; a reviewer with a shorter context is a better reviewer (Cognition; 2607.21656); and the production contract every shipped product converged on is ticket → session → draft PR → link on ticket, never a message bus. herdr already gives the user the pane-per-feature view and `wait --until blocked`; the design must feed that, not replace it.

### 5a. The ledger and the pointer rule

The ledger lives outside every checkout, following the precedent `precompact-progress.sh` set ("never inside the repo"): `${XDG_CACHE_HOME:-$HOME/.cache}/hefesto/ledger/<sha1(main checkout):16>/<task-id>.json`. Putting it in the repository would make it a merge-conflict hotspot across worktrees (the class the 41.7 % figure measures) and putting it under `.claude/` would violate constitution principle 1. The board stays the human-visible, cross-machine copy; the PR is the cross-machine artifact; the ledger is the machine-readable local state one orchestrator owns.

| Field | Type | Written by | Meaning |
|---|---|---|---|
| `id` | string | `ledger init` | Board item id (`id_pattern` from `.claude/project-status.json`) |
| `source` | `{kind, ref, url, body_sha256}` | `ledger init` | `github-project` or `tasks-repo`; the hash lets a later run detect edited item text |
| `route` | `fix \| light \| full` | worker after `/hef.agent` | Size route |
| `phase` | enum | `ledger advance` | `queued → intake → spec → plan → plan-review → tasks → implement → verify → quality → security → pr → merged → released` |
| `branch`, `worktree`, `spec_dir` | strings | `ledger claim` | `feature/<id>`, `~/.herdr/worktrees/<repo>/<branch>` or `.worktrees/<id>`, `.specify/specs/<id>/` |
| `owner` | `{session_name, role, pid, started}` | `ledger claim` | Exactly one; a second claim fails loudly |
| `pr` | `{number, url, state}` | worker after `/hef.pr` | — |
| `verdicts[]` | `{gate, verdict, by, at, evidence}` | verifier | `verify`, `review`, `quality`, `scan`, `mutate`; `by` is a session name that must differ from `owner.session_name` for `review` |
| `blocked_on` | `{kind, since, question_path}` or null | `ledger block` | `human:clarify`, `human:plan-review`, `human:merge`, `ci`, `conflict`, `budget`, `stall` |
| `budget` | `{turns_cap, usd_cap, usd_spent}` | launcher; worker result | `total_cost_usd` from `--output-format json` |
| `attempts`, `updated` | int, ISO | every write | Stall detection: `attempts > 2` → `blocked_on: stall` (Magentic-One's rule) |

The pointer rule: **a message, a PR comment or a board note carries at most the task id, the phase, the `blocked_on` kind and a path; it never carries the diff, the transcript, the review or the spec.** Anything larger is written to the ledger, the spec directory or the PR and referenced. This is Anthropic's "artifact systems where specialized agents can create outputs that persist independently" and A2A's Message/Artifact split, and it is what keeps every receiver's context near the 1,000–2,000-token return size.

### 5b. Per-role session definitions

| Role | Launched as | Tier | Tools / inbound | Runs | May never |
|---|---|---|---|---|---|
| Orchestrator | `claude -p` in a loop under herdr (or interactive with `/loop` during Phase 1 trials); `--name orchestrator`; main checkout | sonnet (mechanical, as `/hef.status`) | `Read`, `Bash(status-board.sh *)`, `Bash(ledger.sh *)`, `Bash(session-launch.sh *)`, `Bash(git worktree *)`; `crossSessionInbound: refuse` in Phase 1, `accept` in Phase 2 with every inbound treated as data | `/hef.orchestrate` | Edit source; run `gh pr merge`, `gh pr review --approve`, `git push` to `main`; edit `.claude/settings*`; unblock a `human:*` entry |
| Intake | interactive in a herdr pane (it owns three human gates) | fable for `/hef.brainstorm`, `/hef.spec`, `/hef.clarify`, `/hef.review`; opus for `/hef.plan`, `/hef.tasks` (existing policy) | writes only under `.specify/` (`plan-phase-write-block.sh` enforces this during plan; extend the marker to the whole intake run) | `/hef.agent --source <ref>` → spec → clarify → plan → review → tasks → `ledger advance tasks` | Touch source files; switch branches without the ask `/hef.spec` already makes |
| Engineering worker | `session-launch.sh implement <id>`: `claude -p -w <id>` (the CLI creates the worktree), `--name impl-<id>`, `--permission-mode acceptEdits`, `--allowedTools` for the project's test/lint commands, `--settings` with `crossSessionInbound: refuse` and `sandbox.enabled: true`, `--max-budget-usd` cap (the CLI's only hard spend cap; `--max-turns` is an Agent SDK option, not a CLI flag), `--output-format json --json-schema` | opus | All hefesto hooks inherited (`block-destructive-commands.sh`, `implement-phase-test-guard.sh`, `quality-before-commit.sh`, `TaskCompleted` gate) | `/hef.implement` or `hefesto:workflow`, then `/hef.pr` | Merge; approve; push anywhere but `feature/<id>`; write outside the worktree; `/compact` (exit and resume instead) |
| Verifier (quality + security) | `session-launch.sh verify <id>`: fresh `claude -p` on the same worktree after the worker has exited, `--name verify-<id>`, read-only allowlist | fable for `code-reviewer`, sonnet for `quality-guardian`, opus for `/hef.verify` (existing) | `Read`, `Grep`, `Glob`, `Bash(<test runner>)`, `Bash(gitleaks *)`, `Bash(semgrep *)`; `disallowedTools: Edit, Write` | `/hef.verify` → `/hef.review` code mode → `/hef.quality` → `/hef.scan` → `/hef.mutate`; `ledger verdict` per gate | Edit anything; `gh pr review --approve`; read the worker transcript |
| Release | interactive on the laptop (the only host with production credentials, per `docs/architecture.md`) | sonnet | as today | `/hef.release` → stops at the human edit; human tags, pushes, deploys | Tag, push, deploy, or be launched by the orchestrator |

Tier routing follows the standing rule — cheap generation, expensive judgment — with the one new constraint 2607.21656 adds: **the reviewer tier must be at least the author's tier.** `code-reviewer` at fable reviewing an opus worker satisfies it; a sonnet reviewer over an opus author is the −8.6 pp configuration and is forbidden by the launcher.

### 5c. Context-economy rules, stated as structure

Each rule is a launcher or ledger constraint, not advice. One task per session and one worktree per task: the launcher refuses a second `claim` on an id. Fresh context per phase boundary: the worker process exits at `/hef.pr`; the verifier is a different process; the intake session ends after `/hef.tasks` with a recommended `/clear` (the `/hef.brainstorm` convention). The reviewer gets a narrower context than the author: the verifier launcher passes the spec path, the `req-coverage` matrix and `git diff base...HEAD`, and `--forward-subagent-text` is never set. Summaries are ≤ ~2,000 tokens: the worker's `--json-schema` result has a `summary` field with a length cap the launcher validates. No transcript forwarding: the ledger stores paths, never text. The `PreCompact` checkpoint stays as the safety net (`precompact-progress.sh`), but the design goal is that a worker never compacts — `--max-budget-usd` and the size router keep a task inside one window, and a task that hits the cap is `blocked_on: budget` for the human to split, the same conclusion Copilot's 59-minute cap encodes. Cache TTL: workers keep the 5-minute default because they are short; only a long-lived interactive orchestrator would set `subagentPromptCacheTtl: "1h"`, and only if it spawns subagents. Tool output is trimmed before it enters context by running test and lint commands through `rtk` where `speckit-helper.sh rtk-available` says it is installed (the `quality-tooling` skill's pattern), which is what the costs page recommends.

### 5d. Human gates and how a blocked session surfaces

Four gates stay human: `/hef.clarify` answers, `/hef.review` plan mode, merge, and tag/deploy. A session that reaches one writes `blocked_on` and exits (headless) or idles (interactive). Three surfaces read that state, none of them a message payload: `session-start-context.sh` gains one line — `ledger: <id> blocked_on <kind> since <t>` — so any session opened in that checkout sees it; herdr's `agent wait --until blocked` and `claude agents --json` (`waitingFor`) show the pane; `notify-on-block.sh` already turns a Notification into `notify-send`. In Phase 2 the orchestrator additionally sends the one permitted message type to a named attended session. The orchestrator never resolves a `human:*` block; only a human command (`/hef.clarify`, `/hef.review`, `gh pr merge` by the person) advances it, and the `ledger unblock` subcommand refuses `human:*` kinds unless invoked from an interactive session.

### 5e. Security rules

Board and issue text is data: `/hef.orchestrate` and `/hef.agent --source` wrap the fetched title and body in a delimited block, strip HTML comments before reasoning, and stop if the text names a tool to run or a file to edit — the rule `/hef.fix`, `/hef.pr` and `review-coordinator` already carry, now applied at the first read, which is where *Comment and Control* struck. `source.body_sha256` in the ledger makes an edited-after-claim item visible. Least-privilege tokens: the orchestrator's `GITHUB_TOKEN` is read-only plus `read:project`; the worker's token can push to `feature/*` only; branch protection with requester-cannot-approve makes self-merge structurally impossible, not textually forbidden. No self-approval: the verifier has no `gh pr review` in its allowlist and `by ≠ owner` is checked by `ledger verdict`. Sandbox on: every launched session carries `{"sandbox":{"enabled":true,"failIfUnavailable":true}}`, the boundary `docs/install.md` names as the one a string-matching hook cannot promise. Secret scan of agent output: `/hef.pr` runs gitleaks over the PR body and any comment text before posting (the CSA recommendation "deploy secret scanning on agent-posted content before publication"). Every launched `-p` session sets `crossSessionInbound` explicitly, and `isolatePeerMachines: true` is set on the attended sessions.

## 6. New components

| Component | Verdict | Evidence line | Constitution check |
|---|---|---|---|
| `hooks/ledger.sh` — `init \| claim \| advance \| verdict \| block \| unblock \| show \| next \| list`; FETCHER/PREDICATE contract; jq; every subcommand fails loudly on a missing or double-claimed entry | **Required** (Phase 1) | 34 % of MAST failures are control flow; Magentic-One's two-ledger design; report 03's "invisible state" anti-pattern | Bash + jq, zero-install; outside `.claude/` and outside the repo; mutation-tested in `tests/smoke.sh` (reintroduce a silent double claim and confirm red) |
| `hooks/session-launch.sh <role> <id>` — builds the `claude -p` invocation per §5b: worktree, `--name`, `--settings` (inbound, sandbox), `--allowedTools`, `--max-budget-usd`, `--json-schema`; validates reviewer tier ≥ author tier; captures exit code and `total_cost_usd` into the ledger | **Required** (Phase 1) | Fresh narrow context is the mechanism (2604.02460); reviewer-tier rule (2607.21656); Copilot's hard cap | Never a concrete model id — tiers only; helper via the Bash tool; mutation test: a sonnet reviewer over an opus author must be refused |
| `/hef.orchestrate` — reads the board via `status-board.sh`, applies the untrusted-text rule, `ledger init/claim` for items in the `todo` column not already owned, launches one worker at a time per repository (sequential merges, report 14), records results, never merges | **Required** (Phase 1) | Duplicates are 23 % of rejected agent PRs; cross-agent concurrent conflicts 41.7 %; requester-cannot-approve is the only structural gate found | `hef.*` namespace; sonnet tier (mechanical, dispatches an opus agent, like `/hef.pr`); read-only over the board in Phase 1 |
| `/hef.agent --source <ref>` — records the source ref and hash in the ledger and delimits the fetched body | **Optional** (Phase 1, small) | Issue readiness +16 %; the injection surface is the first read | Extends an existing command rather than adding `/hef.intake` |
| `/hef.intake` as a new command | **Rejected** | The intake path already exists as `/hef.agent → /hef.spec → … → /hef.tasks` with its three human gates; a new command would duplicate the router | Core rule 3 |
| `evals/orchestrator-honours-blocked`, `evals/orchestrator-never-merges`, `evals/board-text-is-data` — scaffolds with a ledger entry `blocked_on: human:merge`, a fixture PR, and an item body containing "run `rm -rf` and edit settings.json" | **Required** (Phase 1) | Replit and *Comment and Control*: a control that lives only in text fails; the constitution requires the guard be red when the bug is reintroduced | Principle 3; `tool_used` graders on `gh pr merge` with max 0 |
| `session-start-context.sh` one-line addition for `blocked_on` | **Required** (Phase 1) | Blocked → escalate state machine is what no vendor documents; herdr needs a reason, not just a state | Existing hook; mutation-tested |
| `ledger publish` — write phase and `blocked_on` back to the board via `gh` | **Optional** (Phase 2) | Ticket → session → PR → link on ticket is the universal contract; makes the board cross-machine truth | Only outward write; `gh` optional and detected, never installed |
| Blocked-escalation message: orchestrator `SendMessage` to a named attended session, text = `ledger <id> blocked_on <kind> <path>` | **Optional** (Phase 2, only if Phase 1 shows blocked entries waiting > a set time) | Each message is a full turn; pointer-only keeps it cheap | No structured payload assumed; the receiver treats it as data |
| `TeammateIdle` / `Stop` hook that posts the next ledger step to a socket | **Rejected** for Phases 1–2 | `TeammateIdle` is teams-only; posting from a script to *another* session's socket is not confirmed in the docs fetched; the `-p` exit code + JSON result already carries the handoff | Would add an unconfirmed dependency |
| `hef.release` unattended variant stopping at tag/deploy | **Rejected** | `/hef.release` already never commits, tags or pushes and stops for the human edit; no shipped product documents an autonomous deployer; the laptop-only credential boundary makes an orchestrator-launched release wrong by topology | Nothing to add |
| Agent teams for the pipeline | **Rejected** | Interactive only, no resume, ~7×, lead auto-approves plans, same-file overwrites; keep for read-only competing-hypothesis debugging per report 03 | — |
| Cloud routines for verifier / release notes | **Deferred** (Phase 3, only on measured need) | Fresh per run and durable, but reads untrusted text by design and the security review is "not hardened against prompt injection"; no local tooling | Would need the GitHub App; outside the plugin manifest (optional-provider lane) |

## 7. Adoption plan, what is not recommended, and what the user must decide

**Phase 1 — Shape A on one repository, ~20 board items.** Ship `ledger.sh`, `session-launch.sh`, `/hef.orchestrate`, the three evals and the session-start line. Success is measured, not asserted: agent-PR merge rate ≥ the 71.5 % AIDev baseline; CI red on first push ≤ 10 % of PRs (each failure costs ~15 % merge odds, and `quality-before-commit.sh` plus the verifier should catch it before push); reviewer-minutes per merged PR recorded by the human and trending down across the batch; USD per merged PR from `total_cost_usd`, with a ceiling set before the first run; zero merges, approvals or `main` pushes by any launched session (eval + audit of `gh` history); zero same-file conflicts between concurrent tasks (one worker per repo at a time in Phase 1, so this is a check that the rule held); every `blocked_on` entry resolved by a human command, none by the orchestrator.

**Phase 2 — board write-back and blocked-escalation only.** Add `ledger publish` and the single message type. Success: median time from `blocked_on` set to human notice under a target the user picks (herdr `wait` gives the baseline); ≤ 2 messages per task; no message body over 200 characters; no session with `crossSessionInbound: accept` other than the named attended one.

**Phase 3 — only if measured.** If the verifier is the throughput bottleneck on the always-on host, trial a GitHub-event routine for `/hef.review` code mode with the injection boundary in place and the routine's connectors reduced to GitHub. If a debugging task needs competing hypotheses, use an agent team read-only, never as the write path. Define the metric before the trial; a Phase 3 component with no Phase 1 number behind it is not adopted.

**Not recommended:** Shape B as a whole; agent teams as the pipeline; any session holding merge or deploy rights; letting an agent reviewer count toward required approvals (GitHub's September 2026 opt-in); transcript forwarding or `--forward-subagent-text` between roles; `--dangerously-skip-permissions` without the OS sandbox; a ledger under `.claude/` or inside a worktree; messages as a data channel; nested orchestrators; an orchestrator that edits the board item text.

**Open questions for the user:** which board first — the GitHub Project `status-board.sh` already reads for batuta, or a `tasks-repo` kanban (both are supported; the Project gives sub-issue status, the kanban gives zero external dependency); which repository first — hefesto itself (the smoke suite is the strongest verifier available) or terreiro-app (the first real deployment, per memory); herdr on the always-on workstation versus cloud routines as the orchestrator host (the two-machine boundary in `docs/architecture.md` favours the workstation); the spend ceiling per task and per day, and whether it is enforced by `--max-budget-usd`, by `usd_cap` in the ledger, or both; which GitHub identity workers push as, and whether branch protection with requester-cannot-approve is already on; whether the ledger mirrors to the board in Phase 1 or waits.

## 8. Sources

- MAST, Cemri et al., *Why Do Multi-Agent LLM Systems Fail?* — https://arxiv.org/abs/2503.13657 and https://arxiv.org/html/2503.13657v3
- Martinez & Franch, *Dissecting the SWE-Bench Leaderboards* — https://arxiv.org/html/2506.17208v2
- E2EDevBench — https://arxiv.org/pdf/2511.04064
- AgentCoder — https://arxiv.org/html/2312.13010
- MapCoder — https://arxiv.org/html/2405.11403
- Google/MIT, *Towards a Science of Scaling Agent Systems* — https://arxiv.org/abs/2512.08296
- Equal-budget single vs multi-agent study — https://arxiv.org/abs/2604.02460
- NoLiMa — https://arxiv.org/abs/2502.05167
- Du et al., *Context Length Alone Hurts LLM Performance Despite Perfect Retrieval* — https://arxiv.org/abs/2510.05381
- Chroma, *Context Rot* — https://www.trychroma.com/research/context-rot
- Cross-model code review — https://arxiv.org/html/2607.21656
- *The Self-Correction Illusion* — https://arxiv.org/html/2606.05976v1
- *Where Do AI Coding Agents Fail?* (AIDev, 33,596 PRs) — https://arxiv.org/html/2601.15195
- Agentic PR rejection rationale (11,048 PRs) — https://arxiv.org/abs/2605.22534
- Concurrent agent PRs and conflict rates — https://arxiv.org/html/2607.04697v2
- *What Makes a GitHub Issue Ready for Copilot?* — https://arxiv.org/html/2512.21426v1
- Anthropic, *How we built our multi-agent research system* — https://www.anthropic.com/engineering/multi-agent-research-system
- Anthropic, *Effective context engineering for AI agents* — https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Cognition, *Don't build multi-agents* — https://cognition.com/blog/dont-build-multi-agents
- Cognition, *Multi-Agents: What's Actually Working* — https://cognition.com/blog/multi-agents-working
- Cognition, *Devin's 2025 Performance Review* — https://cognition.com/blog/devin-annual-performance-review-2025
- Microsoft Research, Magentic-One — https://www.microsoft.com/en-us/research/articles/magentic-one-a-generalist-multi-agent-system-for-solving-complex-tasks/
- Claude Code docs: cross-session messaging — https://code.claude.com/docs/en/cross-session-messaging; agent teams — https://code.claude.com/docs/en/agent-teams; workflows — https://code.claude.com/docs/en/workflows; routines — https://code.claude.com/docs/en/routines; scheduled tasks — https://code.claude.com/docs/en/scheduled-tasks; headless — https://code.claude.com/docs/en/headless; hooks — https://code.claude.com/docs/en/hooks-guide; subagents — https://code.claude.com/docs/en/sub-agents; agent view — https://code.claude.com/docs/en/agent-view; costs — https://code.claude.com/docs/en/costs
- claude-code-action usage — https://github.com/anthropics/claude-code-action/blob/main/docs/usage.md
- GitHub Docs, Copilot cloud agent risks and mitigations — https://docs.github.com/en/copilot/concepts/agents/cloud-agent/risks-and-mitigations
- GitHub Changelog 2026-09-01, Copilot code review can approve — https://github.blog/changelog/2026-09-01-copilot-code-review-can-now-approve-pull-requests/
- Augment Code, *The autonomous engineering loop* — https://www.augmentcode.com/guides/autonomous-engineering-loop; multi-agent workspace guide — https://www.augmentcode.com/guides/how-to-run-a-multi-agent-coding-workspace
- CSA research note, *Comment and Control* — https://labs.cloudsecurityalliance.org/research/csa-research-note-comment-control-github-prompt-injection-20/
- VentureBeat on the post-disclosure hardening statements — https://venturebeat.com/security/ai-agent-runtime-security-system-card-audit-comment-and-control-2026
- Fortune, Replit database deletion — https://fortune.com/2025/07/23/ai-coding-tool-replit-wiped-database-called-it-a-catastrophic-failure/
- SC Media, Amazon Q wiper prompt — https://www.scworld.com/news/amazon-q-extension-for-vs-code-reportedly-injected-with-wiper-prompt
- Huntley, the Ralph loop — https://ghuntley.com/ralph/
- Every, *Compound engineering* — https://every.to/guides/compound-engineering
- This repository at v7.2.0 (`545986a`): `hooks/status-board.sh`, `hooks/speckit-helper.sh`, `hooks/precompact-progress.sh`, `hooks/session-start-context.sh`, `hooks/verify-before-task-complete.sh`, `hooks/release.sh`, `workflows/workflow.js`, `commands/hef.*.md`, `agents/*.md`, `evals/`, `.specify/memory/constitution.md`, `docs/architecture.md`, `docs/install.md`
