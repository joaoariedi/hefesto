# Plan review log — macos-case-guard
<!-- appended by speckit-helper.sh plan-review-round; never edit by hand -->

## Segment — first review — 2026-11-16 — cap 5

## Round 1 — 2026-11-16 — REVISE_PLAN
decision: no
1. Fix the double-quoted `$((` frame handling: only the outer `P` saves the quote state, the inner saves `""`. Add `x="$(echo "$((a+1))")"` followed by a top-level `case` to the good fixture.
2. Make desync loud. At end of file (and at `FNR == 1` for the previous file), if a heredoc is still pending, a quote is open or the stack is non-empty, print `FILE:0: scanner lost sync` so the tree check fails. Add a mutation, or a good-fixture shape, that exercises it. Tighten the heredoc opener so an arithmetic shift is not one, and handle `<<\WORD`.
3. Name the fixtures without a `.sh` extension (for example `macos-case-in-subst-bad.txt` and `-good.txt`), or state why the Mac commit gate's `bash -n` does not apply.
4. Add a third mutation in the opposite direction (`in_subst` always true, or drop the `C`-frame `)` skip / quote restore) that must make the good fixture report. Require the good fixture to exist and be non-empty, and require each mutant awk to exit 0.
5. State that the block's comments cite `macos-case-guard/FR-001` … `FR-008` in qualified form.
6. In T001, record the measured output (tree: none; pre-`8365d75`: the `fg_pushrw` `case` line) and re-run the pre-fix check against the final `mp_case_in_subst`, not only the prototype (SC-002). Include a grep for unquoted `case ` argument words and note that limit in Risks.

## Round 2 — 2026-11-16 — REVISE_PLAN
decision: no
1. Exercise the lost-sync path. Add a third fixture, `tests/fixtures/macos-case-in-subst-desync.txt`, holding an unterminated `x="$(` and an `echo in case of` line. Add a check that `mp_case_in_subst` on it prints a `:0: scanner lost sync` line. Add mutation (d), which neutralises the `print` in `sync_check()` and must make that check go red. Update the mutation count in the `ok` line and the file list.
2. Make every good-fixture skip shape discriminating. Replace `$(( 1 << 2 ))` with `$(( 1 << n ))` followed by a top-level `case`. State in Approach 4 that each skipped region (the `<<EOF`, `<<-EOF`, `<<'EOF'` and `<<\EOF` bodies, comment, `'…'`, `"…"`) contains a `$(` + `case` that would be reported if the skip were removed.
3. Close SC-002 against the landed guard. Add a closing step beside T001 that runs the final `mp_case_in_subst` once on `git show 8365d75^:hooks/hefesto-setup.sh` (written to a scratch file) and records the output in `research.md`. In Risks, reword "Silent desync" to say the end-of-file check catches unbalanced state only, with smoke-macos as the backstop for a balanced misread.

## Round 3 — 2026-11-16 — APPROVE
decision: no
None required (APPROVE). Carried into tasks.md: (1) mutation (d) gets the same rc 0 requirement as (a)–(c); (2) word the failure so a `:0: scanner lost sync` line does not sit under the "move it into a function" remedy; (3) T001 records all three measurements in research.md before the fixtures are cut.
