# Changelog

All notable changes to Hefesto will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Versioning

This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) **from 4.5.0
onward**: the next change that breaks an existing install — a renamed command, a moved path,
a permission rule that must be edited — will be a **major** bump.

It has not always. 4.5.0 itself renamed `/context` and moved the helper path under a *minor*
bump, which semver does not permit. Saying so here is more useful than pretending otherwise;
the breakage is flagged inline in that entry.

Releases before 4.5.0 were never tagged. `v4.4.0` was applied retroactively to `6b02e5d`, the
tip of `main` when 4.4.0 was current. Earlier versions have no identifiable release commit and
are not tagged.

## Releasing

Six declarations of the version are bumped **by hand**, and `tests/smoke.sh` fails if they
disagree — that check exists because nothing else would notice a half-bumped release:

1. `.claude-plugin/plugin.json` → `version`
2. `.claude-plugin/marketplace.json` → `metadata.version` **and** `plugins[0].version`
3. `README.md` → the title and the **Framework Version** footer
4. `.claude/CLAUDE.md` → the title
5. Write the entry here, dated.
6. `tests/smoke.sh` (and `SMOKE_LIVE=1` if you are logged in — it is the only check that
   drives the plugin end to end).
7. Tag it: `git tag -a vX.Y.Z && git push origin vX.Y.Z`, then cut a GitHub Release from the
   entry above.

## [6.1.0] - 2026-09-22

**Tier 1 of the 2026-09 harness review: the traceability chain gets its last link, the review agents
get commands, and tests can no longer shrink to go green.** Additive — no command renamed, no path
moved, no permission rule to edit; 6.0.0 installs pick this up with `git pull`. Every item traces to
`reports/14` (the review) and to `.specify/specs/harness-review-tiers/`.

### Added

- **`/speckit.verify`** — the post-implementation gate. `speckit-helper.sh req-coverage` maps every
  `FR-NNN` in `spec.md` to the test files that cite it (marker, `describe` title, or comment; the
  match is lexical on purpose) and exits non-zero on an `UNCOVERED` requirement or an `UNKNOWN` id;
  the command then runs `code-reviewer` stage 1 on the diff. Before this, the implement report's
  "coverage mapping" was prose the model wrote about its own work — exactly what the Iron Law says
  is not evidence. `/speckit.analyze` mapped FR → tasks *before* code existed; nothing mapped
  FR → tests after.
- **`/hef.review`** and **`/hef.pr`** — `code-reviewer` and `review-coordinator` were reachable by no
  command; the documented chain `implement → code-reviewer → quality-guardian → review-coordinator`
  had no entry point for its first link. `/hef.pr` never merges and carries the untrusted-input rule.
- **`implement-phase-test-guard.sh`** (PreToolUse on `Bash` and `Edit|Write`). While
  `/speckit.implement` is active (`.specify/.implement-in-progress`, set/cleared by the new helper
  trio `implement-phase-{start,end,status}`), an edit that leaves a test file with fewer assertions,
  a whole-file overwrite of an existing test, or an `rm` of a test file is blocked. Snapshot-update
  flags (`jest -u`, `pytest --snapshot-update`, `UPDATE_SNAPSHOTS=1`…) are blocked regardless of
  phase; `CLAUDE_ALLOW_SNAPSHOT_UPDATE=1` bypasses visibly. Why a hook: TDD *instructions* without a
  mechanism made agent regressions worse in a controlled study (arXiv 2603.17973), and the
  documented failure mode is an agent deleting the test it cannot pass.
- **`session-start-context.sh`** (SessionStart) and **`precompact-progress.sh`** (PreCompact) — the
  session-start ritual and the progress checkpoint that `context-management.md` asked the model to
  perform by hand, performed by hooks instead. The checkpoint lands in `~/.cache/hefesto/progress/`,
  never in the repo.
- **`audit-config-change.sh`** (ConfigChange) — announces a settings rewrite mid-session, the
  escalation path a compromised skill or plugin would take.
- `quality-guardian` and the `quality-tooling` skill: the AI-code defect profile — new-duplication
  baseline (`jscpd`), dead code (`knip`/`vulture`/`deadcode`), error-swallowing lint, patch coverage
  (`diff-cover`) — as delta gates. The measured failure modes of agent code are duplication, dead
  code, swallowed errors, and over-mocking, not complexity.
- `test-specialist`: a **mock budget** — named fakes at I/O boundaries only, mock-only assertions
  flagged, and every spec test cites its FR id.
- `mcp-security` skill: a vetting checklist for third-party **skills, plugins, and agents** (dynamic
  `` !` `` blocks, permission grabs, hooks, pinning).
- `docs/install.md`: how to turn on `/sandbox`, and why the string-matching hooks are not the
  boundary.

### Changed

- `llm-security.md` now maps to the OWASP GenAI LLM Top 10 (2026) and the Top 10 for Agentic
  Applications (Goal Hijack, Tool Misuse, Agentic Supply Chain, Unexpected Code Execution, Memory
  Poisoning), and states the sandbox-is-the-boundary rule.
- `/hef.pr-summary`, `/speckit.fix`, and `review-coordinator` treat fetched issue/PR/commit text as
  delimited data, never instructions.
- `code-reviewer`: evidence over assertion; flag only correctness, security, and requirement gaps.
- `/speckit.implement` arms the test guard in pre-flight, tells every test to cite its FR, runs
  `req-coverage` in the final gate, and points at `/speckit.verify`.

## [6.0.0] - 2026-08-19

### Changed - BREAKING

- **Renamed the project to Hefesto.** The plugin name, and therefore the command and skill
  namespace, is now `hefesto`. `ai-development-framework:speckit-workflow` becomes
  `hefesto:speckit-workflow`; the install id becomes `hefesto@hefesto`.
- **The `adf.*` command prefix is now `hef.*`** — `/adf.agent` becomes `/hef.agent`, and the same
  for `context`, `pr-summary`, `quality`, `security-scan`, and `sync`. The `speckit.*` pipeline is
  unchanged.
- The marketplace id is now `hefesto`.

Major per the versioning policy above: this breaks existing installs. Settings hold literal
`ai-development-framework@ai-development-framework` and `extraKnownMarketplaces` keys, and after
the rename they resolve to nothing — the plugin does not error, it silently stops loading.
Uninstall the old plugin and remove the old marketplace BEFORE pulling, then reinstall under the
new id. Do it in every config profile, `CLAUDE_CONFIG_DIR` ones included.

### Added

- Brand identity under `docs/brand/`: icon and banner cuts in light, dark, and mono, the brief
  that generated them, and brand notes.
- A centred README header carrying the banner, plus badges whose version reads
  `.claude-plugin/plugin.json` directly rather than being bumped by hand.

## [5.2.0] - 2026-07-17

**The FxCube #314 field report is fully delivered, and every defect found building it is fixed.**
5.1.0 shipped feature A (resilience). This ships B (overload) and C (multi-repo), plus five defects
surfaced while building them. Seven issues, all measured against the shipped file, none reasoned about.

Minor, not major: the new capabilities are additive (`args.repos`, `args.maxConcurrency`,
`args.sequential`), single-repo runs behave as before, and only *failure paths* change — no command is
renamed, no path moves, no permission rule needs editing.

### Added

- **Multi-repo support** (#30). A `repos[]` map — `{path, testCommand, testCommandStatus, lintCommand}`,
  detected by the loader or overridden with `args.repos` — routes each task to the repo whose path
  prefixes its files (longest-prefix, with a `+ '/'` boundary so `apple/` is not a match for a repo
  `app`). The motivating case now runs: a monorepo whose spec lives in `tasks/` and whose code lives in
  `operations_api/` (pytest) and `cube_ui/` (vitest). A cross-repo task is rejected naming both repos; a
  file matching no repo is logged, not silently dropped; a no-files task goes to the first listed repo
  (operator-ordered, never positional-by-path-length); the phase gate runs once per repo the phase
  touched. **Single-repo is a `repos[]` of length 1 — one code path, unchanged behaviour.**
- **Concurrency control** (#29). `args.maxConcurrency` (default **4**) caps how many agents run at once,
  via a global semaphore at the one choke point every spawn passes — the harness's `min(16, cores-2)`
  is a CPU bound that says nothing about a shared API. `args.sequential` forces 1. An adaptive throttle
  drops to 1 after two terminal agent failures. Measured before: 2 tasks ⇒ peak 6, self-inflicting
  sustained 429/529 (one verifier hit 529 twenty-one times). After: peak 4.

### Changed

- **Fan-out amplitude cut from `2N+1` to `1` full-suite run per phase** (#29, #38). The regression lens
  and every implementer used to run the whole suite; now each runs only the task's own test and the
  phase gate owns whole-suite regression, running it once per repo. Measured on a 3-task phase: full-
  suite run instructions 4 → 1.
- **The Iron Law's evidence is now read** (#32). `redConfirmed`/`greenConfirmed` were collected,
  rendered into the verifier's prompt, and consulted by no code — so an implementer admitting
  `redConfirmed:false` was accepted like one that ran the full cycle. `tddStatus` is now required and
  enforced; a task with no testable behaviour must declare `not-applicable` with a reason, which the
  test-integrity lens is told to refute.
- **Every verifier lens must report** (#28). Two null verdicts used to silently shrink the quorum,
  accepting a task on a single lens; the lenses are diverse, not redundant, so the dimension that would
  have caught the defect could be the one that went quiet. A silent lens is now a rejection, naming
  which lens. There is no `.filter(Boolean)` on a `parallel()` result left in the file.
- `.claude/rules/code-quality.md`: the 500-line file limit now counts **code, not comments**, and
  `workflows/speckit-workflow.js` is the one documented exemption — the Workflow harness runs the script
  as a function body, so a static `import` is a compile error and the limit's remedy ("split the file")
  does not exist there.

### Fixed

- **`testCommand: ""` conflated "no tests exist" with "detection failed"** (#31), silently disabling
  every verification gate on a detection failure — and *this repo was that case*, so the workflow could
  not run on its own monorepo. The status is now a schema-forced tri-state (`detected`/`none-exist`/
  `undetectable`); `undetectable` halts at load; the gate agent is told to *refute* a false `none-exist`
  claim, because asking a model nicely is not a mechanism.
- **Helpers returned sentinels at exit 0** (#27). `speckit-helper.sh spec` printed `NO_SPEC` and exited
  0, so a command told to load the spec loaded that string — the bug that cost the 5.1.0 run an hour.
  Subcommands are now explicitly fetchers (absence ⇒ stderr + non-zero, nothing on stdout) or predicates
  (answer in both the string and the exit code). This surfaced a second instance: `rtk-available` also
  exited 0 always, so `quality-tooling.md`'s documented `&& rtk … || …` guard never guarded.

## [5.1.0] - 2026-07-16

**`speckit-workflow` no longer loses work to a single transient agent failure — and no longer
reports a perfect score when it does.**

Driven by a field report from a real two-repo run (`reports/12-…`, FxCube #314). That report named
three findings; this release ships **one** of them. The other two are #29 and #30, split out after
review found the combined plan carried ~18 defects concentrated in the multi-repo design.

Every claim below was measured against the shipped file, not reasoned about.

### Fixed

- **A crashed `[P]` implementer no longer vanishes.** `parallel()` converts a thrown implementer to
  `null`, and `.filter(Boolean)` then *erased the task*: it landed in neither `accepted` nor
  `rejected`, the halt could not see it, and the run returned `{"completed":1,"total":1}` — a
  **perfect score for a phase where the task never ran**. It now becomes an explicit rejection.
- **A crashed sequential implementer no longer kills the run.** Same root cause, opposite symptom:
  the sequential path had no `parallel()` wrapper, so the throw propagated out of the script and a
  20-minute run died. *The sequential path screamed; the parallel path lied.*
- **A non-Error throw no longer kills the error handler.** `throw null` made `e.message` inside the
  `catch` raise a `TypeError` that escaped — the handler became the failure, on exactly the scenario
  the retry exists to survive. Now `e?.message ?? String(e)`.
- **A dead phase gate now halts.** *This one was introduced by the retry fix itself and caught at
  review.* `if (gate && !gate.passed)` let a `null` straight through once the gate's throw became a
  null, so the phase silently skipped its gate. Measured: both gates dead ⇒
  `{"completed":2,"total":2}`, six gate invocations, **zero confirmations**, phase 2 building on
  unverified work — strictly worse than the loud crash it replaced. Absence of confirmation is not
  confirmation. A project that *configures* no gate still correctly passes: it returns an object,
  and only a dead agent returns null.
- **A run whose `tasks.md` write died no longer reports clean.** That call discarded its result, so a
  dead writer produced `{"completed":3,"total":3}` with no checkbox written — a green run whose only
  persisted artifact never happened, and whose next invocation re-implements everything. It now halts
  with a reason that says the work *is* done, so the operator does not re-run it.
- **The ledger can no longer be fooled by a duplicate task id.** Ids come from a model parsing
  `tasks.md` and nothing enforces uniqueness; keying on them let a later duplicate count as
  "attempted" and under-report `notAttempted` (measured: `balance 1 vs total 2` — a task vanished).
  Identity is now positional. This file already refused to trust the model-written `[P]` marker; ids
  earn the same distrust.
- **A terminal API error is no longer retried.** A `null` means the harness already exhausted its own
  backoff; retrying pours load onto an API that is refusing us. Only a *throw* is retried, bounded at
  3 attempts.

### Changed

- **Halts now report the full ledger** — `total`, `accepted`, `rejected`, `notAttempted`. Previously
  a halt carried no `total` at all, so "how much got done?" was unanswerable exactly when it mattered.
- **The success return additionally gains `accepted`/`rejected`/`notAttempted`** — additive, but it is
  a shape change on the success path, declared rather than discovered. `total`'s *value* is unchanged.
- `.claude/rules/code-quality.md`: the 500-line file limit now counts **code**, not raw lines. It sits
  among complexity limits and comments add no complexity — a raw cap would have deleted documentation
  and kept the complexity. If the *code* exceeds 500, split the file.

### Added

- **`tests/workflow.test.js`** — the workflow's first behaviour tests. Drives the **shipped file** by
  rewriting `export const meta` and wrapping it in `new Function` with stub agents, so it tests the
  artifact that ships rather than a copy of its logic. `node --test`, zero-install: no `package.json`,
  no lockfile, no `node_modules`. 18 tests; every one was **red against the unmodified file first**,
  and every mutation named in the spec was executed to prove the test can fail.
- **Six smoke guards** for shape invariants a behaviour test cannot reach, each mutation-tested. Two
  details worth keeping: the unwrapped-spawn guard counts **occurrences**, not lines (`grep -c` passes
  two calls smuggled onto one line — verified), and the null-gate guard anchors both halves to
  `^if`, without which commenting *out* the fix reads as green.
- CI runs `node --test` with no `setup-node` step.

### Known issues

Six defects were found while building this and filed rather than folded in:

- **#27** — `speckit-helper` returns `NO_SPEC` at **exit 0**, so a command cannot distinguish a missing
  spec from a real one. Bit this very run.
- **#28** — two null verdicts silently shrink the verifier quorum, accepting a task on a single lens.
- **#29** — **B**: fan-out amplitude self-inflicts 429/529 (2 tasks ⇒ 12 agents, peak 6, three full
  suites where one would do).
- **#30** — **C**: the single-repo `projectRoot` assumption blocks monorepos.
- **#31** — `testCommand: ""` conflates "no tests exist" with "detection failed". **This repo is that
  case**: running `speckit-workflow` on the framework itself silently disables every verification gate
  and reports a clean run.
- **#32** — `redConfirmed`/`greenConfirmed` are collected, rendered into the verifier's prompt, and
  **never read by any code**. The Iron Law's own mechanical evidence is discarded.

## [5.0.0] - 2026-07-13

**Every command is renamed.** This is the first release under the versioning policy stated
above, and it is a major bump because it breaks every command a user types.

### Changed
- **⚠️ BREAKING — all commands are namespaced.** The five bare-named commands now carry an
  `adf.` prefix. The `speckit.*` pipeline is unchanged: it was already namespaced.

  | Was | Now |
  |---|---|
  | `/project-context` | `/adf.context` |
  | `/quality` | `/adf.quality` |
  | `/agent` | `/adf.agent` |
  | `/pr-summary` | `/adf.pr-summary` |
  | `/security-scan` | `/adf.security-scan` |

  This closes a class of bug rather than an instance of one. A command whose name a Claude
  Code **built-in** already owns is unreachable — typing the bare name gets the built-in,
  every time. `/context` shipped that way and was dead for every user for four releases (see
  4.5.0); it only *looked* fine because the repo's own project-scope copy shadowed the
  built-in while dogfooding.

  The previous guard was a hand-maintained list of built-in names, which protects against the
  past and not the future: the day Claude Code ships a `/quality`, that command goes silently
  unreachable and a stale list says nothing. **No built-in slash command contains a dot**, so
  requiring every command to be namespaced makes the collision impossible by construction —
  and deletes the list. The smoke test now enforces the rule structurally.

  Verified end to end, not assumed: a dotted command name loads and runs through a real model
  session.

## [4.5.0] - 2026-07-13

4.4.0 shipped the plugin. This release makes it *work*.

Installing 4.4.0 exactly as `SETUP.md` prescribed produced a plugin that reported
`✔ enabled` and in which **every helper-backed command was dead** — `/context`, `/quality`,
`/pr-summary`, and the entire `/speckit.*` pipeline. Three separate bugs, all traced to one
root cause: the plugin payload lived at `.claude/`, which is also where Claude Code looks
for *project-scope* config. A project-scope command outranks both plugins and built-ins, so
while working in this repository the commands resolved to the repo's own copies and behaved
correctly. **The framework was never once dogfooded as a plugin**, and every one of these
bugs is invisible from inside the repo and fatal outside it.

Each was found by running the thing, not by reading it. None would have been caught by a
linter, a schema check, or `claude plugin validate --strict` — all three pass on a
completely broken plugin.

### Fixed
- **Commands could not invoke the plugin's own helper script.** Every one of the 54 helper
  calls across 15 commands sat in a `` !`…` `` pre-execution block naming
  `${CLAUDE_PLUGIN_ROOT}`. A `!` block is permission-checked **before** that variable is
  substituted, so the matcher sees a literal `${…}`, cannot predict what it expands to, and
  rejects the command with `Contains expansion`. **No allowlist entry can match such a
  pattern**, and `allowed-tools:` frontmatter does not change the outcome. This was verified
  against the live permission checker rather than inferred: `${CLAUDE_SKILL_DIR}` fails
  identically; only `${CLAUDE_PROJECT_DIR}` is substituted pre-check, and it points at the
  user's project, not the plugin — useless for locating a bundled script. What *does* work
  is that `${CLAUDE_PLUGIN_ROOT}` is substituted in ordinary body text, so the commands now
  hand the model an already-literal path to run with the Bash tool. Note the regression this
  replaced: `aa32e83` had *fixed* a real bug (commands hardcoding `~/.claude/hooks/…`,
  correct under the old stow install, wrong under a plugin) and traded it for this one.
- **`/context` was unreachable behind a Claude Code built-in.** Claude Code ships its own
  `/context` (a token-usage readout), and a built-in wins over a plugin command of the same
  name — so no user could ever reach this one by typing it. It only appeared to work from
  inside this repo, where the project-scope copy shadowed the built-in. **Renamed to
  `/project-context`.**
- **The anti-regression notes destroyed themselves.** The note added to each command
  explaining why its calls cannot live in a `!` block was prose inside skill content — and
  skill content is substituted. It spelled the plugin-root variable with a `$` and braces,
  so the harness replaced it with a path and the warning became gibberish about a filesystem
  location. The note was eaten by the exact mechanism it documented.
- **The permission rule in `SETUP.md` never matched.** `${CLAUDE_PLUGIN_ROOT}` expands *with*
  a trailing slash, so the helper reaches the permission matcher as
  `…/.claude-framework//hooks/…`. The matcher compares literally and does **not** normalise
  `//`, so the single-slash rule silently failed to match and every helper call prompted —
  which, in a non-interactive context, means denied, which means the command aborts with no
  output at all. Both slash forms are now documented, and the doubled one is not a typo.

### Added
- **`tests/smoke.sh` — the first test of the plugin's own components**, and `.github/workflows/smoke.yml`
  to gate CI. Four consecutive releases shipped packaging bugs; nothing would have caught any
  of them, because they are *load-and-run* failures, not shape failures. Tier 1 needs no auth
  and no tokens: it asserts that every path `plugin.json` declares exists, that every hook is
  shipped **and executable**, that no command invokes the helper from a `!` block, that no
  command is named after a Claude Code built-in, that no payload sits under `.claude/`, that
  the anti-regression notes survive substitution, and that every helper subcommand a command
  calls is actually implemented. Tier 2 (`SMOKE_LIVE=1`) installs the plugin into a throwaway
  `CLAUDE_CONFIG_DIR` and executes every helper invocation the commands hand the model,
  substituted exactly as the harness substitutes it.
- **Every check is mutation-tested.** A check that cannot fail is decoration, so each was
  verified to turn the suite red when the bug it guards is reintroduced. The suite earned
  this on its first real use: during the payload relocation it caught `hooks.json` still
  pointing at the old location — a rewrite regex had silently matched nothing, leaving all
  **eight hooks declared but not shipped** while the plugin still installed and still
  reported `enabled`.

### Changed
- **⚠️ BREAKING — the plugin payload moved out of `.claude/`.** `commands/`, `agents/`,
  `skills/`, `hooks/` and `workflows/` now live at the repository root. `.claude/` keeps only
  what is genuinely this repo's own project config (`CLAUDE.md`, `rules/`). This is the root-
  cause fix: the payload can no longer shadow itself, so the commands finally behave the same
  here as in a real install.

  **The helper path changes**, and the permission rule in `~/.claude/settings.json` must be
  updated to match or every helper call will prompt:

  ```jsonc
  "allow": [
    "Bash($HOME/.claude-framework//hooks/speckit-helper.sh:*)",
    "Bash($HOME/.claude-framework/hooks/speckit-helper.sh:*)"
  ]
  ```
- **⚠️ BREAKING — `/context` is renamed `/project-context`.** Muscle memory and any scripts or
  docs referencing the old name must be updated. `/context` now unambiguously means Claude
  Code's built-in.
- `README.md` corrected: it advertised the pre-fix single-slash permission rule and described
  the helper as running from a `!` pre-flight block — the one thing that provably does not work.

### Known limitation
- **No test can drive an actual slash-command invocation.** Plugin commands do not exist
  outside an interactive session: `claude -p "/context"` silently resolves to the *built-in*,
  and `/pr-summary` and `/ai-development-framework:project-context` both return
  `Unknown command`. An assertion on `claude -p` would therefore pass against a completely
  broken plugin. **This is why the 4.4.0 bugs survived: the real invocation cannot be
  scripted, so nobody ever ran it.** The human verification step in `SETUP.md` — restart, run
  `/project-context`, confirm it prints — remains the only proof that an install works.

## [4.4.0] - 2026-07-12

Covers everything unreleased since 4.3.0. The repository carries no git tags, so the
`v4.3.1` label in commit `153ec98` was a working marker rather than a cut release; its
contents are folded in here. A minor bump is the correct level — this window shipped a new
agent, a new hook, a new rule, and a new skill.

### Added
- **`speckit-workflow` — the spec-kit task list as a deterministic Workflow** (`.claude/workflows/speckit-workflow.js`). Named distinctly from the `/speckit.implement` **command**: both execute `tasks.md`, and a shared name invited invoking the wrong one. Moves the orchestration out of model discretion and into code: phase order is a barrier the script enforces (spec-kit declares Phase N+1 blocked by Phase N, and a model can talk itself into skipping ahead); every task is verified by three agents that did not write it, through distinct lenses (one reads the test diff hunting for a weakened assertion, one checks the requirement rather than the test, one runs the full suite itself), with any single refutation blocking the task; and `tasks.md` is written once at the end by one agent, because parallel implementers ticking their own checkboxes would race on the file. Testing surfaced a design bug before the first run: `[P]` does not imply disjoint files — the marker is model-written and nothing enforces it — so tasks are batched by *actual* file disjointness rather than by trusting the marker.
- **The full pipeline is deliberately NOT one workflow.** A workflow cannot take mid-run input, but `/speckit.clarify` asks the user questions, `/speckit.review` is a sign-off, and `/speckit.checklist` is a gate. Encoding the whole pipeline would silently delete every human gate and turn spec-*driven* development into fire-and-forget. The workflow starts where human sign-off ends.
- **The framework is now a Claude Code plugin.** `.claude-plugin/plugin.json` bundles skills, commands, agents, hooks, workflows, and the MCP server into one unit, and `.claude-plugin/marketplace.json` makes it **installable**: `claude plugin install` resolves only through a marketplace, so without that manifest the sole install path was the session-scoped `--plugin-dir` flag — i.e. there was no persistent install at all. The flow is `claude plugin marketplace add <clone>` then `claude plugin install ai-development-framework@ai-development-framework`, which writes `enabledPlugins` to `~/.claude/settings.json` and applies everywhere. Because the marketplace source is a directory, the plugin is read from the clone in place, so updating is a `git pull`. **This ships the hooks**, eliminating the hand-written `settings.json` that was the framework's single largest installation friction — and which meant `plan-phase-write-block.sh` had been dead for every user but the author, since the README never told anyone to register it. `claude plugin validate --strict` passes, and it checks the manifest, the skill/agent frontmatter, *and* `hooks.json` against the real schema, so a broken component now fails loudly instead of silently not loading. Note: do not stow the dotfiles *and* install the plugin — that registers everything twice.
- **`verify-before-task-complete.sh` — a `TaskCompleted` hook that makes the Verification Iron Law mechanical.** Exit 2 blocks a task from being marked complete while the test suite fails, and feeds the failure back to the agent. Every other quality mechanism in the framework was advisory: a rule the model can rationalize past, or a `Stop` hook that prints a reminder and exits 0. This is the first that cannot be talked around. It skips when there is no test runner; when the runner is on `PATH` but cannot execute (a version-manager shim failing at exec time is a *tooling* fault, not a test failure — blocking on that would be a false positive, and a gate that cries wolf gets disabled); and when no source files changed. Results are cached against a hash of the working tree, so a tree already proven green is not re-run. `CLAUDE_SKIP_VERIFY_GATE=1` opts out deliberately and visibly.
- **`task-effort-estimation` skill**: Deterministic change sizing built on Pfeiffer's Contribution Complexity algorithm, computed from git metadata alone (lines added/removed, hunks, modified methods, file count, change kinds) with exponential `i^i` histogram weighting, so one high-complexity file outweighs a hundred trivial ones. Zero dependencies — `scc`, `lizard`, `git-effort`, and the Epoch MCP server are optional enhancers behind `command -v` guards. Runs in **Actual** mode (measure a real diff) or **Projected** mode (size unimplemented work with the projection stated for review).
- **Non-Local Context Check** (within the above): the skill's headline output is a risk flag, not an hour count. Effort under AI assistance is bimodal — up to 78% of high-complexity *isolated* features land under a quarter of expected effort, while ~22% of *low*-complexity tasks needing non-local context exceed 180%. The check catches the small diff with high coupling, which is the shape of work a naive estimate waves through. The skill refuses to emit hours until `.claude/effort-calibration.json` maps observed scores to recorded durations.
- **`repo-scout` agent**: The framework's first one-shot subagent. Answers a single targeted question about a repository *other than* the current project and returns only a citation-backed `<repo-scout-digest>`, discarding its working context. Read-only tool allowlist by construction.
- **One-Shot Subagents doctrine** (`rules/agent-workflow.md`): when to dispatch, the non-negotiable design rules (narrow trigger, tool allowlist, no side effects, output contract, model tier, stop-early budget), and the common anti-patterns.
- **`rules/context-management.md`**: the 40% "Dumb Zone" context threshold, the Document & Clear pattern, compact-context priorities, and context scaling by project size. Adds RTK CLI-output compression as an auto-detected, never-required optimization (60–90% token reduction on common dev commands).
- **`plan-phase-write-block.sh` hook**: RIPER-style mechanical enforcement that blocks `Edit`/`Write` outside `.specify/` while `/speckit.plan` is active, upgrading the pipeline from "trust the agent to respect phases" to a hard gate. Reads stay unrestricted so the Truth Map phase still works.
- **Surgical Changes rule** (`rules/code-quality.md`): every changed line must trace to the user's request; forbids opportunistic cleanup of pre-existing dead code and unrelated reformatting. Reviewer attention is the scarce resource in AI-assisted workflows.
- **Research corpus** (`reports/`): eleven single-subject files covering context engineering, CLAUDE.md authoring, agent topology, the AI protocol stack, codebase retrieval, security/DevSecOps, quality gates, project organization, Fabric, and deterministic effort estimation. The five original source documents were carried in `reports/sources/` during the restructure and dropped once the corpus superseded them; they remain in git history.
- **Framework stack diagram** and a Request Flow & Stack Composition section in the README, tracing a single SDD request through all five layers.

### Changed
- **Skills modernized to current frontmatter.** `context: fork` + `agent: Explore` on `task-effort-estimation` and `performance-audit` — both produce a bounded report, so the main conversation now receives the conclusion instead of the whole git-diff/profiling trawl. Deliberately **not** applied to `systematic-debugging`: it is a methodology the main agent follows *through to the fix*, and the evidence gathered in phases 1–3 is exactly what phase 4 edits against — forking would discard it at the moment it becomes useful. Added `disallowed-tools` to the two read-only skills: the framework had been declaring `allowed-tools` in the belief that it restricted them, but it only pre-grants permission and prevents nothing, so the "read-only" skills could always have called `Write`. Added `when_to_use` trigger phrases to all three.
- **Parallelism guidance rewritten around three primitives** — subagents, Agent Teams, and the deterministic `Workflow` script — with an explicit note that none supersedes the others. Subagents are the default; teams are for work where agents must *challenge each other*.
- **`reports/` restructured into non-overlapping subjects.** The three research reports overlapped heavily with each other and with `.claude/rules/`, which had already harvested most of their conclusions. The Fabric report also duplicated itself — its §4 "Integration Opportunities" and §8 "Practical Usage Guide" covered the same seven areas with the same examples (merged: 573 → 315 lines). `reports/` is now the **"why" layer** and `rules/` stays the **"what" layer**: 16 `Codified in` pointers reference the enforcing rule instead of restating it, so no text lives in two places. Net 1,357 → 1,203 lines across the topic files, losing nothing.
- `/speckit.brainstorm` now recommends `/clear` before `/speckit.specify`, so the spec is written in fresh context with the design document as the sole source of truth.
- `docs/` removed; research documents now live in `reports/`.
- `rules/git-workflow.md`: the `Co-Authored-By` trailer no longer hardcodes a model version — hardcoding guaranteed it went stale on every model change.
- README and `CLAUDE.md` refreshed: agent count 5 → 6, skill count 6 → 7, models updated to Opus 4.8 / Sonnet 5 / Haiku 4.5.

### Fixed
- **The plugin shipped everything except the workflow.** `.claude-plugin/plugin.json` declared skills, commands, agents, hooks, and MCP — but had no `workflows` key, so `claude plugin install` delivered every component *except* the workflow, the headline feature of the same release. Added `"workflows": "./.claude/workflows/"`. Verified empirically rather than from the docs, which do not currently list the key: the validator resolves it as a path (a missing directory fails with `workflows[0]: Path not found`), and a plugin-shipped workflow does load — under a **namespaced** name. It runs as `ai-development-framework:speckit-workflow`; the bare name does not resolve (`Workflow "speckit-workflow" not found`). The README said `/speckit-implement` and was wrong on both counts.
- **Every spec-kit command's pre-flight broke under a plugin install.** The plugin-packaging change converted `hooks.json` to `${CLAUDE_PLUGIN_ROOT}` but left 55 call sites across 15 command files hard-coding `~/.claude/hooks/speckit-helper.sh`. Under a plugin the framework lives in the plugin directory, not `~/.claude/`, so every pre-flight pointed at a file that was not there — and a denied or failing pre-flight aborts the entire slash command **silently**, producing no output at all. All 55 now invoke `${CLAUDE_PLUGIN_ROOT}/.claude/hooks/speckit-helper.sh`, which Claude Code substitutes inline throughout command content (verified: the substitution reaches fenced `bash` blocks in the body, not just `` !`…` `` pre-flight blocks, so the agent-executed snippets resolve too). The legacy stow install is unaffected: it sources its commands from the separate dotfiles repository, whose copies keep the `~/` paths — but for that reason **do not sync these command files verbatim into dotfiles**, or stow's pre-flights will break in the mirror image of this bug.
- **The `speckit-helper.sh` permission rule in the README no longer matched the command.** Consequence of the path fix, and verified against the permission engine: rules expand `$HOME` but **not** `${CLAUDE_PLUGIN_ROOT}`, and a leading wildcard (`Bash(*/speckit-helper.sh:*)`) does not match either. Plugin users must allowlist the **absolute** helper path inside their plugin install. Documented, along with the diagnostic that matters — a spec-kit command that emits nothing at all is a denied pre-flight, not a hung model. No fallback syntax is available to paper over this: `${CLAUDE_PLUGIN_ROOT:-$HOME}` and every other `${VAR:-default}` form is rejected by the pre-flight parser and silently aborts the command.
- **The framework's own quality gate was a no-op against the framework.** Every check in `quality-before-commit.sh` is gated behind a language manifest (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `pom.xml`). A repo of shell scripts and markdown matches none of them, so the gate never ran on its own 9 shell scripts and 52 markdown files — it shipped a gate it did not run. (Found by accident: a misdirected workflow agent audited this repo instead of its target and reported it.) Added two manifest-free checks on **staged files only**: shell (`bash -n` always, `shellcheck -S error` when installed) and markdown (balanced code fences always — an unclosed fence silently breaks rendering — plus `markdownlint-cli2` when installed). The zero-dependency baseline is deliberate: guarding purely on `command -v shellcheck` would have reproduced the original bug on any machine without it, and a check that only runs where it is already unnecessary is not a check. Verified: the gate now blocks a deliberately broken hook in this repo (exit 2) and passes its clean source (exit 0). A dead-markdown-reference check was prototyped and **rejected** — it produced 98 false positives, because this repo cites files by bare name; a linter that cries wolf gets disabled.
- **Agent Teams documentation was built on removed API.** `rules/agent-workflow.md` documented a 7-step team workflow whose steps 1, 3, and 7 no longer exist: `TeamCreate` and `TeamDelete` were removed in v2.1.178, and the `team_name` parameter on the Agent tool is accepted but **ignored** and deprecated. A team now forms when the first teammate spawns and is cleaned up automatically at session end — there is no setup or teardown step. Rewritten against the current API, with sizing guidance (3–5 teammates, 5–6 tasks each), the adversarial-debate pattern for competing hypotheses, and the `TeammateIdle`/`TaskCreated`/`TaskCompleted` quality-gate hooks.
- **The entire skills layer never loaded.** Claude Code registers a skill only as `.claude/skills/<name>/SKILL.md` — a directory containing `SKILL.md`. The framework shipped seven bare `.claude/skills/*.md` files, which are silently ignored: no warning, no error, no entry in the `/` menu. Both **Iron Law** skills that `code-quality.md` called non-negotiable, and that `quality-guardian` claimed to enforce, had therefore never been executable; agents referencing them by name were improvising the behaviour from surrounding prose. Confirmed empirically — the skills appeared in the `/` menu the moment the directories were created. All surviving skills converted to the `SKILL.md` layout.
- **GitHub MCP server never loaded.** `.claude/mcp.json` is not a path Claude Code reads — it only reads `~/.claude.json` (user scope) and `.mcp.json` at a project root (project scope) — so the file was silently inert and the server has never been active, despite the README advertising it as such. `review-coordinator` has been running without it. The config also carried four independent errors: `"transport"` instead of `"type"` (fails to load), a `/mcp/v1` URL instead of `/mcp` (404), no `Authorization` header (401), and two fields that are not in the schema at all (`"scope"`, which is CLI-only, and `"description"`). Replaced with a correct project-scoped `.mcp.json` at the repo root using `Bearer ${GITHUB_TOKEN}` env-var expansion so no secret is committed; verified loading via `claude mcp list`. The README now documents `claude mcp add --scope user` for consumers' own projects and warns that a server absent from `claude mcp list` is not loaded regardless of how correct its JSON looks.
- **`stop-quality-check.sh` silent exit 141**: the `find | while | head -1` pipeline raced with SIGPIPE under `set -euo pipefail` whenever a match was found. Replaced with process substitution plus `break`.
- **Spurious permission prompts**: normalized every speckit preflight path from `$HOME/.claude/hooks/...` to `~/.claude/hooks/...` to match the Bash allowlist entry.
- **Documentation drift**: `repo-scout` shipped in `c0f873b` but was never documented in the README, which still advertised five agents. The CHANGELOG had recorded nothing since 4.3.0 despite nine intervening commits.

### Removed
- **Four skills that duplicated — and would have shadowed — stronger bundled built-ins.** A project skill overrides a bundled one of the same name, so repairing these would have *replaced* Claude Code's own with weaker versions.
  - `verification-before-completion` → the bundled `/verify` builds and drives the real app instead of settling for a green typecheck. The **Iron Law survives as a rule** in `code-quality.md` (now with a rationalization table): a rule is always in context, whereas a skill loads only when invoked, so the law must bind even when the skill never fires.
  - `security-review` → would have shadowed the bundled `/security-review`. `/security-scan` remains as the fast, diff-only pass.
  - `context-analysis` → the `/context` command already carries the methodology and injects live git data via `` !`command` ``.
  - `spec-template` → unreachable by construction (`user-invocable: false` **and** `disable-model-invocation: true` closes both invocation paths) while `/speckit.specify` instructed the agent to use it. Its Given/When/Then patterns now live in that command.
  Surviving skills are the three with no built-in equivalent: `systematic-debugging`, `task-effort-estimation`, `performance-audit`.
- **`reports/sources/` — the five original research documents.** They were kept through the corpus restructure as a citation trail, but the eleven topic files supersede them and they were the largest thing in the tree (a 340 KB PDF among them). Deleting them costs nothing permanent: they remain in git history at `git show b515e2f:reports/sources/`, which is the same guarantee the directory was providing.
- **`reports/sources/harness-inovation.txt`.** Despite the filename, it is Harness.io (the commercial CI/CD platform) product documentation in Portuguese — Rego policies for Harness pipelines, the Harness MCP server, Harness STO, Backstage annotations. Its transferable ideas are already owned by corpus files 06 (Policy-as-Code/OPA, MCP controls) and 07 (CI shape). The one genuinely novel idea — **contract testing as a spec-drift gate** — was extracted into `07-quality-gates.md` before deletion.
- **voicemode MCP server** and its `mcp__voicemode__converse` permission entry. Removed from user scope via `claude mcp remove voicemode -s user`; `mcpServers` in `~/.claude.json` is now empty. The README no longer lists it as an active integration.

### Notes
- Files under `.claude/` are ignored by a common global gitignore rule (`.claude/`). Existing tracked files are unaffected, but **any new file added under `.claude/` needs `git add -f`** or it is silently dropped.

## [4.3.0] - 2026-03-31

### Added
- **`verification-before-completion` skill**: Evidence-first completion gate with Iron Law ("NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE"), rationalization prevention table, and fresh-evidence requirements. Auto-invoked before task completion.
- **`systematic-debugging` skill**: 4-phase root cause investigation (read errors → reproduce → gather evidence → fix) with Iron Law ("NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST"), defense-in-depth pattern, and anti-pattern guidance.
- **`code-reviewer` agent**: Two-stage pre-PR review specialist. Stage 1 validates spec compliance against plan/spec artifacts. Stage 2 checks SOLID principles, architecture, error handling, security, and naming. Produces structured review report with verdict.
- **`/speckit.brainstorm` command**: Socratic design exploration before specification. Uses a hard gate (no code until design is approved), structured clarifying questions (one per message, multiple-choice preferred), proposes 2-3 approaches with trade-offs, writes a design document, and includes inline self-review. Inspired by obra/superpowers brainstorming skill.
- **`/speckit.fix` command**: Quick-fix bypass for trivial changes (typos, config, style) that skip the full SDD pipeline. Includes triviality gate with explicit criteria to prevent misuse.
- **`/speckit.review` command**: Read-only plan review gate that challenges scope, architecture, design, tests, performance, and constitution compliance before task generation. Slots between `/speckit.plan` and `/speckit.tasks`.
- **`/speckit.baseline` command**: Reverse-engineer specs from existing code for brownfield projects. Analyzes source files, extracts behaviors, generates spec.md with coverage gap analysis and source file references.
- **Development Lifecycle section** in README with three workflow paths: Quick Fix, Standard SDD, and Brownfield
- **The Four Balances** philosophy: security + performance + maintainability + efficacy as framework design principles
- **Iron Law enforcement pattern**: Non-negotiable rules in skills with rationalization prevention tables (inspired by obra/superpowers)

### Enhanced
- **`code-quality.md`**: Added verification-before-completion requirement, security-specific test files recommendation (`*_security_test.*` convention), Iron Law enforcement pattern
- **`quality-tooling.md`**: Added lefthook recommendation as structured hook alternative (YAML, parallel execution, staged-files-only), pre-commit vs pre-push separation strategy, CI/CD best practices (cancel-in-progress, fail-fast:false, screenshot artifacts, Dependabot for github-actions, smart cache keys)
- **`agent-workflow.md`**: Added CLAUDE.md template guidance for cross-cutting change maps, "What NOT to change" guardrails, trust boundary documentation, and security posture statements (patterns from production repos)
- **`speckit-helper.sh`**: Added helper functions for new commands: `check-plan-review`, `detect-existing-code`, `trivial-change-check`
- **`CLAUDE.md`**: Updated agent table to include code-reviewer (5 agents), added speckit.fix/review/baseline to SDD workflow, version bump to v4.3
- **`README.md`**: Major restructure with Development Lifecycle (3 paths), Four Balances table, updated component counts (5 agents, 6 skills, 17 commands), Iron Laws integration

---

## [4.1.0] - 2026-03-30

### Added
- **Pipeline Security Rules** (`pipeline-security.md`): New rules file with managed ASPM service catalog (Snyk, Aikido, Checkmarx, Veracode, Corgea, Cycode), open-source tool reference (Semgrep, OWASP ZAP, Gitleaks, TruffleHog, Knip, deadcode), and strategic selection guide by team size/budget and pipeline tier
- **Java Ecosystem Support**: Full tooling across all quality files — Checkstyle, PMD, SpotBugs, Spotless (pre-commit), Error Prone (compile-time), FindSecBugs, SonarQube
- **Universal Security Tools**: Gitleaks secrets detection, Semgrep cross-language SAST, Syft/Grype SBOM generation, Trivy all-in-one scanning
- **Tiered Validation Strategy**: 3-tier approach in quality-tooling.md — Tier 1 pre-commit (<5s), Tier 2 PR/CI (deep semantic), Tier 3 release (compliance/SBOM)
- **Mandatory Secrets Detection**: quality-guardian now requires gitleaks scan as first step before all other checks
- **Supply Chain Checks**: Language-specific SCA in quality-guardian and security-review — govulncheck (Go reachability), npm audit, pip-audit, cargo audit, OWASP Dependency-Check (Java)

### Enhanced
- **quality-guardian agent**: Added secrets detection mandatory first step, Semgrep SAST, supply chain SCA per language, Java quality standards, Biome option for JS/TS, govulncheck reachability analysis, SBOM generation for releases
- **quality-tooling.md**: Added Universal section, Biome as JS/TS alternative (~35x faster), pyright as mypy alternative, ruff as unified Python toolchain, golangci-lint (50+ linters), govulncheck, deadcode, Java ecosystem, tiered strategy
- **security-review skill**: Added Semgrep SAST step, secrets tool recommendations (gitleaks/trufflehog), supply chain & dependency section with reachability analysis, refined severity definitions with examples
- **security-scan command**: Added automated tool checks section (gitleaks, Semgrep, govulncheck, npm audit, pip-audit, cargo audit), enhanced severity descriptions
- **quality command**: Added secrets detection step, security & supply chain step, Java support, Biome/pyright alternatives, updated report format with Secrets and Security rows
- **quality-before-commit.sh**: Added gitleaks secrets detection (mandatory, runs first), Java project support via Spotless (Maven/Gradle)

---

## [4.0.2] - 2026-03-10

### Added
- **Compact Instructions in CLAUDE.md**: Built-in keep/drop rules for context compaction — preserves architectural decisions, key paths, debugging insights, error patterns; drops raw output, code blocks, intermediate steps

---

## [4.0.0] - 2026-02-23

### Added
- **Spec-Kit SDD Pipeline**: 9 new `/speckit.*` slash commands for full spec-driven development
  - `/speckit.init`: Bootstrap `.specify/` directory with templates
  - `/speckit.constitution`: Define project governance principles
  - `/speckit.specify`: Generate specs with scenarios, requirements, success criteria
  - `/speckit.plan`: Generate implementation plans with constitution compliance
  - `/speckit.tasks`: Generate phased task lists with Claude Code tracker integration
  - `/speckit.implement`: TDD execution with quality gates (red-green cycle)
  - `/speckit.analyze`: Read-only cross-artifact consistency analysis
  - `/speckit.clarify`: Targeted clarification questions for ambiguous specs
  - `/speckit.checklist`: Requirement quality checklists
- **`spec-template` skill**: Internal skill for Given/When/Then pattern generation
- **`.specify/` directory structure**: Per-project spec artifacts committed to version control

### Changed
- **Agent count reduced from 9 to 4**: Removed framework-orchestrator, context-analyst, plan-architect, implementation-engineer, metrics-collector. These roles are now handled by Claude Code's built-in agents (Explore, Plan, general-purpose)
- **Task management**: Replaced TodoWrite with TaskCreate/TaskUpdate/TaskGet/TaskList API
- **Hooks**: Now implemented as shell scripts (`*.sh`) instead of JSON config files, configured via `settings.json`
- **MCP servers**: Simplified to GitHub only (removed filesystem and memory servers)
- **Rules system**: 4 modular policy files in `rules/` directory (code-quality, git-workflow, agent-workflow, quality-tooling)

### Removed
- **5 agents**: framework-orchestrator, context-analyst, plan-architect, implementation-engineer, metrics-collector
- **`/spec-driven` skill**: Replaced by `/speckit.implement` command
- **JSON hook files**: Replaced by shell script hooks
- **Filesystem MCP server**: Not needed with Claude Code's built-in file tools
- **Memory MCP server**: Replaced by Claude Code's auto-memory feature

### Enhanced
- **Agent workflow**: Updated to reference spec-kit pipeline for SDD
- **CLAUDE.md**: Simplified to focus on 4 custom agents + TaskCreate API + SDD reference
- **Quality tooling**: Comprehensive per-language tool detection (JS/TS, Python, Rust, Go)

## [3.1.0] - 2025-11-26

### Added
- **Hooks System**: Automated quality enforcement without manual intervention
  - `pre-edit.json`: Blocks edits to sensitive files (.env, *.key, credentials, .git/*)
  - `pre-commit.json`: Auto-runs format, lint, typecheck, and tests before commits
- **Skills System**: Specialized, tool-restricted analysis modes
  - `security-review.md`: Read-only security audits (secrets, SQL injection, XSS, auth)
  - `context-analysis.md`: Project structure and tech stack analysis
  - `performance-audit.md`: Performance bottleneck detection
- **Expanded Slash Commands**: Quick access to common workflows
  - `/security-scan`: Security audit of staged changes
  - `/pr-summary`: Generate PR summary from current branch
  - `/context`: Refresh project context analysis
  - `/quality`: Run comprehensive quality checks
- **MCP Integration**: Model Context Protocol server configuration
  - GitHub MCP for PR/Issue automation
  - Filesystem MCP for enhanced file operations
  - Memory MCP for cross-session context persistence
- **Proactive Agent Triggers**: Agents auto-delegate based on task patterns
  - `MUST BE USED` triggers for mandatory agent involvement
  - `Use PROACTIVELY` triggers for context-based auto-delegation
- **Inter-Agent Communication Protocol**: Standardized agent coordination
  - JSON handoff format (task_id, status, findings, next_steps)
  - Quality gate signals (PASS/FAIL/WARN)
  - Escalation path definition
- **9th Agent**: Added `forensic-specialist` for security forensics and threat analysis

### Changed
- **Model Assignments**: Hybrid approach for cost/performance optimization
  - Opus (claude-opus-4-5) for orchestrator and plan-architect
  - Sonnet (claude-sonnet-4-5) for all specialist agents
- **Settings Configuration**: Permissive permissions with hook-based protection
  - Removed restrictive sandbox in favor of pre-edit hooks
  - Added explicit allow rules for common dev tools
- **README.md**: Complete rewrite with comprehensive usage manual
  - Added hooks documentation with examples
  - Added skills usage guide
  - Added slash commands reference
  - Added 10 quick tips section
  - Updated directory structure diagram

### Enhanced
- **Agent Descriptions**: Added proactive trigger phrases to all agents
- **Quality Gates**: Now automated through pre-commit hooks
- **File Protection**: Sensitive files blocked by hooks instead of global restrictions

### Improved
- **Developer Experience**: Less manual quality checking, more automation
- **Security**: Automatic protection of sensitive files
- **Workflow Speed**: Hooks eliminate manual lint/format/test runs

## [3.0.0] - 2025-09-04

### Released
- **Complete Agent-Enhanced Framework**: All 8 Claude Code sub-agents operational
- **Production Ready**: Comprehensive documentation and samples included
- **Performance Validated**: All targets met for automated workflow execution

## [2.0.0] - 2025-09-02

### Added
- **18-Step Enhanced Workflow**: Expanded from 11 to 18 steps across 4 phases
- **Phase 1: Planning & Context Setup** (Steps 1-4)
  - Context Preparation with PROJECT_CONTEXT.md management
  - Risk assessment and time estimation in planning
  - Architecture Decision Records (ADRs) integration
  - Plan refinement with validation steps
- **Phase 2: Implementation with Quality Gates** (Steps 5-10)
  - Pre-implementation setup with quality gates
  - Documentation during development
  - Comprehensive test creation and validation
  - Enhanced quality checks with security scanning
- **Phase 3: Review, Integration & Feedback** (Steps 11-16)
  - CI/CD pipeline integration
  - Multi-AI code review process
  - Structured feedback loop with iteration limits
  - Final validation before merge
- **Phase 4: Post-Merge Activities** (Steps 17-18)
  - Metrics collection and analysis
  - Retrospective and continuous improvement

### Enhanced
- **Core Principles**: Added Continuous Improvement as 5th principle
- **Performance Benchmarks**: 
  - API response < 200ms (95th percentile)
  - Page load < 3 seconds
  - Build time < 5 minutes
  - Test suite < 10 minutes
- **Security Standards**: OWASP Top 10 compliance requirements
- **Quality Metrics**: Enhanced with specific targets and measurement criteria
- **Tool Integration**: Added pre-commit hooks, diagnostics, and git integration
- **Context Management**: Systematic approach to maintaining AI model context

### Updated
- **CLAUDE_CONFIGURATION_SAMPLE.md**: Complete rewrite to match 18-step workflow
- **QUICK_REFERENCE.md**: Visual workflow diagram and enhanced checklists
- **AI_DEVELOPMENT_FRAMEWORK.md**: Merged all improvements into workflow steps
- **File Structure**: Added ADRs directory, CHANGELOG.md, PROJECT_CONTEXT.md

### Fixed
- Inconsistencies between framework documentation and configuration
- Missing performance targets and success metrics
- Lack of systematic approach to context management
- Incomplete quality gate definitions

## [1.0.0] - 2025-09-02

### Added
- Initial AI Development Framework documentation
- Basic 11-step workflow (Planning → Implementation → Review)
- Core principles: Plan-First, Isolated Development, Test-Driven, Multi-AI Review
- Claude configuration sample
- Quick reference guide
- Git integration and tool recommendations
- Basic success metrics and benchmarks

### Created
- `AI_DEVELOPMENT_FRAMEWORK.md` - Core framework documentation
- `CLAUDE_CONFIGURATION_SAMPLE.md` - AI configuration template
- `QUICK_REFERENCE.md` - Daily use cheat sheet
- `PLAN_FRAMEWORK_DOCUMENTATION.md` - Planning document example
- `.gitignore` - Git ignore patterns for plan files

---

## Template for Future Releases

## [3.0.0] - 2025-09-04

### Added
- **Claude Code Sub-Agent Orchestration**: Complete automation of 18-step workflow through 8 specialized agents
- **Agent Hierarchy**: 
  - framework-orchestrator (master coordinator)
  - context-analyst (project analysis and tech stack detection)
  - plan-architect (comprehensive planning and architecture)
  - implementation-engineer (code implementation with quality standards)
  - test-specialist (testing and validation with 80% coverage)
  - quality-guardian (quality assurance and performance monitoring)
  - review-coordinator (PR management and review coordination)
  - metrics-collector (data collection and retrospective insights)
- **Go Language Support**: Added alongside JavaScript/TypeScript, Python, and Rust
- **Agent Samples**: Complete agent configurations in `/agents` folder
- **Enhanced GitIgnore**: Comprehensive *PLAN* file exclusion patterns

### Changed
- **Workflow Automation**: From manual TodoWrite to fully automated agent coordination
- **Performance Targets**: 
  - Planning time: 15-30min → 5-15min (automated analysis)
  - Implementation time: 2 hours → 1-1.5 hours (focused specialist work)  
  - Review cycles: 3 iterations → 1-2 iterations (higher initial quality)
  - Quality checks: 15-20min → 5min (automated execution)
- **User Interaction**: Simple task description triggers complete automated workflow
- **Framework Coordination**: Agent-to-agent communication replaces human coordination

### Enhanced
- **CLAUDE_CONFIGURATION_SAMPLE.md**: Added agent usage instructions and coordination workflows
- **README.md**: Updated for agent-enhanced approach with practical usage examples
- **AI_DEVELOPMENT_FRAMEWORK.md**: Integrated agent-specific workflow automation
- **QUICK_REFERENCE.md**: Added agent automation timing and coordination details

### Improved
- **Agent Specialization**: Each phase handled by dedicated expert agents
- **Quality Enforcement**: Continuous monitoring through quality-guardian agent
- **Context Analysis**: Automated project structure and tech stack detection
- **Documentation Generation**: Automated by implementation-engineer during development
- **Metrics Collection**: Comprehensive data gathering for continuous improvement

### Fixed
- **Workflow Bottlenecks**: Eliminated manual coordination delays through agent orchestration
- **Quality Consistency**: Standardized quality enforcement across all projects
- **Context Switching**: Reduced cognitive load through specialized agent delegation
- **Planning Overhead**: Automated comprehensive planning reduces setup time

## [Unreleased]

### Added
### Changed  
### Deprecated
### Removed
### Fixed
### Security

## [2.1.0] - 2025-01-09

### Added
- **Claude Code CLI Optimization**: Streamlined 18-step workflow specifically for Claude Code
- **TodoWrite Integration**: Mandatory task tracking with specific enforcement triggers
- **Project Detection**: Automatic tooling discovery for JavaScript/TypeScript, Python, Rust
- **Quality Command Discovery**: Dynamic detection of lint/test/typecheck commands via project files
- **Enforcement Triggers**: Clear integration points with Claude Code workflow

### Changed
- **Simplified Framework**: Removed team-specific requirements (PR templates, CI/CD pipelines)
- **Individual Development Focus**: Adapted workflow for solo development scenarios
- **Practical Implementation**: Emphasis on actionable steps over theoretical frameworks
- **Response Guidelines**: Added conciseness requirements for CLI usage
- **Git Integration**: Simplified commit process with co-authoring options

### Enhanced
- **CLAUDE_CONFIGURATION_SAMPLE.md**: Complete rewrite for Claude Code CLI
  - Focused on practical Claude Code tool integration
  - Streamlined 18 steps for individual development
  - Added project-specific tooling detection
  - Included enforcement triggers and forbidden actions
- **Quality Standards**: Simplified metrics focusing on tool availability rather than fixed targets
- **Documentation Guidelines**: Reduced emphasis on extensive documentation, focused on code clarity

### Improved
- **Task Granularity**: Better guidance on when to use TodoWrite vs direct implementation
- **Tool Discovery**: Specific patterns for finding configuration files and available commands
- **Branch Strategy**: Simplified for individual development workflows
- **Performance Expectations**: Realistic targets based on project tooling availability

### Fixed
- **Configuration Complexity**: Removed enterprise/team features not relevant to individual use
- **Tool Integration**: Better alignment with Claude Code's actual capabilities
- **Workflow Enforcement**: Clear triggers for when to use specific tools and practices

---

**Notes:**
- This changelog follows semantic versioning
- Breaking changes are clearly marked
- Each version includes migration guidance when needed
- Framework improvements are continuously integrated