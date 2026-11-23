# Plan review log — exhaustive-review
<!-- appended by speckit-helper.sh plan-review-round; never edit by hand -->

## Segment — first review — 2026-11-23 — cap 5

## Round 1 — 2026-11-23 — REVISE_PLAN
decision: yes
1. Add a truth-map section on the verify permission surface (`session-launch.sh:215, 662, 675`, and the lane mode) and derive from it how the verifier runs a recipe and where scratch files go. If that needs a launcher or allowed-tools change, SC-002 and D1 must be amended in the spec first.
2. Give `code-review-check` an invocation that is one plain command starting with the helper path, and that needs no `Write`. Add a smoke check that the documented call matches `Bash(<hooks>/*)`.
3. [DECISION] Choose what a blocking `UNREPRODUCED` candidate does to the verdict. Either it blocks (a third outcome that goes to the HEF-57 dispute path), or it approves with open questions as FR-007 says now. The item says a finding counts only once reproduced; D6 says uncertainty is never a pass.
4. Add one in-command retry before `INCOMPLETE`: re-spawn the silent finder or verifier once, and re-format once when the check fails on shape only. Report `FAIL` only after that.
5. Put a few words of the defect in each `BLOCKING` entry (`<file:line> (<lens>) <defect>`), and say where the builder reads the recipe. Correct the risk row about the 2000-char summary.
6. Scope the Rule 0 rewrite, Rule 1 and the Verdict Criteria to the finder and verifier roles, and keep today's wording for plan mode and the Stage-1-only spawn. Add a smoke check that the plan-mode discipline text survives.
7. Make the first replay task a probe: one case run that shows whether git and the recipes work in the eval sandbox, and whether the plugin root is readable. If git is denied, have the scaffold ship the diff as a file and name which defects grade on the finding alone.
8. Fix the scaffold sketch: `set -euo pipefail`, a commit identity, `git cat-file -e` on both SHAs with a loud failure. State `runs`, `allowed_tools` and whether the without-plugin arm applies.
9. Add `README.md`, `docs/architecture.md` (subcommand count), the `evals/README.md` case count and the `hef.review.md` frontmatter description to Affected Files. Say what `--second-opinion` sends in code mode.
10. Define "the reviewer's tier" in FR-002 as the agent's pinned tier, and drop or justify the "otherwise `fable`" branch. Have the `Finders:` line record the tier each finder was asked for.
11. [DECISION] Decide whether the five-finder round runs on every code-mode review or only above a size or route threshold (fix-route items, a person's own run). The item names only the verify stage.

## Segment — person answer — 2026-11-23 — cap 5

## Round 1 — 2026-11-23 — REVISE_PLAN
decision: no
1. Fix the lane channel: `lane-guard.sh:66-114` denies a heredoc whose body contains an excluded word (`gh`) and admits heredocs only for `ledger.sh answer|revise|direct`. Add `hooks/lane-guard.sh` to Affected Files with a narrow, mutation-tested exception (quoted heredoc whose first line is exactly the plugin's `speckit-helper.sh code-review-check` or `review-repro.sh`; a body with `gh` in the fixture), or choose another channel. Drop the `--report '<text>'` fallback.
2. Make the scratch copy git-safe: exclude `.git` (file or directory) and give the copy its own `git init` when git exists. Fixture in a real linked worktree: a recipe runs `git config` and `git commit`; the real repo's config, index and HEAD are unchanged.
3. `review-route` fails loudly (exit 1, naming the cause) on an empty or detached branch. Decide "no entry" by the entry file's existence under `ledger.sh dir`, not by message text. Both fixtures.
4. Extend the probe to run `review-route` and the command's pre-flight in the eval sandbox; the other 17 cases wait on it. If git is denied, say how the route and spec folder resolve (e.g. a `.git/HEAD` read).
5. Move the heredoc permission proof ahead of the build: a person-run probe of the documented `code-review-check` and `review-repro.sh` heredoc calls through a headless verify permission set and a lane, before the command is rewritten around them.
6. Define severity: the blocking criterion in the finder role; the verifier may mark `REFUTED` a candidate that reproduces but is not a defect of that class; a class disagreement between lenses merges as blocking.
7. Fix the report contract: where a multi-line recipe sits relative to the one-line finding, a delimiter longer than `R`, and that the command hands each agent the resolved absolute helper path.
8. An `INCOMPLETE` round with blockers still ends with the `BLOCKING` line; gate evidence leads with it, then the reason. Fixture.
9. Complete the worktree guard: detect deletions, ignore gitignored paths, define the candidate status for exit 3.
10. Bound the copy: tracked plus unignored files, or one copy per verifier.
11. Correct the eval count to 15 → 34; name the probe case in the spec (FR-016/SC-003) or the plan as a non-FR artefact; state whether the scaffold is whole-tree, against D9's "relevant files".
12. Add a tool-level grader for a `review-repro.sh` call on cases that must be `REPRODUCED`; record the readable answer key as a known limit in `evals/README.md`.
13. Optional: `code-review-check` prints the verdict and the `BLOCKING` line instead of checking the model's; use real symbols in Sketch 3 (`$BRANCH`, `$SELF`).

## Round 2 — 2026-11-23 — REVISE_PLAN
decision: no
1. Make the `lane-guard.sh` exception a path that ends the guard for that call: decide it before `:88` and exit there (or clear `EXCL_HIT`), so `:88-90`, `:229-234` and `:243-246` do not deny it afterwards. Extend the truth map past `:114`. 19s fixtures use a record with `lanes: true`: body with `gh`; body with a custom excluded command; body with `gh` and `lane-build`; the near misses still denied. Mutate each.
2. `review-repro.sh` refuses, loudly, when it is not running inside the sandbox (the `lane-build.sh:31-34` technique or an equivalent that also works headless). Test seam for the unsandboxed smoke suite, a 19s fixture and a mutation. State what a `--strict` lane does with a helper that has no allow rule: add `hooks/hefesto-setup.sh` to Affected Files, or record the per-recipe dialog as a known limit.
3. `review-route`: call `ledger.sh dir` only for a `worktree-<ID>` branch and exit 1 naming the cause when it fails there. Resolve the spec folder through the spec root (add `review-route` to the list at `speckit-helper.sh:53-55`), with an app-folder fixture. Add `review-route` to probe 1 in both modes.
4. Add a control to the replay: at least one case per item at its merged head, recording the verdict and the number of blockers reported, and a "blockers on the merged head" column in the results table (measurement only, no pass/fail claim).
5. Reconcile the six finding-alone cases with FR-016 and FR-019: keep the `review-repro.sh` grader on them, or amend both FRs to name the exception.
6. Write the contract's example recipe against the scratch copy (cwd-relative) and say what `HEF_REPRO_SRC` is for, or drop it. Run the recipe with stdin from `/dev/null`. Cap output by bytes as well as lines.

## Round 3 — 2026-11-23 — REVISE_PLAN
decision: no
1. FR-022 and `review_heredoc_ok`: admit the heredoc only when exactly one line equals the delimiter, and it is the last. 19s fixtures for both helpers (delimiter early in the body, then a command, then the delimiter → denied as today) and a mutation that drops the rule. State whether the exception sits before or after the `CLAUDE_CODE_SESSION_ID=` deny at `lane-guard.sh:64`, with a fixture for the chosen behaviour.
2. Replace plan.md's "one more `case` in `heredoc_ok`" (No sketch — trivial) with a short sketch of the path the truth map describes: decided after `:81`, before `:88`, `exit 0`, `dangerouslyDisableSandbox` refused.
3. `review-repro.sh` contract: remove the scratch copy on every exit path, with a fixture. Keep the recipe timeout clearly under the Bash tool's 120 s default, or have the verifier brief pass a longer tool timeout, so the after-listing always runs. Name the portable primitive for the before/after listing (`cksum` per file is POSIX and catches same-size rewrites). Refuse (exit 2) when the probe's folder is missing, as `lane-build.sh:31` does, with a fixture and a mutation.
4. Align the spec's grader counts: FR-019 "its two graders" and D9 against FR-016's three graders for per-defect cases and two for controls. Add "a full copy per recipe on a large tree" to the known limits.

## Round 4 — 2026-11-23 — REVISE_PLAN
decision: no
1. Sketch 6 / FR-022: make the head exact. The head's words must be exactly one (`review-repro.sh`) or two (`speckit-helper.sh code-review-check`), the first an absolute path ending in `/hooks/<helper>` — compare the word list, not a `*`-prefixed glob (today `<excluded cmd> … --body <x>/hooks/review-repro.sh <<'WORD'` is admitted and runs outside the sandbox). 19s fixtures for both helpers, each with a mutation: an excluded command first with the helper path as a later argument, and a leading assignment before the helper — both denied.
2. Sketch 6: define `words()` before the new call (move it above the call site, or place the call after `:104` and before `:106`), and correct the truth map's "after `:81`, before `:88`".
3. Give the finders the spec on a `worktree-<ID>` branch: `review-route` prints the entry's spec folder on the ledger path (the entry's `spec_dir`, as `session-launch.sh:242` resolves it); the command writes it into every finder and verifier brief. Route fixture; structural check for the folder in the brief. A `light`/`full` entry with no readable spec folder exits 1 (US7).
4. Settle which candidates the verifier must status, in one place: either only `[BLOCKING]` candidates go to the verifier (amend D5, D6, FR-005 to match FR-010 and `crc_statuses_ok`), or `crc_statuses_ok` requires a status on every finding with a fixture and mutation. The first is cheaper and changes no verdict.

## Round 5 — 2026-11-23 — REVISE_PLAN
decision: no
1. State and test what the round does when `review-repro.sh` cannot run in this environment (exit 2: no `$(hef_cache)`, or not sandboxed). Recommended: after `review-route` answers `exhaustive`, the command runs one trivial `review-repro.sh` call; on exit 2 on a no-ledger branch (a person's own run) it runs today's single reviewer and opens the report with one line naming the cause and the fix; on exit 2 on a ledger item the round is `INCOMPLETE` naming the cause, never a fall-back (US7). Amend FR-021/US7 and D11, add a structural check for the preflight and both outcomes in `commands/hef.review.md`, and a line in `docs/commands.md`. Or, if the round should run with every candidate `UNREPRODUCED`, say so in Risks and have the report's first line say so and why.
2. Make probe 2 establish that a recipe ran in the eval sandbox, and name the outcome if it did not: record `review-repro.sh`'s printed `exit:` line and its exit status in `evals/README.md`; if the helper refuses there, the build stops `blocked` before the other 17 cases, as probe 1 does. Add `execution.allowed_tools` (with `Agent`) to the Sketch 4 case.
3. Make the no-ledger `review-route` line match the contract: print the spec folder as an absolute path (spec root joined with `.specify/specs/<branch>`), fix Sketch 3, and have the app-folder route fixture assert the absolute path.
