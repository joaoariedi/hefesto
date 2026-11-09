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
