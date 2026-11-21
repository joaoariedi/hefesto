# Contributing

[← back to README](../README.md)

How to change hefesto itself: run the tests, make a change, commit it, open the pull request. Each line names the
file that makes it true.

## Run the tests

- **Tier 1** — `tests/smoke.sh`: the structural and regression checks CI runs. No login, no model, no tokens
  (`tests/smoke.sh`, header).
- **Tier 2** — `SMOKE_LIVE=1 tests/smoke.sh`: installs the plugin into a throwaway `CLAUDE_CONFIG_DIR` and runs a real
  command headlessly against a scratch repo. It needs a logged-in `claude` and spends tokens; without a login the
  end-to-end check prints `skip` and tier 1 still runs (`tests/smoke.sh`).
- **The Workflow script** — `node --test` from the repository root, bare: it finds the `*.test.js` files itself, and
  passing a directory makes node try to load it as a module and fail (the `Workflow behaviour tests` step of
  `.github/workflows/smoke.yml`).
- **macOS** — `/bin/bash tests/smoke.sh`, the stock bash 3.2 the hooks are written for (the `smoke-macos` job of
  `.github/workflows/smoke.yml`).

## Make a change

- **Branches:** `feature/<name>`, `fix/<name>`, `refactor/<name>` (`.claude/rules/git-workflow.md`, Branch Naming).
- **A feature** goes through the spec-driven pipeline — `/hefesto:hef.spec` → `/hefesto:hef.plan` →
  `/hefesto:hef.review` → `/hefesto:hef.tasks` → `/hefesto:hef.implement` ([`sdd.md`](sdd.md)); **a trivial change**
  (a typo, a config line) takes `/hefesto:hef.fix`.
- **A guard is mutation-tested:** reintroduce the bug it guards against and confirm the suite goes red
  (`.specify/memory/constitution.md`, principle 3). In `tests/smoke.sh` the check is a function of its input, run on
  the tree and then on mutated temporary copies.
- **Never name an adopting project** in this repository — examples, fixtures and docs use neutral names, as the
  [case study](case-study-sdlc.md) does ("one production adopter").

## Commit

- **Subject:** a conventional commit, `<type>(<scope>)?: <description>` with a type from `feat fix docs style refactor
  perf test chore ci build revert`. The commit hook blocks any other subject (`hooks/quality-before-commit.sh`,
  `CONVENTIONAL_RE`), and also runs secrets detection and linting.
- **Trailer:** `Co-Authored-By: Claude <model> <noreply@anthropic.com>` when Claude wrote it — a convention of
  `.claude/rules/git-workflow.md`, not checked by the hook.

## Pull request

- **CI:** the `smoke` (Linux) and `smoke-macos` jobs of `.github/workflows/smoke.yml` must pass.
- **Review:** `/hefesto:hef.verify` maps every requirement to the tests that cite it; `/hefesto:hef.review` in code
  mode runs `code-reviewer` in a fresh context, so the session that wrote the change never grades it
  ([`commands.md`](commands.md)).
- **Merge:** a person merges, with a **merge commit** — never squash or rebase. The `human:merge` gate is cleared by
  `git merge-base --is-ancestor <branch> main`, which a squash- or rebase-merged branch never satisfies
  ([`install.md`](install.md) §7, step 2).
