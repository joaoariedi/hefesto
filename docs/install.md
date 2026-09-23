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

**The clone is shared; only the enablement is per profile.** Because the marketplace source is a *directory* read in place, every profile runs the same working tree — so a single `git pull` updates all of them and you never keep a second copy. What each profile needs is its own one-time `marketplace add` + `install`.

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

One pull covers **every** profile, since they all read this same clone. Only `claude plugin marketplace update` is per profile, and only for profiles you actually run.

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

