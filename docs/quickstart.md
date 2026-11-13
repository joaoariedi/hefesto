# Quick start

This page takes you from an installed hefesto to work shipping: prepare a project, then pick one of two ways to work —
a **single lane** or **four or more lanes**. Every decision — approving a plan, answering a question, asking for
changes — is a form in one session, the orchestrator; nothing is copied between sessions. Linux, macOS and Windows
(WSL) — install from your OS's page: [Linux](install-linux.md) · [macOS](install-macos.md) ·
[Windows (WSL)](install-windows.md). The install and configuration reference is [`install.md`](install.md); to have
Claude walk you through it instead, [`SETUP.md`](../SETUP.md).

*Em português: [`quickstart.pt-BR.md`](quickstart.pt-BR.md).*

> **Typing the commands.** Claude Code names a plugin's commands after the plugin, so every hefesto command is
> typed with the `hefesto:` prefix: `/hefesto:hef.orchestrate`, `/hefesto:hef.ship`, `/hefesto:hef.doctor`.
> Type `/hefesto:` in the prompt to list them all. Every command in these docs is written that way, ready to paste.

## 1. Before you start

Install hefesto first: [Linux](install-linux.md) · [macOS](install-macos.md) · [Windows (WSL)](install-windows.md).
Each page lists the tools, the one install command, and the check.

## 2. Install or upgrade hefesto

The `install.sh` command on your OS page installs hefesto and also upgrades it.

**After an upgrade**, in every project you set up for hefesto, run the setup again from its main folder and restart
its Claude Code sessions:

```bash
bash ~/.claude-framework/hooks/hefesto-setup.sh            # add --lanes in a four-lane project
```

A four-lane session's first lines say when this is due; in a single lane `/hefesto:hef.orchestrate` stops and names
the command. What changed between releases: [Upgrade notes](#upgrade-notes) below.

## 3. Single lane or four or more lanes?

|  | **Single lane** | **Four or more lanes** |
|---|---|---|
| For | experiments, small projects, one feature at a time | a steady stream of RFCs and fixes |
| Sessions you keep open | one: the orchestrator | the orchestrator + a planner, a builder, a deployer — and more builders with `orchestrate.max_builders` |
| What runs the stages | background sessions the orchestrator starts | the three stage lanes, rung by the orchestrator |
| Setup | `hefesto-setup.sh` | `hefesto-setup.sh --lanes` |

Start with the single lane; the same project can add the three stage lanes later (run the setup with `--lanes`).

## 4. Prepare the project

hefesto works in a git repository with a GitHub remote: the builder opens pull requests with `gh` and the deployer
watches their CI. Run the setup for your choice first — step 1 of section 5 or 6 — as soon as the folder is a git
repository: it writes the rule that lets hefesto's helper run without a permission prompt (before it, each helper call
asks; approving it is safe).

**A project you already have:**

1. Open a terminal in its main folder (the main checkout, not a worktree).
2. If it has no `.specify/` yet, open `claude` there and run `/hefesto:hef.init` (the spec folder and a skeleton
   constitution), then `/hefesto:hef.constitution` (your project's rules). Commit `.specify/`.
3. Optional: `/hefesto:hef.baseline` writes specs for code that already exists, before you change it.
4. A board you already have (a `tasks/` folder, a backlog file, a GitHub Project) is adopted, not replaced: the
   first `/hefesto:hef.orchestrate` lists what it finds and asks which one.
5. One repository with several apps (`backend/`, `apps/web/`)? Give each its own `.specify/`; see
   [`install.md`](install.md) §7, step 15.

**A new project:**

```bash
mkdir myproduct && cd myproduct
git init -b main && git commit --allow-empty -m "start"
gh repo create myproduct --private --source . --push
```

Run the setup (section 5 or 6, step 1), then open `claude` in that folder, run `/hefesto:hef.init`, then `/hefesto:hef.constitution`, and commit `.specify/`. The
first `/hefesto:hef.orchestrate` creates the board (a `tasks/` folder, `docs/rfcs/` and `.claude/project-status.json`).

## 5. Single lane

1. **Set the project up once** — in a terminal, in the project's main folder:
   ```bash
   bash ~/.claude-framework/hooks/hefesto-setup.sh
   ```
   `--check` tells you whether it is still current, and `--help` lists the options.
2. **Open the lane** — with `claude`, or any wrapper that passes claude's arguments on:
   ```bash
   claude --name myproduct-orchestrator
   ```
3. **Check it:** `/hefesto:hef.orchestrate` — it reports the setup and creates a board if there is none.
4. **Ship something:** `/hefesto:hef.ship "export orders as CSV"` (or `/hefesto:hef.ship ABC-12` for an item already
   on the board). A feature is brainstormed with you, saved as an RFC and planned in the background; the plan comes
   to you as a form (`"plan_review": "human"`, which the board config hefesto creates sets); it is built, checked by
   a separate session, and its pull request is babysat until CI is green. A bug fix goes straight to the builder.
5. **Merge** the pull request on GitHub with **Create a merge commit**, then run `/hefesto:hef.orchestrate` once: it
   records the merge.

## 6. Four lanes

1. **Set the project up once** — in a terminal, in the project's main folder:
   ```bash
   bash ~/.claude-framework/hooks/hefesto-setup.sh --lanes
   ```
2. **Open and name the four lanes**, each in its own terminal, all with the same Claude Code profile. The names come
   from the project folder, or from `"lane_prefix": "myproduct"` under `orchestrate` in `.claude/project-status.json`:
   ```bash
   claude --name myproduct-orchestrator
   claude --name myproduct-planner
   claude --name myproduct-builder
   claude --name myproduct-deployer
   ```
   An explicit map works too: `"lanes": {"orchestrator": "…", "plan": "…", "build": ["…", "…"], "deploy": "…"}`. Run
   the setup again after changing the names.
3. **Start each stage lane once:** `/hefesto:hef.orchestrate --stage plan` in the planner, `--stage build` in the
   builder, `--stage deploy` in the deployer. From then on they wait for the orchestrator's doorbell, and each
   narrates its run as it goes (`· /hefesto:hef.spec`, `· write …/plan.md`, `· run: go test ./...`, `■ done`). The
   three stages overlap; for more builders set `"max_builders": 2` under `orchestrate` and open `myproduct-builder2`
   too.
   **Lanes that do the work themselves:** add `"lane_mode": "interactive"` under `orchestrate`, or per stage
   (`{"build": "interactive"}`). Each stage lane then plans, builds or deploys in its own conversation, in the item's
   worktree, with no background session and no USD spent beyond the lane's own. You can talk to it mid-task, and after
   a compaction or a restart it resumes what it holds. Open those lanes with `--permission-mode acceptEdits`, so
   their edits in the worktree don't ask; the orchestrator stays in the default mode.
4. **In the orchestrator:** `/hefesto:hef.orchestrate` — it checks the setup and finds the three lanes.
5. **Feed it RFCs:** `/hefesto:hef.ship ABC-12` for an item with its RFC on the board (`rfc: docs/rfcs/ABC-12.md`
   under its heading), or `/hefesto:hef.ship "<idea>"`. The orchestrator rings the planner; when a plan is ready it
   asks you to approve it, then rings the builder, then the deployer. Approvals, answers and change requests all
   happen in the orchestrator; you merge on GitHub.

Stage lanes build and test through `hooks/lane-build.sh <command>` (for example `lane-build.sh go test ./...`): it
gives the build a writable cache of its own inside the sandbox. A build run without it fails on the read-only cache.

## Day to day

- **Decisions** come as forms in the orchestrator. Answering one runs the matching command, and Claude
  Code shows its permission dialog — confirm it. That dialog is your signature; run the orchestrator in the
  default permission mode (in a four-lane project it warns you under auto, dontAsk or bypassPermissions).
- **RFCs** live in `docs/rfcs/<ID>.md`, one per item, linked by an `rfc:` line. If an RFC changes after its
  plan was approved, the builder stops and the orchestrator asks you to bring the plan in line.
- **The status line** keeps your own (profile, model, folder…) and adds `ctx 45% · 90k/200k` (context used,
  tokens in context over the window). Rows for the background runs (`▶ implement FAB-1 · 4m`) and the decisions
  waiting on you (`⏸ FAB-3 · plan approval`) are off by default; `"context": {"gauge_rows": true}` in
  `.claude/project-status.json` shows them below it. Track that file in git for the rows to show inside a worktree
  (`git add -f` when your global excludes ignore `.claude/`).
  The orchestrator's pass brief lists runs and decisions either way.
- **Compact** when a lane's status line says `/compact`, with that lane's own prompt
  ([`performance.md`](performance.md), "Compact prompts per pane"). `/clear` only for unrelated work.
  `context.compact_at` in `.claude/project-status.json` sets when it says so (default 40%; per lane, or 0 for never).
- **Spend and network.** Background runs have no spend limit unless you set one: `orchestrate.usd_cap` caps each run,
  and `daily_usd_cap` a board's total for the day; work done in an interactive lane is not capped. A background run reaches no
  network host unless it is listed: for dependency work add `"allowed_domains": ["registry.npmjs.org"]` under
  `orchestrate` (public hostnames only).
- **A GitHub Project as the board.** The lanes can take their items from a GitHub Project: each of the repo's issues
  on the Project is an item (`BC-42` for issue #42), and its Status is the column. `/hefesto:hef.orchestrate` offers
  the repo's Projects when you adopt a board, and `/hefesto:hef.ship` adds issues to it; with `"publish": true` under
  `orchestrate`, each state change moves the card. Issues from accounts outside the team wait for you to read them
  first. Setup and scopes: [`install.md`](install.md) §7, step 14.
- **Several apps in one repository** (`spec_roots`): `/hefesto:hef.ship` asks which app owns a new item, and the
  orchestrator asks for any item that names none; each item is planned and built in its app's folder.
  [`install.md`](install.md) §7, step 15.
- **When something looks wrong**, run `/hefesto:hef.doctor`, copy the exact message, and ask your lead.

**Four-lane projects only** — these are done by a stage lane:

- **Lane actions.** Anything a lane should do for you (merge PR #726 at its head SHA, cut a release, deploy to stg,
  run a backfill, restart a container) is a form in the orchestrator. Ask the orchestrator for it in your words. It
  writes the steps, the exact heads, the stop checks and the commands, and shows them. You answer **Approve**, then
  confirm the dialog. The lane does exactly that, with no dialog in its own pane, and reports done or where it
  stopped. A head that moved, or anything the scope didn't cover, comes back to you as a new form. With
  `context.gauge_rows: true` the status line shows each one waiting on you (`⏸ DET-7-A2 · action: merge PR #726`).
- **Deploy recipes.** Write a deploy once, per environment, under `orchestrate.deploy.recipes` in
  `.claude/project-status.json`: ordered steps, each a title and its commands, with `{version}`, `{sha}` and `{env}`
  filled in when you ask. A step with `"expect": "{version}"` stops the run when the version it reads back differs.
  ```json
  "deploy": { "recipes": { "stg": { "steps": [
    { "title": "deploy",  "commands": ["/usr/bin/ssh deploy@stg-host ./deploy.sh {version}"] },
    { "title": "version", "commands": ["/usr/bin/curl -fsS https://stg-host/api/version/"], "expect": "{version}" } ] } } }
  ```
  A command that leaves the sandbox (ssh, docker, an internal host) is added once with
  `hefesto-setup.sh --lanes --unsandboxed-command "/usr/bin/ssh deploy@stg-host"` (an absolute path); add the curl
  check the same way when `stg-host` is internal. Then say "deploy stg 1.4.2" in the orchestrator: it shows one form
  with every command written out, you approve it, and the deployer runs exactly those, step by step, with no dialog
  in its pane. Editing the recipe later changes nothing already approved.
- **Release trains.** To promote several repos together (an external board with a `repos` map, and a `branches`
  model in each repo), name them under `orchestrate.deploy.trains`
  (`"app": {"repos": ["api", "ui"], "order": ["api", "ui"]}`), open one promotion PR per repo against its environment
  branch, and ask the orchestrator to "promote app to stg". It is one form; the deployer goes repo by repo in that
  order — the PR's state, the checks, then the merge — and a failure in one repo stops it before the next is touched.
- **Merges by the deployer.** With `"merge_by": "lane"` under `orchestrate`, the merge form gains **Merge**: the
  deployer re-reads the PR (clean, CI green, head still the SHA you saw), runs your `orchestrate.merge.checks` (for
  instance `changelog-check.sh -C {repo_path} placement --base origin/{base}`, by absolute path), then merges with a
  merge commit at that exact head and records it. A head that moved, a red check or a conflict comes back to you as a
  form. One merge per repository at a time. The default, `"merge_by": "person"`, is unchanged: you merge on GitHub.
  Either way every PR waiting for you is in **one** merge form per pass: tick the ones to merge (up to 16, oldest
  first), the rest wait for the next pass.
- **Merges with no form.** With `"merge_by": "auto"`, a PR into the **integration branch** merges itself when its
  gates (verify, review, quality, scan) passed at the head that is open, CI is green and every
  `orchestrate.merge.checks` command exits 0. Config alone never turns it on: the orchestrator shows you once what
  it pins — per repo its path, `origin` and integration branch, and the checks verbatim — and **Turn on** is your
  `ledger.sh merge-auto grant` (its permission dialog). Change any of those and it is asked again. An environment,
  `main`/`master` or a protected branch never auto-merges (with no `branches` block the integration branch is `main`,
  so auto never applies); a moved head, a gate that did not pass or a failing check comes back to you as the merge
  form. A merge check is split on whitespace and run without a shell. Turn it off with `ledger.sh merge-auto revoke`.
- **Your name, once.** Setup writes `"decider"` under `orchestrate` from `git config user.name` when it is absent
  (never over yours); the orchestrator records your decisions with it and stops asking your name.

**Security in one paragraph.** The lanes keep Claude Code's sandbox, and commands inside it run without asking.
Outside it run only hefesto's own helpers, `gh` and the commands you added with `--unsandboxed-command`, each called
as one plain command; in a four-lane project those added commands run only as an approved action. Under
`"merge_by": "auto"` your granted merge checks run outside it too, in the repo's folder — so their program must be a
bare name on PATH, or an absolute path in hefesto's hooks folder or a system bin folder (`/usr/bin` …) — a
`./script` or any other file a lane could edit is refused. The ledger, your approvals and
the record of which session is which lane live in `~/.cache/hefesto`, where no sandboxed command and no file edit
can reach them. The commands that record your decisions run only in the orchestrator, behind a dialog, and
`gh pr merge` never runs without an approved action or your dialog. A lane reads item and RFC text that others
wrote, so read each form and dialog before you answer it.

## Upgrade notes

Run the install command, then the setup in each project (section 2). Beyond that:

- **To 9.4:** run the setup again in each project and reopen the lanes: it removes the permission asks on the ledger's
  mechanics, so a dialog appears only where you sign. Spend is open unless `orchestrate.usd_cap` or
  `orchestrate.daily_usd_cap` is set: delete them for no cap. The footer shows only the context gauge
  (`"context": {"gauge_rows": true}` brings the run rows back).
- **To 9.3:** commands are written `/hefesto:hef.<name>` everywhere, the way Claude Code resolves them (the bare
  name never worked for a plugin). A repository can now hold several apps with a `.specify/` each (`spec_roots`,
  [`install.md`](install.md) §7, step 15); a repository without it behaves as before. In a single-app repository, a
  spec command run from a subfolder now uses the top `.specify/` instead of creating one there.
- **To 9.2:** run the setup with `--lanes` again and restart the lanes: it creates the lanes' build cache, and stage
  lanes build through `hooks/lane-build.sh`. A launched worker's hooks no longer run the project's code outside the
  sandbox. A GitHub Project can be the board.
- **To 9.1, in a four-lane project:** a lane now runs a command that leaves the sandbox only as an approved action —
  every command in setup's `--unsandboxed-command` list and any `excludedCommands` in your other Claude Code
  settings. `gh` (its reads stay free) and hefesto's own helpers are unchanged. If a lane used such a command on its
  own in 9.0, it is now denied with a message naming it: ask the orchestrator for an action (a recipe makes a repeated
  one a single form).
