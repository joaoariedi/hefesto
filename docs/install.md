# Installing & Configuring

[← back to README](../README.md)

### 1️⃣ Install as a Plugin (recommended)

The framework is a Claude Code plugin. **The hooks ship with it** — you no longer hand-write `settings.json`, which is where every previous version leaked its most-reported friction.

**The quick way: the installation wizard.** In a normal terminal (not inside a Claude Code
session), run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/install.sh)
# pinned to a release:  …/hefesto/v<X.Y.Z>/install.sh  ·  from a clone:  bash ~/.claude-framework/install.sh
```

It does every step in this section, *Updating* (§5) and §6 for each profile it finds: it reports
the clone, each profile's installed version and any old install, prints the numbered plan with the
reason for each step, and asks about each one (Enter accepts the recommendation; `--yes` accepts all
of them, `--dry-run` changes nothing). It never deletes or uses `sudo`; a file it replaces is backed
up to `~/hefesto-old/<timestamp>/` first; it stops on a clone with local changes; and it leaves
symlinked `rules/` or `CLAUDE.md` (dotfiles) alone. Files from an old stow install are listed with
the exact commands to move them, never moved for you. It ends with a table of profile → version →
enabled, read from each profile's plugin registry. The manual steps follow.

**Next:** [`quickstart.md`](quickstart.md) (in Portuguese, [`quickstart.pt-BR.md`](quickstart.pt-BR.md))
takes you from the install to a project with its four sessions running.

It runs on Linux and on macOS as shipped: `/bin/bash` 3.2 and the BSD tools, no Homebrew bash or
coreutils. The hooks keep to the same rule, and a `smoke-macos` CI job runs the whole suite on macOS.

A plugin is installed **from a marketplace**, so the framework ships one (`.claude-plugin/marketplace.json`) that lists exactly one plugin: itself. Clone once, then point the marketplace at the clone:

```bash
git clone https://github.com/joaoariedi/hefesto.git ~/.claude-framework

claude plugin marketplace add ~/.claude-framework
claude plugin install hefesto@hefesto
```

That is a **persistent, user-scoped** install: it writes `enabledPlugins` to `~/.claude/settings.json` and applies to every project, in every session, with no flags. (`~/.claude` is the *default* config directory — if you run more than one, see *Installing into more than one profile* below.) Confirm it:

```bash
claude plugin list          # → hefesto@hefesto  ✔ enabled
```

Because the marketplace source is a **directory**, `plugin install` copies your clone into this profile's plugin cache (`$CLAUDE_CONFIG_DIR/plugins/cache/hefesto/hefesto/<version>/`), and that copy is what sessions load. **Updating is a `git pull` in the clone plus `claude plugin update hefesto@hefesto` in each profile** (see *Updating* below).

<details>
<summary><b>Alternative: try it for a single session, without installing</b></summary>

```bash
claude --plugin-dir ~/.claude-framework      # this session only; nothing is written to settings
claude plugin validate ~/.claude-framework   # check the manifest without loading it
```

</details>

The plugin bundles **skills, commands, agents, hooks, workflows, and the MCP server** in one unit.

> **⚠️ Do not stow the dotfiles *and* install the plugin.** Every component would register twice. If `~/.claude/agents/` or `~/.claude/commands/` already contains these files from the legacy stow install, remove them (`stow -D claude`) before installing the plugin.

#### What the plugin is called once installed

Plugin components are **namespaced by plugin name**, but the namespace is only *required* where a bare name is ambiguous or unsupported:

| Component | How you invoke it |
|---|---|
| **Commands** | `/hef.context`, `/hef.plan`, `/hef.quality` — the bare name works. The `hefesto:` prefix also works, and disambiguates if another plugin defines the same name. |
| **Agents** | Dispatched by Claude, or by name — they appear as `hefesto:code-reviewer`. |
| **The workflow** | **Must be namespaced**: `hefesto:workflow`. A bare `workflow` **does not resolve**. |

#### Installing into more than one profile

`~/.claude` is the **default** config directory, not the only one. Claude Code keys everything it stores to `CLAUDE_CONFIG_DIR`: installed plugins, registered marketplaces, `settings.json`, `.claude.json`, sessions and memory all live *inside* it. So pointing that variable somewhere else — to run a second account, or to keep client work separate from personal — hands you a profile with **no plugin installed**. As in step 3, the absence is silent: the `/` menu simply comes up short.

Install once per profile:

```bash
export CLAUDE_CONFIG_DIR=~/.claude-work            # whatever that profile uses

claude plugin marketplace add ~/.claude-framework
claude plugin install hefesto@hefesto
claude plugin list                                 # → hefesto@hefesto  ✔ enabled
```

**The clone is shared; the running copy is per profile.** The marketplace source is a *directory*, but `plugin install` copies it into that profile's cache — `$CLAUDE_CONFIG_DIR/plugins/cache/hefesto/hefesto/<version>/` — and the hooks, commands, and skills a session loads come from *there*, not from the clone (measured 2026-09-23: three profiles, three caches, two of them a version apart). So a `git pull` in the clone changes nothing a session sees until each profile runs `claude plugin update hefesto@hefesto`, which re-copies the clone when its manifest version is newer. What each profile needs is its own one-time `marketplace add` + `install`, and its own `plugin update` after every release.

The gap in step 6 is per profile too. `rules/` and `CLAUDE.md` are copied *into a config directory*, so each profile needs its own copy — and its own re-copy after an upgrade.

### 2️⃣ Optional Configuration

Two things the plugin cannot ship, because they are machine-local by design:

```jsonc
// In ~/.claude/settings.json — only if you want these:
{
  "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" },   // Agent Teams (experimental)
  "permissions": {
    "allow": [
      "Bash(/home/you/.claude-framework//hooks/speckit-helper.sh:*)",   // ← your REAL home dir
      "Bash(/home/you/.claude-framework/hooks/speckit-helper.sh:*)"
    ]
  }
}
```

> ⚠️ The `speckit-helper.sh` permission avoids a prompt on every hef command. The commands run the helper with the Bash tool; they cannot pre-execute it in a `` !`…` `` block, because a `!` block is permission-checked *before* `${CLAUDE_PLUGIN_ROOT}` is substituted and is rejected outright as `Contains expansion`.
>
> **The rule must mirror the command byte for byte. The matcher does no expansion and no normalisation.** Tested against the live matcher:
>
> | Rule | Result |
> |---|---|
> | `Bash(/home/you/.claude-framework//hooks/speckit-helper.sh:*)` | ✅ matches |
> | same, but one slash before `hooks` | ❌ blocked |
> | `Bash($HOME/…)` | ❌ blocked — **`$HOME` is not expanded** |
> | `Bash(~/…)` | ❌ blocked — **`~` is not expanded** |
> | leading wildcard | ❌ blocked |
>
> **Write your home directory out literally** (`echo $HOME`). The doubled slash is not a typo and is the entry that works: `${CLAUDE_PLUGIN_ROOT}` expands *with* a trailing slash, so the helper reaches the matcher as `…/.claude-framework//hooks/…`. The single-slash entry is a hedge against a future release dropping that slash; it matches nothing today. Keep both.
>
> **This is the single most common failure.** A pre-flight command that is denied aborts the whole slash command **silently** — no error, no output, exit 0. If a hef command appears to do nothing at all, this rule is the first thing to check.
>
> The same applies to the other helpers the commands call — `status-board.sh` (`/hef.status`), `ledger.sh` and `session-launch.sh` (`/hef.orchestrate`), `pr-watch.sh` (`/hef.babysit`), `arena-run.sh` (`--arena --via`, `--second-opinion`), `release.sh` (`/hef.release`): they prompt on first use; allow them in the same form if you use those commands.

Export `GITHUB_TOKEN` if you want the bundled GitHub MCP server to connect.

#### Turn on the sandbox

The hooks are string matchers. `block-destructive-commands.sh` denies `git push --force` in every
spelling it can see — but Claude Code's own documentation says a Bash deny rule *"isn't a security
boundary"*: `sh -c "git push --force"` and `/usr/bin/git reset --hard` compose around any pattern.
The hook's header says the same. The boundary is the OS sandbox:

```
/sandbox            # inside a session — enables filesystem + network isolation for shell tools
```

or set it in project settings so every session gets it. With the sandbox on, the hooks catch the
careless path and the sandbox catches the determined one. Without it, the hooks are a very good
seatbelt in a car with no doors.

```json
{ "sandbox": { "enabled": true, "failIfUnavailable": true } }
```

in `.claude/settings.json` (or `settings.local.json`) is the project-settings form. On Linux it needs
`bubblewrap` and `socat` installed; `failIfUnavailable` makes a missing backend refuse to run rather
than run unconfined.

**What to expect once it is on** (measured 2026-09-23 on this repository):

- `git status` from a sandboxed shell lists phantom entries — `.bashrc`, `.gitconfig`, `.idea`,
  `.gitmodules` — in the repository root. They are `/dev/null` masks the sandbox places over
  sensitive dotfile names, not files; outside the sandbox they do not exist. Do not `rm` them.
- `.git/config.lock` is masked the same way, so anything that writes `.git/config` fails with
  *could not lock config file*: `git push -u`, `git remote add`, `git branch --set-upstream-to`.
  Commits, `git push` without `-u`, tags, and branch deletes work. Push without `-u`.
- Only `$TMPDIR` is writable under `/tmp`. The plugin's hooks honour it, so `tests/smoke.sh` runs
  clean from a sandboxed shell; a script of your own that hard-codes `/tmp` will not.
- Writes outside the working directory are denied (`Read-only file system`), which is the point —
  updating the installed plugin clone or a dotfiles checkout from inside a session needs the `!`
  prefix, which runs the command outside the sandbox.

### 3️⃣ Verify the Installation

```bash
cd ~/any-project && claude
```

Three checks, in increasing strength:

1. **`claude plugin list`** — the plugin is `✔ enabled`. If it is not here, nothing else matters.
2. **The `/` menu** — every command should be listed. **A component that does not appear is not loaded**, and its absence is silent. This is the only reliable test.
3. **Run one** — `/hef.context` should print a tech-stack summary. If it prints *nothing*, the pre-flight permission rule in step 2 is missing (see the warning above).

> ⚠️ `claude plugin details hefesto` prints a component inventory, but it reports **`Agents (0)`** for this plugin even though all seven agents load correctly. That is a quirk of the inventory display, not a fault in your install — confirmed by dispatching the agents in a live session. Do not chase it.

### 4️⃣ Your First Feature (the 60-second tour)

The framework's core loop is **spec first, then code, then a gate you cannot talk your way past.**

```bash
/hef.init                    # once per project — bootstraps .specify/
/hef.spec  add user login # → a spec: scenarios, requirements, success criteria
/hef.plan                    # → an implementation plan (writes are blocked outside .specify/)
/hef.review                  # → plan mode: a fresh code-reviewer gates the plan; APPROVE writes "## Reviewed"
/hef.tasks                   # → a phased, dependency-ordered task list
/hef.implement               # → TDD execution, red-green, one task at a time (tests may grow, not shrink)
/hef.verify                  # → every FR mapped to the tests that cite it, then spec-compliance review
/hef.quality                         # → lint, types, secrets, SOLID — before you commit
/hef.review                          # → two-stage code review
/hef.pr                              # → the pull request, with the evidence attached
```

For a **large** task list, swap the implementation step for the workflow, which runs independent tasks in parallel and has every task adversarially verified by agents that did not write it:

```
hefesto:workflow
```

Not every change deserves a spec. For a typo or a config tweak, `/hef.fix` skips the pipeline. For an existing codebase with no specs, `/hef.baseline` reverse-engineers them.

**What happens without you asking:** on every edit, formatters run and tests fire; on every `git commit`, secrets detection and linting must pass or the commit is blocked; and a task cannot be marked complete while the test suite fails. You do not opt into these — they ship with the plugin.

### 5️⃣ Updating

Updating is two steps: refresh the clone, then re-copy it into each profile's cache:

```bash
git -C ~/.claude-framework pull
claude plugin marketplace update hefesto   # re-read the manifest
```

Restart Claude Code to pick up the new components. To check what changed first, read `CHANGELOG.md` in the clone.

One pull refreshes the clone, but **each profile runs its own cached copy**, so the update is per profile, and only for profiles you actually run:

```bash
claude plugin update hefesto@hefesto                                   # default profile
CLAUDE_CONFIG_DIR=~/.claude-work claude plugin update hefesto@hefesto  # each other profile
```

`plugin update` compares manifest versions, not commits: a pull that did not bump `plugin.json` reports "already at the latest version" and leaves the cache as it was. Releases always bump it; between releases, `plugin uninstall` + `install` is the way to pick up an unreleased commit.

**Rolling a release out to a team** — the message to send, with `X.Y.Z` filled in:

```bash
# Hefesto X.Y.Z is out. Upgrade (about a minute):
git -C ~/.claude-framework pull --ff-only
claude plugin marketplace update hefesto
claude plugin update hefesto@hefesto                     # once per profile: CLAUDE_CONFIG_DIR=~/.claude-<profile> claude plugin update hefesto@hefesto
cp ~/.claude-framework/.claude/rules/*.md ~/.claude/rules/
diff ~/.claude-framework/.claude/CLAUDE.md ~/.claude/CLAUDE.md        # merge by hand if you customised it
# Restart Claude Code, then /hef.doctor must report RUNNING_MATCHES_CLONE at X.Y.Z.
```

### 6️⃣ The two things the plugin cannot ship

`plugin.json` ships **skills, commands, agents, hooks, workflows, and the MCP server**. There is no plugin component for **`rules/`** or **`CLAUDE.md`** — so installing the plugin does *not* give you the framework's global rules (code quality, git workflow, the Iron Laws, security, context management). If you want those to apply everywhere, copy them into `~/.claude/` yourself:

```bash
cp -r ~/.claude-framework/.claude/rules ~/.claude/rules
cp    ~/.claude-framework/.claude/CLAUDE.md ~/.claude/CLAUDE.md
```

> ⚠️ **These drift.** Nothing keeps them in sync — a `git pull` updates the plugin's components but not your copies. Re-copy them after an upgrade, and read `CHANGELOG.md` to see whether they changed. This is the one genuine gap in the plugin install, and it is a limitation of what a Claude Code plugin can contain, not an oversight.

<details>
<summary><b>Historical: the old dotfiles + stow install</b></summary>

Before 4.4.0 the framework was installed by symlinking a dotfiles package into `~/.claude/` with GNU Stow. **That path is gone.** As of 4.5.0 the plugin payload lives at the repository root, not under `.claude/`, and the dotfiles package no longer carries `agents/`, `commands/`, `hooks/`, or `skills/` — following the old instructions today produces a half-install with none of them.

If you have a legacy stow install, retire it before installing the plugin, or every component registers **twice**:

```bash
cd ~/dotfiles && stow -D claude    # then install the plugin as above
```

Keep `CLAUDE.md` and `rules/` if your dotfiles carry them — as above, the plugin cannot ship those.

</details>

---

### 7️⃣ Running the orchestrator (the multi-session pipeline, Phase 1)

`/hef.orchestrate` dispatches **one** board item at a time to a fresh headless worker and then a
separate verifier, through a ledger in the repository's git common dir (`.git/hefesto/ledger/`).
The design and the evidence behind it are `reports/17-multi-agent-session-orchestration.md`.

1. **Declare the board** in `.claude/project-status.json` (the same file `/hef.status` reads; only
   `source: tasks-repo` is dispatchable in Phase 1) and add the `orchestrate` block:
   `{"usd_cap": 20, "daily_usd_cap": 100, "tiers": {"implement": "opus", "verify": "fable"}}` — tiers,
   never model ids; the reviewer tier must rank at or above the author's.
2. **Protect `main`**: require a pull request before merging (0 approvals is enough on a solo repo,
   include administrators). No launched session can then push `main`, whatever its prompt says.
   Merge with **merge commits**, not squash or rebase: the `human:merge` gate is cleared by
   `git merge-base --is-ancestor <branch> main`, which a squash- or rebase-merged branch never satisfies.
3. **Open the orchestrator pane with its own sandbox off**, in the main checkout, on the always-on
   host that holds GitHub access and nothing else:
   `claude --settings '{"sandbox":{"enabled":false}}'` (under herdr: one pane in the company
   workspace). The launcher spawns `claude -p` as a child of the shell, and a sandboxed shell would
   let it neither reach the API nor save its transcript — `session-launch.sh` refuses with that
   reason. The workers it starts are sandboxed by the settings it passes them.
4. **Dry-run first**: `/hef.orchestrate --dry-run` prints the exact `claude -p` line for the next
   item and claims nothing. Then `/hef.orchestrate` for real: one item, a PR, verdicts in the ledger,
   the entry blocked on `human:merge`.
5. **Watch for blocks**: every session opened in the checkout prints `ledger: <id> blocked_on <kind>`
   at start; `herdr agent wait --until blocked` and `claude agents --json` show the pane. A `human:*`
   block is cleared only by the artifact the human command leaves behind (`/hef.clarify`,
   `/hef.review`, the merge itself — the branch in the integration branch or, once GitHub deletes it,
   the PR's merge commit there), or — for `human:intake` only — by a person who read the item
   text (`status-board.sh --item <id>`) running
   `hooks/ledger.sh unblock <id> --reviewed-by-human --by <name>`. That clear works from any session,
   and the name and time are recorded on the entry (`.reviewed`). The gate is Claude Code's
   **permission prompt**: never add `--reviewed-by-human` (or a blanket `ledger.sh` rule) to any
   allowlist, so every intake clear is a dialog you answer. That needs the pane in **`default`
   permission mode**: under `auto`, `bypassPermissions` or `dontAsk` no dialog appears (the session-start
   hook warns when an intake or a `human:merge` block is open in such a session). Never answer "Yes, don't ask again" on a
   `ledger.sh` call in the orchestrator pane either: the saved prefix rule would admit the clear
   silently. The command is refused inside a launched worker. Nothing replaces an intake block, and nothing claims
   an intake-blocked entry: the named clear is the only way out. A worker cannot replace any other
   person's block either.
6. **After you merge**: with a deploy stage running (`/hef.orchestrate --stage deploy`), its next pass on
   the item does this for you — it fetches, runs the same `unblock` evidence check and `advance … merged`,
   removes a clean worktree, and launches nothing. Without one: `git fetch --prune origin` (and `git pull --ff-only`), then
   `hooks/ledger.sh unblock <id>` and `hooks/ledger.sh advance <id> merged`. The unblock accepts the
   branch inside the integration branch or, once the branch is deleted, the recorded PR's merge commit
   (read through `gh`, which must say MERGED from that branch); it records that commit as
   `.pr.merge_sha`, which `advance … merged` re-checks. For a squash or rebase merge whose branch still
   exists, pass the merge commit yourself: `hooks/ledger.sh unblock <id> --merge-sha <sha>` (refused
   inside a launched worker). With gh installed the sha is checked against the PR, and a gh that
   cannot read it refuses (fail closed — fix `gh auth status` or retry); without gh it is accepted but
   printed `UNVERIFIED` and recorded as `.pr.merge_unverified`. Remove the worktree with
   `git worktree remove .claude/worktrees/<id>`.
7. **Between the PR and the merge, let the babysitter watch it**: from the checkout of the PR's
   branch, `/hef.babysit` (or `/loop 25m /hef.babysit <n> --once` while a review is pending). It
   waits on CI inside one helper call — that Bash call runs with the tool timeout raised to
   600 000 ms — fixes a red check inside the PR's own diff, answers pertinent review comments with
   the commit hash, asks you about doubtful ones, and stops at mergeable with the ledger blocked
   on `human:merge`. Under the sandbox, `gh` needs `api.github.com` granted; the push uses the
   remote's transport (ssh on most checkouts), so when the sandbox refuses it the command prints
   the exact `git push origin <branch>` line for you to run with the `!` prefix and ends the
   pass. It never merges, approves, force-pushes, or edits CI configuration — a fix that would
   need any of those becomes a question for you.
8. **Running the by-stage layout** (README §5): `/hef.orchestrate --stage plan` plans the next
   queued item in a fresh session that writes only under `.specify/`; the default stage builds it;
   `--stage deploy` runs one babysitter pass on the next PR. Two settings matter: every role's
   allowlist gets the plugin's own hooks directory appended automatically, so put the **project's
   test command** in `orchestrate.allowed_tools.<role>` (this repository: `Bash(bash tests/smoke.sh*)`
   and `Bash(node --test*)` for `implement` and `verify`) without fear of losing the helpers — but the
   configured list *replaces* the role's default list (only the hooks rule is appended), so copy the
   defaults from `session-launch.sh` and add the test command to them; and every launch is one Bash
   call that can block for many minutes (a deploy pass waits on CI inside the babysitter), so the
   command makes it with the tool timeout raised to 600 000 ms. `orchestrate.panes` maps block
   kinds to your pane names; the session-start line then says whose block it is.
   With the plan and build stages each on a `/loop` (the four-session setup in
   [`quickstart.md`](quickstart.md)), set `orchestrate.plan_first: true`: the build stage then takes
   only planned items (phase `tasks`, or an `implement` retry), never a queued one, so a new item cannot
   be built before it is planned. Without it, build also takes queued items, as before.

8b. **RFCs, plan approval and the lanes** (lanes v2; [`quickstart.md`](quickstart.md) steps 5–8). An
   item names its RFC with a line `rfc: docs/rfcs/<ID>.md` (folder: `orchestrate.rfc_dir`); the plan stage
   hands the RFC to the planner as comment-stripped, delimited data, pins its path and sha256 on the entry,
   and the planner specs from it, citing it. With `orchestrate.plan_review: "human"` (`"agent"` = the
   reviewer's verdict suffices; anything else is refused) a finished plan stops at phase `plan-review` on
   `human:plan-approval`: only `ledger.sh unblock <id> --reviewed-by-human --by <name>` clears it (refused in a
   launched worker; recorded with the RFC's hash), nothing replaces that block, and leaving `plan-review`
   needs the approval on record. An RFC that changes after approval stops the build and re-blocks the item
   until a person aligns the plan, re-pins (`ledger.sh record <id> --rfc`) and approves again. Set the
   project up once with `hooks/hefesto-setup.sh` (`--lanes` for four lanes), in a terminal. It writes
   `.claude/settings.local.json`:
   - hefesto's helper allowlist;
   - a person's decisions (`approve`, `unblock`, `record`, `answer`, `revise`, `release`, …) in `ask`;
   - outside the sandbox (`sandbox.excludedCommands`): the launcher, `ledger.sh` (hefesto 9 keeps the ledger outside
     the project) and `gh` (so a merge is decided by the permission rules, never by the sandbox). Only gh's read
     forms and `gh pr create` are allowed; `gh pr merge`, `gh pr review` and `gh api` always need an approved
     action or your dialog;
   - `Edit` denied on hefesto's own state (`~/.cache/hefesto/{ledger,approvals,sessions}`);
   - the sandbox on (`enabled`, `failIfUnavailable`), and sandboxed commands running without a dialog
     (`--strict` keeps 8.0's every-command-asks);
   - the trusted project folder, the context gauge;
   - with `--lanes`: `crossSessionInbound: "accept"`, `HEFESTO_LANES` and the lane map (`HEFESTO_LANE_MAP`, from
     `orchestrate.lanes`, `orchestrate.lane_prefix` or the folder name).

   Lanes open with `claude --name <a name in the map>`; the name is the lane, and a session whose name is not in the
   map is no lane. In the orchestrator, `/hef.orchestrate` asks every decision as a form and rings the stage lanes;
   `/hef.ship` starts new work. `context.compact_at` sets each lane's compaction nudge.
   **What a background worker can reach.** Its sandbox writes only its worktree and a cache of its own
   (`~/.cache/hefesto/worker-cache/<repo>`, which `XDG_CACHE_HOME`, `GOCACHE` and npm's cache point at — never
   your own `~/.cache/go-build`, which your unsandboxed builds share). Go's module cache (`~/go/pkg/mod`) stays
   read-only: modules already there work, a task that adds one cannot download it. The network: only
   `orchestrate.allowed_domains` (public hostnames). A worker cannot push over SSH (the sandbox proxy carries
   HTTPS only), so for workers that push, add `"github.com"` and `"api.github.com"` and, in the repository,
   `git config url."https://github.com/".pushInsteadOf git@github.com:` — pushes then go over HTTPS with the
   `gh` credential helper.

8c. **Lane actions, and what protects them** (hefesto 9; [`quickstart.md`](quickstart.md), "Lane actions"). Any
   action a stage lane carries out for you — a merge with its head SHA, a release cut, a deploy, a backfill, a
   server command — is a **request** the orchestrator writes (`ledger.sh request <id> --to <lane> --scope-file <f>`;
   `ledger.sh op new` for one that belongs to no item):
   - the steps;
   - the heads as full SHAs;
   - the stop checks;
   - what is not covered;
   - whether it is irreversible;
   - the exact commands it needs.

   You answer it as a form in the orchestrator. **Approve** runs `ledger.sh approve` behind its permission dialog
   there, naming the hash, the lane and the title. The lane then takes it, checks the heads live, follows the steps,
   and records done or stopped-at-step-N. While the action is open, its commands run without a dialog in the lane's
   pane (`hooks/lane-guard.sh`). One approval, one use; a changed scope or head stops the lane and comes back as a
   new form. Directives (`ledger.sh direct`) route a precise instruction to a lane inside an item's scope; they
   approve nothing.

   The trust model:
   - **The approval store, the ledger and the session records** live in `~/.cache/hefesto/`, outside every
     sandbox's write set. Only hefesto's helpers write them; file edits there are denied, through a symlink too.
   - **The lane** is the session's name, recorded by the session-start hook outside the sandbox.
   - **A person's decision is recorded only from the orchestrator lane**: lane-guard and `ledger.sh` both check.
   - **A command hefesto runs outside the sandbox** must be one plain word list: no pipe, redirect or chain. A command
     that merely names one (`echo gh`, `grep -rn gh docs/`) is refused too, on purpose: use the Grep tool to search.
   - **A command that stays inside the sandbox runs without approval.** The sandbox's network allowlist is part of the
     trust model: keep it to what the lanes need.
   - **Hefesto's hooks that run a project's own commands** (tests after an edit, the formatter, the task-completion
     gate, the commit gate's linters) stand down in a `--lanes` project. A hook runs outside the sandbox, so those
     would be a way out of it.
   - **In auto mode** a command no rule matches is the classifier's call, with no dialog; every lane says so at start.
   - **The GitHub API is denied to the sandbox** (`sandbox.network.deniedDomains`). Only the unsandboxed `gh` and
     `pr-watch.sh` reach it, each called as one plain command and decided by the permission rules. `git push` over
     HTTPS (github.com) still works.
   - **Your own command lists** are typed on setup's command line, never read from a file a lane can write. Setup
     keeps them in `settings.local.json`; a later run keeps them, and `--forget-commands` drops them:
     - `--allow-command "<pattern>"` adds an allow rule (for `gh`, only its view, list, checks and diff forms);
     - `--unsandboxed-command "<absolute path …>"` runs a command outside the sandbox, e.g. `/usr/bin/ssh
       debian@vm-apps *` for the steps an approved scope needs. Each still needs the grant or your dialog.

     A shell or interpreter (by basename: `/bin/sh` too), a wrapper, `-c`/`-e` or a shell operator is refused.

   **Interactive lanes** (`orchestrate.lane_mode`: `"worker"`, the default, or `"interactive"`, for all stages or per
   stage `{plan, build, deploy}`). A stage lane takes its item with `session-launch.sh <role> <id> --prepare --lane
   <its name>`. That makes every check a launch makes, claims the item for the lane (no lease: it ends with
   `--finish`, or `ledger.sh release` by a person) and makes the worktree and the prompt. The lane then does the stage
   with the `/hef.*` commands in its own conversation. `--finish --lane <name> --outcome-file <f>` checks its outcome
   against the role's schema and records it exactly as a background run's ($0, `note: in-lane`). An interactive build
   verifies through `/hef.verify` and `/hef.review`, whose reviewers run in a fresh context; their verdicts are
   recorded as `<lane>:code-reviewer`. That name is the lane's claim, not proof: keep `"build": "worker"` when you
   want the separate verifier session. On an external board the lanes work in the code repos' worktrees, which
   `setup --lanes` grants as `additionalDirectories`.

   **The ledger moved.** Hefesto 9 keeps it in `~/.cache/hefesto/ledger/<key>`. The first `ledger.sh` call that can
   write there moves an 8.x ledger itself:
   - once, under a lock, only while no 8.x run renews a lease;
   - it leaves `.git/hefesto/MOVED` and keeps the old folder, renamed.

   A sandboxed session without setup cannot write there: run `hefesto-setup.sh` before the first `/hef.orchestrate`
   or `/hef.ship`. `run-follow.sh` shows nothing for runs started before the upgrade.

9. **Hand-run items, the board and escalation** (all optional): a person who ran an item by hand runs
   `hooks/ledger.sh handoff <id> --pr <url>` on its branch — one call instead of four. Set
   `orchestrate.publish: true` and every orchestrator pass writes the item's state as the first token
   of its board heading (⏸ waits on a person, ⛔ blocked otherwise, 📐 planning, 🔨 building, 🔀 PR, ✅
   merged); add those glyphs to the board's `states` map so `/hef.status` labels them, and override
   them with `orchestrate.publish_markers`. Set `orchestrate.escalate_after_hours: <n>` and a `human:*`
   block older than `<n>` hours is sent once, as one line, to the session that owns it
   (`orchestrate.pane_sessions.<pane>`, default `<repo>-<pane>`). That receiving pane must accept
   cross-session messages (`crossSessionInbound: accept` in its settings, with `isolatePeerMachines:
   true`), or every pointer fails and is retried next pass; no other pane needs inbound. Escalation is
   opt-in because report 17 asked for it only once Phase 1 showed blocks waiting too long — no such
   baseline has been measured yet.
10. **Incidents and vulnerabilities on the board**: put 🐞 before an item's id for an incident fix, 🛡 for
    a vulnerability (`## 🐞 HEF-21 — login fails after refresh`; `kinds` in the config maps your own
    glyphs to `feature`, `incident` or `vulnerability`, never to a publish marker). The glyph must come
    before the id — one after it is title text — and 🛡 and 🛡️ (with or without the emoji variation
    selector) are the same glyph. The orchestrator records the kind; the worker is told to write a regression test that
    cites the id first (incident) or to re-scan before the PR (vulnerability); the verifier must
    report that gate, and a missing or SKIPPED one blocks the entry on `verdict`. `/hef.status` reads
    a heading's first token as its sub-state, so add the kind glyphs to `states` if you want them
    labelled.
11. **Providers: other vendors as arena readers and as a second opinion** (optional, HEF-13). Declare
    the model access you already have in `.claude/project-status.json`:

    ```json
    {
      "providers": {
        "codex":  {"via": "codex"},
        "gemini": {"via": "gemini", "model": "<your gemini model>"},
        "bedrock_llama": {"via": "aws", "model": "<your Bedrock model id>", "region": "us-east-1", "max_tokens": 4096}
      }
    }
    ```

    (`providers` is a top-level key in `.claude/project-status.json`, beside `orchestrate`.)

    Names are `[a-z0-9_]+` (they become Arena columns) and may not be a Claude tier (`sonnet`, `opus`,
    `fable`, `haiku`). `model` and `region` must look like ids (no leading `-`, no `://`: the AWS CLI
    would read a `file://` value from disk), and `max_tokens` must be a positive integer. `via` is one of four runners, each the CLI's own
    non-interactive mode, detected with `command -v`, never installed by hefesto: `claude` (`claude -p
    --permission-mode plan`), `codex` (`codex exec --sandbox read-only`), `gemini` (`gemini -p`, with no
    approval flags; its headless mode has no read-only switch), `aws` (`aws bedrock-runtime converse`).
    **Authentication is each CLI's own**: hefesto reads, stores and passes no key. A concrete model id
    belongs here, in your config, never in the framework's files. Then `hooks/arena-run.sh --check`
    prints one line per provider (`ok`, `missing (<install hint>)`, `ok (second-opinion only)` for
    `aws`).

    They are used in two places only: `/hef.plan --arena K --via <p,…>` gives up to K−1 arena slots
    to providers (one `truth-scout` is always kept), and `/hef.review --second-opinion <p>` relays
    another vendor's reading under "Second opinion (<p>) — not the gate". It never writes
    `## Reviewed`, and a foreign model is never the verifier of record. `aws` is a message API that
    cannot read the repository, so it is second-opinion only. **Sending the spec, the plan or the diff
    to a provider is egress to that vendor:** `arena-run.sh` runs only from an unsandboxed pane. It
    refuses inside a launched worker (`HEFESTO_WORKER=1`, which `session-launch.sh` exports) and from a
    sandboxed shell (`$HOME` not writable).
12. **A branch model other than trunk-on-`main`** (optional, HEF-15). If changes integrate on
    another branch and promote through environments, declare it in `.claude/project-status.json`:

    ```json
    {
      "branches": {
        "integration": "dev",
        "protected": ["release/*"],
        "environments": ["dev", "stg", "main"]
      }
    }
    ```

    `hooks/ledger.sh branches` prints the resolved model. Unconfigured, it is `main` everywhere,
    exactly as before. What it changes:
    - **Integration branch:**
      - workers open PRs against it (`gh pr create --base dev`), and so does `/hef.pr` when you name
        no base;
      - the verifier's diff base, `pr-files` and `deps-diff` compare against it, using the newer of
        the merge-bases with `origin/dev` and the local `dev`;
      - the merge-tree probe bases on it;
      - `ledger.sh unblock` clears `human:merge` once the branch is in `dev` or `origin/dev`.
    - **Protected set:** `main`, `master`, the integration branch, every environment and your
      `protected` globs. These are never a worker's head and never pushed: `ledger.sh handoff`
      refuses them, and `pr-watch.sh resolve` marks a promotion PR (`stg → main`) `"push": false`, so
      `/hef.babysit` reports its red checks without ever fixing them.
    - **Environments, in order:** the last is the **final** branch.
      - `ledger.sh where <id>` shows how far a merged branch has travelled (`yes`, `no`, or `unknown`
        when that branch exists neither locally nor on `origin`).
      - `ledger.sh advance <id> released` waits for the final branch.
      - `/hef.release` tags the final branch's commit.

    A config file that is not valid JSON is an error, never "unconfigured". Without a `branches`
    block, PRs keep the repository's default branch as their base. Every promotion is still a
    person's merge. The remote is assumed to be named `origin`, and
    `where` and the `released` check assume merge commits: a squash promotion defeats the ancestry
    test.
13. **External board** (optional, HEF-14). If the board is its own git repository and feeds several
    code repositories, keep two configs:

    ```jsonc
    // <code repo>/.claude/project-status.json — a pointer, plus that repo's own branch model (step 12)
    { "board": "../tasks", "branches": { "integration": "dev" } }

    // <board repo>/.claude/project-status.json — the board config as in step 1, plus the repos it feeds
    { "source": "tasks-repo", "root": ".", "orchestrate": { … },
      "repos": { "ops": "../api_service", "ui": "../web_app" } }
    ```

    `hooks/ledger.sh board` prints the resolved board (`mode` `in-repo` or `external`, the board top,
    its config, the ledger dir, `repos` as absolute paths, and the current repo's name). Without a
    `board` pointer and without `repos`, everything is in-repo, exactly as before.
    - **Which config holds what.** `board` is a path relative to the code repo's top, or absolute;
      `repos` maps a name (`[a-z0-9_-]+`) to a path relative to the board's top, or absolute. The
      board config holds the board fields, `orchestrate` (tiers, caps, allowlists, publish, escalate,
      panes) and `kinds`. Each code repo keeps its own `branches`, so ops can integrate on `dev`
      while ui stays on trunk. A config with both `board` and `repos`, a pointer to a board that
      itself has a `board`, or a config that does not parse when it names `board` or `repos` is
      refused, naming the value (an unparseable config that names neither stays in-repo, where the
      branch model and `/hef.status` report it as before). Every `repos` path must exist on this
      machine, or every call refuses naming it. Only a `source: tasks-repo` board can be external:
      routing (`--item-repo`) reads item bodies, which a `github-project` board does not have here.
    - **The pointer is read through the main worktree.** If `.claude/` is ignored (globally, as some
      teams do), the pointer file is untracked and a linked worktree has none; `ledger.sh` reads it
      from `$(dirname "$(git rev-parse --git-common-dir)")`. Submodules and `--separate-git-dir`
      checkouts are out of scope. External mode needs git; the launcher exports
      `HEFESTO_BOARD_TOP` so every child call, the worker included, resolves the same board.
    - **Routing.** An item names its repo on a body line `repo: <name>`, which may be indented and
      bulleted (`  - repo: ops`, `* repo: ops`) and may end in CRLF; a bold `**repo:**` is **not** a
      repo line. The line must sit **above any `###` sub-heading** on a `^#{2,3}` board, because a
      sub-heading ends the item's body. A `repo:` inside an HTML comment does not count. A refusal
      shows names only as `[a-z0-9_-]` (anything else as `?`, at most 32 characters, five names). With no `repo:` line, the item goes to the
      board's only repo; with several repos it is refused ("names no repo"), as is an item naming
      two repos ("split it into one item per repo") or an undeclared one.
      `status-board.sh --item-repo <id>` prints `<name>` TAB `<path>`; `/hef.orchestrate` reports a
      refusal and skips the item, writing nothing.
    - **One central ledger** in the board repo's git common dir (`<board>/.git/hefesto/ledger/`). Each
      entry records `repo`, so `list`, `metrics` and escalation see every repo, and `next` keeps
      **one worker per repository** (an `ops` worker and a `ui` worker run side by side). A repo you
      switch to external starts from the central ledger; its old entries stay in its own
      `.git/hefesto/ledger/`. `daily_usd_cap` sums today's spend across every repo the board feeds.
    - **Where sessions run.** The planner, the worker, the verifier and the babysitter run in the
      entry's repo (`<repo>/.claude/worktrees/<id>`); start the launcher from the board repo or any
      code repo it feeds. `ledger.sh handoff` records the repo you run it in, and `unblock`,
      `where` and `advance … released` check git in the entry's repo.
    - **Publish** marks the item in the board repo's file. Commit it yourself; committing
      automatically is board item HEF-16.

Spend: `--max-budget-usd` caps each session; the launcher also refuses when today's total across
the ledger plus the next cap would exceed `daily_usd_cap`. Cost per merged PR comes from the
`runs[]` on each entry.

**Two hosts, if you run the by-stage layout** (README §5): the `deploy` pane splits along the
trust boundary in `docs/architecture.md` — CI, the PR and the babysitter on the always-on
workstation that holds GitHub access only; environment transitions and the production release on
the laptop that holds the credentials. The ledger is per checkout, so the laptop reads the release
queue with `git pull --ff-only` and `hooks/ledger.sh list --phase merged`; board write-back (HEF-4, opt-in
`orchestrate.publish: true`) is what makes that queue visible across both machines without a message.
