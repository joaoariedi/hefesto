# Plan review log: docs-front-door
<!-- /hefesto:hef.review plan mode, fresh-context code-reviewer, 2026-11-07 -->

## Round 1 — REVISE_PLAN (applied to plan.md / spec.md)
1. "README §5" citations in `docs/install.md:369,742`, `docs/architecture.md:155`, `docs/performance.md:51` → added to Affected Files + SC-007.
2. README `:79-88` (SETUP.md, the Claude-guided path) had no destination → kept in README "Set up a project".
3. Quick start §2 must keep the literal `install.sh` (`tests/smoke.sh:6019`) → Sketch 3 + FR-007.
4. `docs/install.md` §1 edit pinned by line; the wizard's full reference has one owner (install.md §1).
5. Guard mutation story → `fd_check <root>` run on mutated temp copies in-suite; SC-003 aligned.
6. Windows claims anchored to Microsoft's / Claude Code's install pages.

## Round 2 — REVISE_PLAN (NOT applied — second REVISE_PLAN stops for a person)
1. FR-003: the pinned-tag form (`v<X.Y.Z>/install.sh`, 7.10.0 or later) and the clone-first form (README `:65-77`) would vanish once `docs/install.md:12-15` is cut → put both in the per-OS pages' §2, or keep `install.md:14`.
2. Sketch 4: add the `bubblewrap` mutation SC-003 lists and one quick-start link mutation; make the Constitution box match.
3. Sketch 5 / FR-011: "one PR per change" has no source — drop or cite; the trailer is a `git-workflow.md` rule, only the subject is hook-enforced (`hooks/quality-before-commit.sh:66-69`); cite merge commits from the `human:merge` ancestry gate (install.md §7 step 2). The spec's US4 wording "trailer, enforced by the commit hook" is wrong.
4. SETUP.md is read via `curl`, so its new links must be absolute GitHub URLs (it is outside the `tests/smoke.sh:435` link guard).
5. Windows page: Affected Files says "keep projects in the Linux filesystem", Sketch 2 says no own claims — reconcile (remove, or anchor to Microsoft's docs).
6. Minor: `yes x | head -150` → a loop (SIGPIPE pattern constitution 3 names); the quick starts' intro paragraphs (`:3-5,15-17`, both languages) must be rewritten too ("Linux and macOS" → add Windows (WSL); SC-005 depends on it).

All six are edits to plan.md/spec.md; none needs a product decision. A person can approve applying them and re-run `/hefesto:hef.review plan`.

**2026-11-07 — the owner answered: "Apply all six, re-review once"; direction approved.** Applied:
1. Pinned-tag + clone-first forms → per-OS pages §2 (Sketch 2b, FR-007, destination table, install.md row).
2. Sketch 4: `bubblewrap` mutation + `qs_links` function with a quick-start link mutation; Constitution box = five mutations.
3. Sketch 5 / FR-011 / US4: "one PR per change" dropped; subject hook-enforced (`:66-69`), trailer a `git-workflow.md` rule; merge commits cited from install.md §7 step 2 (`:318-319`).
4. SETUP.md links are absolute GitHub URLs (Affected Files, FR-010).
5. Windows row reconciled with Sketch 2 ("Linux filesystem" claim removed).
6. Counted `while` loop instead of `yes | head`; both quick starts' openings `:3-5` (and §1 `:15-17`) rewritten in Affected Files + Sketch 3.

## Round 3 — APPROVE (2026-11-07)
All six round-2 items verified resolved. Two task-level notes, carried into tasks.md:
1. Per-OS pages §1 open with the Claude Code prerequisite sentence (from `docs/quickstart.md:15-16` / `README.md:397`) — else FR-003 loses it.
2. The guard task adds mutations for the three un-mutated `fd_check` branches: README per-OS links, macOS `brew install`, Windows `(install-linux.md)` hand-over.
Also: the `fd_fail` block needs its closing `ok` line; reword the quick-start `bad` message at `tests/smoke.sh:6024`.
