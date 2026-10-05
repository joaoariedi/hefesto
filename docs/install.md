# Installing & Configuring

[← back to README](../README.md)

### 1️⃣ Install as a Plugin (recommended)

The framework is a Claude Code plugin. **The hooks ship with it** — you no longer hand-write `settings.json`, which is where every previous version leaked its most-reported friction.

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

Because the marketplace source is a **directory**, the plugin is read from your clone in place — nothing is copied. **Updating is therefore just `git pull`** (see *Updating* below), and the install path is stable and predictable, which the permission rule in step 2 depends on.

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

> ⚠️ The `speckit-helper.sh` permission avoids a prompt on every hef commands. The commands run the helper with the Bash tool; they cannot pre-execute it in a `` !`…` `` block, because a `!` block is permission-checked *before* `${CLAUDE_PLUGIN_ROOT}` is substituted and is rejected outright as `Contains expansion`.
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
> **This is the single most common failure.** A pre-flight command that is denied aborts the whole slash command **silently** — no error, no output, exit 0. If a hef commands appears to do nothing at all, this rule is the first thing to check.

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

> ⚠️ `claude plugin details hefesto` prints a component inventory, but it reports **`Agents (0)`** for this plugin even though all six agents load correctly. That is a quirk of the inventory display, not a fault in your install — confirmed by dispatching the agents in a live session. Do not chase it.

### 4️⃣ Your First Feature (the 60-second tour)

The framework's core loop is **spec first, then code, then a gate you cannot talk your way past.**

```bash
/hef.init                    # once per project — bootstraps .specify/
/hef.spec  add user login # → a spec: scenarios, requirements, success criteria
/hef.plan                    # → an implementation plan (writes are blocked outside .specify/)
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

The plugin is read from your clone in place, so updating is a `git pull`:

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
   `{"usd_cap": 5, "daily_usd_cap": 25, "tiers": {"implement": "opus", "verify": "fable"}}` — tiers,
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
   `/hef.review`, the merge itself), never by a flag.
6. **After you merge**: `git pull --ff-only`, then `hooks/ledger.sh unblock <id>` and
   `hooks/ledger.sh advance <id> merged`; remove the worktree with
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
   for `implement` and `deploy`) without fear of losing the helpers; and every launch is one Bash
   call that can block for many minutes (a deploy pass waits on CI inside the babysitter), so the
   command makes it with the tool timeout raised to 600 000 ms. `orchestrate.panes` maps block
   kinds to your pane names; the session-start line then says whose block it is.

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
    "providers": {
      "codex":  {"via": "codex"},
      "gemini": {"via": "gemini", "model": "<your gemini model>"},
      "bedrock_llama": {"via": "aws", "model": "<your Bedrock model id>", "region": "us-east-1", "max_tokens": 4096}
    }
    ```

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

Spend: `--max-budget-usd` caps each session; the launcher also refuses when today's total across
the ledger plus the next cap would exceed `daily_usd_cap`. Cost per merged PR comes from the
`runs[]` on each entry.

**Two hosts, if you run the by-stage layout** (README §5): the `deploy` pane splits along the
trust boundary in `docs/architecture.md` — CI, the PR and the babysitter on the always-on
workstation that holds GitHub access only; environment transitions and the production release on
the laptop that holds the credentials. The ledger is per checkout, so the laptop reads the release
queue with `git pull --ff-only` and `hooks/ledger.sh list --phase merged`; board write-back (HEF-4)
is what makes that queue visible across both machines without a message.
