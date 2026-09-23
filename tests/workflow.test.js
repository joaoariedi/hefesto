// Behaviour tests for workflows/workflow.js.
//
// Run: node --test tests/
// No package.json, no npm install, no lockfile. `node --test` is built into node >=18, and
// ubuntu-latest ships node — so this stays inside constitution principle 4, which forbids the
// INSTALL STEP, not the runtime.
//
// ---------------------------------------------------------------------------------------------
// WHY THIS FILE LOADS THE WORKFLOW BY TEXT REWRITE
//
// workflow.js is executed by the Claude Code Workflow harness, which requires a script
// exporting `meta` and injects agent/parallel/phase/log/args as GLOBALS. It cannot be imported:
// there is nothing to import from, and its top-level `return` statements (at the "no tasks" guard,
// the halt sites, and the final return) are illegal in an ES module but legal in a function body.
// That is exactly why wrapping it in `new Function` works, and it is the only way to drive the
// SHIPPED file rather than a copy of its logic.
//
// A copy would be worse than nothing. This repo's constitution (principle 3) records why: an
// end-to-end assertion on helper DATA once went green against a completely broken plugin, because
// when the helper was permission-blocked the model just ran plain `git log` and produced identical
// output. Test the artifact that ships, and assert at the tool-call level.
//
// ---------------------------------------------------------------------------------------------
// KNOWN FIDELITY LIMITS — stated, not implied:
//
//  1. THE LOADER IS STUBBED. Nothing here tests that a real model parses tasks.md correctly. These
//     tests prove the script CONSUMES a parsed task graph correctly; detection is untested.
//  2. THE STUBS ARE OUR IMITATION of the real harness. A comment cannot detect drift. The defence
//     is `bothParallelContracts` below: run resilience tests against BOTH plausible parallel()
//     contracts, so "which one is real?" stops mattering. Only a live SMOKE_LIVE probe could
//     confirm the real one, and it cannot run in CI.
//  3. THE HARNESS'S THROW TYPE IS NOT PINNED. We pin parallel()'s contract (quoted below) and not
//     the type of value a failing schema'd agent throws — which is exactly the gap that let
//     `throw null` kill a run through `e.message`. `e?.message ?? String(e)` is the hedge.
// ---------------------------------------------------------------------------------------------

import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
export const WF_PATH = path.join(REPO, 'workflows', 'workflow.js')

// --- the loader ------------------------------------------------------------------------------

/**
 * Wrap workflow source so it can be driven with stub globals.
 *
 * ONE makeRun, used by BOTH the real load and the strict-mode fixture. Two wrappers would mean the
 * `'use strict'` mutation has two sites: the test would prove the TEST's wrapper is strict while the
 * real load silently lost it and stayed green. (SC-007)
 *
 * `'use strict'` is load-bearing. A `new Function` body is SLOPPY by default, but the shipped file is
 * an ES module and therefore always strict. Without this line the harness runs different semantics
 * from production: an assignment to an undeclared identifier — an ordinary typo — passes green here
 * and throws ReferenceError on the first real run. (FR-008)
 */
export function makeRun(src) {
  return new Function(
    'agent', 'parallel', 'phase', 'log', 'args',
    `'use strict'; return (async () => {\n${src}\n})()`,
  )
}

/** Read the shipped workflow and rewrite its export so `new Function` will accept it. */
export function loadWorkflowSource() {
  const raw = fs.readFileSync(WF_PATH, 'utf8')
  const src = raw.replace('export const meta', 'const meta')
  // If this rewrite ever matches nothing, the harness would test a stale shape — or nothing at all.
  // `new Function` also throws on an unreplaced `export`, so this fails loudly twice over. (SC-006)
  assert.notStrictEqual(src, raw, 'the `export const meta` rewrite matched nothing — workflow.js changed shape and this harness would be testing a stale assumption')
  return src
}

// --- pinned harness contract -----------------------------------------------------------------

// PINNED from the Workflow tool contract, quoted verbatim 2026-07-16 (Claude Code, Opus 4.8):
//   "parallel(items, ...): run tasks concurrently. ... A thunk that throws (or whose agent errors)
//    resolves to `null` in the result array — the call itself never rejects"
// Re-check this at every Claude Code upgrade. It is the reason :320's `.filter(Boolean)` silently
// DELETED a crashed task instead of crashing, and the reason the fix is an index-mapped fallback.
export const parallelThrowToNull = async ts =>
  Promise.all(ts.map(async t => { try { return await t() } catch { return null } }))

// The contract we do NOT believe is real, tested anyway. If the harness ever propagates instead of
// nulling, the resilience fix must STILL produce an explicit rejection. Running both makes the
// question moot rather than load-bearing.
export const parallelPropagate = async ts => Promise.all(ts.map(t => t()))

export const bothParallelContracts = [
  ['parallel: throw->null (pinned contract)', parallelThrowToNull],
  ['parallel: propagating (hedge)', parallelPropagate],
]

// --- the stub kit ----------------------------------------------------------------------------

/**
 * Build a stub `agent` plus the recorders the assertions read.
 *
 * THE STUB MUST AWAIT. `return canned(label)` un-awaited makes a `finally` block run BEFORE the
 * returned promise settles — so any in-flight counter reads 1 forever, no matter what the code does.
 * That defect gave an earlier revision of this work a test that could not fail: deleting the entire
 * feature under test left it green. It reads 1 even when canned() is itself async.
 *
 * Counters are PER LABEL, not global: the retry loop lives INSIDE agentTyped, so a retry-on-null
 * mutation is only observable at the stub, and a global total is muddied by the other agents in the
 * fixture. (SC-003, SC-015)
 */
export function makeAgentStub(canned) {
  const spawned = []
  const calls = new Map()
  const agent = async (prompt, opts = {}) => {
    const label = opts.label ?? '(unlabelled)'
    spawned.push(label)
    calls.set(label, (calls.get(label) ?? 0) + 1)
    await new Promise(r => setImmediate(r))   // yield — see the note above
    const r = canned(label, opts)
    if (typeof r === 'function') return r()    // let a fixture throw from inside the await
    return r
  }
  return {
    agent,
    spawned,
    callsFor: label => calls.get(label) ?? 0,
    // [...spawned].sort(), never spawned.sort(): the in-place sort destroys spawn order for any
    // later order-sensitive assertion.
    labels: () => [...spawned].sort(),
  }
}

/** Drive the shipped workflow with a stub kit. Returns the workflow's own return value. */
export async function drive({ canned, parallel = parallelThrowToNull, args = { featureDir: '/f' }, src }) {
  const kit = makeAgentStub(canned)
  const run = makeRun(src ?? loadWorkflowSource())
  const result = await run(kit.agent, parallel, () => {}, () => {}, args)
  return { result, ...kit }
}

// --- fixtures --------------------------------------------------------------------------------
//
// Every requirement below was EARNED: each is a case where the mutation provably does NOT fire
// without it. They are not style notes.

/** Build a `load-artifacts` payload. */
export const graph = (phases, extra = {}) => ({
  featureDir: '/f', projectRoot: '/r', testCommand: 'pytest', testCommandStatus: 'detected', phases, ...extra,
})

export const task = (id, o = {}) => ({
  id, description: `do ${id}`, parallel: o.parallel ?? false,
  files: o.files ?? [`${id}.py`], done: o.done ?? false, ...o,
})

/** Default happy answers for every label the workflow spawns. */
export const baseCanned = (loadPayload) => (label) => {
  if (label === 'load-artifacts') return loadPayload
  if (label.startsWith('impl:')) return { id: label.slice(5), succeeded: true, summary: 's', tddStatus: 'cycle-confirmed', redConfirmed: true, greenConfirmed: true }
  if (label.startsWith('verify:')) return { refuted: false, reason: 'ok' }
  if (label.startsWith('gate:')) return { passed: true, summary: 'green' }
  return 'report text'
}

/** Compose: override specific labels on top of the happy path. */
export const withOverrides = (base, overrides) => (label, opts) => {
  for (const [match, value] of overrides) {
    if (typeof match === 'string' ? label === match : match(label)) {
      return typeof value === 'function' ? value : () => value
    }
  }
  return base(label, opts)
}

/** A throw the fixture can hand back through the stub's await. */
export const throws = (v) => () => { throw v }

export const FIXTURES = {
  // 2 phases, a done:true task. SC-017 needs BOTH: with one phase `notAttempted` is [] and a
  // mutation returning [] stays green; without a done:true task, `!t.done` is undiscriminating.
  twoPhases: () => graph([
    { name: 'Phase 1', tasks: [task('T001', { parallel: true }), task('T002', { parallel: true, done: true })] },
    { name: 'Phase 2', tasks: [task('T003')] },
  ]),

  // Duplicate id across phases, AND the run must HALT before the second one's phase — otherwise
  // both T001s are attempted, notAttempted is [] under either keying, and the id-keyed mutation
  // goes GREEN. The halt is what makes SC-013's mutation fire.
  duplicateId: () => graph([
    { name: 'Phase 1', tasks: [task('T001')] },
    { name: 'Phase 2', tasks: [task('T001')] },
  ]),

  // Single [P] task per phase, two phases — for gate tests. Phase 1's task must PASS verification,
  // or the :329 task-rejection halt fires BEFORE the gate ever spawns and SC-004's mutation goes
  // green for the wrong reason.
  twoPhasesSequential: () => graph([
    { name: 'Phase 1', tasks: [task('T001')] },
    { name: 'Phase 2', tasks: [task('T002')] },
  ]),

  // Two [P] tasks, one phase — the silent-drop fixture.
  parallelPair: () => graph([
    { name: 'Phase 1', tasks: [task('T001', { parallel: true }), task('T002', { parallel: true })] },
  ]),
}

// --- meta ------------------------------------------------------------------------------------

test('harness: the shipped workflow loads and its meta rewrite still matches', () => {
  const src = loadWorkflowSource()
  assert.ok(src.includes('const meta'), 'meta declaration missing after rewrite')
  assert.ok(!/^export /m.test(src), 'an unrewritten `export` remains — new Function would throw')
})

test('harness: drives the SHIPPED file end to end', async () => {
  const { result, spawned } = await drive({ canned: baseCanned(FIXTURES.parallelPair()) })
  assert.equal(result.completed, 2, 'both tasks should be accepted on the happy path')
  assert.ok(spawned.includes('load-artifacts'), 'loader never ran')
  assert.ok(spawned.some(l => l.startsWith('gate:Phase 1')), 'phase gate never ran')
  // Spike 3's measured amplitude: 2 tasks => 12 agents (1 loader + 2 impl + 6 verify + 1 gate +
  // update-tasks-md + completion-report). If this number moves, the fan-out changed. (#29)
  assert.equal(spawned.length, 12, `expected 12 agents for 2 tasks, got ${spawned.length}: ${spawned.join(', ')}`)
})

// =============================================================================================
// THE HARNESS MUST BE ABLE TO FAIL.
//
// This suite is code, and unexecuted code is unreliable regardless of who wrote it — this repo has
// proved that three times: `pipefail` + `grep -q` blinded three shell guards while they "passed";
// an earlier stub here read peak=1 forever, so deleting the feature under test left it green; and
// a reviewer's own smoke guards shipped with a false-green. So: prove the mechanism fires before
// trusting it to pass. (constitution principle 3)
// =============================================================================================

test('SC-007: makeRun executes in STRICT mode — a sloppy-mode escape would be a false green', async () => {
  // The shipped file is an ES module and therefore always strict. A `new Function` body is SLOPPY by
  // default. Without 'use strict' the harness runs DIFFERENT SEMANTICS from production: an
  // assignment to an undeclared identifier — an ordinary typo — passes green in CI and throws
  // ReferenceError on the first real run.
  //
  // NOTE `rejects`, not `throws`: the violation happens INSIDE the async arrow, so it rejects the
  // returned promise rather than throwing synchronously. Written with assert.throws this test fails
  // with "Missing expected exception" even though strict mode is working perfectly — which is how it
  // was first written here, and what running it immediately revealed.
  const strictOnlyBug = "undeclaredGlobal = 1; return 'reached'"

  await assert.rejects(
    () => makeRun(strictOnlyBug)(null, null, null, null, null),
    /undeclaredGlobal is not defined/,
    'makeRun must run strict — an undeclared assignment has to reject',
  )

  // ...and prove the mutation is REAL: without 'use strict' the same source RESOLVES, silently
  // swallowing the typo. If this half ever fails, the assertion above is decorative.
  const sloppy = new Function('agent', 'parallel', 'phase', 'log', 'args',
    `return (async () => {\n${strictOnlyBug}\n})()`)
  assert.equal(await sloppy(null, null, null, null, null), 'reached',
    'sloppy mode must silently PASS the typo — if it does not, SC-007 cannot tell strict from sloppy and is vacuous')
})

test('SC-006: the meta-rewrite assertion fires when the declaration is reworded', () => {
  // If `export const meta` is ever renamed, String.replace matches nothing and the harness would
  // test a stale shape — or nothing at all.
  const raw = 'export default const meta = {}\nreturn null'
  const src = raw.replace('export const meta', 'const meta')
  assert.equal(src, raw, 'precondition: this fixture must NOT match the rewrite')
  assert.throws(
    () => { assert.notStrictEqual(src, raw, 'rewrite matched nothing') },
    /rewrite matched nothing/,
    'the guard must fire when the rewrite is a no-op',
  )
})

test('SC-008: the label-multiset floor rejects a workflow that spawns nothing', async () => {
  // A ceiling with no floor passes MORE easily the more broken the file is: break the loader and the
  // workflow spawns one agent and quits, and any `<=` assertion sails through. Force the early
  // return and prove an exact-multiset assertion goes red instead.
  const { result, spawned } = await drive({
    canned: () => ({ featureDir: '/f', projectRoot: '/r', testCommand: '', phases: [] }),
  })
  assert.ok(result.error, 'precondition: an empty task graph must take the early-return path')
  assert.deepEqual(spawned, ['load-artifacts'], 'a broken loader spawns exactly one agent')
  assert.throws(
    () => assert.deepEqual([...spawned].sort(), ['load-artifacts', 'impl:T001', 'gate:Phase 1'].sort()),
    'an exact-multiset assertion must REJECT a run that did less — this is the floor',
  )
})

// =============================================================================================
// RESILIENCE — every test below MUST be RED against the unmodified file.
//
// A green test here is a test of nothing. Three of these were proven red by executed spikes
// before a line of the fix existed: the 1/1 silent drop, the 2/2 dead gates, the 3/3 unwritten
// tasks.md. That is this framework's own Iron Law applied to its own repair.
//
// ASSERT AT THE TOOL-CALL LEVEL — which labels spawned, how many invocations per label. Never on
// data an agent returned. (constitution principle 3)
// =============================================================================================

const SCHEMA_FAILURE = 'completed without calling StructuredOutput (after in-conversation nudge)'

for (const [contractName, parallel] of bothParallelContracts) {
  // Run the resilience suite against BOTH plausible parallel() contracts. With the fix in place the
  // thunk never rejects, so these agree — the discipline earns its keep against SC-002's PAIR
  // mutation, where the contract is what decides whether the task vanishes or the run dies.

  test(`SC-002 [${contractName}]: a crashed [P] implementer becomes an explicit rejection, never a silent drop`, async () => {
    const { result } = await drive({
      parallel,
      canned: withOverrides(baseCanned(FIXTURES.parallelPair()), [
        ['impl:T001', throws(new Error(SCHEMA_FAILURE))],
      ]),
    })
    // The bug: T001 vanishes, the gate runs green, and the run returns {"completed":1,"total":1} —
    // a PERFECT SCORE for a phase where the task never ran. Measured, Spike 2.
    assert.ok(result.halted, `the phase must halt; instead the run returned ${JSON.stringify(result)}`)
    const ids = (result.rejected ?? []).map(r => r.id)
    assert.ok(ids.includes('T001'), `T001 must appear in the halt's rejected list; got ${JSON.stringify(result.rejected)}`)
    assert.equal(result.total, 2, 'total must count the crashed task, not erase it from the denominator')
  })

  test(`SC-001 [${contractName}]: a persistently throwing sequential implementer halts the phase and does not kill the run`, async () => {
    const g = FIXTURES.twoPhasesSequential()
    const { result, callsFor } = await drive({
      parallel,
      canned: withOverrides(baseCanned(g), [['impl:T001', throws(new Error(SCHEMA_FAILURE))]]),
    })
    // Unfixed, the sequential path propagates the throw out of the script and the whole run dies.
    assert.ok(result.halted, 'the phase must halt cleanly rather than the run dying')
    assert.equal(callsFor('impl:T001'), 3, 'FR-001: bounded at 3 attempts (throw is retried)')
  })

  test(`SC-001b [${contractName}]: a NON-ERROR throw does not kill the run`, async () => {
    // `throw null` makes `e.message` in the catch throw a TypeError — the error handler becomes the
    // failure. Measured. Must be SEQUENTIAL: on the [P] path parallel swallows it and the
    // index-mapped fallback converts it to a rejection, so the same mutation goes green there.
    // That inversion — sequential dies, parallel is protected — is the opposite of this feature's
    // own thesis, which is why it gets its own test.
    const g = FIXTURES.twoPhasesSequential()
    const { result } = await drive({
      parallel,
      canned: withOverrides(baseCanned(g), [['impl:T001', throws(null)]]),
    })
    assert.ok(result.halted, 'a thrown null must halt cleanly, not escape as a TypeError')
  })
}

test('SC-003: a null-returning agent is invoked EXACTLY once — a terminal API error is never retried', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const { callsFor } = await drive({
    canned: withOverrides(baseCanned(g), [['impl:T001', () => null]]),
  })
  // null means the harness ALREADY exhausted its own backoff. Retrying pours load onto an API that
  // is already refusing us — the exact overload #29 exists to shed. Counted on the STUB: the retry
  // loop lives inside agentTyped, so this mutation is invisible from outside it.
  assert.equal(callsFor('impl:T001'), 1, 'FR-002: a null must NOT be retried')
})

test('SC-015: a throwing agent is invoked EXACTLY 3 times — the retry is bounded', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const { callsFor } = await drive({
    canned: withOverrides(baseCanned(g), [['impl:T001', throws(new Error(SCHEMA_FAILURE))]]),
  })
  // Nothing else pins FR-001's bound: set tries=10 and no other test notices, yet unbounded retry
  // against a hot API is the field report's own failure mode.
  assert.equal(callsFor('impl:T001'), 3, 'FR-001: 3 attempts total, not more')
})

test('SC-004: a DEAD phase gate halts — absence of confirmation is not confirmation', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const { result, spawned } = await drive({
    canned: withOverrides(baseCanned(g), [[l => l.startsWith('gate:'), () => null]]),
  })
  // The bug: `if (gate && !gate.passed)` lets null through, phase 2 builds on ungated work, and the
  // run returns {"completed":2,"total":2} — 6 gate invocations, 0 confirmations. Measured, Spike 5.
  //
  // THREE POSITIVE FLOORS. The negative alone ("phase 2 never ran") is vacuous — it holds whenever
  // phase 2 doesn't run for ANY reason, including the :329 halt firing before the gate ever spawns.
  assert.ok(spawned.some(l => l.startsWith('gate:Phase 1')), 'FLOOR (a): the gate path must actually have been reached')
  assert.ok(result.halted, 'the phase must halt on a dead gate')
  assert.equal(result.haltedAt, 'Phase 1', 'FLOOR (c): must halt at the gate, not elsewhere')
  assert.match(result.reason, /gate agent died|never confirmed/i,
    `FLOOR (c): the reason must name the gate as DIED, not failed, and not a task rejection; got: ${result.reason}`)
  assert.ok(!spawned.some(l => l === 'impl:T002'), 'phase 2 must never run on an unconfirmed gate')
})

test('SC-016: a gate FAILURE still reports the failing tests', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const { result } = await drive({
    canned: withOverrides(baseCanned(g), [
      [l => l.startsWith('gate:'), () => ({ passed: false, summary: '3 tests failed', failures: ['test_a', 'test_b'] })],
    ]),
  })
  // :364 carried `failures`. Dropping it loses the failing-test list at exactly the moment the gate
  // fails — the one moment the operator needs it.
  assert.ok(result.halted)
  assert.deepEqual(result.failures, ['test_a', 'test_b'], 'the failing-test list must survive the halt')
})

test('SC-012: a run whose tasks.md write died must NOT report clean', async () => {
  const g = FIXTURES.parallelPair()
  const { result } = await drive({
    canned: withOverrides(baseCanned(g), [['update-tasks-md', () => null]]),
  })
  // The bug: :376 discards its result, so the run returns {"completed":2,"total":2} with NO checkbox
  // written — a green run whose only persisted artifact never happened, and whose next invocation
  // re-implements every task.
  assert.ok(result.halted, `a dead tasks.md write must not report clean; got ${JSON.stringify(result)}`)
  assert.match(result.reason, /tasks\.md|checkbox/i, 'the reason must say the WRITE failed, not the work')
  assert.match(result.reason, /do not re-run|complete|on disk/i,
    'the reason must tell the operator the work IS done, or they re-run everything')
})

test('SC-005 + SC-013 + SC-017: the ledger balances and is not fooled by a duplicate model-authored id', async () => {
  const g = FIXTURES.duplicateId()
  // Halt in phase 1 so phase 2's duplicate T001 is never attempted. Without the halt both T001s run,
  // notAttempted is [] under either keying, and the id-keyed mutation goes GREEN.
  const { result } = await drive({
    canned: withOverrides(baseCanned(g), [
      [l => l.startsWith('verify:T001'), () => ({ refuted: true, reason: 'nope' })],
    ]),
  })
  assert.ok(result.halted)
  assert.equal(result.total, 2, 'both T001s are pending')
  const sum = (result.accepted?.length ?? 0) + (result.rejected?.length ?? 0) + (result.notAttempted?.length ?? 0)
  assert.equal(sum, result.total,
    `BALANCE: accepted+rejected+notAttempted must equal total; got ${sum} vs ${result.total} — ` +
    `a task vanished. Keying on the model-authored id does exactly this.`)
  assert.deepEqual(result.notAttempted, ['T001'], "phase 2's T001 was never attempted and must say so")
})

// =============================================================================================
// #31 — `testCommand: ""` conflated "this project has no tests" with "I could not detect them".
//
// Nothing distinguished them, and every consumer treated the second as the first: implementers
// could not confirm RED/GREEN, the lens had no suite, and the gate was TOLD to report passed:true
// for a project with no gate — so a DETECTION FAILURE produced a clean N/N run that verified
// nothing. This repo is that case: its suite is tests/smoke.sh, and the loader was told to look
// only for package.json/pytest/cargo/go.
// =============================================================================================

test('#31: an UNDETECTABLE test command halts at load — before any work is spawned', async () => {
  const g = graph([{ name: 'Phase 1', tasks: [task('T001')] }],
    { testCommand: '', testCommandStatus: 'undetectable' })
  const { result, spawned } = await drive({ canned: baseCanned(g) })
  // Nothing downstream can verify anything, so refuse to start rather than burn a full run and
  // report clean. The file's own bias: a task wrongly refused costs one round; wrongly accepted
  // ships a bug.
  assert.ok(result.halted, `must halt; got ${JSON.stringify(result)}`)
  assert.equal(result.haltedAt, 'Load')
  assert.match(result.reason, /could not|undetectable|args\.testCommand/i,
    'the reason must name the remedy — the operator has to know to pass args.testCommand')
  assert.deepEqual(spawned, ['load-artifacts'], 'NO implementer may spawn — that is the point of halting at load')
})

test('#31: a project that genuinely has NO tests still runs — absence is not failure', async () => {
  const g = graph([{ name: 'Phase 1', tasks: [task('T001')] }],
    { testCommand: '', testCommandStatus: 'none-exist' })
  const { result, spawned } = await drive({ canned: baseCanned(g) })
  // The carve-out is CORRECT for the case it was written for. Halting over a project that never
  // had tests would be a false alarm — this is the regression guard for that.
  assert.ok(!result.halted, `a genuinely test-less project must still run; got ${JSON.stringify(result)}`)
  assert.equal(result.completed, 1)
  assert.ok(spawned.some(l => l.startsWith('gate:Phase 1')), 'the gate still runs — it just has no suite to assert')
})

test('#31: the gate is not asked to run a suite that does not exist', async () => {
  const g = graph([{ name: 'Phase 1', tasks: [task('T001')] }],
    { testCommand: '', testCommandStatus: 'none-exist' })
  let gatePrompt = ''
  const { } = await drive({
    canned: withOverrides(baseCanned(g), [
      ['gate:Phase 1', () => ({ passed: true, summary: 'no suite' })],
    ]),
    // capture the prompt the gate actually receives
    args: { featureDir: '/f' },
  })
  // Re-drive capturing the prompt text (the stub kit records labels, not prompts).
  const kit = makeAgentStub(baseCanned(g))
  const agent = async (p, o = {}) => { if (o.label?.startsWith('gate:')) gatePrompt = p; return kit.agent(p, o) }
  await makeRun(loadWorkflowSource())(agent, parallelThrowToNull, () => {}, () => {}, { featureDir: '/f' })
  assert.ok(!/Full test suite.*must be green/i.test(gatePrompt),
    'with no suite in existence the gate must NOT be told "Full test suite — must be green" with no command')
  assert.match(gatePrompt, /no automated test suite|has no tests/i,
    'the gate must be told plainly that this project has no suite')
  // The loader must not grade its own homework. "none-exist" is the one status that silently disables
  // every verification gate, and it is model-authored — so the gate agent, which is a DIFFERENT agent
  // standing in the repo, is told to refute it. A prompt asking the model nicely is not a mechanism;
  // an independent agent that can say "I found tests/" is.
  assert.match(gatePrompt, /CHECK THAT CLAIM|claim is false/i,
    'the gate must be told to REFUTE the no-tests claim, not take the loader\'s word for it')
  assert.match(gatePrompt, /passed:false/,
    'the gate must know what to do when it finds tests the loader missed')
})

test('#31: args.testCommand overrides detection and makes an otherwise-undetectable repo runnable', async () => {
  // Without this, halt-on-undetectable has no remedy but editing the workflow. With it, THIS repo
  // can run its own workflow: args.testCommand = 'tests/smoke.sh'.
  const g = graph([{ name: 'Phase 1', tasks: [task('T001')] }],
    { testCommand: '', testCommandStatus: 'undetectable' })
  let gatePrompt = ''
  const kit = makeAgentStub(baseCanned(g))
  const agent = async (p, o = {}) => { if (o.label?.startsWith('gate:')) gatePrompt = p; return kit.agent(p, o) }
  const result = await makeRun(loadWorkflowSource())(
    agent, parallelThrowToNull, () => {}, () => {}, { featureDir: '/f', testCommand: 'tests/smoke.sh' })
  assert.ok(!result.halted, `an explicit testCommand must override an undetectable status; got ${JSON.stringify(result)}`)
  assert.match(gatePrompt, /tests\/smoke\.sh/, 'the gate must be given the operator-supplied command')
})

test('#31: a non-string or empty args.testCommand is rejected, not silently honoured', async () => {
  // A had no argument surface until now, so it inherits #29's lesson the moment it gains one:
  // `args` can arrive as a JSON blob, and a value that is not a usable command must not silently
  // become one. "" must not mean "detected an empty command".
  for (const bad of ['', '   ', 42, null, {}]) {
    const g = graph([{ name: 'Phase 1', tasks: [task('T001')] }],
      { testCommand: '', testCommandStatus: 'undetectable' })
    const result = await makeRun(loadWorkflowSource())(
      makeAgentStub(baseCanned(g)).agent, parallelThrowToNull, () => {}, () => {},
      { featureDir: '/f', testCommand: bad })
    assert.ok(result.halted,
      `args.testCommand=${JSON.stringify(bad)} is not a usable command and must NOT override the undetectable halt`)
  }
})

test('#31: an unrecognised testCommandStatus is treated as undetectable, never as fine', async () => {
  // The status is model-authored, so the model can return something outside the enum — a typo, a
  // hallucinated fourth state, or nothing at all if an older loader payload is replayed from cache.
  // The safe reading of a value we do not understand is "we do not know", never "everything is fine".
  // That is the whole of #31 in one line, so it gets a test: without one, deleting the fallback goes
  // unnoticed (verified — the mutation was green until this existed).
  for (const status of ['DETECTED', 'maybe', '', undefined, null, 42]) {
    const g = graph([{ name: 'Phase 1', tasks: [task('T001')] }],
      { testCommand: '', testCommandStatus: status })
    const { result } = await drive({ canned: baseCanned(g) })
    assert.ok(result.halted,
      `testCommandStatus=${JSON.stringify(status)} is not a status we understand and must halt, not proceed`)
    assert.equal(result.haltedAt, 'Load')
  }
})

test('#31: an incoherent loader answer (detected + empty command) is treated as undetectable', async () => {
  // The status is model-authored. `detected` with no command is self-contradictory, and this file
  // does not trust model-authored fields it can check — the [P] marker sets that precedent.
  const g = graph([{ name: 'Phase 1', tasks: [task('T001')] }],
    { testCommand: '', testCommandStatus: 'detected' })
  const { result } = await drive({ canned: baseCanned(g) })
  assert.ok(result.halted, 'a "detected" status with no command must not be believed')
})

// =============================================================================================
// #32 — the Iron Law's own evidence was collected and thrown away.
//
// The implementer was asked to report redConfirmed/greenConfirmed "based on output you actually
// observed, not intent". Those fields were declared in the schema, rendered into the verifier's
// prompt, and read by NO CODE — zero conditionals. So an implementer reporting redConfirmed:false,
// openly admitting the test never failed first, was accepted exactly like one that ran the full
// cycle. The only mitigation was that a verifier MIGHT refute on the prose — model judgment, in a
// file whose founding thesis is that a script guarantees the barrier because a model can talk
// itself past it.
//
// Not every task has a RED phase: this repo's own T012 was "bump the version in six files". So the
// implementer DECLARES tddStatus and a different agent REFUTES a false claim — the #31 pattern.
// =============================================================================================

const implSays = (over) => (label) =>
  label.startsWith('impl:') ? { id: label.slice(5), succeeded: true, summary: 's', ...over } : undefined

/** baseCanned, with the impl payload replaced. */
const withImpl = (g, over) => (label, opts) => implSays(over)(label) ?? baseCanned(g)(label, opts)

test('#32: an implementer that admits the test never failed first is NOT accepted', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const { result } = await drive({
    canned: withImpl(g, { tddStatus: 'cycle-confirmed', redConfirmed: false, greenConfirmed: true }),
  })
  // redConfirmed:false IS the admission that the test may assert nothing — which the test-integrity
  // lens calls "the single most common way an agent fakes completion". It was accepted anyway.
  assert.ok(result.halted, `must not accept an unconfirmed RED; got ${JSON.stringify(result)}`)
  assert.match(JSON.stringify(result.rejected), /red|never observed failing|TDD/i,
    'the rejection must name the missing RED evidence')
})

test('#32: omitting the evidence entirely is not acceptance either', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const { result } = await drive({ canned: withImpl(g, { tddStatus: 'cycle-confirmed' }) })
  // `undefined` rendered into the verifier's prompt as the literal text "red confirmed: undefined".
  // Absence of evidence is not evidence.
  assert.ok(result.halted, 'claiming cycle-confirmed while reporting no red/green must not be accepted')
})

test('#32: greenConfirmed is required too, not just red', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const { result } = await drive({
    canned: withImpl(g, { tddStatus: 'cycle-confirmed', redConfirmed: true, greenConfirmed: false }),
  })
  assert.ok(result.halted, 'a cycle is not confirmed until the test was seen to PASS as well')
})

test('#32: a task with no RED phase still runs, if the implementer says why', async () => {
  // The regression guard that keeps this usable. This repo's own tasks.md is full of these: the
  // version bump, the CI step, the CHANGELOG. Strict enforcement would halt on all of them and
  // someone would rightly rip the check out.
  const g = FIXTURES.twoPhasesSequential()
  const { result } = await drive({
    canned: withImpl(g, { tddStatus: 'not-applicable', tddNotApplicableReason: 'bumps a version string in six files; there is no behaviour to test' }),
  })
  assert.ok(!result.halted, `a declared non-TDD task must still run; got ${JSON.stringify(result)}`)
  assert.equal(result.completed, 2)
})

test('#32: "not applicable" without a reason is not a declaration, it is an escape hatch', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const { result } = await drive({ canned: withImpl(g, { tddStatus: 'not-applicable' }) })
  // Without this, `not-applicable` is a free pass any implementer can claim — the check would exist
  // and enforce nothing.
  assert.ok(result.halted, 'an unexplained not-applicable must not be accepted')
})

test('#32: an unrecognised tddStatus is unverified, never fine', async () => {
  const g = FIXTURES.twoPhasesSequential()
  for (const s of ['confirmed', '', undefined, null, true]) {
    const { result } = await drive({ canned: withImpl(g, { tddStatus: s, redConfirmed: true, greenConfirmed: true }) })
    assert.ok(result.halted, `tddStatus=${JSON.stringify(s)} is not a status we understand and must not be accepted`)
  }
})

test('#32: a project with NO test suite cannot be asked for a cycle it could never observe', async () => {
  // The #31 interaction. With no suite, RED/GREEN are unobservable by construction — demanding them
  // would halt every test-less project, which is the false alarm #31's carve-out exists to prevent.
  const g = graph([{ name: 'Phase 1', tasks: [task('T001')] }],
    { testCommand: '', testCommandStatus: 'none-exist' })
  const { result } = await drive({ canned: withImpl(g, { tddStatus: 'cycle-confirmed', redConfirmed: false }) })
  assert.ok(!result.halted, `a test-less project must not be held to TDD evidence; got ${JSON.stringify(result)}`)
})

test('#32: a task rejected on TDD evidence does not spawn three verifiers', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const { spawned } = await drive({
    canned: withImpl(g, { tddStatus: 'cycle-confirmed', redConfirmed: false }),
  })
  // Reject before the fan-out: there is nothing for three agents to adversarially verify about work
  // that already failed its own evidence check. This thing already spawns too many agents (#29).
  assert.ok(!spawned.some(l => l.startsWith('verify:')),
    `no verifier should spawn for an already-rejected task; got ${spawned.join(', ')}`)
})

test('#32: the test-integrity lens is told to refute a FALSE not-applicable claim', async () => {
  const g = FIXTURES.twoPhasesSequential()
  let lensPrompt = ''
  const kit = makeAgentStub(withImpl(g, { tddStatus: 'not-applicable', tddNotApplicableReason: 'nah' }))
  const agent = async (p, o = {}) => { if (o.label?.includes('test-integrity')) lensPrompt = p; return kit.agent(p, o) }
  await makeRun(loadWorkflowSource())(agent, parallelThrowToNull, () => {}, () => {}, { featureDir: '/f' })
  // The implementer must not grade its own homework. `not-applicable` is the one status that skips
  // the evidence check, so the lens that already reads the test diff is told to contradict it.
  //
  // Assert on text UNIQUE to the cross-check. The obvious assertions — /not-applicable/ and /refute/ —
  // both pass with the cross-check deleted: the base lens already says "Refute if: the assertion was
  // loosened", and verifyPrompt itself renders "claims NO test was needed". Matching those proves the
  // prompt exists, not that the cross-check does. Verified: with the loose assertions, removing the
  // whole block left this test green.
  assert.match(lensPrompt, /CHECK THAT CLAIM/,
    'the lens must be told to check the not-applicable claim, not just to look for weakened tests')
  assert.match(lensPrompt, /the claim is FALSE/,
    'the lens must be told what to conclude when the reason does not hold up')
  assert.match(lensPrompt, /version bump|config edit|docs change/i,
    'the lens needs the line between a genuine exemption and an inconvenient test')
})

// =============================================================================================
// #28 — a dead verifier silently shrank the quorum.
//
// The verdicts were collected with `.filter(Boolean)` — the same shape as the batch collector's
// silent drop — and acceptance read `refutations.length === 0 && verdicts.length > 0`. All three
// dead correctly blocked the task. TWO dead did not: the task was accepted on the strength of a
// SINGLE lens, with no signal that the other two never reported.
//
// The lenses are deliberately DIVERSE, not redundant — "redundant verifiers find the same thing;
// diverse ones catch failure modes the others are blind to". So losing two of three is not 33% less
// confidence. It can mean the one dimension that would have caught the defect is the one that went
// silent — including test-integrity, the lens that reads the test diff for a weakened assertion,
// described in this file as "the single most common way an agent fakes completion".
// =============================================================================================

const LENS_KEYS = ['test-integrity', 'requirement', 'regression']

test('#28: two dead verifiers must not accept a task on the strength of one', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const { result } = await drive({
    canned: withOverrides(baseCanned(g), [
      [l => l === 'verify:T001:test-integrity', () => null],
      [l => l === 'verify:T001:requirement', () => null],
      // only `regression` reports, and it says fine
    ]),
  })
  assert.ok(result.halted,
    `a task must not be accepted on 1 of 3 lenses; got ${JSON.stringify(result)}`)
  assert.match(JSON.stringify(result.rejected), /verif|lens|quorum|1 of 3|did not report/i,
    'the rejection must say the verification was incomplete, not invent a different reason')
})

test('#28: even ONE dead verifier blocks — a dead lens is uncertainty, and uncertainty refutes', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const { result } = await drive({
    canned: withOverrides(baseCanned(g), [[l => l === 'verify:T001:test-integrity', () => null]]),
  })
  // The file's own bias, verbatim: "Default to refuted=true when uncertain — a task wrongly accepted
  // ships a bug; a task wrongly refuted costs one more round." A lens that never reported is the
  // uncertainty that rule is about.
  assert.ok(result.halted, `2 of 3 lenses is not a verified task; got ${JSON.stringify(result)}`)
})

test('#28: all three dead still blocks (regression guard — this half already worked)', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const { result } = await drive({
    canned: withOverrides(baseCanned(g), [[l => l.startsWith('verify:T001'), () => null]]),
  })
  assert.ok(result.halted, 'three dead verifiers must never accept')
})

test('#28: the reason names WHICH lenses went silent, not just that something did', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const { result } = await drive({
    canned: withOverrides(baseCanned(g), [
      [l => l === 'verify:T001:test-integrity', () => null],
      [l => l === 'verify:T001:requirement', () => null],
    ]),
  })
  const reason = JSON.stringify(result.rejected)
  // "verification incomplete" sends the operator to read three transcripts. Naming the lens tells
  // them whether the dimension that matters to this task is the one that died.
  assert.match(reason, /test-integrity/, 'the reason must name the silent lens')
  assert.match(reason, /requirement/, 'both silent lenses must be named')
  assert.ok(!/regression/.test(reason.replace(/regression check|regressions/g, '')),
    'the lens that DID report must not be listed as silent')
})

test('#28: a lens whose THUNK throws is silent too, not vanished', async () => {
  // agentTyped returning null is handled by the .then() — that null never reaches the collector. The
  // index-map exists for the other path: a throw inside the thunk itself. verifyPrompt interpolates
  // impl fields, so a hostile impl reaches it. parallel() then converts that throw to null, and
  // filtering the null away would drop the lens, leave silent.length === 0, and accept the task on
  // two lenses — the bug, reintroduced through the back door.
  //
  // This test exists because the mutation `raw.map(...)` -> `raw.filter(Boolean)` was GREEN without
  // it: none of the other fixtures put a real null in `raw`, so the belt-and-braces looked like dead
  // code while actually being load-bearing.
  const g = FIXTURES.twoPhasesSequential()
  let boom = false
  const hostileImpl = {
    id: 'T001', succeeded: true, tddStatus: 'cycle-confirmed', redConfirmed: true, greenConfirmed: true,
    // verifyPrompt reads .summary — throw the first time a lens's prompt is built.
    get summary() { if (!boom) { boom = true; throw new Error('prompt construction exploded') } return 's' },
  }
  const { result } = await drive({
    canned: (label) => (label.startsWith('impl:') ? hostileImpl : baseCanned(g)(label)),
  })
  assert.ok(result.halted, `a lens whose thunk threw must not silently shrink the quorum; got ${JSON.stringify(result)}`)
  assert.match(JSON.stringify(result.rejected), /never reported|unverified/i,
    'a thrown thunk must be reported as a lens that did not report')
})

test('#28: a refutation still wins over a dead lens — the refuter is the more urgent news', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const { result } = await drive({
    canned: withOverrides(baseCanned(g), [
      [l => l === 'verify:T001:test-integrity', () => ({ refuted: true, reason: 'assertion was deleted' })],
      [l => l === 'verify:T001:requirement', () => null],
    ]),
  })
  assert.ok(result.halted)
  assert.match(JSON.stringify(result.rejected), /assertion was deleted/,
    'a real refutation must survive into the reason, not be masked by the quorum complaint')
})

test('#28: all three reporting and none refuting still accepts — the happy path is untouched', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const { result, spawned } = await drive({ canned: baseCanned(g) })
  assert.ok(!result.halted, `a fully verified task must still be accepted; got ${JSON.stringify(result)}`)
  assert.equal(result.completed, 2)
  for (const k of LENS_KEYS) {
    assert.ok(spawned.includes(`verify:T001:${k}`), `lens ${k} should have run`)
  }
})

// =============================================================================================
// #29 — fan-out amplitude. Measured, not argued: 2 tasks => 12 agents, peak 6, of which THREE run
// a full test suite where one would do. On a 728-test / ~12-minute suite that is the shape that
// trips a shared rate limit, and the retries then pile on more load. One verifier hit 529 twenty-one
// times before the run died.
//
// PRIOR ART — the adversarial review measured all of this; do not re-derive it:
//   * the semaphore ALGORITHM survived every attack (no lost wakeup, no starvation at 200 arrivals,
//     balanced accounting across the retry path, correct under drop-to-1 and nested fan-out). It is
//     not the thing that was broken.
//   * its INPUT VALIDATION was: `0`/`-1` hang the run forever having spawned nothing; `"abc"` deletes
//     the cap entirely (measured peak 20/20, because `active >= NaN` is always false); `2.5` silently
//     becomes 3. `??` does not catch `0` — which is how a user writes "unlimited".
//   * `assert.ok(peak <= cap)` is a CEILING WITH NO FLOOR: it passes more easily the more broken the
//     file is. Break the loader and peak collapses to 1. Assertions below use strictEqual against the
//     cap the test passed in, plus a floor, plus a fixture whose UNBOUNDED peak exceeds the cap.
// =============================================================================================

/** Drive with an instrumented stub that records true concurrency. The stub MUST await. */
async function driveMeasuringPeak({ canned, args }) {
  let inFlight = 0, peak = 0
  const spawned = []
  const logs = []
  const agent = async (p, o = {}) => {
    spawned.push(o.label)
    peak = Math.max(peak, ++inFlight)
    await new Promise(r => setTimeout(r, 2))   // a real yield — see the un-awaited-stub trap
    inFlight--
    return canned(o.label, o)
  }
  const result = await makeRun(loadWorkflowSource())(
    agent, parallelThrowToNull, () => {}, m => logs.push(m), args ?? { featureDir: '/f' })
  return { result, peak, spawned, logs }
}

/** N parallel tasks: unbounded peak is well above any cap we test, so the assertion can fail. */
const wideGraph = (n) => graph([{
  name: 'Phase 1',
  tasks: Array.from({ length: n }, (_, i) => task(`T${String(i + 1).padStart(3, '0')}`, { parallel: true, files: [`f${i}.js`] })),
}])

test('#29: concurrency is capped at 4 by default', async () => {
  const g = wideGraph(8)
  const { peak } = await driveMeasuringPeak({ canned: baseCanned(g) })
  // 8 [P] tasks x (1 impl + 3 verifiers) is an unbounded peak far above 4 — so this CAN fail.
  assert.equal(peak, 4, `expected peak exactly 4, got ${peak} — a cap that never binds is not a cap`)
})

test('#29: args.maxConcurrency is honoured, and the assertion uses the cap the test passed in', async () => {
  for (const cap of [1, 2, 6]) {
    const g = wideGraph(8)
    const { peak } = await driveMeasuringPeak({ canned: baseCanned(g), args: { featureDir: '/f', maxConcurrency: cap } })
    // Hardcoding 4 here would let a fixture with cap:2 and a broken cap of 4 pass green.
    assert.equal(peak, cap, `maxConcurrency=${cap} but peak was ${peak}`)
  }
})

test('#29: args.sequential runs one agent at a time', async () => {
  const g = wideGraph(6)
  const { peak, result } = await driveMeasuringPeak({ canned: baseCanned(g), args: { featureDir: '/f', sequential: true } })
  assert.equal(peak, 1, `sequential must mean one in flight, got ${peak}`)
  assert.ok(!result.halted, 'sequential must still complete the run')
})

test('#29: maxConcurrency 0 and -1 must not hang the run', async () => {
  // MEASURED on the drafted design: `??` does not catch 0, `while (active >= 0)` is always true, and
  // every agent blocks on its first acquire — 20 agents spawned, none completed, forever. The plan's
  // own risk table called a hang "worse than crashing". `0` is how a user writes "unlimited".
  for (const bad of [0, -1]) {
    const g = wideGraph(4)
    const done = await Promise.race([
      driveMeasuringPeak({ canned: baseCanned(g), args: { featureDir: '/f', maxConcurrency: bad } }).then(() => 'completed'),
      new Promise(r => setTimeout(() => r('HUNG'), 2000)),
    ])
    assert.equal(done, 'completed', `maxConcurrency=${bad} hung the run`)
  }
})

test('#29: a non-numeric maxConcurrency must not delete the cap', async () => {
  // MEASURED: `"abc"` makes `active >= "abc"` always false, the semaphore vanishes, and peak hit 20/20
  // — the exact overload the cap exists to prevent, from a one-character typo. `args` is documented as
  // possibly arriving JSON-encoded, so a string is live, not paranoia.
  for (const bad of ['abc', null, {}, [], '4']) {
    const g = wideGraph(8)
    const { peak } = await driveMeasuringPeak({ canned: baseCanned(g), args: { featureDir: '/f', maxConcurrency: bad } })
    assert.ok(peak <= 4 && peak > 0,
      `maxConcurrency=${JSON.stringify(bad)} must fall back to the default cap, not remove it; peak was ${peak}`)
  }
})

test('#29: a fractional maxConcurrency does not silently round up', async () => {
  const g = wideGraph(8)
  const { peak } = await driveMeasuringPeak({ canned: baseCanned(g), args: { featureDir: '/f', maxConcurrency: 2.5 } })
  assert.equal(peak, 4, `2.5 is not an integer cap — it must be rejected for the default, not become 3; peak was ${peak}`)
})

// The throttle is asserted through the workflow's OWN log, not inferred from peak. Peak is the wrong
// instrument here: the drop lands mid-fan-out, so agents already past acquire() still finish and the
// observed peak reflects the cap *before* the drop. A racy fixture that infers it produces a test that
// passes for the wrong reason — the first version of these two did exactly that.

test('#29: the throttle drops concurrency to 1 after two terminal failures', async () => {
  let nulls = 0
  const g = wideGraph(8)
  const { logs } = await driveMeasuringPeak({
    canned: (label) => {
      // Two agents the harness gives up on — a null means its own backoff is spent.
      if (label.startsWith('verify:') && nulls < 2) { nulls++; return null }
      return baseCanned(g)(label)
    },
  })
  const drop = logs.find(l => /dropping concurrency to 1/i.test(l))
  assert.ok(drop, `the throttle must fire and say so; logs were:\n  ${logs.join('\n  ')}`)
  assert.match(drop, /2 terminal/i, 'the log must say how many failures tripped it, or it is unactionable')
})

test('#29: ONE terminal failure does NOT throttle — a single flake must not serialize a healthy run', async () => {
  let nulls = 0
  const g = wideGraph(8)
  const { logs } = await driveMeasuringPeak({
    canned: (label) => {
      if (label.startsWith('verify:') && nulls < 1) { nulls++; return null }
      return baseCanned(g)(label)
    },
  })
  // The floor for the test above: without this, a throttle that fires on the FIRST failure also
  // passes, and "2" would be decoration.
  assert.ok(!logs.some(l => /dropping concurrency/i.test(l)),
    'one terminal failure must not trip the throttle')
})

test('#29: retry exhaustion counts toward the throttle, not just a null return', async () => {
  // The drafted design incremented `terminal` only on a null from agent(), so a run dying of repeated
  // SCHEMA failures never tripped the throttle — and that is the symptom the field report actually
  // describes ("completed without calling StructuredOutput", alongside 21 consecutive 529s). A throw
  // that survives every retry is a terminal failure by any useful definition.
  //
  // Sequential fixture, deliberately: with [P] tasks retrying concurrently against a shared counter
  // the throws scatter, every task can burn one and then succeed, and nothing is exhausted. The first
  // version of this test did that and asserted a halt that never came.
  const g = graph([{ name: 'Phase 1', tasks: [task('T001'), task('T002')] }])
  const { logs } = await driveMeasuringPeak({
    canned: (label) => {
      if (label.startsWith('impl:')) throw new Error('completed without calling StructuredOutput')
      return baseCanned(g)(label)
    },
  })
  // Two implementers, each exhausting all 3 attempts => two terminal failures => throttle.
  assert.ok(logs.some(l => /gave up after 3 attempts/i.test(l)), 'precondition: an implementer must exhaust its retries')
  assert.ok(logs.some(l => /dropping concurrency to 1/i.test(l)),
    `retry exhaustion must count as terminal; logs were:\n  ${logs.join('\n  ')}`)
})

test('#29: the effective cap is logged before the first implementer spawns', async () => {
  const g = wideGraph(4)
  const { logs, spawned } = await driveMeasuringPeak({ canned: baseCanned(g), args: { featureDir: '/f', maxConcurrency: 2 } })
  const capLog = logs.findIndex(l => /concurrency/i.test(l) && /2/.test(l))
  assert.ok(capLog >= 0, `the effective cap must be logged; logs were:\n  ${logs.join('\n  ')}`)
  // An operator debugging an overloaded run needs to know what the cap actually was — after the fact
  // is too late to be useful, and after the fan-out is after the damage.
  assert.ok(!spawned.slice(0, 1).some(l => l?.startsWith('impl:')), 'cap must be known before implementers spawn')
})

test('#38: the implementer confirms its OWN test and does not run the full suite — the gate owns that', async () => {
  // Step 3 used to tell every implementer to run the whole suite, so a phase of N tasks ran N full
  // suites from implementers alone (plus the gate). #29 fixed the concurrency overload; this removes
  // the redundant volume. The phase gate already runs the whole suite per repo and catches any
  // regression the implementer's run would — same dedup #29 applied to the lens, one layer up.
  const g = FIXTURES.twoPhasesSequential()
  const { prompts } = await driveCapturing({ canned: baseCanned(g) })
  const impl = prompts['impl:T001']
  assert.ok(!/full (test )?suite/i.test(impl),
    'the implementer must NOT be told to run the full suite — that is the phase gate\'s job now')
  assert.match(impl, /own test|the phase gate/i,
    'it must confirm its own test and be told the gate owns whole-suite regression')
})

test('#38: only the GATE is told to RUN the full suite now — not the implementer, not the lenses', async () => {
  // The invariant after narrowing: exactly one KIND of agent is instructed to RUN the full suite — the
  // gate. This is the pair to #38's narrowing: "implementer does not run it" passes vacuously if the
  // whole-suite check vanished everywhere, so assert the gate STILL does.
  //
  // The loader is excluded deliberately: its job is to DETECT "the command that runs the full test
  // suite", so it names the phrase without running anything. Detecting the command and running the
  // suite are different acts; only the second is what amplitude counts.
  const g = FIXTURES.twoPhasesSequential()
  const { prompts } = await driveCapturing({ canned: baseCanned(g) })
  const runsSuite = Object.entries(prompts)
    .filter(([l]) => l !== 'load-artifacts')
    .filter(([, p]) => /Full test suite \(`/.test(p) || /run the full (test )?suite/i.test(p))
    .map(([l]) => l.replace(/:.*/, ''))
  const kinds = [...new Set(runsSuite)]
  assert.deepEqual(kinds, ['gate'], `only the gate may be told to RUN the full suite; got: ${runsSuite.join(', ')}`)
})

test('#29: the regression lens no longer runs the full suite — the gate owns that', async () => {
  const g = FIXTURES.twoPhasesSequential()
  const prompts = {}
  const kit = makeAgentStub(baseCanned(g))
  const agent = async (p, o = {}) => { prompts[o.label] = p; return kit.agent(p, o) }
  await makeRun(loadWorkflowSource())(agent, parallelThrowToNull, () => {}, () => {}, { featureDir: '/f' })

  const lensPrompt = Object.entries(prompts).find(([k]) => k.startsWith('verify:T001:') && !k.includes('integrity') && !k.includes('requirement'))?.[1] ?? ''
  assert.ok(!/FULL test suite|full test suite/i.test(lensPrompt),
    'no verifier may run the full suite — 2 tasks meant 3 full suites where 1 would do')
  assert.match(lensPrompt, /only this task|own test file/i,
    'the lens must be told to run only the task\'s own test')
})

test('#29: ...and the phase gate STILL runs it — the pair is the invariant', async () => {
  // The half that makes the previous test meaningful. "No lens runs the suite" passes vacuously if
  // the suite check is DELETED rather than MOVED: no lens asks, no gate asks, nothing runs the tests,
  // and both assertions are green. Neither half is the invariant; the pair is.
  const g = FIXTURES.twoPhasesSequential()
  let gatePrompt = ''
  const kit = makeAgentStub(baseCanned(g))
  const agent = async (p, o = {}) => { if (o.label?.startsWith('gate:')) gatePrompt = p; return kit.agent(p, o) }
  await makeRun(loadWorkflowSource())(agent, parallelThrowToNull, () => {}, () => {}, { featureDir: '/f' })
  assert.match(gatePrompt, /Full test suite/,
    'the gate must still own the full-suite check — if it is gone from both, nothing runs the suite at all')
})

// =============================================================================================
// #30 — multi-repo. The loader computed projectRoot by stripping /.specify/specs/<name>, which is
// right ONLY when the spec lives inside the repo it describes. In the FxCube monorepo the spec is in
// tasks/, and the code is in operations_api/ (pytest) and cube_ui/ (vitest) — so the strip yielded
// fxcube/tasks, a directory containing none of the code, and there is no single testCommand.
//
// Design decisions settled up front (issue #30 listed four open questions):
//   Q1 cross-repo task  -> REJECT with a tagged reason naming both repos
//   Q2 unmatched file   -> logged and attributed, never silently dropped
//   Q3 default repo     -> the FIRST listed repo (operator-ordered), never positional-by-path-length
//   Q4 normalisation    -> strip trailing slashes; a path of "/" is rejected, not a catch-all
// =============================================================================================

const REPOS = [
  { path: '/mono/operations_api', testCommand: 'poetry run pytest', testCommandStatus: 'detected', lintCommand: 'ruff check .' },
  { path: '/mono/cube_ui', testCommand: 'npx vitest run', testCommandStatus: 'detected', lintCommand: 'npm run typecheck' },
]
const monoGraph = (tasks, repos = REPOS, extra = {}) => ({
  featureDir: '/f', projectRoot: '/mono', repos, phases: [{ name: 'Phase 1', tasks }], ...extra,
})

/** Drive and capture every prompt by label, plus logs. */
async function driveCapturing({ canned, args }) {
  const prompts = {}
  const logs = []
  const kit = makeAgentStub(canned)
  const agent = async (p, o = {}) => { prompts[o.label] = p; return kit.agent(p, o) }
  const result = await makeRun(loadWorkflowSource())(
    agent, parallelThrowToNull, () => {}, m => logs.push(m), args ?? { featureDir: '/f' })
  return { result, prompts, logs, spawned: kit.spawned }
}

test('#30: a task routes to the repo that owns its files, and that repo\'s command reaches its prompts', async () => {
  const g = monoGraph([task('T001', { files: ['operations_api/operation/models.py'] })])
  const { prompts } = await driveCapturing({ canned: baseCanned(g) })
  assert.match(prompts['impl:T001'], /operations_api/, 'the implementer must cd into the owning repo')
  assert.ok(!/cube_ui/.test(prompts['impl:T001'] ?? ''), 'and not the other repo')
  // its GATE must run that repo's suite, not the frontend's
  assert.match(prompts['gate:Phase 1:operations_api'] ?? Object.values(prompts).find(p => /poetry run pytest/.test(p)) ?? '', /poetry run pytest/,
    'the gate for this repo must use its own test command')
})

test('#30: longest-prefix wins — app/ui/x goes to app/ui, not app', async () => {
  const repos = [
    { path: '/r/app', testCommand: 'a', testCommandStatus: 'detected', lintCommand: '' },
    { path: '/r/app/ui', testCommand: 'b', testCommandStatus: 'detected', lintCommand: '' },
  ]
  const g = monoGraph([task('T001', { files: ['app/ui/button.tsx'] })], repos, { projectRoot: '/r' })
  const { prompts } = await driveCapturing({ canned: baseCanned(g) })
  assert.match(prompts['impl:T001'], /\/r\/app\/ui/, 'must resolve to the deepest matching repo')
})

test('#30: a task spanning two repos is REJECTED, and the reason names both', async () => {
  const g = monoGraph([task('T001', { files: ['operations_api/api.py', 'cube_ui/src/App.tsx'] })])
  const { result } = await driveCapturing({ canned: baseCanned(g) })
  assert.ok(result.halted, `a cross-repo task must halt; got ${JSON.stringify(result)}`)
  const reason = JSON.stringify(result.rejected)
  assert.match(reason, /operations_api/, 'must name the first repo')
  assert.match(reason, /cube_ui/, 'must name the second repo')
  assert.match(reason, /split|one task per repo|different suites/i, 'must tell the operator what to do')
})

test('#30: a no-files task goes to the FIRST listed repo, never positional-by-length', async () => {
  // The drafted bug chose the default by path length. To catch BOTH "longest" and "shortest"
  // mutations, the first-listed repo must be neither the longest nor the shortest — so it takes THREE
  // repos, ordered [middle, longest, shortest]. Only "first-listed" gives the right answer for all.
  const repos = [
    { path: '/w/svc_mid', testCommand: 'm', testCommandStatus: 'detected', lintCommand: '' },      // first, middle length
    { path: '/w/service_longest', testCommand: 'l', testCommandStatus: 'detected', lintCommand: '' }, // longest
    { path: '/w/ui', testCommand: 's', testCommandStatus: 'detected', lintCommand: '' },            // shortest
  ]
  const g = monoGraph([task('T001', { files: [] })], repos, { projectRoot: '/w' })
  const { prompts } = await driveCapturing({ canned: baseCanned(g) })
  assert.match(prompts['impl:T001'], /\/w\/svc_mid\b/, 'a no-files task must go to the FIRST listed repo, not the longest or shortest path')
})

test('#30: a prefix-sibling directory is not a false match — apple/x must not match repo app', async () => {
  // The `+ '/'` boundary earns its keep only when a SHORTER repo is a false prefix and no longer repo
  // matches (a longer real match would win the longest-first `find` and hide the bug). Construct that:
  // repos [service (first/default), app], and a file in `apple/` — which belongs to neither.
  //   with the boundary:    /r/apple/x startsWith neither /r/service/ nor /r/app/ -> unmatched
  //                         -> the DEFAULT repo (service, first-listed).
  //   WITHOUT the boundary: /r/apple/x startsWith /r/app -> falsely matched to app.
  // So the boundary is the difference between routing to `service` and misrouting to `app`.
  const repos = [
    { path: '/r/service', testCommand: 's', testCommandStatus: 'detected', lintCommand: '' },
    { path: '/r/app', testCommand: 'a', testCommandStatus: 'detected', lintCommand: '' },
  ]
  const g = monoGraph([task('T001', { files: ['apple/button.tsx'] })], repos, { projectRoot: '/r' })
  const { prompts } = await driveCapturing({ canned: baseCanned(g) })
  assert.match(prompts['impl:T001'], /REPO ROOT: \/r\/service(\s|$)/m,
    'apple/x belongs to no repo -> it must fall to the default (service), never falsely match app')
  assert.ok(!/REPO ROOT: \/r\/app(\s|$)/m.test(prompts['impl:T001']), 'and must NOT misroute to app')
})

test('#30: a file matching no repo is logged and attributed, not silently ignored', async () => {
  // ["CHANGELOG.md", "operations_api/api.py"] — CHANGELOG.md matches no repo. The old hits.size===1
  // silently dropped it. It must be surfaced.
  const g = monoGraph([task('T001', { files: ['CHANGELOG.md', 'operations_api/api.py'] })])
  const { result, logs, prompts } = await driveCapturing({ canned: baseCanned(g) })
  assert.ok(!result.halted, 'one matched repo + a root file still routes (to the matched repo)')
  assert.match(prompts['impl:T001'], /operations_api/, 'routes to the repo the matched file owns')
  assert.ok(logs.some(l => /CHANGELOG\.md/.test(l) && /operations_api|attributed|matched no repo/i.test(l)),
    `the unmatched file must be logged, not dropped; logs:\n  ${logs.join('\n  ')}`)
})

test('#30: args.repos overrides loader detection', async () => {
  const g = monoGraph([task('T001', { files: ['svc/main.go'] })], REPOS)   // loader says operations_api/cube_ui
  const override = [{ path: '/w/svc', testCommand: 'go test ./...', testCommandStatus: 'detected', lintCommand: '' }]
  const { prompts } = await driveCapturing({ canned: baseCanned(g), args: { featureDir: '/f', repos: override } })
  assert.match(prompts['impl:T001'], /\/w\/svc/, 'args.repos must win over the loader')
  assert.match(prompts['gate:Phase 1:svc'] ?? Object.values(prompts).find(p => /go test/.test(p)) ?? '', /go test/, 'and carry its command')
})

test('#30: a repo path with a trailing slash still matches its files (normalisation)', async () => {
  const repos = [{ path: '/mono/operations_api/', testCommand: 'pytest', testCommandStatus: 'detected', lintCommand: '' }]
  const g = monoGraph([task('T001', { files: ['operations_api/models.py'] })], repos)
  const { result, prompts } = await driveCapturing({ canned: baseCanned(g) })
  assert.ok(!result.halted, `a trailing slash must not break matching; got ${JSON.stringify(result.rejected ?? result)}`)
  assert.match(prompts['impl:T001'], /operations_api/, 'the file must still resolve to the repo')
})

test('#30: a repo path of "/" is rejected, not treated as a catch-all', async () => {
  const repos = [
    { path: '/', testCommand: 'x', testCommandStatus: 'detected', lintCommand: '' },
    { path: '/mono/operations_api', testCommand: 'pytest', testCommandStatus: 'detected', lintCommand: '' },
  ]
  // A no-files task exposes the filter: if "/" survives, it normalises to "" and becomes repos[0] —
  // the DEFAULT — and the prompt gets a bare `REPO ROOT: ` / `cd `. A task with files alone would be
  // saved by longest-prefix and hide the bug, so this drives the default path.
  const g = monoGraph([
    task('T001', { files: ['operations_api/models.py'] }),
    task('T002', { files: [] }),
  ], repos)
  const { prompts, result } = await driveCapturing({ canned: baseCanned(g) })
  assert.ok(!result.halted, `should route, not halt; got ${JSON.stringify(result.rejected ?? result)}`)
  assert.match(prompts['impl:T001'], /operations_api/, 'a file task must route to the real repo, not the "/" catch-all')
  // The no-files task must land in the real repo (the only surviving one), never an empty path.
  assert.match(prompts['impl:T002'], /REPO ROOT: \/mono\/operations_api/, 'the default repo must be real, not the dropped "/"')
  assert.ok(!/REPO ROOT: *(\n|$)/.test(prompts['impl:T002']), 'no bare REPO ROOT from an empty repo path')
})

test('#30: an undetectable status on ANY repo halts at load, naming the repo', async () => {
  const repos = [
    { path: '/mono/operations_api', testCommand: 'pytest', testCommandStatus: 'detected', lintCommand: '' },
    { path: '/mono/cube_ui', testCommand: '', testCommandStatus: 'undetectable', lintCommand: '' },
  ]
  const g = monoGraph([task('T001', { files: ['operations_api/a.py'] })], repos)
  const { result } = await driveCapturing({ canned: baseCanned(g) })
  assert.ok(result.halted, 'a repo whose command is undetectable must halt the whole run')
  assert.equal(result.haltedAt, 'Load')
  assert.match(result.reason, /cube_ui/, 'the halt must name the offending repo')
})

test('#30: the phase gate runs once per repo the phase touched', async () => {
  const g = monoGraph([
    task('T001', { parallel: true, files: ['operations_api/a.py'] }),
    task('T002', { parallel: true, files: ['cube_ui/b.tsx'] }),
  ])
  const { spawned } = await driveCapturing({ canned: baseCanned(g) })
  const gates = spawned.filter(l => l.startsWith('gate:'))
  assert.equal(gates.length, 2, `two repos touched => two gates; got ${gates.join(', ')}`)
  assert.ok(gates.some(l => /operations_api/.test(l)) && gates.some(l => /cube_ui/.test(l)),
    'one gate per repo, each identifiable')
})

test('#30: single-repo mode is unchanged — a payload with no repos[] still works', async () => {
  // The regression that matters most: every existing fixture is single-repo (testCommand at ctx level,
  // no repos). Single-repo must remain one code path, behaving exactly as before this feature.
  const g = FIXTURES.twoPhasesSequential()   // testCommand:'pytest', testCommandStatus:'detected', no repos
  const { result, spawned } = await driveCapturing({ canned: baseCanned(g) })
  assert.ok(!result.halted, `single-repo must still complete; got ${JSON.stringify(result)}`)
  assert.equal(spawned.filter(l => l.startsWith('gate:')).length, 2, 'one gate per phase, as before (2 phases)')
})

test('SC-017: a done:true task is excluded from total, and an unreached phase is notAttempted', async () => {
  const g = FIXTURES.twoPhases()
  const { result } = await drive({
    canned: withOverrides(baseCanned(g), [
      [l => l.startsWith('verify:T001'), () => ({ refuted: true, reason: 'nope' })],
    ]),
  })
  assert.ok(result.halted)
  assert.equal(result.total, 2, 'T002 is done:true and must not count toward total')
  const sum = result.accepted.length + result.rejected.length + result.notAttempted.length
  assert.equal(sum, result.total, `balance ${sum} vs total ${result.total}`)
  assert.deepEqual(result.notAttempted, ['T003'], 'phase 2 never ran')
})
