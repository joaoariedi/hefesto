# Hooks & Quality Gates

[← back to README](../README.md)


## ⚙️ Hooks

Hooks ship **inside the plugin** (`hooks/hooks.json`), so installing the plugin registers all of them. No `settings.json` editing.

| Hook | Trigger | What It Does |
|------|---------|--------------|
| ✅ `verify-before-task-complete.sh` | **TaskCompleted** | **Blocks** a task from being marked complete while the test suite fails. Exit 2 is a hard gate. |
| 🔍 `quality-before-commit.sh` | PreToolUse on `Bash` | Intercepts `git commit` — gitleaks, shell + markdown checks on staged files, then language-specific linters. Blocks on errors. |
| 🔒 `block-sensitive-files.sh` | PreToolUse on `Edit\|Write` | Blocks writes to `.env*`, `*.key`, `*.pem`, `credentials*`, `.git/*`, `secrets/` |
| ⛔ `block-destructive-commands.sh` | PreToolUse on `Bash` | Hard-denies `git push --force` (allows `--force-with-lease`), `reset --hard`, `branch -D`, `clean -f`, and recursive `rm` of catastrophic targets. Bypass: `CLAUDE_ALLOW_DESTRUCTIVE=1` prefix, visible in the transcript |
| 📐 `plan-phase-write-block.sh` | PreToolUse on `Edit\|Write` | Blocks writes outside `.specify/` while `/hef.plan` is active |
| 🧷 `implement-phase-test-guard.sh` | PreToolUse on `Bash` and `Edit\|Write` | While `/hef.implement` is active: **blocks** edits that leave a test file with fewer assertions, overwrites of existing test files, and `rm` of test files. Always: blocks snapshot-update flags on test runners. Bypass: `CLAUDE_ALLOW_SNAPSHOT_UPDATE=1` prefix |
| 🧭 `session-start-context.sh` | SessionStart | Injects branch, dirty-file count, spec artifacts, open tasks, phase markers, and the last checkpoint into context. Silent outside a git repo |
| 💾 `precompact-progress.sh` | PreCompact | Writes the progress checkpoint `context-management.md` asks for — to `~/.cache/hefesto/progress/`, never into the repo |
| 👁️ `audit-config-change.sh` | ConfigChange | Announces a settings rewrite mid-session — the escalation path a compromised skill or plugin would take |
| 🔀 `merge-tree-probe.sh` | PostToolUse on `Edit\|Write` | Once a minute: would this branch's committed state conflict with its base (`git merge-tree`)? How far has the base drifted? Advisory |
| 🚀 `release.sh` | Run by `/hef.release` | Moves all six version declarations together and scaffolds the CHANGELOG entry (not a hook — a script) |
| 🎨 `format-after-edit.sh` | PostToolUse on `Edit\|Write` | Auto-formats edited files (ruff, biome/prettier, gofmt, rustfmt), 10s throttle |
| 🧪 `run-tests-after-edit.sh` | PostToolUse on `Edit\|Write` | Auto-runs test suite after source edits, 15s throttle, non-blocking |
| 🔔 `notify-on-block.sh` | Notification | Desktop alert when agent needs attention (notify-send / osascript) |
| 📊 `stop-quality-check.sh` | Stop event | Reminds if source files were edited but tests not run |
| 🔧 `speckit-helper.sh` | Pre-flight commands | Routes backtick logic to avoid Claude Code permission errors (not a hook — a helper) |

### The framework lints itself

Every language check in `quality-before-commit.sh` is gated behind a manifest — `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `pom.xml`. A repo made of shell scripts and markdown matches **none** of them, so for its whole history the framework's own quality gate was a **no-op against its own source**. It shipped a gate it did not run.

Two manifest-free checks now run on **staged files only** (per the Tier 1 rule this framework itself states):

| Check | Zero-dependency baseline | Upgraded when installed |
|---|---|---|
| **Shell** | `bash -n` — syntax must parse | `shellcheck -S error` |
| **Markdown** | code fences must be balanced (an unclosed ``` silently breaks rendering) | `markdownlint-cli2` |
| **Commit message** | conventional `<type>(<scope>)?: <description>` on the inline subject (`git-workflow.md`); bypass `CLAUDE_ALLOW_NONCONVENTIONAL=1` | — |
| **Complexity delta** | *(none — no zero-dependency checker exists)* | `lizard`: a staged file may not gain functions over the `code-quality.md` limits versus `HEAD` |

The zero-dependency baseline is the point. Guarding purely on `command -v shellcheck` would have reproduced the original bug on any machine without it installed — a check that only runs where it's already unnecessary is not a check. To get the stronger tier:

```bash
# Arch / Manjaro
sudo pacman -S shellcheck && npm i -g markdownlint-cli2
```

The **language** checks are scoped the same way — but only where the tool permits it. `ruff`, `eslint`, and `biome` take a file list, so they see staged files only. A **type checker cannot**: `tsc` needs the whole program graph to resolve an import, and `cargo clippy` analyses a crate, not a file. Those stay whole-unit, which is correct rather than lazy — they are simply gated on their language actually being staged, so they cost nothing otherwise.

### The implement-phase test guard

`hef.implement` has always said *"never modify the test to make it pass."* Prose. The evidence
says prose is not enough here: TDD *instructions* without a mechanism made agent regressions worse
in a controlled study (9.9% vs 6.1% baseline — arXiv 2603.17973), and Kent Beck reports agents
deleting tests to get to green. So `/hef.implement` now arms a marker
(`.specify/.implement-in-progress`), and while it is set the guard applies one rule: **tests may
grow, never shrink** — no edit that removes assertions, no whole-file overwrite of an existing test,
no `rm` of a test file. New test files and added cases pass through untouched. Snapshot-update flags
(`jest -u`, `pytest --snapshot-update`, …) are blocked regardless of phase, because a regenerated
baseline is a deleted test that still shows green.

`speckit-helper.sh implement-phase-end` disarms it; `CLAUDE_ALLOW_SNAPSHOT_UPDATE=1` bypasses the
snapshot block visibly.

### The `TaskCompleted` gate

Every other quality mechanism in this framework is **advisory** — a rule the model can rationalize past, or a `Stop` hook that prints a reminder and exits 0. `verify-before-task-complete.sh` is the first one that is **mechanical**: exit 2 blocks the completion outright and feeds stderr back to the agent.

It is the enforcement the Verification Iron Law always claimed to have:

- Skips entirely when there is no test runner, or when the runner is on `PATH` but cannot execute (a version-manager shim that fails at exec time is a **tooling** fault, not a test failure — blocking on that would be a false positive, and a gate that cries wolf gets disabled).
- Skips when the working tree has no source changes. Docs cannot break a test suite.
- Caches the result against a hash of the working tree, so the suite is not re-run for a tree already proven green.
- `CLAUDE_SKIP_VERIFY_GATE=1` disables it — deliberately, and visibly, rather than by quietly working around it.

---



## 🛡️ Automated Quality Gates

Fourteen hooks enforce quality automatically — and they ship with the plugin, so there is nothing to register:

- 🔍 **Pre-commit** — secrets detection (gitleaks) + language-specific linting blocks the commit on errors
- 🔒 **File protection** — writes to `.env`, `*.key`, `*.pem`, credentials, and `.git/` internals are blocked
- ⛔ **Destructive-command denials** — `git push --force`, `reset --hard`, `branch -D`, `clean -f`, and recursive `rm` of catastrophic targets are hard-denied at the PreToolUse layer. The llm-security rule always said "never without explicit user request"; this is the mechanism behind the prose, with a transcript-visible bypass (`CLAUDE_ALLOW_DESTRUCTIVE=1`) for when the user *does* request it
- 🎨 **Auto-format** — formatters run after every edit (ruff, biome, gofmt, rustfmt)
- 🧪 **Auto-test** — test suite runs after source file edits (throttled 15s, non-blocking)
- 📊 **Reminders** — alerts if source files were edited but tests weren't run
- 🔔 **Notifications** — desktop alerts when the agent needs human input (Linux/macOS)
- 📐 **Plan-phase write-block** — while `/hef.plan` is active, edits outside `.specify/` are blocked, so the planning phase cannot quietly become the implementation phase
- ⛔ **Verification gate** (`TaskCompleted`) — a task **cannot be marked complete** while the test suite fails. This is the Iron Law made mechanical: every other quality mechanism in the framework is advisory, and this is the one the model cannot rationalize past
- 🧷 **Implement-phase test guard** — while `/hef.implement` runs, tests may grow but not shrink; snapshot regeneration is always blocked
- 🧭 **Session context** — every session starts knowing its branch, spec state, and open tasks; every compaction leaves a checkpoint behind
- 👁️ **Config audit** — a settings rewrite mid-session is announced, not silent
- 🔀 **Merge-tree probe** — a branch that would conflict with its base, or has drifted far behind it, is told so while the diff is still small
- 📏 **Complexity as a delta** — where `lizard` is installed, a change may not make a file's functions longer or more complex than the limits; existing debt is visible, not blocking

The **boundary** under all of this is OS sandboxing, not string matching: a Bash deny rule can be composed around (`sh -c`, an absolute binary path — Claude Code's own docs say so), and the destructive-command hook documents that limit in its header. Enable `/sandbox` (see `docs/install.md`); the hooks catch the careless path, the sandbox catches the determined one.

The `quality-guardian` agent validates before commit/PR/merge with secrets scanning, SAST, supply chain checks, SOLID architectural analysis, performance validation, and **Iron Law enforcement**.

### 🔐 Security Posture

The framework implements layered defenses against OWASP LLM vulnerabilities:

| Layer | Mechanism | Covers |
|-------|-----------|--------|
| **Enforcement** | Hooks | Sensitive file blocking, destructive-command denials, secrets detection, pre-commit quality |
| **Guidance** | Rules | OWASP LLM Top 10, MCP security, code quality, SOLID principles |
| **Analysis** | Skills & Agents | Built-in `/security-review`, `/hef.scan`, forensic investigation, quality gates |
| **Efficacy** | Iron Laws | Verification before completion (rule + `TaskCompleted` hook), systematic-debugging |

MCP servers follow strict security posture — OAuth 2.1 for production, least privilege, input validation, and human-in-the-loop for high-impact actions.

---

