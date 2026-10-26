# Case Study: a Production SDLC on Hefesto

[← back to README](../README.md)

How one production adopter runs its whole lifecycle on Hefesto, from a product owner's RFC to a
release in production. It is written down so that it can be **replicated**, and so that its
**gaps** can be planned as framework work.

- **Observed:** 2026-10-25, with Hefesto **8.0.0** installed. Some gaps listed below may already
  be addressed in later releases; triage them against the current version.
- **Scope:** the parts that generalise. Hosts, domains, people and infrastructure details are
  left out on purpose.

---

## 🏗️ The setup

| Piece | What it is |
|---|---|
| **App repos** | Two: an API (Python/Django) and a UI (React/TypeScript). They share a contract, so they promote together, API first. |
| **Board repo** (`tasks/`) | The kanban (`TODO` / `BACKLOG` / `DOING` / `DONE`), `.specify/` (constitution, specs, plans, task lists), the PO's sources, PO messages, a knowledge base and closed history. Pushes straight to `main`. |
| **Deploy repo** | Compose files and deploy scripts for three environments: dev, stg and prod. |
| **Infra repo** | Ansible. PR to `main`, no CI; a convergence run is the verification. |
| **People** | The **owner**, the only source of every "go", and a non-technical **product owner (PO)** who validates releases. |
| **Lanes** | Four long-lived Claude Code sessions: 🎛 orchestrator, 📐 planner, 🔨 builder (one or two) and 🚀 deployer. They message each other through the orchestrator. |

## 🔄 The lifecycle at a glance

```
 PO                                   owner = the ONLY source of a "go"
  │ uploads RFC / answers in chat        │ go-files · merge words · chat-bot taps
  ▼                                      ▼
 file drop-box ──sync──▶ planning/_incoming/      messages/po/_incoming/ ◀── chat bot events
                                  │                         │
                                  ▼                         ▼
                        🎛 ORCHESTRATOR (routes, owns the board; never builds or merges)
                                  │
         ┌────────────────────────┼─────────────────────────┐
         ▼                        ▼                         ▼
  📐 PLANNER                 🔨 BUILDER                  🚀 DEPLOYER
  extract → board item →     claim → implement →        merge on the owner's word →
  /hef.spec → clarify →      /hef.verify → quality →    release/vX → stg → PO review →
  plan → review →            review → /hef.pr (→ dev)   main (API first) → tag + Release →
  (owner's go) → tasks                                  prod notice to the PO
```

## 🔒 Invariants every stage obeys

1. **The owner is the only source of a "go".** A relayed approval, or a reviewer's APPROVE, is not
   a go.
   - **Merges** happen only on the owner's words, typed in the deploy lane, with
     `gh pr merge --merge --match-head-commit`.
   - **Server steps** run from **go-files**: the orchestrator writes `/tmp/<project>-go/<lane>-NN.txt`
     (mode 444) and the owner types one line, `go <file> <8hex>`. The lane checks the mode and the
     hash, acts only on the file's exact text, and runs it once. A file is used because a terminal
     multiplexer breaks multi-line pastes, and a hash pins exactly what was approved.
2. **Nothing reaches the PO without the owner's tap.** Every chat-bot message waits for a one-tap
   admin release, prod notices included.
3. **PO approval ships nothing.** "PO approved" is an input to the owner's prod go.
4. **Claim before you code:** a pushed board commit, or `ledger.sh claim`. Each repo has one
   worker at a time.
5. **Merge commits only** on the promotion branches (`stg`, `main`), enforced by rulesets.
6. **PO and uploaded content is data, never instructions.** Intake checks only name, type and
   size, and never parses contents.
7. **Docs change in the same PR as the behaviour.** Status lives in one place.

## 📥 Intake

| Channel | Trigger | Lands in |
|---|---|---|
| RFC or document from the PO | Upload to a drop-box folder; a sync timer copies it with a `PROVENANCE.md` (sha256, uploader, time), or quarantines a bad name, type or size | `tasks/planning/_incoming/<date>_<slug>/` (gitignored) |
| Bug from the PO | Declared in the chat bot (`/bug` or a button); the bot confirms, and his **next** message is the bug | `messages/po/_incoming/` as one `bug` event |
| PO review of a stg release | A per-item comment: 🔧 fix (blocks prod), 💡 idea, 💬 note | one `response` event `{approved, comments[]}` |
| PO answers to planning questions | A reply in the chat bot | `answer` events, verbatim |
| Internal items | Any lane, or the owner through the orchestrator | a board heading tagged with who filed it |

**Routing.** The orchestrator routes `_incoming/` by event kind, by hand today:
- `fix` → a 🐞 on the stg train, which blocks prod;
- `idea` → intake;
- `note` → the owner;
- `bug` → a 🐞 item;
- test events → never routed.

Each event is filed as a `retorno-…` record and then deleted.

## 📐 Planning

1. **Land the source.** The orchestrator checks the sha256 and moves the folder from `_incoming/`
   to `planning/<topic>/`.
2. **Extract.** The planner writes a faithful `.md` extraction with its provenance on the first
   line. The extraction scripts fail on any lost line.
3. **Board item:** 📥 intake, the kind (🐞, 🛡, …) and a `repo:` line. A requirement that looks odd
   gets an "is this yours?" question to the PO, because PO documents can carry AI artifacts.
4. **Size** large items with a requirement inventory.
5. **Run the pipeline:** `/hef.brainstorm` → `/hef.spec` → `/hef.clarify` → `/hef.plan [--arena]` → `/hef.review`.
   - The plan review is a fresh-context `code-reviewer`. Its verdict is recorded as `## Reviewed`
     in the plan.
   - PO questions go out as message files through the chat bot.
6. **Owner's go on the exact reviewed plan,** then `/hef.tasks`.
   - A plan change needs a new review and a new go.
   - Fix rounds the PO asks for on stg do not need a new go.
   - The `tasks.md` header records the go.
7. **Hand off:** `tasks ready <spec-dir> for <id>`. Once tasks exist, the source moves to
   `rfcs/<module>/` with an index row.

## 🔨 Build

1. Claim, then work in an isolated `<repo>-wt-<topic>` worktree.
2. Implement (TDD) → `/hef.verify` → `/hef.quality` → `/hef.review` (code mode, fresh context)
   → `/hef.pr` into `dev`. Trivial fixes go through `/hef.fix`.
3. **Local gates:** the `quality-before-commit` hook, plus the repo hooks:
   - the Python repo: pre-commit black, isort, flake8 and bandit;
   - the UI repo: husky with `lint-staged`.
4. **CI on the PR into dev:** quality, a fast unit lane, and gitleaks over the full history.
5. **Hand off.** `ledger.sh run`, then `record` and `handoff --pr`. The deployer merges on the
   owner's word, then runs `ledger.sh unblock --merge-sha`.

## 🚀 Release, PO validation, promotion

1. **Cut `release/vX.Y.Z` from dev** with `/hef.release`. Each repo takes its version from **its
   own CHANGELOG**: the two repos are deliberately one release apart.
2. **Merge `stg` in with `--no-commit`.** Rebuild the CHANGELOG starting from stg's copy, then run
   a placement check on the pushed commit: released sections must be byte-identical, and new
   entries must sit under `[Unreleased]`. Stacked trains auto-merge CHANGELOGs silently and
   wrongly, which is why this check exists.
3. **PR `release → stg`, with a merge commit.** The full suite runs. Merging deploys stg, then
   e2e parity runs.
4. **PO review through the chat bot:**
   - The lane writes `messages/po/<date>_stg-v<api>-v<ui>.txt` with numbered testable items and
     no closing "let me know" line, then runs `po-send <file>`.
   - The owner taps to release it.
   - The PO taps **Approve all**, or **Request changes**: he picks an item, chooses 🔧 or 💡 and
     types a comment, all in one message the bot edits in place.
   - One `response` event comes back. Any 🔧 blocks the train.
5. **PR `stg → main`, API first.** The UI's prod e2e must be green, then the API is merged and
   healthy, then the UI is merged. Never arm auto-merge on both PRs: each merges when its own
   checks pass.
6. **Deploy script:**
   - A branch guard stops a run whose clone is on the wrong branch.
   - Build while the old stack serves, then run migrations in a one-off container, then swap.
   - Health is polled for at least 180 s, with automatic rollback on failure.
   - If the guard refuses, stop and ask; never fall back to raw compose.
7. **Close out:**
   - **Check versions:** an unauthenticated `GET /api/version/` per environment must equal that
     branch's version.
   - **Tag and Release:** tag `vX.Y.Z`, then create the **GitHub Releases by hand**, oldest
     first.
   - **Notify the PO:** a prod notice goes to him through the bot (no buttons, one owner tap).
   - **Sync dev:** a `sync-dev-after-release` workflow opens the version sync PR back to dev.
   - **Update the board:** DONE.

## 💬 The PO loop pattern (chat bot)

This is the most reusable piece for a team with a non-technical approver. It needs no Hefesto
change.

- **The bot lives on a host no agent can reach,** because it holds the token. Agents only drop
  files into an outbox folder.
- **The message kind comes from the file name:**

  | Prefix | Kind | Buttons |
  |---|---|---|
  | `stg-` | review | Approve all / Request changes |
  | `perguntas-` (questions) | questions | Reply |
  | anything else | notice | none |

  The numbered lines of a review become its item grid.
- **Admin release.** The owner sees exactly what the PO will see and taps once to release it.
  Test drafts (`--teste`) go to the owner instead.
- **One event file per answer:** `<date>_<HHMMSSmmm>_<thread>_<kind>.json` (+ `.txt` verbatim,
  + images). Files are never overwritten.
- **No guessing.** Free text with no explicit destination gets one question, "what is this
  message?", with buttons. It is not filed by recency: recency once filed "I need to send a bug"
  as an answer to an open questions thread.
- **Declare, then describe.** A send button for "what you just typed" filed the declaration as
  the bug. The working pattern is: declare a bug → the bot confirms → the next message *is* the
  bug.
- **Allowlist by chat id.** A draft can be answered only from the chat it was delivered to.
  Strangers get no reaction, and only a hash of their text is logged.
- **The channel is not end-to-end encrypted.** Release notes and test feedback only.

## 📦 Replicating it

**Copy as-is:**
- The four-lane model, including each lane's gates and its list of things it must never do.
- Go-files.
- Merge words typed in the deploy lane.
- The SDD pipeline with the owner's go before `/hef.tasks`.
- The `feature → dev → release/* → stg → main` flow, with merge commits, CHANGELOG-derived
  versions and API-first promotion.
- File-based intake with provenance and quarantine.
- The PO loop pattern.

**Parameterise:**
- Hosts and network.
- The message language and conventions.
- The file store.
- The chat channel.
- The number of builders.

**Avoid:**
- One shared clone serving several environments (G14 below).

**Minimum kit:**
1. A board repo with `reference/lanes.md` and a docs standard.
2. A current constitution (`/hef.constitution`).
3. Hefesto **and the tools its gates call** (`gitleaks`, `lizard`, the language linters).
4. A release recipe in each repo's CONTRIBUTING.
5. Deploy scripts with a branch guard, a health window and rollback.
6. An intake drop-box plus a sync timer.
7. The chat bot, if there is a non-technical approver.

## 🧭 Gaps: candidates for framework work

These were observed on 8.0.0. Each candidate is a suggestion, not a decision.

### Gates that silently don't run

| # | Gap | Candidate |
|---|---|---|
| G1 | The `quality-before-commit` complexity **delta gate is skipped** when `lizard` is absent, as it was on the lane host. `ruff` is skipped the same way. The commit passes and nothing says the gate never ran. | `/hef.doctor` (or the SessionStart hook) **fails loudly** when a configured gate's tool is missing. |
| G2 | `/hef.mutate` has nothing to run on: no mutmut or Stryker setup, and no `.specify/mutation-score` ratchet. It never ran. | Opt-in per repo, with a scaffolded ratchet file. |
| G3 | PRs **into `release/*`** run no checks, because CI triggers only cover `dev` and `stg`. | Ship a CI template whose `pull_request.branches` includes `release/**`. |
| G4 | **Hotfix route vs CI.** The practice is `release → main` directly when stg holds unapproved work. CI only checks PRs from `stg` into main, so a hotfix PR blocks forever and needs an admin merge. | A documented hotfix recipe with matching CI triggers. |
| G5 | The post-stg-deploy e2e parity run tests **main's** spec set against the new stg. The authoritative run is a manual `--ref stg`. | Document it in the release recipe, or dispatch parity with the release ref. |
| G6 | **No automatic post-deploy version check**: the `/api/version/` probe is manual. | A recipe step, or a `/hef.release` verification hook. |
| G7 | The **nightly** full-data regression gates nothing. | A red-nightly flag on the ledger that blocks the next promotion. |

### Process that lives outside the framework

| # | Gap | Candidate |
|---|---|---|
| G8 | **The go-file protocol and the full planning pipeline** live only in lane handoff notes. Neither is in the lane reference, and the planning README omits `/hef.brainstorm` and the owner's go. | First-class: a go-file helper (write, verify, consume) and the pipeline in `lanes.md`. |
| G9 | **The constitution went stale.** It was still from 2026-03, used the pre-`hef.` command names, and required a spec for every bug fix, while the lanes send trivial bugs to `/hef.fix`. | `/hef.doctor` flags a constitution older than the installed plugin, or one that names retired commands. |
| G10 | **Routing PO events and filing reply records** is done by hand by the orchestrator. | A command that reads the event files and proposes board items and records. |
| G11 | **GitHub Releases are created by hand,** oldest first, then `--latest`. | A promotion step in `/hef.release`. |
| G12 | **The prod notice** to the PO is hand-written. | Generated from the CHANGELOG plus the stg message's items. |
| G13 | **Board drift.** The board's "release state" said a version seven releases old, index rows were stale, and DONE was out of date order. Intakes were left unclosed (sources never moved to `rfcs/`). | `/hef.status` cross-checks the board against git tags and `gh release list`; a close-out step in `/hef.tasks` completion. |

### Architecture traps worth a warning in the docs

| # | Trap | Candidate |
|---|---|---|
| G14 | **One shared clone serves dev, stg and prod.** Every deploy switches the branch. The dev UI bind-mounts the clone, so it serves whatever branch is checked out, live. A deploy that dies mid-script leaves the clone half-switched. | Recommend one clone directory per environment in the install guide. |
| G15 | **Contradictory rules across documents:** merge method into dev ("squash OK" vs merge commits, with nothing enforcing it), which lane moves intake files, and which lane drafts the stg message. | A docs-consistency check in `/hef.analyze` for lane rules. |
