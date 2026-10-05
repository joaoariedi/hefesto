# Hooks & Quality Gates

[← back to README](../README.md)


## ⚙️ Hooks

Hooks ship **inside the plugin** (`hooks/hooks.json`), so installing the plugin registers all of them. No `settings.json` editing.

| Hook | Trigger | What It Does |
|------|---------|--------------|
| ✅ `verify-before-task-complete.sh` | **TaskCompleted** | **Blocks** a task from being marked complete while the test suite fails. Exit 2 is a hard gate. |
| 🔍 `quality-before-commit.sh` | PreToolUse on `Bash` | Intercepts `git commit` — gitleaks, shell + markdown checks on staged files, then language-specific linters. Blocks on errors. When a staged manifest ADDS a direct dependency it also emits one advisory line through the PreToolUse `additionalContext` (never a block): the dependency names and "run /hef.scan --deps before the PR" |
| 🔒 `block-sensitive-files.sh` | PreToolUse on `Edit\|Write\|MultiEdit` | Blocks writes to `.env*`, `*.key`, `*.pem`, `*.p12`, `*.pfx`, `*.secret`, `credentials*`, `.git/*`, `secrets/`, `.secrets/` |
| ⛔ `block-destructive-commands.sh` | PreToolUse on `Bash` | Hard-denies `git push --force` and a `+refspec` push (allows `--force-with-lease`), `reset --hard`, `branch -D` (and `-d --force`), `clean -f`, and recursive `rm` of catastrophic targets. Bypass: `CLAUDE_ALLOW_DESTRUCTIVE=1` prefix, visible in the transcript |
| 📐 `plan-phase-write-block.sh` | PreToolUse on `Edit\|Write\|MultiEdit` | Blocks writes outside `.specify/` while `/hef.plan` is active |
| 🧷 `implement-phase-test-guard.sh` | PreToolUse on `Bash` and `Edit\|Write\|MultiEdit` | While `/hef.implement` is active: **blocks** edits that leave a test file with fewer assertions, overwrites of existing test files, and `rm` of test files. Always: blocks snapshot-update flags on test runners. Bypass: `CLAUDE_ALLOW_SNAPSHOT_UPDATE=1` prefix |
| 🔗 `spec-cite-probe.sh` | PostToolUse on `Edit\|Write` | Advisory, once a minute per file: when a test that cites an `FR-NNN` is edited **outside** an implement phase, names the spec that declares it and asks for the spec to follow or `/hef.verify` to re-run. The reverse direction of `req-coverage` — the one that catches post-ship drift |
| 🧭 `session-start-context.sh` | SessionStart | Injects branch, dirty-file count, spec artifacts, open tasks, phase markers, blocked ledger entries (one `ledger:` line each, with the human command that clears it), the last checkpoint, and the two routing rules (spec before code for feature-sized work; root cause before any fix) into context. Silent outside a git repo; every blocked ledger line names the pane that owns the kind (`orchestrate.panes` in the project config, default map orchestrator / plan / build / deploy — a malformed map falls back to the default, never to a missing line) |
| 💾 `precompact-progress.sh` | PreCompact | Writes the progress checkpoint `context-management.md` asks for — to `~/.cache/hefesto/progress/`, never into the repo |
| 👁️ `audit-config-change.sh` | ConfigChange | Announces a settings rewrite mid-session — the escalation path a compromised skill or plugin would take |
| 🔀 `merge-tree-probe.sh` | PostToolUse on `Edit\|Write` | Once a minute: would this branch's committed state conflict with its base (`git merge-tree`)? How far has the base drifted? Advisory |
| 🚀 `release.sh` | Run by `/hef.release` | Moves all six version declarations together and scaffolds the CHANGELOG entry (not a hook — a script) |
| 🎨 `format-after-edit.sh` | PostToolUse on `Edit\|Write` | Auto-formats edited files (ruff, biome/prettier, gofmt, rustfmt), 10s throttle |
| 🧪 `run-tests-after-edit.sh` | PostToolUse on `Edit\|Write` | Auto-runs test suite after source edits, 15s throttle, non-blocking |
| 🔔 `notify-on-block.sh` | Notification | Desktop alert when agent needs attention (notify-send / osascript) |
| 📊 `stop-quality-check.sh` | Stop event | Reminds if source files were edited but tests not run |
| 🔧 `speckit-helper.sh` | Pre-flight commands | The pre-flight fetcher every `hef.*` command calls — live git data instead of backtick substitution, 46 subcommands: spec artifacts (`branch`, `check-git-root`, `spec`, `plan`, `check-spec`, `check-plan`, `check-artifacts`, `all-artifacts`, `clarifications`, `checklists`, `checklists-dir`, `checklists-content`, `constitution`, `list-specs`, `list-specs-dir`, `check-specify-dir`, `check-plan-review`); project context (`detect-stack`, `detect-test-framework`, `list-config-files`, `list-rules`, `readme-head`, `recent-commits`, `project-files`, `detect-existing-code`, `trivial-change-check`); PR data (`pr-commits`, `pr-files`, `pr-stats`); phase markers (`plan-phase-start\|end\|status`, `implement-phase-start\|end\|status`); traceability (`req-coverage`); mutation ratchet (`mutation-score`, `mutation-ratchet`, `mutation-raise`); `doctor-copies`; arena (`arena-cite-check`, `arena-metrics`); dependencies (`deps-diff`, `deps-audit`); RTK (`rtk-available`, `rtk-run`) (not a hook — a helper) |
| 📊 `status-board.sh` | `/hef.status` | The mechanical half of the status brief: reads `.claude/project-status.json` and prints the board from a GitHub Project or a tasks repository; `--check` diagnoses, `--detailed` unfolds; `--item`/`--item-raw` read one item (todo, doing, backlog, done). `--item-kind <id>` prints the item's kind — `incident` for a 🐞 before the id, `vulnerability` for 🛡, else `feature` (config `kinds` overrides; the glyph goes before the id and may sit behind a publish state marker; variation selectors are ignored). Its one write path is `--mark <id> <marker|->`: a publish state marker first on the item's heading, replacing only its own markers (`orchestrate.publish_markers` over the default ⏸ ⛔ 📐 🔨 🔀 ✅) and keeping every other token such as a kind marker; a DONE item is left alone. `--config <path>` overrides the config path; `--mark` takes `[--was <marker>]`; `--item`/`--item-raw`/`--item-kind`/`--mark` are tasks-repo only (a github-project board is published by `ledger.sh publish` as an issue comment). A fetcher: stdout at exit 0, or the reason on stderr at non-zero (not a hook — a helper) |
| 📒 `ledger.sh` | `/hef.orchestrate`, `session-launch.sh` | The machine-readable state of one board item — `<git-common-dir>/hefesto/ledger/<id>.json`, shared by every worktree, never committed, written only here: `dir` (print the ledger directory), `branches [--configured]` (the resolved branch model — integration, protected, environments, final — as JSON, read-only; every other script asks here), `where <id>` (which environments contain the entry's branch: yes / no / unknown), `init`, `claim` (exclusive; a third attempt stalls), `advance` (forward-only), `verdict` (a review by the author's session is refused), `block`/`unblock` (a `human:*` block clears only on artifact evidence: `## Reviewed`, no clarification markers, branch merged into `main`, or a person at a TTY), `run` (records cost, releases the owner), `record`, `show`, `list`, `init … --item-kind feature|incident|vulnerability` and `record --item-kind` (an incident or vulnerability fix gets one extra REQUIRED verifier gate — a missing or SKIPPED one is recorded as FAIL by the launcher), `handoff <id> --pr <url> [--branch <b>]` (a hand-run item into the release queue in one call: run, PR, branch, worktree, `pr`, `human:merge`; refuses an owned or blocked entry, a phase already past `pr`, `main`, a non-PR URL), `publish <id>` (opt-in `orchestrate.publish`: the state marker on the board heading via `status-board.sh --mark`, hash verified before and re-taken after so a person's edit is still caught, or one GitHub issue comment; silent when unchanged), `escalate [--record <id>]` (opt-in `orchestrate.escalate_after_hours`: `human:*` blocks older than that, once per block, as `<session>` TAB `ledger <id> blocked_on <kind> <path>` — the PR for a merge, the spec for a clarification, the item for an intake — ≤200 characters), `next` (`--stage plan|build|deploy`: what has no spec yet, what is ready to build, or a PR to babysit — even while it waits on `human:merge`, unblocked first, then least recently babysat), `metrics` (the Phase 1 delivery numbers: merge rate, verify-FAIL rate, spend per merged PR, median hours, blocked by kind — `--json` for machines). Every guard mutation-tested (not a hook — a helper) |
| 🚀 `session-launch.sh` | `/hef.orchestrate` | Starts ONE fresh headless session per role — `plan` (`claude -p -w <id>`, spec → plan → fresh-context review → tasks, `--permission-mode default` with `Edit(.specify/**)` so it writes only under `.specify/`, resumes at the first missing artifact on a retry), `implement` (`claude -p -w <id>`, the size-routed `hef.*` pipeline on the item, or `/hef.implement` onward when a plan stage ran first), `verify` (a separate process on the recorded worktree, read-only, never sees the author's transcript) or `deploy` (`/hef.babysit <pr> --once` in the worktree; the launcher sets `human:merge`, `conflict`, `ci` or `human:intake` from its verdict) — with the flags a session may not choose for itself: sandbox + inbound-refuse settings validated first, a tier never a model id, reviewer tier ≥ author tier, `--max-budget-usd` plus a daily total, `--permission-prompts none`, the plugin's own hooks dir appended to every allowlist after the config-or-default list (so a project can add its test command without losing the helpers; no default list admits `gh pr merge`, `gh pr review` or `gh api`); then transcribes the structured result into the ledger. Every launched session runs with `HEFESTO_WORKER=1` (the tripwire `arena-run.sh` refuses on). An `incident` or `vulnerability` item gets a kind rule in the worker prompt (a regression test citing the id first / re-run `/hef.scan` and `--deps`) and one extra REQUIRED verifier gate; a missing or SKIPPED one is recorded as FAIL. Refuses to run from a sandboxed shell. `--dry-run` prints the line and claims nothing (not a hook — a helper) |
| 🗳 `arena-run.sh` | `/hef.plan --via`, `/hef.review --second-opinion` | Runs ONE prompt file through a provider the user declared (`providers` in `.claude/project-status.json`): `claude -p --permission-mode plan`, `codex exec --sandbox read-only` (only `--output-last-message` is relayed), `gemini -p` (no approval flags), `aws bedrock-runtime converse` (second-opinion only — it cannot read the repository). The prompt goes on stdin (or a `file://` messages document), never argv; `timeout -k 10`, default 540 s; `--purpose arena\|review` (default `review`), `--timeout <s>` (positive, never 0); provider names `[a-z0-9_]+` and never a tier name (`sonnet`/`opus`/`fable`/`haiku`), `model`/`region` id-shaped (no leading `-`, no `://`), `max_tokens` a positive integer; empty output is a failure. `--check` lists each provider ok / missing (install hint). Refuses inside a launched worker (`HEFESTO_WORKER=1`) and from a sandboxed shell; reads no key — auth is each CLI's own (not a hook — a helper) |
| 👀 `pr-watch.sh` | `/hef.babysit` | A fetcher over `gh` + `jq` for ONE pull request: `--check`, `resolve` (refuses closed, head = `main`, head = base, a wrong or stale checkout; adds `"push"`: false for any other protected head — a promotion PR is watched, never fixed), `checks` (state from the check buckets — `cancel` is a failure; `--wait` blocks in `gh pr checks --watch` so CI costs no model turns; `--after <sha>` waits for a pushed sha to register a check), `failed-log`, `threads` (every body HTML-comment-stripped and nonce-delimited; the babysitter's own answers skipped), `reply`/`comment` (marker appended, `gitleaks`-scanned when present), `state` (verdict `mergeable|conflict|checks|review|pending|closed`), `ledger-id`, `in-diff` (refuses CI configuration and anything outside the PR's diff), `fixes`. Has no merge, approve, auto-merge, force-push or thread-resolve code path — asserted statically by the smoke suite (not a hook — a helper) |

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

Fifteen hooks enforce quality automatically — and they ship with the plugin, so there is nothing to register:

- 🔍 **Pre-commit** — secrets detection (gitleaks) + language-specific linting blocks the commit on errors
- 🔒 **File protection** — writes to `.env`, `*.key`, `*.pem`, credentials, `secrets/` directories and `.git/` internals are blocked
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
- 🔗 **Spec-cite probe** — a test that cites an `FR-NNN`, edited outside an implement phase, names the spec that declares it (advisory, once a minute per file)
- 🔀 **Merge-tree probe** — a branch that would conflict with its base, or has drifted far behind it, is told so while the diff is still small
- 📏 **Complexity as a delta** — where `lizard` is installed, a change may not make a file's functions longer or more complex than the limits; existing debt is visible, not blocking

The **boundary** under all of this is OS sandboxing, not string matching: a Bash deny rule can be composed around (`sh -c`, an absolute binary path — Claude Code's own docs say so), and the destructive-command hook documents that limit in its header. Enable `/sandbox` (see `docs/install.md`); the hooks catch the careless path, the sandbox catches the determined one.

The `quality-guardian` agent validates before commit/PR/merge with secrets scanning, SAST, supply chain checks, SOLID architectural analysis, performance validation, and **Iron Law enforcement**.

### 🔐 Security Posture

The framework implements layered defenses against OWASP LLM vulnerabilities:

| Layer | Mechanism | Covers |
|-------|-----------|--------|
| **Boundary** | OS sandbox | `/sandbox` — what the string-match hooks cannot promise |
| **Enforcement** | Hooks | Sensitive file blocking, destructive-command denials, secrets detection, pre-commit quality |
| **Guidance** | Rules | OWASP LLM + Agentic Top 10, code quality, SOLID principles |
| **Analysis** | Skills & Agents | Built-in `/security-review`, `/hef.scan`, forensic investigation, the `mcp-security` vetting checklist, quality gates |
| **Efficacy** | Iron Laws | Verification before completion (rule + `TaskCompleted` hook), systematic-debugging |

MCP servers follow strict security posture — OAuth 2.1 for production, least privilege, input validation, and human-in-the-loop for high-impact actions.

---

