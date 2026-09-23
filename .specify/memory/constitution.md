# Project Constitution
<!-- Version: 1.0.0 | Date: 2026-07-16 -->
<!-- Updated by /hef.constitution -->

Every principle below is distilled from a bug this repository actually shipped. None are aspirational.
They govern *this repo* (the plugin itself); they complement, and do not duplicate, `.claude/rules/`.

## Principles

1. **The plugin payload never lives under `.claude/`** — `.claude/` is where Claude Code looks for
   *project-scope* config, which outranks both plugins and built-ins. Shipping the payload there means
   that while working in this repo the commands silently resolve to the repo's own copies, so the
   framework is never dogfooded *as a plugin* — it behaves one way here and another way in every real
   install. This single mistake caused issues #7, #9, #12, and #13. `.claude/` holds only this repo's
   own config; the payload lives at the repository root. `tests/smoke.sh` fails if any payload
   directory reappears under `.claude/`.

2. **Every command is namespaced** (`hef.*`) — a plugin command that shares a name with a
   Claude Code built-in is silently unreachable, and the built-in wins with no warning. No built-in
   contains a dot, so a mandatory dot eliminates the entire class structurally. This replaces a
   hand-maintained list of built-in names, which is a list that goes stale the moment Claude Code ships
   a new command. Enforced by `tests/smoke.sh` (#17).

3. **Every guard is mutation-tested, and assertions sit at the tool-call level** — a test that cannot
   fail is worse than no test, because it converts absence of verification into a green check. Two
   ways this repo learned it: `set -o pipefail` + `grep -q` made three guards report clean against
   violating files (the producer dies of SIGPIPE, pipefail returns 141, the `if` reads "no match"); and
   an end-to-end assertion on helper *data* went green against a completely broken plugin, because when
   the helper was permission-blocked the model just ran plain `git log` and produced identical output.
   So: reintroduce the bug and confirm the suite goes red, and assert on *whether the tool was invoked*,
   never on data the model could reproduce by hand.

4. **Dependencies are zero-install** — this repo is shell, JavaScript, and markdown, with no package
   manager, no lockfile, and no `node_modules`. `detect-stack` and `list-config-files` both return
   empty, and that is a feature: anyone can clone and run `tests/smoke.sh` immediately. New tooling
   must run from what is already on the machine. Note the boundary precisely: this forbids the *install
   step*, not the *runtime*. `node --test` is built into node ≥18 and needs no `package.json`, so it
   complies; `npm install vitest` does not.

5. **Helpers fail loudly; no exit-0 sentinel a caller can ignore** — a helper that returns a string
   like `NO_SPEC` or `NOT_FOUND` at exit 0 lets a command sail past a missing precondition and invent
   its own answer. `pr_base` once exited 128 with no output and silently degraded every command that
   called it. When a helper cannot answer, it must be impossible for the caller to mistake that for an
   answer.

## Tech Stack
- Language: Bash (hooks, `speckit-helper.sh`, `tests/smoke.sh`), JavaScript (`workflows/`), Markdown
  (commands, agents, skills, rules, docs)
- Framework: Claude Code plugin — `.claude-plugin/plugin.json` + `marketplace.json`
- Database: N/A
- Testing: `tests/smoke.sh` (3 tiers: structural, live, end-to-end) — there is no package manager; CI
  runs tier 1 on `ubuntu-latest`

## Architecture Constraints

- The repository **is** the plugin. Manifests in `.claude-plugin/`; payload at the repo root.
- `CLAUDE.md` and `rules/` are **not** plugin components and cannot be shipped by a plugin. They apply
  only when this repo *is* the project, or when a user copies them into `~/.claude/` themselves.
- `${CLAUDE_PLUGIN_ROOT}` is substituted in skill *body text*, but **not** before the permission check
  on a `` !`…` `` pre-execution block, and it is **not** set in the Bash tool's environment. Helper
  calls therefore run via the Bash tool, never a `!` block.
- The permission matcher performs no expansion and no normalization: `$HOME` and `~` are not expanded,
  and `//` is not collapsed. A rule must mirror the command string byte-for-byte.
- Spec artifacts resolve as `.specify/specs/$(git branch --show-current | sed 's|^feature/||')/`. The
  spec directory name and the branch name are one contract, not two.

## References
- Project rules: `.claude/rules/`
- Code quality: `.claude/rules/code-quality.md`
- Git workflow: `.claude/rules/git-workflow.md`
- Post-mortems: `CHANGELOG.md` (4.5.0, 5.0.0), `tests/smoke.sh` header comments
