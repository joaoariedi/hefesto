# Quick start

Install hefesto, then pick one of two ways to work. Every decision — approving a plan, answering a
question, asking for changes — is a form in one session, the orchestrator; nothing is copied between
sessions. Linux and macOS. The long form is [`install.md`](install.md).

*Em português: [`quickstart.pt-BR.md`](quickstart.pt-BR.md).*

## 1. Install

Close every Claude Code window. In a normal terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/install.sh)
```

Press Enter at each question. It ends with `All good: every profile runs hefesto <version>`.

|  | **Single lane** | **Four lanes** |
|---|---|---|
| For | experiments, small projects, one feature at a time | a steady stream of RFCs |
| Sessions | one: the orchestrator | the orchestrator + a planner, a builder, a deployer |
| What runs the stages | background sessions the orchestrator starts | the three stage lanes, rung by the orchestrator |

Start with the single lane; the same project can add the three stage lanes later.

## 2. Single lane

1. **Set the project up once** — in a terminal, in the project's main folder:
   ```bash
   bash ~/.claude-framework/hooks/hefesto-setup.sh
   ```
2. **Open the lane** — with `claude`, or any wrapper that passes claude's arguments on:
   ```bash
   claude --name myrepo-orchestrator          # or: claude-profile work --name myrepo-orchestrator
   ```
3. **Check it:** `/hef.orchestrate` — it reports the setup and creates a board if there is none.
4. **Ship something:** `/hef.ship "export orders as CSV"` (or `/hef.ship ABC-12` for an item already on the
   board). A feature is brainstormed with you, saved as an RFC and planned in the background; you approve
   the plan in a form; it is built, checked by a separate session, and its pull request is babysat until
   CI is green. A bug fix goes straight to the builder.
5. **Merge** the pull request on GitHub with **Create a merge commit**, then run `/hef.orchestrate` once: it
   records the merge.

## 3. Four lanes

1. **Set the project up once** — in a terminal, in the project's main folder:
   ```bash
   bash ~/.claude-framework/hooks/hefesto-setup.sh --lanes
   ```
2. **Open and name the four lanes**, each in its own terminal, all with the same profile:
   ```bash
   claude --name myrepo-orchestrator
   claude --name myrepo-planner
   claude --name myrepo-builder
   claude --name myrepo-deployer
   ```
3. **Start each stage lane once:** `/hef.orchestrate --stage plan` in the planner, `--stage build` in the
   builder, `--stage deploy` in the deployer. From then on they wait for the orchestrator's doorbell, and each
   narrates its run as it goes (`· /hef.spec`, `· write …/plan.md`, `· run: go test ./...`, `■ done`). The
   three stages overlap; for more builders set `"max_builders": 2` under `orchestrate` and open
   `myrepo-builder2` too.
4. **In the orchestrator:** `/hef.orchestrate` — it checks the setup and finds the three lanes.
5. **Feed it RFCs:** `/hef.ship ABC-12` for an item with its RFC on the board (`rfc: docs/rfcs/ABC-12.md`
   under its heading), or `/hef.ship "<idea>"`. The orchestrator rings the planner; when a plan is ready it
   asks you to approve it, then rings the builder, then the deployer. Approvals, answers and change requests
   all happen in the orchestrator; you merge on GitHub.

## Day to day

- **Decisions** come as forms in the orchestrator. Answering one runs the matching command, and Claude
  Code shows its permission dialog — confirm it. That dialog is your signature; run the orchestrator in the
  default permission mode (it warns you otherwise).
- **RFCs** live in `docs/rfcs/<ID>.md`, one per item, linked by an `rfc:` line. If an RFC changes after its
  plan was approved, the builder stops and the orchestrator asks you to bring the plan in line.
- **The status line** keeps your own (profile, model, folder…) and adds `ctx 45% · 90k/200k` (context used,
  tokens in context over the window); below it, one row per background run (`▶ implement FAB-1 · 4m`) and per
  decision waiting on you (`⏸ FAB-3 · plan approval`).
- **Lane actions.** Anything a lane should do for you (merge PR #726 at its head SHA, cut a release, deploy to stg,
  run a backfill, restart a container) is a form in the orchestrator. Ask the orchestrator for it in your words. It
  writes the steps, the exact heads, the stop checks and the commands, and shows them. You answer **Approve**, then
  confirm the dialog. The lane does exactly that, with no dialog in its own pane, and reports done or where it
  stopped. A head that moved, or anything the scope didn't cover, comes back to you as a new form. The status line
  shows each one waiting on you (`⏸ DET-7-A2 · action: merge PR #726`).
- **Lane names** come from the project: `"lane_prefix": "myproduct"` under `orchestrate` (lanes
  `myproduct-orchestrator`, `-planner`, `-builder`, `-deployer`), or an explicit `"lanes": {"orchestrator": "…",
  "plan": "…", "build": ["…", "…"], "deploy": "…"}`. Run the setup again after changing them.
- **Compact** when a lane's status line says `/compact`, with that lane's own prompt
  ([`performance.md`](performance.md), "Compact prompts per pane"). `/clear` only for unrelated work.
- **Spend and network.** Each background run may spend up to `orchestrate.usd_cap` ($20 by default), and a
  repository up to `daily_usd_cap` ($100) a day. A background run reaches no network host unless it is listed:
  for dependency work add `"allowed_domains": ["registry.npmjs.org"]` under `orchestrate` in
  `.claude/project-status.json`.
- **A board you already have** is adopted, not replaced: with no config yet, `/hef.orchestrate` lists what the
  project uses (a `tasks/` folder, a backlog file, a GitHub repo) and asks which one.
- **After a hefesto update**, run the setup command again (a lane's first lines say so when it is due).
- **When something looks wrong**, run `/hef.doctor`, copy the exact message, and ask your lead.

**Security in one paragraph.** The lanes keep Claude Code's sandbox, and commands inside it run without asking.
Outside it run only hefesto's own helpers and `gh`, each called as one plain command. The ledger, your approvals and
the record of which session is which lane live in `~/.cache/hefesto`, where no sandboxed command and no file edit
can reach them. The commands that record your decisions run only in the orchestrator, behind a dialog, and
`gh pr merge` never runs without an approved action or your dialog. A lane reads item and RFC text that others
wrote, so read each form and dialog before you answer it.
