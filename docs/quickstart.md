# Quick start

From nothing to four sessions running the development lifecycle, in six steps. Linux and macOS, as
shipped. The long form is [`install.md`](install.md); to have Claude guide you through the same steps,
open Claude Code in a project and type:
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

## 3. Set up the project (once per repository)

The easy way: in Claude Code, inside the project, type the `SETUP.md` request above. Claude checks the
project, gathers the decisions that belong to your lead into one message, then writes the setup in a
pull request. What it sets up:

1. `/hef.init`, which creates `.specify/` for specs and plans.
2. The board: `tasks/TODO.md`, `DOING.md`, `DONE.md` and `BACKLOG.md`. Each item is a heading with an id
   and a title, then a few lines on what is wanted:
   ```markdown
   ## ABC-12 — Export orders as CSV

   The orders page gets an "Export CSV" button with the columns shown on screen.
   ```
   The id prefix is two or more capital letters or digits, starting with a letter. The sessions take work
   only from `TODO.md`; items only a person can do go in `BACKLOG.md`.
3. `.claude/project-status.json`, with the board, the spend limits, the command that runs the project's
   tests, and `"plan_first": true` (the template is in [`SETUP.md`](../SETUP.md), Step 4c).
4. On GitHub: merge commits allowed and squash and rebase merges turned off (hefesto recognises a merge
   by finding the branch inside the integration branch), and the branch where work integrates protected
   (a pull request required before merging). A branch other than `main` (say `dev`) is declared under `branches`
   ([`install.md`](install.md) §7, step 12).

Merge the setup pull request, then update the project's main folder (`git pull`) before going on: the
sessions read the board from that folder.

## 4. Open the four sessions

Each in its own terminal, inside the project's main folder. Replace `<repo>` with the folder's name:

```bash
claude --name <repo>-orchestrator --permission-mode default --settings '{"sandbox":{"enabled":false}}'
claude --name <repo>-plan         --permission-mode default --settings '{"sandbox":{"enabled":false}}'
claude --name <repo>-build        --permission-mode default --settings '{"sandbox":{"enabled":false}}'
claude --name <repo>-deploy       --permission-mode default --settings '{"sandbox":{"enabled":false}}'
```

`--permission-mode default` keeps the permission dialogs, which some of the human gates are. The sandbox
is off for these four because they start other sessions; the sessions they start are sandboxed.

## 5. Start the lanes

The sessions do not take orders from each other. Each works when its own command runs, and they hand
work on through the ledger. Run this once in each:

| Session | Run once | What it then does |
|---|---|---|
| plan | `/loop 15m /hef.orchestrate --stage plan` | Every 15 minutes: the spec, plan, review and tasks of the next new item |
| build | `/loop 15m /hef.orchestrate` | The next planned item: implemented, checked by a separate session, pull request opened |
| deploy | `/loop 15m /hef.orchestrate --stage deploy` | The next pull request: CI watched and fixed until it is ready to merge |
| orchestrator | `/hef.status` whenever you want | The board and the delivery numbers. The stage sessions run `/hef.orchestrate`; this one does not |

- Each pass takes one item and stays within `usd_cap` and `daily_usd_cap`. One background session runs
  per repository at a time: a lane that finds the repository busy says so and tries on its next pass.
- `"plan_first": true` keeps the build lane from taking an item the plan lane has not planned yet.
- To see each item's state from the orchestrator: `bash ~/.claude-framework/hooks/ledger.sh list --active`
  (running) and `… list --blocked` (waiting). Use the folder where hefesto is installed if it is not
  `~/.claude-framework`.
- Press Esc to stop a loop. You can also type the same commands by hand instead.

## 6. Day to day

1. Add items to `tasks/TODO.md`.
2. When an item waits on a person, `list --blocked` shows it (and every session lists such items when it
   opens). What to do depends on the kind:
   - `human:clarify` or `human:plan-review` on item `ABC-12`: the planner left its questions in the item's
     own folder. Open Claude Code there (`cd .claude/worktrees/ABC-12 && claude`) and run `/hef.clarify`
     (questions) or `/hef.review` (plan review). Then, from the project folder,
     `bash ~/.claude-framework/hooks/ledger.sh unblock ABC-12`. The plan lane picks it up on its next pass.
   - anything else (`verdict`, `stall`, `budget`, `conflict`, `ci`, `human:intake`): ask your lead.
3. Merge each pull request yourself on GitHub, with **Create a merge commit**. No session merges. On its
   next pass the deploy lane checks that the merge really happened, records it and moves the item on:
   there is nothing to type. After a squash or rebase merge that check cannot see the merge: ask your
   lead, who records it with `ledger.sh unblock <id> --merge-sha <the merge commit>`.
4. Between items, or when a session's conversation grows long, run that session's own `/compact` prompt
   ([`performance.md`](performance.md), "Compact prompts per pane").
5. When something looks wrong, run `/hef.doctor`, copy the exact message, and ask your lead.
