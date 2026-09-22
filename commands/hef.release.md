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

## Instructions

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
   `git commit`, `git tag -a vX.Y.Z`, `git push origin vX.Y.Z`, and the GitHub Release.
