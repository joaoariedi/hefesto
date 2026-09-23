---
model: sonnet
description: "Framework self-check: the running copy against the clone and upstream, the rules against upstream, the hooks linted, the manifest valid, and (opt-in) the plugin's own prompts scored"
argument-hint: "[--eval]  (opt-in: run the plugin eval suite; spends tokens)"
---

# Doctor

Everything that can go wrong with the framework *itself*, in one report. This command **reports
only** — it proposes remediation commands but never runs them without the user's say-so.

## 1. The four copies

Four copies of this framework exist on a machine, and a change to one is inert in the others
until deliberately propagated:

1. **Upstream** — `origin/main` of the framework repository (source of truth).
2. **Installed clone** — the directory the marketplace record points at (`~/.claude-framework`
   by convention). It is where installs are *copied from*, not what runs.
3. **Running copy** — `$CLAUDE_CONFIG_DIR/plugins/cache/hefesto/hefesto/<version>/`, one per
   profile. `plugin install` and `plugin update` copy the clone here; the hooks, commands, skills,
   and agents a session loads come from *here*. It is a plain copy, not a git clone — this
   command itself is running from it.
4. **Global rules** — `~/.claude/rules/*.md` (often stow-symlinked from a dotfiles repo). These
   are NOT plugin payload; they are hand-synced and drift silently.

> The commands below must be run with the Bash tool; they cannot be pre-executed in a
> `!` block. A `!` block is permission-checked before the CLAUDE_PLUGIN_ROOT variable is
> substituted, so it is rejected as "Contains expansion".

### Running copy vs clone vs upstream
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh doctor-copies`

It prints the profile, the running copy's version and commit (from that profile's plugin
registry), the clone's version, commit, distance behind `origin/main`, and local modifications,
and one `status:` line: `RUNNING_MATCHES_CLONE`, `RUNNING_BEHIND_CLONE`,
`RUNNING_BEHIND_CLONE_SAME_VERSION`, or `UNMEASURABLE` (the marketplace source is not a git
clone). Do not `git rev-parse` CLAUDE_PLUGIN_ROOT: it is the cache, and it is never a git clone.

### Global rules vs upstream
Compare each `~/.claude/rules/*.md` against the same file at `origin/main` — via
`git -C <clone> show origin/main:.claude/rules/<file>` (the clone path is in the `doctor-copies`
output) piped to `diff - ~/.claude/rules/<file>` (or `HEAD:` if the clone has no remote). Also list files present
on one side only, and report `readlink ~/.claude/rules` / `readlink ~/.claude/rules/<file>` so
the user can see whether stow manages them.

## 2. The hooks

Run with the Bash tool: `for f in "${CLAUDE_PLUGIN_ROOT}"/hooks/*.sh; do bash -n "$f" || echo "SYNTAX: $f"; done`

Then, only if `shellcheck` is on PATH: `shellcheck -S warning "${CLAUDE_PLUGIN_ROOT}"/hooks/*.sh`.
A hook that does not parse is a hook that silently never fires — the founding failure mode of this
plugin's test suite.

## 3. The manifest

Run with the Bash tool: `claude plugin validate "${CLAUDE_PLUGIN_ROOT}"`

## 4. Skill hygiene (report only)

Remind the user that the built-in `/skill-doctor` reports each skill's context cost and which
skills were never invoked — the input for deciding what to demote to `user-invocable: false`
(knowledge) or retire.

## 5. Evals — only with `--eval`

Run with the Bash tool: `claude plugin eval "${CLAUDE_PLUGIN_ROOT}" --trust-plugin --threshold 0.8`

Each case in `evals/` is scored with and without the plugin. This spends tokens and needs an
authenticated CLI, so it runs only when **$ARGUMENTS** contains `--eval`. A case that scores the
same with and without the plugin is a prompt that earns nothing — say so.

## Output Format

```
FRAMEWORK DOCTOR
================
Running copy:    [version @ sha] — [matches the clone | BEHIND the clone (update needed) | unmeasurable]
Installed clone: [path] — [in sync | N commits behind origin/main | locally modified | not a git clone]
Global rules:    [N/N identical | list of differing/missing files]
Stow-managed:    [yes → dotfiles target | no — plain files]
Hooks:           [all parse | SYNTAX: …] · shellcheck: [clean | N findings | not installed]
Manifest:        [valid | errors]
Evals:           [not run (pass --eval) | N/M cases ≥ 0.8 | ablation delta …]

Remediation (propose, do not run):
  [only the commands the findings actually call for]
```

## Remediation Rules

- Clone behind → propose `git -C <clone> pull --ff-only`, **then** the per-profile refresh below —
  a pull alone changes nothing a session sees.
- Running copy behind the clone → propose `claude plugin update hefesto@hefesto` for this profile
  (`CLAUDE_CONFIG_DIR=<profile>` when it is not the default), then a Claude Code restart. Same
  version on both sides means `plugin update` will report up to date: propose uninstall + install.
  Every other profile on the machine needs the same step; name the ones the user runs.
- Rules differ → propose copying the upstream version **into the dotfiles target** (follow the
  readlink), or the reverse if the local edit is the intended one — ask, don't guess.
- **Never `mv` onto a path under `~/.claude/`** — if the path is a stow symlink, `mv` replaces the
  symlink with a regular file and the dotfiles repo silently stops receiving updates. Use `cp`
  (which writes *through* the symlink) or edit the dotfiles file directly.
- Local modifications in the installed clone are a red flag: edits there are overwritten by the
  next pull. Propose moving them to the dev repo as a PR instead.
- A hook with a syntax error → the fix belongs upstream; propose the PR, not a local patch.
