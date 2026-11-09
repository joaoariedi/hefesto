# Installing & Configuring

[← back to README](../README.md)

This is the install and configuration **reference**: the wizard's full behaviour, the manual install, profiles,
optional configuration, the sandbox, updating, what the plugin cannot ship, and the orchestrator (§7). To install
quickly, use your OS's page — [Linux](install-linux.md) · [macOS](install-macos.md) ·
[Windows (WSL)](install-windows.md); to set a project up after that, the [quick start](quickstart.md); to have Claude
walk you through it, [`SETUP.md`](../SETUP.md).

### 1️⃣ Install as a Plugin (recommended)

The framework is a Claude Code plugin. **The hooks ship with it** — you no longer hand-write `settings.json`, which is where every previous version leaked its most-reported friction.

**The quick way: the installation wizard.** The install command, its pinned-release and clone-first forms, and the
tools it needs are on the per-OS pages ([Linux](install-linux.md) · [macOS](install-macos.md) ·
[Windows (WSL)](install-windows.md)); what follows is everything the wizard does.

It does every step in this section, *Updating* (§5) and §6 for each profile it finds: it reports
the clone, each profile's installed version and any old install, prints the numbered plan with the
reason for each step, and asks about each one (Enter accepts the recommendation; `--yes` accepts all
of them, `--dry-run` changes nothing; `--version <tag|main>` installs that release instead of the latest,
`--profile <dir>` adds a profile, and `HEFESTO_CLONE_DIR` puts the clone somewhere other than
`~/.claude-framework`). It never deletes files or uses `sudo` (the one removal: with your yes, it
uninstalls the old `ai-development-framework` plugin); a file it replaces is backed
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

Every plugin component is **namespaced by the plugin's name**: Claude Code turns `commands/<file>.md` into
`/<plugin>:<file>` and offers no alias without the prefix
([plugins reference](https://code.claude.com/docs/en/plugins/components.md)). So every command in these docs is
written the way you type it, `/hefesto:hef.<name>`; typing `/hefesto:` in the prompt lists them all.

| Component | How you invoke it |
|---|---|
| **Commands** | `/hefesto:hef.context`, `/hefesto:hef.plan`, `/hefesto:hef.quality` — always with the `hefesto:` prefix. Without the `hefesto:` prefix the name does not resolve. |
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
      // ← your REAL home dir, this profile, the installed version
      "Bash(/home/you/.claude/plugins/cache/hefesto/hefesto/X.Y.Z//hooks/speckit-helper.sh:*)",
      "Bash(/home/you/.claude/plugins/cache/hefesto/hefesto/X.Y.Z/hooks/speckit-helper.sh:*)"
    ]
  }
}
```

> ⚠️ The `speckit-helper.sh` permission avoids a prompt on every hef command. The commands run the helper with the Bash tool; they cannot pre-execute it in a `` !`…` `` block, because a `!` block is permission-checked *before* `${CLAUDE_PLUGIN_ROOT}` is substituted and is rejected outright as `Contains expansion`.
>
> **The rule names the profile's plugin cache, not the clone.** `${CLAUDE_PLUGIN_ROOT}` is the copy the session loaded, `<profile>/plugins/cache/hefesto/hefesto/<version>/` (`jq -r '.plugins["hefesto@hefesto"][].installPath' <profile>/plugins/installed_plugins.json` prints it), so the path changes with every release: re-write the rule after each update. In a project, `hooks/hefesto-setup.sh` (§7, step 8b) writes these rules for the clone and every profile's installed copy, and drops those of versions no longer installed — run it again after each update instead.
>
> **The rule must mirror the command byte for byte. The matcher does no expansion and no normalisation.** Tested against the live matcher:
>
> | Rule | Result |
> |---|---|
> | `Bash(/home/you/…/hefesto/X.Y.Z//hooks/speckit-helper.sh:*)` | ✅ matches |
> | same, but one slash before `hooks` | ❌ blocked |
> | `Bash($HOME/…)` | ❌ blocked — **`$HOME` is not expanded** |
> | `Bash(~/…)` | ❌ blocked — **`~` is not expanded** |
> | leading wildcard | ❌ blocked |
>
> **Write your home directory out literally** (`echo $HOME`). The doubled slash is not a typo and is the entry that works: `${CLAUDE_PLUGIN_ROOT}` expands *with* a trailing slash, so the helper reaches the matcher as `…/X.Y.Z//hooks/…`. The single-slash entry is a hedge against a future release dropping that slash; it matches nothing today. Keep both.
>
> **This is the single most common failure.** Without the rule, every helper call shows a permission prompt; a prompt you deny stops the command. If a hef command asks on every call, or stops at its first step, this rule is the first thing to check.
>
> The same applies to the other helpers the commands call — `status-board.sh` (`/hefesto:hef.status`), `ledger.sh` and `session-launch.sh` (`/hefesto:hef.orchestrate`), `pr-watch.sh` (`/hefesto:hef.babysit`), `arena-run.sh` (`--arena --via`, `--second-opinion`), `release.sh` (`/hefesto:hef.release`): they prompt on first use; allow them in the same form if you use those commands — never `ledger.sh` as a whole, and never `pr-watch.sh reply` or `comment`, which `hefesto-setup.sh` keeps in `ask`.

Export `GITHUB_TOKEN` if you want the bundled GitHub MCP server to connect.

**Optional tools** — auto-detected, silent when absent: `gitleaks` (the secrets gate), `lizard` (the
function complexity gate — the commit says when it was skipped), `shellcheck`, `rtk` (CLI output compression),
`graphify` (knowledge graph), `GITHUB_TOKEN` (the bundled GitHub MCP server), and on Linux `bubblewrap` + `socat`
for the OS sandbox below, the boundary the hooks cannot be.

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

#### Claude Code's temp directory on a RAM-backed `/tmp`

Claude Code keeps every session's scratch files, background-task output and the sandbox's `TMPDIR` under one
directory: `CLAUDE_CODE_TMPDIR`, else `/tmp/claude-<uid>`. Where `/tmp` is a tmpfs (RAM, often with a per-user
quota), a day of sessions and test runs can fill it, and from then on every command's output is lost (`EDQUOT`) and
commits fail. Point it at a disk directory instead, in your shell's startup file, then restart the sessions:

```bash
mkdir -p ~/.cache/claude-tmp && chmod 700 ~/.cache/claude-tmp
echo 'export CLAUDE_CODE_TMPDIR="$HOME/.cache/claude-tmp"' >> ~/.zshenv   # or ~/.bashrc / ~/.profile
```

Optional, on systemd: clear entries untouched for a week with a user tmpfiles rule,
`~/.config/user-tmpfiles.d/claude.conf` holding `d %h/.cache/claude-tmp 0700 - - 7d`, and
`systemctl --user enable --now systemd-tmpfiles-clean.timer`. `/hefesto:hef.doctor` warns when the temp directory sits on a
tmpfs over 80% full (`HEFESTO_TMP_WARN_PCT`).

### 3️⃣ Verify the Installation

```bash
cd ~/any-project && claude
```

Three checks, in increasing strength:

1. **`claude plugin list`** — the plugin is `✔ enabled`. If it is not here, nothing else matters.
2. **The `/` menu** — every command should be listed. **A component that does not appear is not loaded**, and its absence is silent. This is the only reliable test.
3. **Run one** — `/hefesto:hef.context` should print a tech-stack summary. If it asks permission for `speckit-helper.sh`, the rule in step 2 is missing or names another path (see the warning above); approve it, or the command stops there.

> ⚠️ `claude plugin details hefesto` prints a component inventory, but it reports **`Agents (0)`** for this plugin even though all seven agents load correctly. That is a quirk of the inventory display, not a fault in your install — confirmed by dispatching the agents in a live session. Do not chase it.

### 4️⃣ Your First Feature (the 60-second tour)

The framework's core loop is **spec first, then code, then a gate you cannot talk your way past.**

```bash
/hefesto:hef.init                    # once per project — bootstraps .specify/
/hefesto:hef.spec  add user login # → a spec: scenarios, requirements, success criteria
/hefesto:hef.plan                    # → an implementation plan (writes are blocked outside .specify/)
/hefesto:hef.review                  # → plan mode: a fresh code-reviewer gates the plan; APPROVE writes "## Reviewed"
/hefesto:hef.tasks                   # → a phased, dependency-ordered task list
/hefesto:hef.implement               # → TDD execution, red-green, one task at a time (tests may grow, not shrink)
/hefesto:hef.verify                  # → every FR mapped to the tests that cite it, then spec-compliance review
/hefesto:hef.quality                         # → lint, types, secrets, SOLID — before you commit
/hefesto:hef.review                          # → two-stage code review
/hefesto:hef.pr                              # → the pull request, with the evidence attached
```

For a **large** task list, swap the implementation step for the workflow, which runs independent tasks in parallel and has every task adversarially verified by agents that did not write it:

```
hefesto:workflow
```

Not every change deserves a spec. For a typo or a config tweak, `/hefesto:hef.fix` skips the pipeline. For an existing codebase with no specs, `/hefesto:hef.baseline` reverse-engineers them.

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

**In each project you set up** (§7, step 8b), run the setup again from the project's main folder — its rules name the installed version's folder — then restart that project's sessions:

```bash
bash ~/.claude-framework/hooks/hefesto-setup.sh            # add --lanes if the project runs four lanes
```

**Rolling a release out to a team** — the message to send, with `X.Y.Z` filled in:

```bash
# Hefesto X.Y.Z is out. Upgrade (about a minute):
git -C ~/.claude-framework pull --ff-only
claude plugin marketplace update hefesto
claude plugin update hefesto@hefesto                     # once per profile: CLAUDE_CONFIG_DIR=~/.claude-<profile> claude plugin update hefesto@hefesto
cp ~/.claude-framework/.claude/rules/*.md ~/.claude/rules/
diff ~/.claude-framework/.claude/CLAUDE.md ~/.claude/CLAUDE.md        # merge by hand if you customised it
# In each set-up project's main folder: bash ~/.claude-framework/hooks/hefesto-setup.sh (add --lanes if used)
# Restart Claude Code, then /hefesto:hef.doctor must report RUNNING_MATCHES_CLONE at X.Y.Z.
```

### 6️⃣ The two things the plugin cannot ship

`plugin.json` ships **skills, commands, agents, hooks, workflows, and the MCP server**. There is no plugin component for **`rules/`** or **`CLAUDE.md`** — so installing the plugin does *not* give you the framework's global rules (code quality, git workflow, the Iron Laws, security, context management). If you want those to apply everywhere, copy them into `~/.claude/` yourself:

```bash
mkdir -p ~/.claude/rules && cp ~/.claude-framework/.claude/rules/*.md ~/.claude/rules/
# keep your own CLAUDE.md, as the wizard does: move it aside and import it from hefesto's
[ -e ~/.claude/CLAUDE.md ] && mv ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.mine
cp ~/.claude-framework/.claude/CLAUDE.md ~/.claude/CLAUDE.md
[ -e ~/.claude/CLAUDE.md.mine ] && printf '\n@CLAUDE.md.mine\n' >> ~/.claude/CLAUDE.md
```

(On a re-copy, skip the `mv` when `~/.claude/CLAUDE.md` is a previous hefesto copy, or your `.mine` is overwritten.)

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

`/hefesto:hef.orchestrate` dispatches **one** board item at a time to a fresh headless worker and then a
separate verifier, through a ledger outside every sandbox: `~/.cache/hefesto/ledger/<key>/<id>.json`, one
folder per board (`<key>` is a hash of the board repository's git common dir; `hooks/ledger.sh dir` prints it).
The design and the evidence behind it are `reports/17-multi-agent-session-orchestration.md`.
For the short path — install, one lane or four, a new or a running project — see [`quickstart.md`](quickstart.md).

1. **Declare the board** in `.claude/project-status.json` (the same file `/hefesto:hef.status` reads;
   `source: tasks-repo` or `github-project` (step 14) is dispatchable) and add the `orchestrate` block:
   `{"tiers": {"implement": "opus", "verify": "fable"}}` — tiers, never model ids; the reviewer tier must
   rank at or above the author's. Spend caps (`usd_cap`, `daily_usd_cap`) are optional; none by default.
2. **Protect `main`**: require a pull request before merging (0 approvals is enough on a solo repo,
   include administrators). No launched session can then push `main`, whatever its prompt says.
   Merge with **merge commits**, not squash or rebase: the `human:merge` gate is cleared by
   `git merge-base --is-ancestor <branch> main`, which a squash- or rebase-merged branch never satisfies.
3. **Set the project up once, then open the orchestrator pane normally**, in the main checkout, on the
   always-on host that holds GitHub access and nothing else: run `bash ~/.claude-framework/hooks/hefesto-setup.sh`
   in a terminal (step 8b), then `claude --name <repo>-orchestrator`, sandbox on. The launcher spawns `claude -p`,
   which a sandboxed shell cannot; setup lists it (with `ledger.sh`, `pr-watch.sh`, `status-board.sh` and `gh`)
   in `sandbox.excludedCommands`, so those run outside the sandbox while the pane keeps its own. Call them as
   the commands write them — a bare command, no `cd`, redirect or `$(…)` — or they stay sandboxed and
   `session-launch.sh` refuses. The workers it starts are sandboxed by the settings it passes them.
4. **Dry-run first**: `/hefesto:hef.orchestrate --stage build --dry-run` prints the exact `claude -p` line for the next
   item and claims nothing. Then `/hefesto:hef.orchestrate` for real: one item, a PR, verdicts in the ledger,
   the entry blocked on `human:merge`.
5. **Watch for blocks**: every session opened in the checkout prints `ledger: <id> blocked_on <kind>`
   at start; `herdr agent wait --until blocked` and `claude agents --json` show the pane. A `human:*`
   block is cleared only by the artifact the human command leaves behind (`/hefesto:hef.clarify`,
   `/hefesto:hef.review`, the merge itself — the branch in the integration branch or, once GitHub deletes it,
   the PR's merge commit there), or — for `human:intake` only — by a person who read the item
   text (`status-board.sh --item <id>`) running
   `hooks/ledger.sh unblock <id> --reviewed-by-human --by <name>`. That clear works from any session,
   and the name and time are recorded on the entry (`.reviewed`). The gate is Claude Code's
   **permission prompt**: never add `--reviewed-by-human` (or a blanket `ledger.sh` rule) to any
   allowlist, so every intake clear is a dialog you answer. Keep the pane in **`default` permission
   mode**: under `dontAsk` every person-only clear is refused; under `auto` and `bypassPermissions`
   hefesto's `ask` rules still show their dialog, but a command no rule matches runs without one (the
   session-start hook says so in every lane, and warns when an intake or a `human:merge` block is open). Never answer "Yes, don't ask again" on a
   `ledger.sh` call in the orchestrator pane either: the saved prefix rule would admit the clear
   silently. The command is refused inside a launched worker. Nothing replaces an intake block, and nothing claims
   an intake-blocked entry: the named clear is the only way out. A worker cannot replace any other
   person's block either.
6. **After you merge**: with a deploy stage running (`/hefesto:hef.orchestrate --stage deploy`), its next pass on
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
   branch, `/hefesto:hef.babysit` (or `/loop 25m /hefesto:hef.babysit <n> --once` while a review is pending). It
   waits on CI inside one helper call — that Bash call runs with the tool timeout raised to
   600 000 ms — fixes a red check inside the PR's own diff, answers pertinent review comments with
   the commit hash, asks you about doubtful ones, and stops at mergeable with the ledger blocked
   on `human:merge`. Under the sandbox, `gh` needs `api.github.com` granted; the push uses the
   remote's transport (ssh on most checkouts), so when the sandbox refuses it the command prints
   the exact `git push origin <branch>` line for you to run with the `!` prefix and ends the
   pass. It never merges, approves, force-pushes, or edits CI configuration — a fix that would
   need any of those becomes a question for you.
8. **Running the by-stage layout** ([Pane layouts](#pane-layouts), below): `/hefesto:hef.orchestrate --stage plan` plans the next
   queued item in a fresh session that writes only under `.specify/`; `--stage build` builds it;
   `--stage deploy` runs one babysitter pass on the next PR; `--stage all` runs the three in a row in this
   session, a catch-up. With no `--stage` it is the orchestrator pass. Two settings matter: every role's
   allowlist gets the plugin's own hooks directory appended automatically, so put the **project's
   test command** in `orchestrate.allowed_tools.<role>` (this repository: `Bash(bash tests/smoke.sh*)`
   and `Bash(node --test*)` for `implement` and `verify`) without fear of losing the helpers — but the
   configured list *replaces* the role's default list (only the hooks rule is appended), so copy the
   defaults from `session-launch.sh` and add the test command to them; and every launch is one Bash
   call that can block for many minutes (a deploy pass waits on CI inside the babysitter), so the
   command makes it with the tool timeout raised to 600 000 ms. `orchestrate.panes` maps block
   kinds to your pane names; the session-start line then says whose block it is.
   With a plan lane and a build lane open (the four-lane setup in [`quickstart.md`](quickstart.md); each
   waits for the orchestrator's doorbell), set `orchestrate.plan_first: true`: the build stage then takes
   only planned items (phase `tasks`, or an `implement` retry), never a queued one — except a queued 🐞
   incident fix, which is built without a plan — so a new item cannot be built before it is planned.
   Without it, build also takes queued items, as before.
   Other `orchestrate` keys: `max_builders` (default 1, at most 8) builders at once per repository, beside
   one planner and one deployer (the verifier does not count); `max_fixes` (default 3) the babysitter's fix
   budget per PR; `merge_by` — `person` (the default: you merge on GitHub) or `lane` (the orchestrator drafts a
   merge action for the deploy lane, approved by you as a form); `merge.checks`, the commands a lane merge runs
   first (`{repo_path}` and `{base}` placeholders); `deploy.recipes.<env>` and `deploy.trains.<name>`, the
   deploy and release-train scopes a request is built from (8c).

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
     the project), `pr-watch.sh` and `status-board.sh` (they call the GitHub API) and `gh` (so a merge is decided by
     the permission rules, never by the sandbox). Only gh's read
     forms and `gh pr create` are allowed; `gh pr merge`, `gh pr review` and `gh api` need an approved action
     (with `--lanes`) or your dialog (a single lane);
   - `Edit` denied on hefesto's own state (`~/.cache/hefesto/{ledger,approvals,sessions}`);
   - the sandbox on (`enabled`, `failIfUnavailable`), and sandboxed commands running without a dialog
     (`--strict` keeps 8.0's every-command-asks);
   - the trusted project folder, the context gauge;
   - with `--lanes`: `crossSessionInbound: "accept"`, `HEFESTO_LANES` and the lane map (`HEFESTO_LANE_MAP`, from
     `orchestrate.lanes`, `orchestrate.lane_prefix` or the folder name).

   Its other flags: `--check` (read-only: `setup: ok`, or what is missing; exit 1), `--print` (show the merged file,
   write nothing), `--remove` (take out every entry it wrote, for any version), `--keep-statusline` (never touch
   `statusLine`), `--strict`, and the command lists below (`--allow-command`, `--unsandboxed-command`,
   `--forget-commands`). Run it again after every hefesto update: its rules name each installed version's folder.

   Lanes open with `claude --name <a name in the map>`; the name is the lane, and a session whose name is not in the
   map is no lane. In the orchestrator, `/hefesto:hef.orchestrate` asks every decision as a form and rings the stage lanes;
   `/hefesto:hef.ship` starts new work. `context.compact_at` sets each lane's compaction nudge.
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
     gate, the commit gate's linters) stand down in a `--lanes` project, and in a launched worker's session
     (`HEFESTO_WORKER`, pinned in the worker's `--settings`). A hook runs outside the sandbox, so those would be a
     way out of it.
   - **The lanes' build cache** (#162). The sandbox makes `~/.cache/go-build`, the npm cache and the like read-only,
     so a lane builds through `hooks/lane-build.sh <command>`, which points those caches at
     `~/.cache/hefesto/lane-cache/<repo key>/` (in the sandbox's `allowWrite`) for that one command:
     - it refuses unless it runs inside the sandbox: a write into `~/.cache/hefesto/lane-cache-probe/`, never in
       `allowWrite`, must fail;
     - setup never sets a cache variable in the settings `env`, because that reaches hooks and approved unsandboxed
       actions too, and an unsandboxed build would link what a sandboxed lane planted;
     - nothing that runs outside the sandbox may name the wrapper or the cache: lane-guard denies it, `request` and
       `--unsandboxed-command` refuse it, and no allow rule names the wrapper (under `--strict` every wrapper call
       asks);
     - launched workers keep their own cache (#126): they run in linked worktrees, which carry no
       `.claude/settings.local.json`, so they have neither `HEFESTO_LANE_CACHE` nor the lane cache in `allowWrite`.
       `--remove` leaves the folder and says where it is.
   - **In auto mode** a command no rule matches is the classifier's call, with no dialog; every lane says so at start.
   - **In a `--lanes` project, a `gh` command that writes to GitHub runs only as an approved action.** lane-guard
     denies `gh pr merge`, `gh api`, `gh release create` and every other form that is not a read (`gh pr view`, `list`,
     `checks`, `diff`, `gh run view`, …) or `gh pr create`, in every permission mode. In auto mode a command no rule
     matches is otherwise the classifier's call.
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
   with the `/hefesto:hef.*` commands in its own conversation. `--finish --lane <name> --outcome-file <f>` checks its outcome
   against the role's schema and records it exactly as a background run's ($0, `note: in-lane`). An interactive build
   verifies through `/hefesto:hef.verify` and `/hefesto:hef.review`, whose reviewers run in a fresh context; their verdicts are
   recorded as `<lane>:code-reviewer`. That name is the lane's claim, not proof: keep `"build": "worker"` when you
   want the separate verifier session. On an external board the lanes work in the code repos' worktrees, which
   `setup --lanes` grants as `additionalDirectories`.

   **The ledger moved.** Hefesto 9 keeps it in `~/.cache/hefesto/ledger/<key>`. The first `ledger.sh` call that can
   write there moves an 8.x ledger itself:
   - once, under a lock, only while no 8.x run renews a lease;
   - it leaves `.git/hefesto/MOVED` and keeps the old folder, renamed.

   A sandboxed session without setup cannot write there: run `hefesto-setup.sh` before the first `/hefesto:hef.orchestrate`
   or `/hefesto:hef.ship`. `run-follow.sh` shows nothing for runs started before the upgrade.

9. **Hand-run items, the board and escalation** (all optional): a person who ran an item by hand runs
   `hooks/ledger.sh handoff <id> --pr <url>` on its branch — one call instead of four. Set
   `orchestrate.publish: true` and every orchestrator pass writes the item's state as the first token
   of its board heading (⏸ waits on a person, ⛔ blocked otherwise, 📐 planning, 🔨 building, 🔀 PR, ✅
   merged); add those glyphs to the board's `states` map so `/hefesto:hef.status` labels them, and override
   them with `orchestrate.publish_markers`. Set `orchestrate.escalate_after_hours: <n>` and a `human:*`
   block older than `<n>` hours is sent once, as one line, to the session that owns it
   (`orchestrate.pane_sessions.<pane>`, default `<name>-<pane>`, where `<name>` is `name` in the config,
   else the board's folder name). That receiving pane must accept
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
    report that gate, and a missing or SKIPPED one blocks the entry on `verdict`. `/hefesto:hef.status` reads
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

    They are used in two places only: `/hefesto:hef.plan --arena K --via <p,…>` gives up to K−1 arena slots
    to providers (one `truth-scout` is always kept), and `/hefesto:hef.review --second-opinion <p>` relays
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
      - workers open PRs against it (`gh pr create --base dev`), and so does `/hefesto:hef.pr` when you name
        no base;
      - the verifier's diff base, `pr-files` and `deps-diff` compare against it, using the newer of
        the merge-bases with `origin/dev` and the local `dev`;
      - the merge-tree probe bases on it;
      - `ledger.sh unblock` clears `human:merge` once the branch is in `dev` or `origin/dev`.
    - **Protected set:** `main`, `master`, the integration branch, every environment and your
      `protected` globs. These are never a worker's head and never pushed: `ledger.sh handoff`
      refuses them, and `pr-watch.sh resolve` marks a promotion PR (`stg → main`) `"push": false`, so
      `/hefesto:hef.babysit` reports its red checks without ever fixing them.
    - **Environments, in order:** the last is the **final** branch.
      - `ledger.sh where <id>` shows how far a merged branch has travelled (`yes`, `no`, or `unknown`
        when that branch exists neither locally nor on `origin`; `yes (deployed <sha12>)` when a
        recorded deployment is still in that environment).
      - `ledger.sh advance <id> released` waits for the final branch.
      - `ledger.sh deployed <id> --env <env> --commit <sha>` records what a deployment actually
        shipped (hefesto 9.1). The commit must be in `<env>` or `origin/<env>`. Recording the final
        environment on a `merged` item advances it to `released`, so a release built from cherry-picked
        commits, where the item's branch is not an ancestor of the final branch, is still released.
      - `/hefesto:hef.release` tags the final branch's commit.

    A config file that is not valid JSON is an error, never "unconfigured". Without a `branches`
    block, PRs keep the repository's default branch as their base. Every promotion is still a
    person's merge. The remote is assumed to be named `origin`, and
    `where` and the `released` check assume merge commits: a squash promotion defeats the ancestry
    test (`deployed` is the way around it: the recorded commit is checked, not the item's branch).
    On an external board (step 13), the block can live on the board instead.
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
      branch model and `/hefesto:hef.status` report it as before). Every `repos` path must exist on this
      machine, or every call refuses naming it. Only a `source: tasks-repo` board can be external:
      routing (`--item-repo`) reads item bodies, which a `github-project` board does not have here.
    - **A branch model on the board** (hefesto 9.1). A `repos` value can be an object instead of a
      path, so a code repo with no `.claude/project-status.json` of its own still gets a branch model:

      ```json
      { "repos": { "ops": { "path": "../api_service",
                            "branches": { "integration": "dev", "environments": ["dev", "stg", "main"] } },
                   "ui": "../web_app" } }
      ```

      The repo's own `branches` block, when present, wins; then the board's; then trunk on `main`.
      `hooks/ledger.sh branches --repo ops` prints the effective model and its `source` (`repo file`,
      `board` or `default`), and `branches --configured` answers 0 for a board block exactly as for a
      repo-file one. An object without `path`, a key other than `path` and `branches`, or an invalid
      `branches` block is refused, naming the repo and the board config; nothing falls back to trunk
      silently. A plain string value works as before.
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
      `status-board.sh --item-repo <id>` prints `<name>` TAB `<path>`; `/hefesto:hef.orchestrate` reports a
      refusal and skips the item, writing nothing.
    - **One central ledger** for the board (`~/.cache/hefesto/ledger/<key>/`, keyed by the board repo's git
      common dir; `ledger.sh dir` prints it). Each entry records `repo`, so `list`, `metrics` and escalation
      see every repo, and `claim` keeps **one planner, `max_builders` builders and one deployer per
      repository** (an `ops` builder and a `ui` builder run side by side; the verifier is exempt). A repo you
      switch to external starts from the central ledger; its old entries stay in its own ledger folder. `daily_usd_cap` sums today's spend across every repo the board feeds.
    - **Where sessions run.** The planner, the worker, the verifier and the babysitter run in the
      entry's repo (`<repo>/.claude/worktrees/<id>`); start the launcher from the board repo or any
      code repo it feeds. `ledger.sh handoff` records the repo you run it in, and `unblock`,
      `where` and `advance … released` check git in the entry's repo.
    - **Publish** marks the item in the board repo's file. Commit it yourself; committing
      automatically is board item HEF-16.
14. **A GitHub Project as the lane board** (optional, hefesto 9.2). The lanes can run from a GitHub Project (v2)
    instead of a `tasks/` folder. Each item is an issue of one repo on the Project, and its Status is the column:

    ```json
    { "source": "github-project", "owner": "acme", "project": 7, "repo": "acme/app", "id_prefix": "BC",
      "columns": { "todo": "Todo", "doing": "In Progress", "review": "In Review", "done": "Done", "backlog": "Backlog" },
      "status_field": "Status", "kinds_labels": { "bug": "incident", "security": "vulnerability" },
      "orchestrate": { "rfc_dir": "docs/rfcs", "publish": true } }
    ```

    - **Ids** are `<id_prefix>-<issue number>` (issue #42 is `BC-42`). Only `repo`'s issues are items. Draft
      items, pull requests and other repos' issues on the same Project are ignored. One repo per board, and the
      board is in-repo only.
    - **Columns** map the keys hefesto uses to the Project's Status options. A name the Project does not have is
      refused, with the options it has, so a typo never reads as an empty column. `review` is optional: without
      it, an item with an open PR stays in `doing`.
    - **The RFC** is still a file in the repo, linked from the issue body by an `rfc: docs/rfcs/<ID>.md` line.
      `/hefesto:hef.ship` writes that line.
    - **Kinds** come from labels (`kinds_labels`; by default `bug` and `incident` → incident, `security` →
      vulnerability).
    - **Author trust.** An issue opened by an account that is not an owner, member or collaborator of the repo,
      or last edited by someone other than its author who is not a collaborator, is registered already blocked
      `human:intake`. You read it before any stage takes it. Widen the set with
      `orchestrate.trusted_associations` (for example adding `CONTRIBUTOR`); `NONE` is never accepted.
    - **Card moves.** With `orchestrate.publish`, each state change sets the card's Status (plan and build →
      `doing`, PR → `review`, merged → `done`) and posts one short comment on the issue. An issue waiting on
      your intake read is left alone.
    - **Scopes.** Reads need gh's `read:project` scope; `/hefesto:hef.ship`'s add and publish need `project`
      (`gh auth refresh -s project`). `status-board.sh --check` says which is missing.
    - **Every gh failure refuses** with its cause; nothing reads an error as "no items".

15. **Several apps in one repository** (optional, hefesto 9.3, #172). A monorepo can keep a `.specify/` per app
    (`backend/.specify/`, `apps/web/.specify/`), each with its own constitution and specs, under one board.
    - **Discovery.** Every spec command and guard uses the nearest folder holding `.specify/`, the way git finds
      `.git`, and never looks above the repository top. Run the commands from the app's folder, or any folder
      under it. `/hefesto:hef.init` in an app folder creates that app's `.specify/`. A single-app repository behaves as
      before, and a subfolder of it now uses the top `.specify/` instead of creating a stray one.
    - **Declare the apps** in the code repository's own `.claude/project-status.json`:
      `"spec_roots": {"backend": "backend", "web": "apps/web"}`. A name is lower case (`a-z`, `0-9`, `-`); a
      folder is a plain path from the repository top (no `.`, `..` or `.claude`). On an external board the code
      repository declares them, not the board.
    - **Each item has one owning app.** It names the app with an `app: backend` line in its body
      (`/hefesto:hef.ship` asks and writes it). An item without the line gets one form in the orchestrator ("Which app
      owns it?", or the repository root). The launcher refuses to plan an undecided item, and refuses an app
      folder with no `.specify/` or one that is a link out of the repository. An item planned before the apps
      were declared keeps the app its spec folder names.
    - **Where the work runs.** Background sessions start in `<worktree>/<app folder>`. An interactive lane's
      `--prepare` prints an extra `app:` line, and the lane works from that folder. The planner may write only that
      app's `.specify/` (an interactive plan lane is held to any `.specify/` by the plan write-block, as before).
      A file in another app is allowed; the plan and the tasks name it, so the review sees the reach.
    - **The constitution is inherited.** A top `.specify/memory/constitution.md` applies under every app's own,
      as `CLAUDE.md` files nest; `speckit-helper.sh constitution` prints both, the top one marked inherited.
    - **Checks.** Tests, lint and types run in the app folder with that app's commands. Secrets, `.github/`
      workflows and a root `Makefile` are checked once from the top. `req-coverage` and `spec-cite-probe` read the
      owning app's specs (requirement ids repeat across apps).
    - **The ledger** stores `spec_dir` relative to the item's worktree. Entries written by 9.2 keep their absolute
      path. `ledger.sh spec-roots <id>` and `ledger.sh list --undecided-app` show what the app form asks.
    - **The board's epics** (`epics.specs`) list each app's features as `<app>/<feature>`. On an external board
      they stay the board's own, as before.

Spend: open by default — neither cap is set unless you add it, and each is opt-in on its own.
`orchestrate.usd_cap` becomes `--max-budget-usd` on each session (no key → no flag). With
`daily_usd_cap` set, the launcher refuses when today's total across the ledger plus the next session's
cap would exceed it; with `daily_usd_cap` but no `usd_cap`, it refuses once today's total has reached
the daily cap. Cost per merged PR comes from the `runs[]` on each entry.

**Two hosts, if you run the by-stage layout** ([Pane layouts](#pane-layouts), below): the `deploy` pane splits along the
trust boundary in `docs/architecture.md` — CI, the PR and the babysitter on the always-on
workstation that holds GitHub access only; environment transitions and the production release on
the laptop that holds the credentials. The ledger is per machine (`~/.cache/hefesto/`), so the laptop's
`hooks/ledger.sh list --phase merged` does not see the workstation's entries: board write-back (HEF-4, opt-in
`orchestrate.publish: true`) and the pull requests themselves are what make that queue visible across both
machines without a message.

#### Pane layouts

The way the harness is meant to be run once a project is live: **one long-lived pane per
responsibility, short-lived workers for the code**, and one shared truth nobody has to repeat to
anybody. The evidence for that shape — and against a mesh of sessions that talk to each other — is
[`reports/17-multi-agent-session-orchestration.md`](../reports/17-multi-agent-session-orchestration.md).

| Pane (start it with `claude --name <repo>-<role>`) | Responsibility | Runs | Owns |
|---|---|---|---|
| 📋 `<repo>-project` | the board and the documents: intake, specs, tasks, status | `/hefesto:hef.status`, `/hefesto:hef.brainstorm` → `/hefesto:hef.spec` → `/hefesto:hef.clarify` → `/hefesto:hef.plan` → `/hefesto:hef.review` → `/hefesto:hef.tasks`, `/hefesto:hef.adr`, and `/hefesto:hef.orchestrate` to dispatch workers | `tasks/`, `.specify/`, `docs/`, the ledger |
| ✨ `<repo>-feature` | one feature at a time, by hand, in its own worktree | `/hefesto:hef.implement` or `hefesto:workflow`, `/hefesto:hef.verify`, `/hefesto:hef.quality`, `/hefesto:hef.review`, `/hefesto:hef.pr` | one branch |
| 🔧 `<repo>-chore` | general tasks, fixes, merges, releases | `/hefesto:hef.fix`, `/hefesto:hef.doctor`, `/hefesto:hef.release`; the merges themselves | `main` |
| 🤖 workers (headless, launched by `/hefesto:hef.orchestrate`) | one board item each, then they exit | the size-routed pipeline, then a separate read-only verifier | one worktree under `.claude/worktrees/<id>` |

That is the layout **by object** — the documents, one feature, `main` — a convention for panes you run by
hand, **not the lanes layout**: no hefesto code knows these names, and `hefesto-setup.sh --lanes` maps only
the four stage lanes below. The same spine also runs
**by stage**, the layout of Galbiati's deck (`reports/18-…`, addendum A2): one pane per stage,
each launching headless sessions for its stage's work and holding that stage's human gates.
A repository that integrates on a branch other than `main` (say `dev → stg → main`) declares it
under `branches` in `.claude/project-status.json` — PR base, verifier diff base, merge check,
protected heads and the promotion chain all follow (step 12 above).
Each long-lived pane has a `/compact` prompt shaped to what it owns — orchestrator, planner, builder,
deployer — in [Performance → Compact prompts per pane](performance.md#-compact-prompts-per-pane).
Set a project up once with `hooks/hefesto-setup.sh` (`--lanes` for four), then open each lane with plain
`claude --name <repo>-<lane>` — any wrapper that passes claude's arguments on works. `/hefesto:hef.ship "<idea>"` in
the orchestrator takes work to a PR; every decision is a form there, and the orchestrator rings the stage
lanes (or, in a single lane, runs the stages itself) — the [quick start](quickstart.md) has both flows.
A board kept in its own repository can feed several code repos — a `board` pointer in each, a
`repos` map in the board, one central ledger, and per repo one planner, `orchestrate.max_builders` builders
(default 1) and one deployer at a time (step 13 above).

| Pane | Owns (ledger phases) | Human gates | Launches / runs |
|---|---|---|---|
| 🎛 `<repo>-orchestrator` | the board's state, `queued` → claim | every `human:*` gate — intake, clarify, plan review, plan approval, merge | `/hefesto:hef.ship` (new work), `/hefesto:hef.orchestrate` (asks each decision as a form and runs its command, then rings each stage lane — or runs the stage itself when no lane is open), `/hefesto:hef.status` ([quick start](quickstart.md)) |
| 📐 `<repo>-plan` | `intake` → `spec` → `plan` → `plan-review` → `tasks` | — (its questions go to the orchestrator) | `/hefesto:hef.orchestrate --stage plan` (a fresh planner: spec from the item's RFC → plan → fresh-context review → tasks, writes only under `.specify/`; with `plan_review: "human"` it then waits on `human:plan-approval`), or by hand `/hefesto:hef.brainstorm` → `/hefesto:hef.spec` → `/hefesto:hef.clarify` → `/hefesto:hef.plan` → `/hefesto:hef.review` → `/hefesto:hef.tasks` |
| 🔨 `<repo>-build` | `implement` → `verify` → `quality` → `security` → `pr` | `verdict`, `stall`, `budget`, `conflict` | `/hefesto:hef.orchestrate --stage build` (the implement worker — continuing from the planner's tasks when there are any — then the separate verifier) |
| 🚀 `<repo>-deploy` | `pr` → `merged` → `released` | `ci`, tag/deploy | `/hefesto:hef.orchestrate --stage deploy` (one headless `/hefesto:hef.babysit --once` pass on the next PR), or by hand `/hefesto:hef.babysit` (`/loop 25m /hefesto:hef.babysit <n> --once` while a review is pending); `/hefesto:hef.release`; the merge itself, by a person |

Choose by object when one person runs the repository and a feature should stay in one pane end to
end; by stage when more than one person attends, when the panes sit on different hosts (CI and the
PR on the workstation, the production release on the laptop), or when each stage should own its own
clarifications. Either way a pane never does a stage's work in its own context: it launches a fresh
session per item, or does the human step by hand, then runs its own `/compact` prompt before the
next item ([Performance → Compact prompts per pane](performance.md#-compact-prompts-per-pane)).
The ledger does not know which layout is in use.

**The shared truth is three things, none of them a conversation:** the board (`tasks/` or the
GitHub Project), the ledger (`~/.cache/hefesto/ledger/<key>/<id>.json` — one folder per board, outside
every sandbox, never committed; `hooks/ledger.sh dir` prints it), and the pull requests. Every pane opened in the checkout is told at start which entries
are blocked, on what, and whose they are (`ledger: HEF-7 blocked_on human:merge … → orchestrator pane`), so
nothing has to be announced; `orchestrate.panes` in `.claude/project-status.json` renames the panes.

**A message is a pointer, never a payload.** Panes can message each other (Claude Code's
cross-session messaging; `claude agents --json` lists them by the name you gave). Keep it to one
line — an id, a phase, a path: `ledger HEF-7 pr https://…/pull/7 — merge?` — never a diff, a review
or a transcript. Each inbound message costs the receiver a full-context turn, and the ledger already
holds everything the line points at.

**Aligning a release across the panes** is a sequence the ledger makes visible, not a meeting:

1. `project` dispatches or a person in `feature` claims an item (`hooks/ledger.sh claim HEF-7
   --session <repo>-feature --role implement`) — the orchestrator then leaves it alone.
2. The PR lands the item in `pr`, blocked on `human:merge`. That block is the release queue.
3. `chore` merges (a person, with a merge commit), then `git pull --ff-only`,
   `hooks/ledger.sh unblock HEF-7`, `hooks/ledger.sh advance HEF-7 merged`, and removes the worktree.
4. When `hooks/ledger.sh list --phase merged` is the release, `chore` runs `/hefesto:hef.release X.Y.Z`,
   tags, and sends `project` one line: `release X.Y.Z tagged — HEF-7 HEF-8`.
5. `project` moves the items to `DONE.md`; `/hefesto:hef.status` shows the quarter delivered.

A hand-run item in `feature` reaches the same release queue in one call from its branch:
`hooks/ledger.sh handoff <id> --pr <url>` (step 9 above). Two rules keep the panes honest: every person-only
command runs in the orchestrator behind its permission dialog (`hefesto-setup.sh` keeps them in `ask`; a sandboxed
command runs without a dialog, and `--strict` makes every unlisted command ask too); and no pane ever merges, approves
or pushes `main` for a worker — branch protection on `main` is the backstop, not the prompt.
