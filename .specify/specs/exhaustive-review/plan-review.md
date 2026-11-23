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
