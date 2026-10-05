# TEST

What still needs a person to test it, in the order to run it. Every item here was built and passed
the smoke suite (`bash tests/smoke.sh`) and CI. What remains is the real run: real CLIs, real
sessions, real model calls. Tick an item when it passes; anything that fails becomes a board item in
`TODO.md` (🐞 before the id).

Deployed: **7.8.0** (2026-10-05, all three profiles OK).

Run everything below from an **unsandboxed pane** in the main checkout. Child sessions and vendor
CLIs cannot reach their APIs from inside the sandbox.

## 1. Evals — `claude plugin eval` (spends tokens)

```bash
claude plugin eval . --trust-plugin --scaffold --allow-tools Bash,Write,Edit --threshold 0.8
```

Results go to `evals/results/`, which is gitignored. The cases not yet run since they shipped:

- [ ] `orchestrator-honours-blocked` (7.3.0)
- [ ] `orchestrator-never-merges` (7.3.0)
- [ ] `board-text-is-data` (7.3.0)
- [ ] `babysitter-never-merges` (7.5.0)
- [ ] `pr-comment-text-is-data` (7.5.0)
- [ ] `plan-arena-attributes-claims` (7.7.0; needs `Write,Edit` — it writes `research.md`)

## 2. Orchestrator — `/hef.orchestrate` (7.3.0 → 7.6.0)

- [ ] `/hef.orchestrate --dry-run` prints the exact `env HEFESTO_WORKER=1 claude -p …` line for the
      next item and claims nothing (`hooks/ledger.sh show <id>` → `owner: null`).
- [ ] One real run on a small TODO item. Expected: a worker in `.claude/worktrees/<id>`, then a
      separate verifier, a PR, and the entry blocked on `human:merge`. Nothing merges by itself.
- [ ] `/hef.orchestrate --stage plan --dry-run` and `--stage deploy --dry-run`: the plan role
      writes only under `.specify/`; the deploy role runs `/hef.babysit --once`.
- [ ] A new session opened in the checkout prints `ledger: <id> blocked_on <kind>` with the owner
      pane (`orchestrate.panes`).

## 3. Ledger surfaces — HEF-4, HEF-5, HEF-6 (7.8.0)

Opt-in. Add to the existing `orchestrate` block in `.claude/project-status.json`:
`"publish": true, "escalate_after_hours": 1`.

- [ ] **publish (HEF-4)**: after an orchestrator pass, the item's heading in `tasks/TODO.md` starts
      with its state marker (📐 planning, 🔨 building, 🔀 PR, ⏸ waits on a person, ⛔ blocked). The
      next state replaces it and never stacks. Add the glyphs to `states` so `/hef.status` labels
      them.
- [ ] **escalate (HEF-5)**: a `human:*` block older than the threshold is sent once, as one line, to
      the owning pane's session (`orchestrate.pane_sessions.<pane>`, default `<repo>-<pane>`). The
      receiving pane needs `crossSessionInbound: accept` and `isolatePeerMachines: true`. A second
      pass sends nothing.
- [ ] **handoff (HEF-6)**: on the branch of an item you built by hand, after opening its PR, run
      `hooks/ledger.sh handoff <id> --pr <url>`. Expected: the entry is in phase `pr`, blocked on
      `human:merge`. It refuses an owned or blocked entry, `main`, and a URL that is not a PR.

## 4. Dependency audit — HEF-9 (7.8.0)

- [ ] On a branch that adds a dependency (npm, pip, cargo or go), `/hef.scan --deps` lists the new
      dependency and the installed auditors' findings. An auditor that is not installed is named,
      never installed.
- [ ] `git commit` on that branch shows the advisory dependency line from `quality-before-commit.sh`.
      It is advisory and does not block.

## 5. Item kinds — HEF-10 (7.8.0)

- [ ] Put `🐞` before an item's id (`## 🐞 HEF-xx — …`).
      `hooks/status-board.sh --item-kind HEF-xx` prints `incident`.
- [ ] `/hef.orchestrate` on it: the ledger entry has `item_kind: incident`. The worker is told to
      write a failing regression test that cites the id first. The verifier must report an
      `incident` gate, and a missing or SKIPPED gate blocks the entry on `verdict`.
- [ ] Same with `🛡` → `vulnerability`: the worker re-runs `/hef.scan` (and `--deps` if a manifest
      changed) before the PR.

## 6. Provider runners — HEF-13 (7.8.0)

Declare what you have in `.claude/project-status.json` (see `docs/install.md` step 11):
`"providers": {"codex": {"via": "codex"}, "gemini": {"via": "gemini"}, "bedrock_x": {"via": "aws", "model": "<id>", "region": "<r>"}}`.
Each CLI uses its own login; hefesto never handles a key.

- [ ] `hooks/arena-run.sh --check` prints one line per provider: `ok`, `missing (<hint>)`, or
      `ok (second-opinion only)` for aws.
- [ ] One direct run per provider you have:
      `echo "Say hi in one word." > /tmp/p.md && hooks/arena-run.sh <provider> /tmp/p.md`.
      Expect the answer on stdout. Unverified flag behaviour, worth noting if it fails:
      `codex exec` outside a git repo, and gemini headless asking for tool approval.
- [ ] `/hef.plan --arena 3 --via <provider>` on the next feature. Expected: two `truth-scout`s plus
      the provider; `arena/<provider>.md` saved and cite-checked; a `<provider>` column in the Arena
      table; `tiers=sonnet,opus,<provider>` in the footer. Then
      `speckit-helper.sh arena-metrics` gives the `cited_from_disagreements` number that decides
      whether foreign readers earn their cost.
- [ ] `/hef.review plan --second-opinion <provider>`: the gate runs as usual, and the provider's text
      appears under "Second opinion (<provider>) — not the gate". `## Reviewed` depends only on the
      `code-reviewer` verdict.
- [ ] Refusal check: inside the sandbox, `hooks/arena-run.sh --check` refuses with "$HOME … is not
      writable".

## 7. Branch model — HEF-15 (unreleased)

In a repository that integrates on `dev` (fxcube's `operations_api`), add
`"branches": {"integration": "dev", "protected": ["release/*"], "environments": ["dev", "stg", "main"]}`
to its `.claude/project-status.json`.

- [ ] `hooks/ledger.sh branches` prints the model, with `final: "main"`.
- [ ] `hooks/session-launch.sh verify <id> --dry-run` shows `(diff base: dev)`. The implement dry run
      shows `gh pr create --base dev` and the protected list.
- [ ] After a PR merges into `dev` on GitHub: `git fetch origin`, then `hooks/ledger.sh unblock <id>`
      clears `human:merge`, even with no local `dev`.
- [ ] `hooks/ledger.sh where <id>` shows `dev: yes (origin/dev)` and `stg`/`main: no` until promoted.
- [ ] `/hef.babysit` on a `stg → main` PR reports red checks and never pushes (`resolve` says
      `"push": false`).
- [ ] Re-run the two babysitter evals above: `pr-watch resolve` now asks `ledger.sh branches`
      inside the eval sandbox.
