# Plan review (second) — run-survival
<!-- /hefesto:hef.review plan mode, fresh code-reviewer, 2026-11-09 -->
<!-- Verdict: REVISE_PLAN (the second one; the first was applied to plan.md earlier the same day) -->

## Verdict: REVISE_PLAN

### Blocking
- **Architecture:** Sketch 1 wraps the detached copy in `env "${WORKER_ENV[@]}"`. But `WORKER_ENV` also gets
  `XDG_CACHE_HOME=$WCACHE` (plus GOCACHE and npm cache) at `hooks/session-launch.sh:299`, which comes after the
  `GIT_CONFIG_*` restores at `:99–106`. Inside the copy this causes four problems:
  - `RUNDIR` moves under the worker cache, which the worker sandbox can write (`:301`), so the result file that
    `:666–667` protects could be swapped by the worker;
  - `run-follow.sh:24` loses the narration;
  - the `.started` path guard never matches, so every non-zero systemd-run copy is retried with `setsid -w` and a
    run that already ran is launched a second time;
  - `WCACHE` nests one level deeper.

### Concerns
- **Design:** `.started` is touched only after about 400 lines of re-run pre-checks. Any earlier refusal in the
  copy therefore triggers the setsid retry, which contradicts Approach 4.
- **Tests (constitution 3):** three guards have no mutation:
  - the D8 `/proc` seam in lane mode;
  - the R4 path guard;
  - the `.started` retry condition.
- **Design:** a verifier refused with exit 75 waits for the 10-minute "phase verify, no owner" window
  (`hef.orchestrate.md:224–227`). The docs should say so.
- **Nit:** the worker inherits `HEFESTO_RUN_DETACHED` (`:625`).

## Suggested Changes
1. Snapshot the `GIT_CONFIG_*` restore entries right after `session-launch.sh:106` into their own array and use that
   array for the re-exec, never `WORKER_ENV`. Add checks that the copy's `RUNDIR` equals the caller's and that the
   worker's `XDG_CACHE_HOME` is the caller's `WCACHE`, not nested.
2. Touch `$HEFESTO_RUN_DETACHED.started` as the copy's first act after argument parsing, or replace retry-with-marker
   with a `systemd-run --user --scope --collect --quiet -- true` probe in `hl_detacher`. Reword Approach 4 to match.
3. Add to SC-007:
   - (i) a mutation that drops the `.started` condition;
   - (ii) a lane-mode negative for the D8 seam (the fixture value must not appear in the output);
   - (iii) a lane-mode negative for the R4 guard (no `.started` file outside RUNDIR).

   The lane-mode launch check must shadow both `systemd-run` and `setsid` with fakes.
4. FR-013: `hef.orchestrate.md` step 3 and the quickstart should say that a verifier refused with 75 is picked up
   after the 10-minute window.
5. Nit: add `-u HEFESTO_RUN_DETACHED` to the worker env. Mark `shellcheck-files` and the `hef.doctor.md` change as
   the only lines beyond the item's ask.

Unmeasured: R1 (shellcheck under `ulimit -v 2097152`). The reviewer's probe was denied by its permission surface, so
it stays the first implementation task.

---

# Plan review (third) — run-survival
<!-- /hefesto:hef.review plan mode, fresh code-reviewer, 2026-11-09, after round-2 changes were applied per the owner's answer -->

## Verdict: REVISE_PLAN

Round-2 blockers resolved (GIT_RESTORE, `.started` first, mutations i–k, verifier wait). New, all applied to
plan.md/spec.md before round 4:
1. Measured: `tests/smoke.sh` runs out of memory under `ulimit -v` at 2/4/8 GiB, so the tier-2 guard cannot be the
   compensating check for the 3000-line skip. The guard now skips oversize files visibly; the skip note no longer
   claims the guard checks them; R1 closed (rc 0 at 2 GiB); R8 records the measurement and the four known findings.
2. `env -u HEFESTO_RUN_DETACHED` in `CMD` would break the byte-exact `launch-920.txt` fixture → `unset` after the
   detach branch instead (same guarantee); fixture test listed as the regression check.
3. `hef.orchestrate.md:358` (stage-pass "exits non-zero") added to FR-013.
4. Mutation (l) for the `HEFESTO_RUN_DETACH=0` seam.
5. Structural greps for FR-011/FR-013 (SC-005, new SC-009).
6. Known `-S warning` findings recorded for task 1.

---

# Plan review (fourth) — run-survival
<!-- /hefesto:hef.review plan mode, fresh code-reviewer, 2026-11-09 -->

## Verdict: APPROVE
Non-blocking suggestions, folded into tasks.md: (1) `shellcheck-changed` with an empty `pr_base` checks staged +
unstaged and says so, a failed `pr_base` exits 2; (2) move the `tests/smoke.sh:1364–1377` mutation to
`hl_shellcheck_bounded`'s `*)` arm and keep the hook's "could not check <f> (exit N" text; (3) R5: prune
`*.launcher.*` by mtime on their own; (4) SC-002: `kill <owner.pid>` → exit 143, `owner.pid` equals the fake
claude's `$PPID`; (5) `HEFESTO_RUN_DETACH=0` also suppresses the "attached" note (macOS CI); (6) spec FR order.
