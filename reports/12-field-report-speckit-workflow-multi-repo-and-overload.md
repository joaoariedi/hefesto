---
status: accepted
date: 2026-07-16
---

# Field Report: speckit-workflow — Multi-Repo Support & Overload Resilience

A field report from running `workflows/speckit-workflow.js` on a **real two-repo monorepo feature**
(the FxCube `#314 portfolio-folders` feature: a Django backend in `operations_api/` and a React
frontend in `cube_ui/`, with the `.specify/` specs living in a *third* directory, `tasks/`). The run
surfaced two structural gaps and one robustness gap. This file records what happened and proposes
concrete, minimal-diff changes. It is a **recommendation, not a spec** — the changes below are
sketches to be reviewed before implementation.

Not covered here: the workflow's *design rationale* (why phases are a barrier, why the implementer
must not grade its own homework) — that is documented in the header comment of
`workflows/speckit-workflow.js` and in `reports/03-agent-topology-orchestration.md`.

**Source:** FxCube `#314 portfolio-folders` run (2026-07-15), run id `wf_ba8bb0be-11d`.
**Proposed change in:** `workflows/speckit-workflow.js`.

---

## TL;DR

| # | Finding | Severity | Fix shape |
|---|---------|----------|-----------|
| 1 | **Single-repo assumption**: `projectRoot` is derived by stripping `/.specify/specs/<name>` from the feature dir, so it only works when code and spec share a repo. Monorepos with a separate spec dir mis-resolve every path. | Blocks monorepos | Accept an explicit `projectRoot` + a `repos[]` map; resolve each task's repo from its file paths; run gates per-repo. |
| 2 | **Overload from fan-out amplitude**: per task the workflow spawns 1 implementer + 3 verifiers, and the regression lens runs the *full test suite* every time. On a shared API rate limit this self-inflicts sustained `429`/`529`, cascading into retries and a killed run. | Kills long runs | Cap concurrency below the CPU bound; run the full suite **once per phase**, not per-task-per-verifier; add a sequential fallback knob. |
| 3 | **A single transient agent failure aborts the whole run**: one schema'd sub-agent that finished without calling `StructuredOutput` threw and killed a ~20-minute run. | Wastes long runs | Wrap `agent({schema})` in a bounded retry; degrade one agent, don't abort the workflow. |

Resume worked (cached prefix replayed instantly), but three sequential resumes were needed, and the
operator ultimately finished the feature **by hand** because the fan-out kept re-triggering overload.

---

## Finding 1 — The single-repo `projectRoot` assumption

### What the code does today

The `Load` phase asks the loader agent to compute `projectRoot` as *"the directory that CONTAINS
`.specify/` (i.e. the feature dir with `/.specify/specs/<name>` stripped off)"* and every downstream
agent is told to `cd` there and resolve relative paths against it.

That is correct **only when the spec lives inside the repo it describes**. In this monorepo:

```
fxcube/
├── tasks/.specify/specs/portfolio-folders/   ← spec lives here
├── operations_api/   ← Django code + its own pytest suite + its own git repo
└── cube_ui/          ← React code + its own vitest suite + its own git repo
```

Stripping `/.specify/specs/portfolio-folders` yields `fxcube/tasks` — a repo that contains **none**
of the code the tasks reference (`operations_api/operation/models.py`, `cube_ui/src/...`). Every
implementer would `cd tasks/` and fail to find its target files. There is also no single
`testCommand`: the backend runs `poetry run pytest` (needs Postgres + Redis env), the frontend runs
`npx vitest run` + `npm run typecheck`.

### Recommendation

Decouple *spec location* from *code location*, and make the repo a per-task property.

1. **Accept an explicit config via `args`** (already normalized at the top of the script), e.g.:

   ```js
   // args: { featureDir, projectRoot, repos: [{ path, testCommand, lintCommand, envPrefix }] }
   const projectRoot = _args?.projectRoot || /* fall back to today's strip-based inference */
   const repos = _args?.repos || null   // null → single-repo mode (current behaviour)
   ```

   When `repos` is absent, behave exactly as today (no regression for single-repo users).

2. **Resolve each task's repo from its file paths.** The loader already returns `files[]` per task.
   Pick the repo whose `path` prefixes the task's files:

   ```js
   function repoFor(task, repos) {
     if (!repos) return null
     const f = (task.files || [])[0] || ''
     return repos.find(r => f.startsWith(r.path + '/')) || repos[0]
   }
   ```

3. **Inject the resolved repo into `implPrompt` / `verifyPrompt` / the phase gate** instead of a
   single global `testCommand`: the impl/verify/gate agents get *that repo's* `cd` target, test
   command, env prefix, and lint command. The phase gate runs the suite of **each repo the phase
   touched**, not one global command.

4. **Per-repo branches (optional but recommended).** A monorepo feature is `N` PRs, one per repo.
   The workflow itself needn't open PRs, but it should not assume a single working tree — document
   that branches are created *before* the run (as the operator did here) and that the Report phase
   summarises changes *grouped by repo*.

The prompts already say *"PROJECT ROOT … is NOT necessarily your shell's starting directory"* — this
change makes that literally true and adds the missing per-repo dimension.

---

## Finding 2 — Overload from fan-out amplitude (429 / 529)

### What happened

Across the run, nearly every sub-agent logged repeated `429` (rate-limit) and `529` (overloaded)
responses — one verifier hit `529` **21 times**. The harness retries these with backoff, but the
workflow's *aggregate* concurrency is the problem, not any single call:

- The harness caps concurrency at `min(16, cores-2)` agents.
- Per task the workflow issues **1 implementer + 3 verifiers** (the three lenses run via `parallel`).
- The **regression lens runs the entire test suite**, and the **phase gate runs it again**. On a
  728-test / ~12-minute backend suite that is a lot of long, token-heavy calls in flight at once.

So a single backend phase can have a dozen agents concurrently hammering the API, several of them
each driving a 12-minute suite — precisely the shape that trips a shared rate limit, and then the
retries pile on more load. The run degraded to a crawl and a transient error (Finding 3) killed it.

### Recommendation

The script cannot change the harness's backoff, but it **controls the amplitude**. Three levers:

1. **Deduplicate the full-suite runs.** Today the suite runs `O(tasks × verifiers) + O(phases)`
   times. The regression lens and the phase gate are asking the same question. Run the full suite
   **once per phase** (the gate), and give the regression lens a cheaper contract: *"run only this
   task's test file; the phase gate owns the full-suite/regression check."* This is the single
   biggest reduction in long-call volume.

   ```js
   // regression lens, per task: run ONLY impl.testFile, not the whole suite.
   // whole-suite regression is asserted once, by the phase gate.
   ```

2. **Make the verifier count and concurrency configurable, and cap below the CPU bound.** Expose
   `args.verifierCount` (default 3) and `args.maxConcurrency`. Chunk the `parallel(...)` fan-outs so
   no more than `maxConcurrency` schema'd agents are ever in flight — a workflow-level cap that is
   *API-aware*, independent of core count.

3. **Adaptive throttle + sequential fallback.** If a phase records N agents that ended in a terminal
   API error (or the run trips a threshold of `429/529`), drop `maxConcurrency` to 1 for the rest of
   the run and log it. A slow sequential finish beats a fast failure. Surface a `args.sequential:true`
   escape hatch so an operator who already knows the API is hot can start in that mode.

Rule of thumb worth adding to the header comment: **a verifier that re-runs the whole suite is the
most expensive agent in the system; spawn the fewest of them, and never more than one full suite in
flight per phase.**

---

## Finding 3 — One transient agent failure aborts the whole run

### What happened

A schema'd sub-agent "completed without calling StructuredOutput (after in-conversation nudge)". The
`agent({schema})` call threw, and because nothing catches it, the **entire workflow died** after
~20 minutes and 6 completed agents. The work already on disk survived (the implementer had committed
its files), and `resumeFromRunId` replayed the cached prefix — but a single flaky call should not
cost a 20-minute run even once.

### Recommendation

Wrap schema'd agent calls in a bounded retry, and degrade a single agent rather than aborting:

```js
async function agentTyped(prompt, opts, tries = 2) {
  for (let i = 0; ; i++) {
    try { return await agent(prompt, opts) }
    catch (e) {
      if (i >= tries) {
        log(`agent ${opts.label} failed after ${tries + 1} tries: ${e.message}`)
        return null            // let the caller treat it as "not accepted", not a crash
      }
      log(`retry ${opts.label} (${e.message})`)
    }
  }
}
```

`implementAndVerify` already handles a `null` implementer (`accepted:false`), so returning `null`
from a dead agent slots into the existing "failed verification" path and halts the *phase* cleanly
with a reason — instead of throwing out of the whole run. Combine with the resume mechanism and a
flaky call becomes a one-round cost, not a whole-run cost.

---

## Suggested rollout order

1. **Finding 3** (retry wrapper) — smallest diff, immediately stops long runs dying to flakes.
2. **Finding 2** (suite dedup + concurrency cap) — the change that makes big runs *finish*.
3. **Finding 1** (multi-repo config) — unlocks monorepos; larger but additive and backward-compatible.

All three are backward-compatible: single-repo runs with no extra `args` behave exactly as today.
