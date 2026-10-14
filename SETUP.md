# SETUP — install, upgrade, fix or configure Hefesto, with Claude

**For the engineer.** Open Claude Code inside one of your git projects (not your home folder) and
type:

> Run `curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/SETUP.md` and follow it.

(Em português: *Rode `curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/SETUP.md` e siga as instruções.*)

Claude checks your machine, tells you what it found, and guides you one step at a time: installing,
upgrading, fixing a broken install, or setting up a project. Answer its questions and do what it
asks. You can type the same request again at any time; it picks up where things stand.

---

**For Claude: this file is your instructions for this conversation.** The engineer asked you to
follow it. If you read it through a tool that summarizes pages, run the `curl` line above first and
work from the exact text: the commands below must be copied exactly.

## How to work

- Speak the engineer's language (Portuguese if they write in Portuguese). Assume a junior engineer:
  one step at a time, exact commands to copy, plain words. Wait for their answer before moving on.
- Read-only checks need no permission. Before any change, say what it changes and ask.
- Some choices are the engineer's lead's, not the engineer's: the board's format, repository
  settings, spend limits, exceptions to the project's own rules. Collect them into one message for
  the lead (Step 4b) instead of asking the engineer to decide.
- Start at Step 1 every time this file is followed. The engineer restarts Claude Code partway
  through (Step 2), and Step 1 finds where things stand. If they also pasted their lead's answer to
  a Step 4b message, run Steps 1 and 3 quickly, then the opening of Step 4 and 4a again
  (read-only, no new message), then Step 4c with the pasted answers.
- Never `sudo` (the engineer may need it to install a missing tool; they run it, not you). Never
  delete: move things to `~/hefesto-old/`. Never use `--force`. Never discard local changes in the
  hefesto clone. Never merge or approve a pull request. Never push to the default branch.
- **Never run `install.sh` from this session, and never unset `CLAUDECODE` to get around its
  refusal.** It refuses inside Claude Code on purpose: it rewrites the profile this session runs
  from, and it asks its questions on a real terminal. The engineer runs it (Step 2).
- Never add `ledger.sh` or `--reviewed-by-human` to any allowlist, and never suggest "Yes, don't ask
  again" on a `ledger.sh` prompt.
- If a step fails, show the exact output and stop. Do not invent another install path. If nothing
  below explains it, tell the engineer to send that output to their lead.

## Step 1 — Find out where things stand (read-only)

Run this block with the Bash tool:

```bash
bash <<'EOF'
tools="git jq claude gh"; [ "$(uname -s)" = Linux ] && tools="$tools bwrap socat"
for t in $tools; do printf '%-7s %s\n' "$t" "$(command -v "$t" || echo MISSING)"; done
C="$(jq -r '.hefesto.installLocation // .hefesto.source.path // empty' "$HOME/.claude/plugins/known_marketplaces.json" 2>/dev/null)"
C="${C:-$HOME/.claude-framework}"
if [ -d "$C/.git" ]; then
  echo "clone: $C  version $(jq -r .version "$C/.claude-plugin/plugin.json" 2>/dev/null) from $(git -C "$C" remote get-url origin 2>/dev/null), $(git -C "$C" status --porcelain --untracked-files=no | wc -l | tr -d ' ') local changes"
else echo "clone: none"; fi
echo "latest: $(git ls-remote --tags --refs https://github.com/joaoariedi/hefesto.git 'v*' | sed -n 's#.*refs/tags/v##p' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
for p in "$HOME/.claude" "$HOME"/.claude-*; do
  case "$p" in "$C"|"$HOME/.claude-framework"|*.backup-*) continue ;; esac
  [ -d "$p" ] || continue
  if [ "$p" != "$HOME/.claude" ]; then
    { [ -f "$p/settings.json" ] || [ -d "$p/plugins" ]; } || continue
    { [ -f "$p/.claude.json" ] || [ -d "$p/projects" ]; } || continue
  fi
  f="$p/plugins/installed_plugins.json"
  v="$(jq -r '[.plugins["hefesto@hefesto"][]? | select(.scope == "user") | .version][0] // "-"' "$f" 2>/dev/null || echo -)"
  o="$(jq -r 'if .plugins["ai-development-framework@ai-development-framework"] then "yes" else "no" end' "$f" 2>/dev/null || echo no)"
  echo "profile: $p  hefesto=$v  old-plugin=$o"
done
ls -d ~/.claude/commands/hef.*.md ~/.claude/commands/speckit.*.md ~/.claude/agents/quality-guardian.md 2>/dev/null | sed 's/^/legacy: /'
d="$(pwd)"; if [ "$d" = "$HOME" ] || ! git -C "$d" rev-parse --show-toplevel >/dev/null 2>&1; then echo "folder: $d is not a git project"; else echo "folder: git project"; fi
EOF
```

Then look at the start of this session's own context for the line
`hefesto <version> hooks loaded from <path>` (a hefesto hook prints it). The hook stays silent
outside a git project, so if Step 1 printed `folder: … is not a git project`, a missing line proves
nothing: ask the engineer to restart Claude Code inside a git project, and run Step 1 again.

| What Step 1 shows | Situation | Go to |
|---|---|---|
| `git`, `jq`, `claude`, or on Linux `bwrap` or `socat`, is `MISSING` | a tool is missing | Tell the engineer how to install it (Linux: their package manager, for `bwrap` the package `bubblewrap`; macOS: `brew install <tool>`), wait until they have, run Step 1 again. |
| `gh` is `MISSING` | fine for now | Recommend installing it now. It is required, with `gh auth login` done, before Step 4. |
| `clone: none`, a profile below `latest` or with `hefesto=-`, `old-plugin=yes`, a `legacy:` line, or local changes in the clone | install or upgrade | Step 2 |
| every profile at `latest`, but the session line is missing or shows an older version | the session is stale, or something is broken | Step 3 |
| every profile at `latest` and the session line matches | installed | Step 3 (quick checks), then Step 4 |

A profile is a Claude config folder: `~/.claude`, or `~/.claude-<name>` used with `CLAUDE_CONFIG_DIR`.
Tell the engineer in at most three lines what you found and what comes next.

## Step 2 — Install or upgrade: the engineer runs the wizard

Tell the engineer, in their language:

1. Open a **new terminal window, outside Claude Code**. Keep this one open.
2. Paste this and press Enter (for Portuguese, add ` --lang pt` at the end):
   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/install.sh)
   ```
3. Press Enter at each question to accept the recommendation.
4. Paste here everything from the line `Check` (Portuguese: `Conferência`) to the end. If there is
   no such line, paste the last 15 lines.

Read what they paste:

| The wizard says | What to do |
|---|---|
| `All good: every profile runs hefesto X` (`Tudo certo: …`) | Tell them to close **every** Claude Code window, open Claude Code again inside a git project, and type the same request as before. A session loads hefesto when it starts, so this session still runs the old copy. Step 1 then leads to Step 3. |
| `Stopped before installing` (`Parei antes de instalar`) | Old files from an earlier install. The wizard printed `$ mkdir …` and `$ mv …` lines above that: the engineer runs them in the same terminal, without the `$`. They move the files into `~/hefesto-old/`. If it also printed `Undo it with: cd X && stow -D Y` (`Desfaça com:`), first have them run `cd X && stow -n -v -D Y` (a dry run) and paste the `UNLINK:` lines. If `settings.json`, `CLAUDE.md` or `rules` is among them, stop: they ask their lead. Otherwise they run the real `stow -D` line. Then the wizard again. |
| `… has local changes. I stop here` (`… tem mudanças locais. Paro aqui`) | Show them `git -C <clone> status`. Do not discard anything; they ask their lead. |
| a missing tool, with an install hint | They install it, then run the wizard again. |
| `Not every profile runs hefesto X` (`Nem todo perfil roda o hefesto X`) | Step 3 |
| anything else | Explain the message in plain words. If it is unclear, stop; they send it to their lead. |

## Step 3 — Check it works, and fix what does not

1. This session's context shows `hefesto <latest> hooks loaded from …`.
2. Ask the engineer to type `/hef.doctor`. Its report must say `status: RUNNING_MATCHES_CLONE`.
   It checks only this session's profile; Step 1 shows the others.
3. Ask them to type `/hef.context`. It prints a summary of the project.

| Symptom | Cause | Fix |
|---|---|---|
| No `hefesto … hooks loaded` line, or an older version, in a git project | The window was opened before the update, or this profile was not updated | Close every Claude Code window and open again. Still old: Step 2 again. |
| `/hef.doctor` says `RUNNING_BEHIND_CLONE` (or `…_SAME_VERSION`) | This profile still runs an old copy | Step 2 again. |
| A profile the engineer uses is not in Step 1's `profile:` lines, or shows `hefesto=-` after the wizard | The wizard did not detect or include it | Step 2 with ` --profile <that folder>` added to the command. |
| A `/hef.*` command does nothing, or asks permission on every call | A helper's permission prompt was denied | Run it again and approve. "Yes, don't ask again" is fine for `speckit-helper.sh`, `status-board.sh` and `pr-watch.sh`, never for `ledger.sh`. To stop the `speckit-helper.sh` prompts in every project, add the rule below. |
| Every command appears twice in the `/` menu | Old copies of hefesto files in `~/.claude/commands` or `~/.claude/agents` (the wizard only flags exact copies of files hefesto shipped) | List the duplicates (`ls ~/.claude/commands ~/.claude/agents`) and show them to the engineer. With their yes, give them the `mkdir -p ~/hefesto-old/manual && mv <files> ~/hefesto-old/manual/` line to run in their terminal. Then restart Claude Code. |
| `git status` lists `.bashrc`, `.gitconfig`, `.idea` or `.gitmodules` the engineer never created | Sandbox masks, not real files | Ignore them. Never commit or delete them. |

**The permission rule for `speckit-helper.sh`.** It goes in the settings of the profile the
engineer works in: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`, once per profile. Merge it,
keeping everything already there: show the engineer the change and write only after they say yes.
If the file does not parse as JSON, stop and report; do not repair it. Replace
`/home/you/.claude-framework` with the clone folder Step 1 printed, written literally: the
permission matcher expands neither `$HOME` nor `~`. The doubled slash is not a typo:
`${CLAUDE_PLUGIN_ROOT}` ends in a slash, so the commands send `…/.claude-framework//hooks/…`, and
the matcher compares literally. The single-slash entry is a hedge for a future release.

```jsonc
{
  "permissions": {
    "allow": [
      "Bash(/home/you/.claude-framework//hooks/speckit-helper.sh:*)",
      "Bash(/home/you/.claude-framework/hooks/speckit-helper.sh:*)"
    ]
  }
}
```

When the three checks pass, go to Step 4.

## Step 4 — Set up the project (once per repository)

Ask which project. It must be a git repository with a GitHub remote, and `gh auth status` must
pass. Work in its main folder, on its default branch (or the branch where work integrates, once
known), with a clean `git status`.

Step 4 runs in three passes: **look** at everything (read-only), send **one message** with every
decision the lead must make, then **write** what was decided. Some of these choices belong to the
engineer's lead, not to the engineer. Never ask the engineer to make them; that is what the message
is for.

### 4a — Look (read-only)

Check each item below and note what is already done, what is missing, and what needs a decision.
Also read the project's own `CLAUDE.md` and any board it already has.

1. **Bootstrap.** Is there a `.specify/` folder?
2. **The board.** Are there `tasks/TODO.md`, `tasks/DOING.md`, `tasks/DONE.md` and `tasks/BACKLOG.md`?
   Hefesto reads an item only as a heading with an id and a title, then a few lines saying what is
   wanted. The id prefix is two or more capital letters or digits, starting with a letter (`ABC-12`
   works; `A-1` and `abc-12` are silently ignored):
   ```markdown
   ## ABC-12 — Export orders as CSV

   The orders page gets an "Export CSV" button with the columns shown on screen.
   ```
   If the project keeps its board another way (table rows, another prefix, another repository),
   note it: converting it is a lead decision. If the board lives in its own repository and that
   repository is already cloned next to this one, read it too.
3. **The config.** Is there a `.claude/project-status.json`, and what does it hold? Which command
   runs the project's tests? Look for it (`package.json` scripts, `Makefile`, the project's
   `CLAUDE.md`) before asking anyone.
4. **GitHub.** Run:
   ```bash
   gh repo view --json nameWithOwner,mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed,defaultBranchRef
   git branch -r
   gh api "repos/{owner}/{repo}/branches/<branch>" -q .protected   # once per branch, see below
   ```
   Run the last line for the default branch and for each branch where work may integrate (for
   example `dev`, if `git branch -r` shows one). It prints `true` or `false` and needs only read
   access.
   Hefesto needs merge commits allowed and the branch where work integrates protected (a pull
   request required before merging): it detects a merge by finding the branch inside that branch,
   which squash and rebase merges break. If changes integrate on a branch other than `main` (say
   `dev`, promoted to `stg` and `main`), note it (`docs/install.md` §7 step 12).
5. **Fit.** Does the project's `CLAUDE.md` have a rule that unattended worker sessions would break
   (for example, every step needs a person's confirmation)? Are there board items that only a
   person can do?

### 4b — The lead's decisions: one message

**Coming back with the answer?** If the engineer pastes the lead's message together with the
lead's reply, do not write a new message: go to 4c with those answers. If they paste only a reply
like `1a 2b`, ask for the message it answers too: the codes mean nothing without it.

Write **one message** in the engineer's language for them to send to their lead. Tell the engineer
to bring back the lead's reply **together with the whole message**, then stop. Put in it every decision that applies, and nothing already settled:

- the board: convert its format, which id prefix, which items stay out of `TODO.md` (workers take
  only from `TODO.md`; a person's items go to `BACKLOG.md`);
- a board kept in its own repository: clone it next to this one (`docs/install.md` §7 step 13);
- the integration branch and the promotion order, if not `main`;
- repository settings only the lead can change: merge commits, protecting the integration branch;
- the test command, if you could not find it;
- the spend limits: `usd_cap` (per worker session) and `daily_usd_cap` (per day);
- a project rule that the sessions would break, and whether to make an exception for board items.

Number the decisions. For each, give the options, **your recommended answer first** with a one-line
reason, and what changes with each answer. End with a line the lead can reply with, for example
`1a 2a 3b`, and say that a value can be written instead of a letter (for example `4: usd_cap 10`). The message must make sense to someone who has not seen this conversation.

If nothing needs a decision, skip to 4c.

### 4c — Write

With the lead's answers, write only what was decided. Ask the engineer before each change.

1. **Bootstrap.** If `.specify/` is missing, ask the engineer to type `/hef.init`.
2. **The board.** If the lead chose a board in its own repository, do this there (item 4). Create
   the missing files with just a title (`# TODO`, `# DOING`, …), or convert the board as the lead
   decided. Never invent items.
3. **The config.** If the lead chose a board in its own repository, this repository gets only the
   pointer, and the template below goes to the board repository (item 4). Otherwise: if
   `.claude/project-status.json` is missing, create it. If it exists, add only
   the keys it lacks; never overwrite it. Put the test command in both `allowed_tools` lists in
   place of `<test command>` (for example `npm test`); without it the worker sessions cannot run the
   tests. Add a `branches` block if the lead named an integration branch (`docs/install.md` §7
   step 12), for example `"branches": {"integration": "dev", "environments": ["dev", "stg", "main"]}`
   with only the branches that exist.
   ```json
   {
     "source": "tasks-repo",
     "root": "tasks",
     "orchestrate": {
       "usd_cap": 5,
       "daily_usd_cap": 25,
       "tiers": { "implement": "opus", "verify": "fable" },
       "allowed_tools": {
         "implement": ["Read", "Edit", "Write", "Glob", "Grep", "Skill", "Agent", "Bash(git *)",
                       "Bash(gh pr create *)", "Bash(gh pr view *)", "Bash(<test command>*)"],
         "verify": ["Read", "Glob", "Grep", "Skill", "Agent", "Bash(git diff*)", "Bash(git log*)",
                    "Bash(<test command>*)"]
       }
     }
   }
   ```
4. **A board in its own repository**, if the lead chose one (`docs/install.md` §7 step 13):
   - the engineer clones it next to this repository (`git clone <url> ../<folder>`): you may not
     write outside this folder;
   - this repository's `.claude/project-status.json` gets only the pointer and its branches:
     `{"board": "../<folder>", "branches": {…}}`;
   - the board repository's `.claude/project-status.json` gets the template above, with `"root"`
     set to the board's folder inside it (`"."` when the files sit at its top) and
     `"repos": {"<name>": "../<this repository's folder>"}`;
   - the board's files and their conversion live in the board repository;
   - check, from this repository, with `bash <clone>/hooks/ledger.sh board`, where `<clone>` is the
     hefesto folder Step 1 printed.
5. **The project rule.** If the lead approved an exception to a project rule, add the sentence the
   lead approved to the project's `CLAUDE.md`, in the setup pull request. If the lead refused it,
   do not go to Step 5; say why under "Report back".
6. **Check the board.** Ask the engineer to type `/hef.status`. It prints the board. Check that it
   counts every item.
7. **Commit the setup.** One pull request per repository you changed: branch
   `chore/hefesto-setup`, stage the files by name, commit, `git push origin chore/hefesto-setup`,
   then `gh pr create`, with `--base <integration branch>` when the lead named one. Never change
   repository settings yourself. A person merges. **Wait until every setup pull request is merged**
   and the lead has changed the repository settings they decided on. Then, in each repository that
   got a setup pull request, `git switch` to the branch where work integrates and
   `git pull --ff-only`. Go to Step 5.

## Step 5 — Hand over the four sessions

Give the engineer this, with `<repo>` replaced by the project's folder name, then answer their
questions. Each session runs in its own terminal, inside the project's main folder:

```bash
claude --name <repo>-orchestrator --permission-mode default --settings '{"sandbox":{"enabled":false}}'
claude --name <repo>-plan         --permission-mode default --settings '{"sandbox":{"enabled":false}}'
claude --name <repo>-build        --permission-mode default --settings '{"sandbox":{"enabled":false}}'
claude --name <repo>-deploy       --permission-mode default --settings '{"sandbox":{"enabled":false}}'
```

| Session | What it does | Type |
|---|---|---|
| orchestrator | Shows the board, what is running and what waits on a person | `/hef.status` |
| plan | Writes the spec, the plan and the tasks for the next item | `/hef.orchestrate --stage plan` |
| build | Implements the next item, checks it, opens the pull request. Start it on an item only after `/hef.status` shows plan finished with it | `/hef.orchestrate` |
| deploy | Watches the next pull request's CI until it is ready to merge | `/hef.orchestrate --stage deploy` |

- `--permission-mode default` keeps the permission dialogs: the human gates are those dialogs.
- The sandbox is off for these four because they start other sessions; the sessions they start run
  sandboxed (on Linux that needs `bwrap` and `socat`, checked in Step 1).
- If an item shows `blocked_on human:…`, it waits on a person: the engineer asks their lead.
- Between items, each session runs its own `/compact` prompt. Fetch them with
  `curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/docs/performance.md`
  (section "Compact prompts per pane") and give the engineer the four, one per session.
- Only a person merges. One item at a time per session. When in doubt, stop and ask the lead.

## Report back

When done, tell the engineer, briefly and in their language:

- what Step 1 found and which steps you went through;
- what changed, and who changed it (the wizard, you, or the engineer);
- each check in Step 3: passed, or failed with its output;
- what is left for a person: restarting Claude Code, the lead's GitHub settings, merging the setup
  pull request.
