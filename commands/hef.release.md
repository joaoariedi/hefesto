---
model: sonnet
description: "Cut a release: move every version declaration together, scaffold the CHANGELOG entry, then stop for the human edit"
argument-hint: "<X.Y.Z> [YYYY-MM-DD]"
---

# Release

Bump **$ARGUMENTS** across every declaration at once and scaffold the changelog entry. The
script never commits, tags, or pushes — those stay deliberate steps you take after reading what
it wrote.

## Pre-Flight

### Current state
> The commands in this section must be run with the Bash tool; they cannot be
> pre-executed in a `!` block. A `!` block is permission-checked before the
> CLAUDE_PLUGIN_ROOT variable is substituted, so it is rejected as "Contains
> expansion". Do not write that variable with a $ and braces here: it would be
> substituted into this note and the warning would read as nonsense.

Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh branch`
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh recent-commits`

## Which path

Run with the Bash tool: `git rev-parse --show-toplevel` — that is `<repo path>`, the repo being released. If it has
a `.claude-plugin/plugin.json`, this is the plugin: follow **Plugin path**. If it has no `.claude-plugin/plugin.json`,
it is a project that adopted Hefesto: follow **Project path**, and do not run `release.sh` — that script edits
only this plugin's own manifests.

## Plugin path

1. **Semver check.** Read the commits since the last tag. A renamed command, a moved path, or a
   permission rule that must be edited is **major**; new commands/hooks/skills are **minor**;
   fixes only are **patch**. If the requested version disagrees with what the commits contain,
   say so and stop — the versioning policy at the top of `CHANGELOG.md` is not advisory.

2. Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/release.sh $ARGUMENTS`

3. **Edit the scaffold.** The script grouped commit subjects under Added/Changed/Fixed. That is a
   list of technical steps, not release notes. Rewrite it as what changed *for the user*, with the
   why; keep the one-sentence thesis line honest; delete noise. Do not add anything that is not in
   the diff — an entry that is fluent, plausible, and false is worse than none.

4. Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/tests/smoke.sh` — the version-consistency block
   is the check that all declarations moved.

5. Stop. Tell the user the entry is ready to review, and that the remaining steps are theirs:
   `git commit`, `git tag -a vX.Y.Z`, `git push origin vX.Y.Z`, and the GitHub Release. The tag goes
   on the **final branch's** commit — the last of `.branches.environments`, `main` by default; run
   `${CLAUDE_PLUGIN_ROOT}/hooks/ledger.sh branches` and name it (`"final"`) — never on an integration
   branch commit that has not been promoted there.

## Project path

The version lives in the repo's own `CHANGELOG.md` (Keep a Changelog), never from another repo: a release train
cuts several repos, each at its own version, so run every command below with `-C <repo path>` pointing at this one.

1. **Read the version.** Run with the Bash tool:
   `${CLAUDE_PLUGIN_ROOT}/hooks/changelog-check.sh -C <repo path> version`. It prints the X.Y.Z on the
   `## [Unreleased]` heading when one is written there — that is the version to cut — else the latest released
   `## [X.Y.Z]`, which is the current one: the next is that bumped by the semver rules below. On exit 2 the
   CHANGELOG has neither; say so and stop. If **$ARGUMENTS** names a version that disagrees, say so and stop.

2. **Semver check.** Read the commits since the last tag, as in the plugin path: a breaking change is **major**, new
   behaviour **minor**, fixes only **patch**, unless the repo's CHANGELOG states its own policy — then that one.

3. **Cut the section.** Edit `<repo path>/CHANGELOG.md`: move the `## [Unreleased]` content into a new
   `## [X.Y.Z] - YYYY-MM-DD` section directly below it (today's date unless **$ARGUMENTS** gives one),
   and leave an empty `## [Unreleased]` above it. If the file has Keep-a-Changelog link references at the foot, point
   `[Unreleased]` at `vX.Y.Z...HEAD` and add the `[X.Y.Z]` link. Change no released section: not a word, not a date.
   Move the text as written; rewrite it for the user only where it is a list of technical steps, and add nothing
   that is not in the diff.

4. **Check the placement.** Run with the Bash tool:
   `${CLAUDE_PLUGIN_ROOT}/hooks/changelog-check.sh -C <repo path> placement --base <base> --cut X.Y.Z`, where
   `<base>` is the branch this release promotes into (`origin/main` by default; the next of `.branches.environments`
   from `${CLAUDE_PLUGIN_ROOT}/hooks/ledger.sh branches`). Exit 0 is placed. Exit 1 names the released section that
   changed and its first differing line: put that section back as the base has it and run the check again. On exit 2
   it cannot judge (the base has no CHANGELOG, an unreadable ref, or no `## [` heading) — report it, never
   read it as a pass.

5. Stop. Tell the user the entry is ready to review, and that `git commit`, the tag `vX.Y.Z` on the final branch's
   commit, the push and the release are theirs.
