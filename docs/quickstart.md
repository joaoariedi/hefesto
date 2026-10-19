# Quick start

From nothing to working with hefesto: install it, check it, then pick one of two ways to work. Linux and
macOS, as shipped. The long form is [`install.md`](install.md); to have Claude guide you through the same
steps, open Claude Code in a project and type:
``Run `curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/SETUP.md` and follow it.``

*Em português: [`quickstart.pt-BR.md`](quickstart.pt-BR.md).*

## 1. Install or upgrade

Close every Claude Code window. In a normal terminal (outside Claude Code), run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/install.sh)
```

Press Enter at each question to accept the recommendation. It ends with
`All good: every profile runs hefesto <version>`. It never deletes anything; backups go to `~/hefesto-old/`.

## 2. Check it

1. Open Claude Code inside a git project, not your home folder: `cd ~/your-project && claude`.
2. Its first lines include `hefesto <version> hooks loaded from …`. An older version means the window was
   open during the upgrade: close every window and open it again.
3. Type `/hef.doctor`. It must report `status: RUNNING_MATCHES_CLONE`.

## 3. Choose how to work

| | **Simple** — one session | **Pipeline** — four sessions |
|---|---|---|
| Fits | experiments, prototypes, small projects, one person | a backlog of RFCs waiting to be built, a steady train of features, several people |
| You run | `/hef.agent <what you want>` in one session | four lanes that hand items on through a ledger |
| Set up | `/hef.init` once | a board, an RFC folder, a config, GitHub settings (step 5) |

Start Simple when in doubt; a project can move to the Pipeline later.

## 4. Simple: one session

1. In Claude Code, inside the project: `/hef.init` (once).
2. For each change: `/hef.agent <what you want>`. It sizes the work and takes the shortest safe path — a
   quick fix, a light spec, or the full spec → plan → review → tasks → implement → verify chain — and stops
   whenever it needs your answer.
3. `/hef.pr` opens the pull request; you merge it.
4. Compaction: at a natural break inside a long task, `/compact` (the general prompt in
   [`performance.md`](performance.md)); between unrelated tasks, `/clear`.

That is all the Simple mode needs. The rest of this guide is the Pipeline.

## 5. Pipeline: set up the project (once per repository)

The easy way is the `SETUP.md` request above: Claude checks the project, gathers your lead's decisions in
one message, then writes the setup in a pull request. What it sets up:

1. `/hef.init`, which creates `.specify/` for specs and plans.
2. The board: `tasks/TODO.md`, `DOING.md`, `DONE.md`, `BACKLOG.md`. Each item is a heading with an id and a
   title (`## ABC-12 — Export orders as CSV`), then a few lines — and, for planned work, its RFC (step 6).
   The id prefix is two or more capital letters or digits, starting with a letter. The lanes take work only
   from `TODO.md`; items only a person can do go in `BACKLOG.md`.
3. `.claude/project-status.json` — the board, the spend limits, the test command, and three settings the
   four lanes rely on (the full template is in [`SETUP.md`](../SETUP.md), Step 4c):
   - `"plan_first": true` — the build lane never takes an item the plan lane has not planned;
   - `"plan_review": "human"` — every plan waits for a person's approval (step 8);
   - `"context": {"compact_at": {"orchestrator": 40, "plan": 50, "build": 0, "deploy": 0}}` — when each
     lane's status line tells you to compact (0 = never).
4. On GitHub: merge commits allowed and squash and rebase merges turned off, and the branch where work
   integrates protected (a pull request required). A branch other than `main` (say `dev`) is declared
   under `branches` ([`install.md`](install.md) §7, step 12).

Merge the setup pull request, then `git pull` in the project's main folder before going on.

## 6. Pipeline: RFCs

An RFC is the design a feature is built from: one file per board item, `docs/rfcs/<ID>.md` (another folder
with `orchestrate.rfc_dir`). The item points to it with a line under its heading:

```markdown
## ABC-12 — Export orders as CSV
rfc: docs/rfcs/ABC-12.md
```

- **Written by someone else:** they drop the finished RFC there and add the item.
- **Written with hefesto:** in the plan lane, `/hef.brainstorm <the idea> for ABC-12` — it saves the
  approved design as that item's RFC and adds the `rfc:` line.

The plan lane's background planner then specs from the RFC — no new design choices, every RFC requirement
becomes a spec requirement that cites its section, the RFC's open questions come back to you as questions
— and plans and writes tasks. If the RFC changes after its plan was approved, the build lane refuses the
item until a person brings the plan in line and approves again.

## 7. Pipeline: open the four lanes

Each in its own terminal, inside the project's main folder:

```bash
bash ~/.claude-framework/hooks/lane-launch.sh orchestrator
bash ~/.claude-framework/hooks/lane-launch.sh plan
bash ~/.claude-framework/hooks/lane-launch.sh build
bash ~/.claude-framework/hooks/lane-launch.sh deploy
```

(Use the folder where hefesto is installed if it is not `~/.claude-framework`.) Each lane opens as
`<repo>-<lane>`, in the default permission mode, with the sandbox off (lanes start background sessions,
which run sandboxed) and an allowlist of hefesto's own helpers only: routine work runs without prompts,
while anything that clears or rewrites a person's decision — and anything unexpected — still asks you. The
status line shows the context gauge; `--keep-statusline` keeps yours.

Then, once in each:

| Lane | Run once | What it then does |
|---|---|---|
| orchestrator | `/hef.status` whenever you want | The board and delivery numbers; your approvals and merges happen here. It can start any stage itself: `/hef.orchestrate --stage plan\|build\|deploy`, or `--stage all` for one catch-up pass of each (it holds the session while they run) |
| plan | `/loop 15m /hef.orchestrate --stage plan` | The next new item: spec from its RFC, plan, review, tasks — then it waits for your approval |
| build | `/loop 15m /hef.orchestrate` | The next approved item: implemented, checked by a separate session, pull request opened |
| deploy | `/loop 15m /hef.orchestrate --stage deploy` | The next pull request: CI watched and fixed until it is ready; after your merge, the merge recorded |

- One background session runs per repository at a time: a lane that finds the repository busy says so and
  tries on its next pass. Each pass stays within `usd_cap` and `daily_usd_cap`.
- A loop expires 7 days after it starts: start it again each week. Press Esc to stop one.
- Per-item state, from the orchestrator: `bash ~/.claude-framework/hooks/ledger.sh list --active` (running)
  and `… list --blocked` (waiting).

## 8. Pipeline: day to day

1. Add items (and their RFCs) to the board.
2. **Approve each plan.** An item waiting on `human:plan-approval` has its spec, plan and tasks in its own
   folder, `.claude/worktrees/<ID>`. Read them — rewrite them there if you want them different — then, in
   the orchestrator:
   ```bash
   bash ~/.claude-framework/hooks/ledger.sh unblock ABC-12 --reviewed-by-human --by "Your Name"
   ```
   It asks for permission every time, and your name is recorded on the item.
3. **Answer the planner's questions.** `human:clarify` or `human:plan-review` on an item: open Claude Code
   in its folder (`cd .claude/worktrees/ABC-12 && claude`), run `/hef.clarify` (questions) or `/hef.review`
   (a plan the reviewer could not settle), then `ledger.sh unblock ABC-12`. Any other block: ask your lead.
4. **Merge** each pull request yourself, with **Create a merge commit**. The deploy lane records the merge
   on its next pass. After a squash or rebase merge it cannot see it: your lead records it with
   `ledger.sh unblock <id> --merge-sha <sha>`.
5. **Compact** when a lane's status line says so, with that lane's own prompt
   ([`performance.md`](performance.md), "Compact prompts per pane"). The loop lanes hold little beyond what
   is on disk: set them to 0 and let Claude Code's auto-compaction handle them. `/clear` only for unrelated
   work or a conversation that went wrong.
6. When something looks wrong, run `/hef.doctor`, copy the exact message, and ask your lead.
