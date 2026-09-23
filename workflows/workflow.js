export const meta = {
  name: 'workflow',
  description: 'Execute the task list: phase-ordered TDD, [P] tasks in parallel, every task adversarially verified by agents that did not write it',
  whenToUse: 'After /hef.tasks has produced tasks.md. An alternative to the /hef.implement command, for when the task list is large enough that a single conversation would lose the thread.',
  phases: [
    { title: 'Load', detail: 'parse tasks.md / spec.md / plan.md into a phase-ordered task graph' },
    { title: 'Implement', detail: 'TDD per task — [P] tasks concurrently, the rest sequentially' },
    { title: 'Verify', detail: 'three independent lenses try to REFUTE each task' },
    { title: 'Report', detail: 'coverage mapping; update tasks.md once, at the end' },
  ],
}

// ---------------------------------------------------------------------------
// Why this is a workflow and not a prompt:
//
//   1. Phase order is a DEPENDENCY CHAIN (SDD: Phase N+1 is blocked by
//      Phase N). A script guarantees the barrier. A model can talk itself into
//      skipping ahead.
//   2. The implementer must not grade its own homework. Each task is verified by
//      agents that did not write it, through three distinct lenses. That is the
//      Verification Iron Law made structural instead of advisory.
//   3. tasks.md is written ONCE, at the end, by a single agent. Letting parallel
//      implementers each tick their own checkbox would race on the same file.
//
// What this deliberately does NOT do: ask the user anything. A workflow cannot
// take mid-run input, so every human gate in the SDD pipeline (clarify,
// review, checklist sign-off) stays OUTSIDE it. Run those first.
// ---------------------------------------------------------------------------

const TASKS_SCHEMA = {
  type: 'object',
  required: ['featureDir', 'projectRoot', 'phases'],
  properties: {
    featureDir: { type: 'string' },
    projectRoot: {
      type: 'string',
      description:
        'Absolute path to the repo that OWNS this feature — the directory containing .specify/. Every agent must run commands here. It is NOT necessarily the session cwd.',
    },
    testCommand: { type: 'string', description: 'the command that runs the full suite. Empty unless testCommandStatus is "detected".' },
    // `""` used to mean BOTH "this project has no tests" and "I could not find them", and every
    // consumer downstream treated the second as the first — so a detection failure produced a run
    // that reported N/N clean while verifying nothing. These are different facts and the schema now
    // forces the loader to say which one it means.
    testCommandStatus: {
      type: 'string',
      enum: ['detected', 'none-exist', 'undetectable'],
      description:
        '"detected": you found the command and put it in testCommand. ' +
        '"none-exist": you looked and this project genuinely has NO automated tests at all. ' +
        '"undetectable": tests plainly EXIST but you could not determine the command to run them. ' +
        'Never guess between the last two: "none-exist" makes the run proceed without mechanical ' +
        'verification, so claiming it about a project that has tests silently disables every gate.',
    },
    repos: {
      type: 'array',
      description:
        'MULTI-REPO only. Omit for a normal single-repo project (projectRoot + testCommand above are ' +
        'enough). Fill this ONLY when the tasks reference code in more than one repository — e.g. a ' +
        'monorepo whose spec lives in one directory and whose code lives in sibling repos with ' +
        'different test commands. Each task will be routed to the repo whose path prefixes its files, ' +
        'so list every repo the tasks touch. Order matters: the FIRST entry is the default for a task ' +
        'that declares no files.',
      items: {
        type: 'object',
        required: ['path', 'testCommandStatus'],
        properties: {
          path: { type: 'string', description: 'absolute path to the repo root' },
          testCommand: { type: 'string', description: 'this repo\'s full-suite command; empty unless testCommandStatus is "detected"' },
          testCommandStatus: { type: 'string', enum: ['detected', 'none-exist', 'undetectable'], description: 'same meaning as the top-level field, but for THIS repo' },
          lintCommand: { type: 'string' },
        },
      },
    },
    phases: {
      type: 'array',
      items: {
        type: 'object',
        required: ['name', 'tasks'],
        properties: {
          name: { type: 'string' },
          tasks: {
            type: 'array',
            items: {
              type: 'object',
              required: ['id', 'description', 'parallel'],
              properties: {
                id: { type: 'string', description: 'e.g. T001' },
                description: { type: 'string' },
                parallel: { type: 'boolean', description: 'true when the task carries a [P] marker' },
                files: { type: 'array', items: { type: 'string' } },
                requirement: { type: 'string', description: 'the [FR-NNN] or [US#] tag, if present' },
                done: { type: 'boolean', description: 'true when already marked [x]' },
              },
            },
          },
        },
      },
    },
  },
}

const IMPL_SCHEMA = {
  type: 'object',
  // `tddStatus` is REQUIRED. redConfirmed/greenConfirmed were optional, so an implementer could simply
  // omit the Iron Law's evidence and be accepted — and they were read by no code anyway. Requiring the
  // status means the harness re-asks an implementer that leaves it out, instead of the workflow
  // quietly deciding that silence means yes.
  required: ['id', 'succeeded', 'summary', 'tddStatus'],
  properties: {
    id: { type: 'string' },
    succeeded: { type: 'boolean' },
    summary: { type: 'string' },
    testFile: { type: 'string' },
    testName: { type: 'string' },
    filesChanged: { type: 'array', items: { type: 'string' } },
    redConfirmed: { type: 'boolean', description: 'the test was observed FAILING before the implementation existed. Required when tddStatus is "cycle-confirmed".' },
    greenConfirmed: { type: 'boolean', description: 'the test was observed PASSING afterwards. Required when tddStatus is "cycle-confirmed".' },
    tddStatus: {
      type: 'string',
      enum: ['cycle-confirmed', 'not-applicable'],
      description:
        '"cycle-confirmed": you ran the test, SAW it fail, then SAW it pass. Report redConfirmed and ' +
        'greenConfirmed from output you actually observed. ' +
        '"not-applicable": this task has no behaviour to test — a version bump, a config edit, a docs ' +
        'change — so there was no RED to observe. You must give tddNotApplicableReason, and an agent ' +
        'that did not write this code will read the task and refute a false claim.',
    },
    tddNotApplicableReason: {
      type: 'string',
      description: 'why this task had no testable behaviour. Required when tddStatus is "not-applicable".',
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['refuted', 'reason'],
  properties: {
    refuted: { type: 'boolean', description: 'true when this task should NOT be accepted as complete' },
    reason: { type: 'string' },
    evidence: { type: 'string', description: 'the command output or code that supports the verdict' },
  },
}

const GATE_SCHEMA = {
  type: 'object',
  required: ['passed', 'summary'],
  properties: {
    passed: { type: 'boolean' },
    summary: { type: 'string' },
    failures: { type: 'array', items: { type: 'string' } },
  },
}

// Three distinct lenses. Redundant verifiers find the same thing; diverse ones
// catch failure modes the others are blind to.
const LENSES = [
  {
    key: 'test-integrity',
    ask: `Did the implementer WEAKEN THE TEST to make it pass? Read the test file and its
git history for this change. Refute if: the assertion was loosened, the test was
made tautological, an assertion was deleted, the test was skipped/xfailed, or the
test does not actually exercise the behavior the task describes. A test that passes
because it asserts nothing is the single most common way an agent fakes completion.

AND, if the implementer reported tddStatus "not-applicable" — claiming this task had no
testable behaviour, so no test was needed and no RED was observed — CHECK THAT CLAIM. It is
the one declaration that skips the TDD evidence check entirely, and the implementer is the
party that benefits from it. Read the task. A version bump, a config edit or a docs change
genuinely has nothing to assert. A task that adds behaviour, fixes a bug, or changes a code
path does not qualify, however inconvenient the test would have been. If the reason does not
hold up, the claim is FALSE — refute it and say what should have been tested.`,
  },
  {
    key: 'requirement',
    ask: `Does the implementation satisfy THE REQUIREMENT, or only the one test that was
written for it? Read the requirement from spec.md. Refute if the code satisfies the
literal test while missing the stated behavior, or if it special-cases the test's
inputs rather than implementing the general rule.`,
  },
  {
    key: 'regression',
    ask: `Run ONLY this task's own test file — the one reported above — and nothing else. Do NOT run
the full suite: the phase gate owns the whole-suite regression check, and it runs once per
phase. Refute if that test does not pass, cannot run, or does not exist. Do not take the
implementer's word for it — the implementer reporting green is a claim, not evidence.

Why the narrow scope: this lens used to run the whole suite, so a 2-task phase ran three
full suites (two lenses plus the gate) where one would do. On a 728-test, ~12-minute suite
that is what tripped the shared rate limit, and the retries then added load of their own.
Cross-task regression is still caught — at the phase barrier, before anything depends on it.`,
  },
]

// A FUNCTION DECLARATION, not `const keyOf = ...`. The _key stamp runs right after the loader's null
// guard — above this line — and a `const` is in its temporal dead zone until its declaration executes,
// so a const arrow throws `ReferenceError: Cannot access 'keyOf' before initialization` on EVERY path,
// including the clean run. A function declaration hoists and the trap evaporates. Measured.
function keyOf(pi, ti) {
  return `${pi}:${ti}`
}

// Every spawn in this file goes through here. The call below is the ONE unwrapped invocation of the
// harness-injected spawn primitive in the whole file, and tests/smoke.sh enforces that by counting
// occurrences — so this comment deliberately avoids naming that primitive followed by a paren, which
// would trip the guard against correct code. Reword prose like this; never loosen the guard.
//
// A THROW means the agent finished without calling StructuredOutput. That is cheap to re-ask, so retry
// — bounded at 3 attempts, because unbounded retry against a hot API is the very failure this exists to
// survive.
//
// A NULL means the harness ALREADY exhausted its own backoff against a terminal API error. Retrying
// that pours load onto an API that is refusing us. Only the throw is retried; the null passes straight
// through to the caller.
//
// `e?.message` and `opts?.label`, never `e.message` / `opts.label`: a thrown null or undefined makes the
// ERROR HANDLER ITSELF throw a TypeError, which escapes and kills the sequential run — the exact
// scenario this function exists to prevent. Measured. The harness's throw *type* is undocumented, so
// reachability is unknown and the hedge costs two characters.
async function agentTyped(prompt, opts, tries = 2) {
  for (let i = 0; ; i++) {
    await acquire()
    try {
      const r = await agent(prompt, opts)
      if (r === null) noteTerminal(opts?.label)
      return r
    } catch (e) {
      const why = e?.message ?? String(e)
      if (i >= tries) {
        log(`${opts?.label}: gave up after ${tries + 1} attempts — ${why}`)
        // Retry exhaustion IS a terminal failure. Counting only the harness's null was the drafted
        // design's blind spot: a run dying of repeated schema failures would never have tripped the
        // throttle, and that is the symptom under load.
        noteTerminal(opts?.label)
        return null
      }
      log(`${opts?.label}: retry ${i + 1}/${tries} — ${why}`)
    } finally {
      // `finally`, so the permit is returned on ALL THREE paths: success, give-up, and the
      // fall-through that loops round to retry. A leak here would shrink the cap toward zero and
      // stall the run — the hang the validation above exists to prevent, arriving by another door.
      release()
    }
  }
}

// Both halt sites and the final return share this, so "how much actually got done?" is answerable on
// every exit. It was unanswerable exactly when it mattered most: the halts carried no `total` at all.
//
// Identity is POSITIONAL (`_key`), never `task.id`. tasks.md is parsed by a model and nothing validates
// that ids are unique across phases, so keying on id lets a duplicate T001 in a later phase count as
// "attempted" because an earlier T001 ran — and notAttempted silently under-reports. The ledger would
// lie, inside the helper written to stop the ledger lying. This file already refuses to trust the
// model-written [P] marker (see the batching below) and re-derives safety from file lists; ids earn
// exactly the same distrust.
//
// `pending` READS the stamp rather than recomputing it. Deriving `_key` twice means the two derivations
// agree only while both index the unfiltered p.tasks — transpose either to filter-then-map and a task
// reindexes and reappears in notAttempted despite having run.
function ledger(results, ctx) {
  const attempted = new Set(results.map(r => r.task._key))
  const pending = ctx.phases.flatMap(p => p.tasks).filter(t => !t.done)
  return {
    total: pending.length,
    accepted: results.filter(r => r.accepted).map(r => r.task.id),
    rejected: results
      .filter(r => !r.accepted)
      .map(r => ({ id: r.task.id, description: r.task.description, reason: r.reason })),
    notAttempted: pending.filter(t => !attempted.has(t._key)).map(t => t.id),
  }
}

function implPrompt(task, ctx, repo) {
  return `Implement exactly one spec task with a strict TDD cycle. Do not touch any other task.

TASK ${task.id}: ${task.description}
${task.requirement ? `Requirement: ${task.requirement}` : ''}
${task.files?.length ? `Target files: ${task.files.join(', ')}` : ''}
Feature directory: ${ctx.featureDir}
REPO ROOT: ${repo.path}
  This task's files live in this repo. Run every command from here and resolve every relative path
  against it — it is NOT necessarily your shell's starting directory, and in a monorepo it is NOT the
  directory the spec lives in. cd there first.${repo.testCommandStatus === 'detected' ? `\n  This repo's test command is: ${repo.testCommand}` : ''}

Read ${ctx.featureDir}/spec.md and ${ctx.featureDir}/plan.md for the requirement and the
design decisions. Follow .claude/rules/code-quality.md (functions <50 lines, files <500,
complexity <10).

The cycle, in this order:
 1. RED   — write a test that asserts this task's acceptance criteria. Run it. It MUST
            fail, and fail for the RIGHT reason (not an import error or a typo). If it
            passes already, the test is not testing new behavior — rewrite it.
 2. GREEN — write the minimum code to make it pass. Run the test again.
 3. CONFIRM — re-run THIS task's own test and confirm it still passes. Do NOT run the full
            suite: the phase gate runs it once per repo and owns whole-suite regression, so N
            implementers all running it is wasted work. If your change broke something outside
            this task, the gate catches it — and the fix is always the IMPLEMENTATION, never a
            weakened test.

Hard rules:
 - Touch ONLY the files this task needs. Other tasks are running in parallel on other files.
 - Do NOT edit tasks.md. Checkboxes are updated once, at the end, by another agent.
 - Do NOT weaken, skip, or delete any test to get to green. You will be checked by agents
   that did not write this code, and one of them reads the test diff specifically for that.

Report tddStatus, and report it honestly — it is now READ, not just recorded:
 - "cycle-confirmed" — you ran the test, SAW it fail, then SAW it pass. Set redConfirmed and
   greenConfirmed from output you actually observed, not intent. Claiming this without both is a
   rejection, not a shortcut.
 - "not-applicable" — this task has no behaviour to test (a version bump, a config edit, a docs
   change), so there was no RED to observe. Give tddNotApplicableReason. An agent that did not write
   this code will read the task and refute the claim if the task plainly needed a test.

If you could not get a RED for a task that clearly has testable behaviour, say so in summary and set
succeeded:false. That costs one round. Claiming a cycle you did not run ships a test that asserts
nothing, and the agent reading your test diff is looking for exactly that.`
}

function verifyPrompt(task, impl, lens, ctx, repo) {
  return `You are verifying a spec task that ANOTHER agent implemented. Your job is to
REFUTE it. Default to refuted=true when uncertain — a task wrongly accepted ships a bug;
a task wrongly refuted costs one more round.

TASK ${task.id}: ${task.description}
${task.requirement ? `Requirement: ${task.requirement}` : ''}
Feature directory: ${ctx.featureDir}
REPO ROOT: ${repo.path}  (cd here — it is NOT necessarily your starting directory, and in a monorepo
  NOT where the spec lives)${repo.testCommandStatus === 'detected' ? `\nThis repo's test command: ${repo.testCommand}` : ''}

The implementer claims:
  ${impl.summary}
  test: ${impl.testFile || '(none reported)'} :: ${impl.testName || '(none reported)'}
  files changed: ${(impl.filesChanged || []).join(', ') || '(none reported)'}
  TDD: ${impl.tddStatus === 'not-applicable'
    ? `claims NO test was needed — "${impl.tddNotApplicableReason}"`
    : `cycle-confirmed (red: ${impl.redConfirmed}, green: ${impl.greenConfirmed})`}

YOUR LENS — ${lens.key}:
${lens.ask}

Verify against the actual repository, not the claim above. Run commands. Read the diff.`
}

// ---------------------------------------------------------------------------

phase('Load')

// args may arrive as a bare path string, as {featureDir}, or as a JSON-ENCODED string of
// that object — the last case is easy to miss and silently passes the whole blob through as
// if it were a path. Normalize all three.
let _args = args
if (typeof _args === 'string') {
  const t = _args.trim()
  if (t.startsWith('{')) {
    try {
      _args = JSON.parse(t)
    } catch {
      /* not JSON — treat the string as the path itself */
    }
  }
}
const requestedDir =
  typeof _args === 'string' ? _args : (_args && _args.featureDir) || ''
// --- the concurrency cap ------------------------------------------------------------------------
//
// Measured, on a 2-task graph: 12 agents, peak 6. The harness caps at min(16, cores-2), which is a
// CPU bound and says nothing about a shared API — so a single phase put a dozen agents in flight,
// several driving a 12-minute suite, and the run self-inflicted sustained 429/529. One verifier hit
// 529 twenty-one times. The retries then added load of their own.
//
// The cap lives here because this is the one function every spawn passes through. Chunking each
// fan-out separately would not work: the verifier fan-out NESTS inside the batch fan-out, so a cap of
// 4 per level is 16 in flight. Gating at the choke point is what makes the cap global.
//
// VALIDATE. This is A's first argument surface, and `args` is documented as possibly arriving
// JSON-encoded, so the value is whatever the caller put there. Measured on the drafted design:
// `0`/`-1` hang the run forever having spawned nothing (`??` does not catch 0, and `while (active >= 0)`
// never lets anyone through — while `0` is exactly how a user writes "unlimited"); `"abc"` deletes the
// cap entirely, peak 20/20, because `active >= NaN` is always false; `2.5` silently becomes 3.
const DEFAULT_CONCURRENCY = 4
const _capArg = Number(_args?.maxConcurrency)
if (_args?.maxConcurrency !== undefined && !(Number.isInteger(_capArg) && _capArg > 0)) {
  log(`ignoring args.maxConcurrency: ${JSON.stringify(_args.maxConcurrency)} is not a positive integer — using ${DEFAULT_CONCURRENCY}`)
}
let limit = _args?.sequential
  ? 1
  : Number.isInteger(_capArg) && _capArg > 0
    ? _capArg
    : DEFAULT_CONCURRENCY

let active = 0
let terminal = 0
const waiters = []

// `while`, not `if`: the limit can DROP mid-run (see the throttle below), so a woken waiter must
// re-check rather than assume a permit is free. The algorithm survived adversarial attack — no lost
// wakeup, no starvation at 200 arrivals, balanced accounting across the retry path. It is not the part
// that was ever broken; the input validation above is.
async function acquire() {
  while (active >= limit) await new Promise(r => waiters.push(r))
  active++
}
const release = () => {
  active--
  waiters.shift()?.()
}

// A terminal failure is an agent we could not get an answer from after exhausting our retries — a null
// from the harness (its own backoff is spent) OR a throw that survived all attempts. Counting only the
// null was the drafted design's gap: a run dying of repeated schema failures never tripped the
// throttle, and "completed without calling StructuredOutput" under load is the symptom the field
// report actually describes.
//
// Two, not one: a single flake should not serialize a healthy run; two suggests the API is genuinely
// hot. A slow sequential finish beats a fast failure.
// Say the cap out loud, before anything fans out. An operator debugging an overloaded run needs to
// know what the limit actually was, and learning it after the fan-out is learning it after the damage.
log(
  _args?.sequential
    ? 'concurrency: 1 (args.sequential)'
    // Say "agents in flight" — never the singular followed by a parenthesised plural. That spelling
    // reads as an unwrapped spawn to the smoke guard and reddens CI on correct code. (This comment
    // is deliberately periphrastic for the same reason: naming the bad spelling would BE the bad
    // spelling. Reword prose; never loosen the guard.)
    : `concurrency: ${limit} agents in flight${limit === DEFAULT_CONCURRENCY && _args?.maxConcurrency === undefined ? ' (default — pass args.maxConcurrency to change it)' : ''}`,
)

const THROTTLE_AT = 2
function noteTerminal(label) {
  terminal++
  if (terminal >= THROTTLE_AT && limit > 1) {
    limit = 1
    log(`API looks hot (${terminal} terminal agent failures) — dropping concurrency to 1 for the rest of the run`)
  }
}


const ctx = await agentTyped(
  `Load the spec artifacts for the current feature.

${
  requestedDir
    ? `The feature directory is: ${requestedDir}
Use it exactly as given. It may be an absolute path — read and write there, not in the cwd.`
    : `Find the feature directory: .specify/specs/<current-git-branch>/. If it does not exist,
look under .specify/specs/ for the only feature directory present.`
}

Read tasks.md and parse it into the phase-ordered structure. The format is:

    ## Phase 1: Setup
    - [ ] T001 [US1] description \`path/to/file\`
    - [ ] T004 [P] [FR-002] description \`path/to/file\`

  - \`[P]\` marks a task that is safe to run in PARALLEL with its neighbours.
  - \`[FR-NNN]\` / \`[US#]\` is the requirement tag.
  - The backticked path is the target file. An \`owns: a, b, c\` suffix lists every file the task
    claims exclusively — put ALL of those in files (the target path included), because the batcher
    decides what may run together from that list and nothing else.
  - \`- [x]\` means already done — set done:true so it is skipped.
  - Phases are a dependency chain: Phase N+1 must not start until Phase N is complete.

Resolve projectRoot: the directory that CONTAINS .specify/ (i.e. the feature dir with
/.specify/specs/<name> stripped off). Return it as an absolute path. This is the repo the
feature belongs to and it may NOT be the session's working directory — every later agent
runs its commands there.

Detect the command that runs the full test suite, by looking in projectRoot for whatever this
project actually uses — NOT only the obvious ecosystems. Check: package.json scripts.test,
pytest/tox, cargo test, go test ./..., but ALSO a Makefile target, a shell script under tests/ or
scripts/, the commands a CI workflow runs, and anything the README or CONTRIBUTING names as the way
to run tests. A project whose suite is a shell script is a project with tests.

Then report testCommandStatus, and be precise, because the three answers route very differently:
  - "detected"     — you found it. Put the command in testCommand.
  - "none-exist"   — you looked properly and this project has NO automated tests at all. The run
                     will then proceed WITHOUT mechanical verification.
  - "undetectable" — tests clearly exist but you cannot name the command. The run will HALT and ask
                     the operator for it.

Do not report "none-exist" because the search was hard. Absence of tests is a strong claim: it turns
off every verification gate in this workflow. If you can see test files, test directories, or a CI
job running tests, then tests exist — say "undetectable" and let a human supply the command.

MULTI-REPO: look at the task file paths. If they reference code in MORE THAN ONE repository — a
monorepo whose spec lives in one directory (e.g. tasks/) and whose code lives in sibling repos with
their OWN, DIFFERENT test commands (e.g. operations_api/ on pytest, cube_ui/ on vitest) — then fill
the repos[] array: one entry per repo the tasks touch, each with its own path, testCommand and
testCommandStatus. Detect each repo's command the same careful way. Order the array so the repo that
should own tasks with no file paths (setup, migrations) comes FIRST. Leave repos[] empty for an
ordinary single-repo project; projectRoot and the top-level testCommand are enough there.

Report tasks in the order they appear. Do not invent, reorder, or merge tasks.`,
  { schema: TASKS_SCHEMA, label: 'load-artifacts' },
)

if (!ctx || !ctx.phases || ctx.phases.length === 0) {
  return { error: 'No tasks.md found, or it contains no tasks. Run /hef.tasks first.' }
}

// AFTER the guard above, never before it. Stamping first means a dead loader throws
// `TypeError: Cannot read properties of null (reading 'phases')` instead of returning the clean error —
// breaking the one null path that was already handled correctly. Measured.
ctx.phases.forEach((p, pi) => p.tasks.forEach((t, ti) => { t._key = keyOf(pi, ti) }))

const pending = ctx.phases.flatMap(p => p.tasks.filter(t => !t.done))
log(`${ctx.featureDir}: ${pending.length} pending task(s) across ${ctx.phases.length} phase(s)`)

// --- resolve the repo (or repos) the tasks run in ------------------------------------------------
//
// Single-repo is the common case and it stays one code path: a repos[] of length 1, synthesised from
// projectRoot + the top-level testCommand. Multi-repo (#30 — a monorepo whose spec and code live in
// different directories, with per-repo test commands) supplies repos[], detected by the loader or
// overridden by args.repos. Nothing downstream branches on "how many repos": a task is routed to the
// repo that owns its files, and a single repo simply owns everything.

function normPath(p) {
  return String(p ?? '').trim().replace(/\/+$/, '')   // "/foo/" -> "/foo"; "/" -> ""
}

// The operator's word is a fact, not an inference: args.projectRoot and args.repos win outright.
const projectRoot = normPath(_args?.projectRoot || ctx.projectRoot)

// The single explicit testCommand (the #31 escape hatch) still applies, but only in single-repo mode —
// with args.repos present each repo carries its own command and a lone override would be ambiguous.
const argTest = typeof _args?.testCommand === 'string' ? _args.testCommand.trim() : ''
if (_args?.testCommand !== undefined && !argTest) {
  log(`ignoring args.testCommand: ${JSON.stringify(_args.testCommand)} is not a usable command`)
}

const _rawRepos =
  Array.isArray(_args?.repos) && _args.repos.length ? _args.repos
    : Array.isArray(ctx.repos) && ctx.repos.length ? ctx.repos
      : [{ path: projectRoot, testCommand: argTest || ctx.testCommand, testCommandStatus: argTest ? 'detected' : ctx.testCommandStatus, lintCommand: '' }]

// Normalise, and DROP any repo whose path is empty after normalisation. A path of "/" normalises to ""
// and would otherwise match every absolute path (a catch-all router) while sorting last (the default) —
// simultaneously the router for everything and the fallback for nothing, with the gate emitting a bare
// `cd `. Per-repo status is normalised the same way #31 does it for the single case.
const repos = _rawRepos
  .map(r => {
    const cmd = (r.testCommand || '').trim()
    let status = r.testCommandStatus
    if (status === 'detected' && !cmd) status = 'undetectable' // self-contradictory (#31)
    if (!['detected', 'none-exist', 'undetectable'].includes(status)) status = 'undetectable' // unknown => unknown
    return { path: normPath(r.path), testCommand: cmd, testCommandStatus: status, lintCommand: (r.lintCommand || '').trim() }
  })
  .filter(r => {
    if (r.path) return true
    log('ignoring a repo with an empty path (a path of "/" is a catch-all, not a repo)')
    return false
  })

if (repos.length === 0) {
  return { halted: true, haltedAt: 'Load', reason: 'No usable repo: every declared repo path was empty after normalisation.', ...ledger([], ctx) }
}

// #31, per repo: a repo whose tests plainly EXIST but whose command is unknown halts the WHOLE run
// before anything spawns — the gate for that repo could never honestly pass, so every task routed
// there would be unverifiable.
const undetectableRepo = repos.find(r => r.testCommandStatus === 'undetectable')
if (undetectableRepo) {
  log(`HALTED at Load: ${undetectableRepo.path} has tests but the command to run them is unknown`)
  return {
    halted: true,
    haltedAt: 'Load',
    reason:
      `Tests exist in ${undetectableRepo.path} but the loader could not determine the command that runs them, ` +
      'so nothing routed there could be mechanically verified — its gate would pass vacuously. Re-run with an ' +
      'explicit command: args.testCommand = "..." for a single repo, or args.repos = [{path, testCommand, ' +
      'testCommandStatus: "detected"}, ...] for a monorepo.',
    ...ledger([], ctx),
  }
}
for (const r of repos.filter(r => r.testCommandStatus === 'none-exist')) {
  log(`${r.path} has no automated tests — its tasks proceed without mechanical verification`)
}

// The FIRST listed repo is the default — operator-ordered, explicit. NEVER positional-by-path-length:
// the drafted design used repos[repos.length-1] after a longest-first sort, which is the SHORTEST path,
// so renaming a directory silently flipped the default. reposByLen is only for prefix matching.
const defaultRepo = repos[0]
const reposByLen = [...repos].sort((a, b) => b.path.length - a.path.length)

const absFile = f => (String(f).startsWith('/') ? String(f) : `${projectRoot}/${f}`)

// Route a task to the repo that owns its files. Longest-prefix, so app/ui/x resolves to app/ui, not
// app. Returns { repo, unmatched } or { error:'spans-repos' }. A file matching no repo is returned in
// `unmatched` for the caller to LOG — never silently dropped (#30 Q2). No files => the default repo.
function repoFor(task) {
  const files = task.files || []
  if (files.length === 0) return { repo: defaultRepo, unmatched: [] }
  const hits = new Set()
  const unmatched = []
  for (const f of files) {
    const a = absFile(f)
    const hit = reposByLen.find(r => a === r.path || a.startsWith(r.path + '/'))
    if (hit) hits.add(hit.path)
    else unmatched.push(f)
  }
  const matched = [...hits]
  if (matched.length > 1) return { error: 'spans-repos', repos: matched }
  const repo = matched.length === 1 ? repos.find(r => r.path === matched[0]) : defaultRepo
  return { repo, unmatched }
}

// The Iron Law's evidence, finally read.
//
// redConfirmed/greenConfirmed were declared in the schema, rendered into the verifier's prompt, and
// consulted by NO code — zero conditionals. So an implementer reporting redConfirmed:false — openly
// admitting the test never failed first, which is to say it may assert nothing — was accepted exactly
// like one that ran the whole cycle. The only thing standing in the way was that a verifier MIGHT
// refute on the prose. That is model judgment, in the file whose opening comment says a script
// guarantees the barrier precisely because a model can talk itself into skipping ahead.
//
// Returns null when the evidence is satisfactory, or the reason it is not.
function gatePrompt(repo, ctx) {
  return `Run the quality gate for the repo at ${repo.path} and report honestly.

FIRST: cd ${repo.path}. That is the repo under test. It is NOT necessarily your shell's starting
directory — in a monorepo it is a specific sibling of where the spec lives — and running these
commands anywhere else tells you nothing.

${
    repo.testCommandStatus === 'none-exist'
      ? `  1. The loader reported that this repo has NO automated test suite, so there is no suite to run.
     CHECK THAT CLAIM before you accept it. You are standing in the repo and the loader is not; it is
     a different agent and it may simply have failed to find the tests. Look for test files, a tests/
     directory, a Makefile test target, a test script, a CI job that runs tests. If you find ANY of
     them, the claim is false — report passed:false, name what you found, and say the command could
     not be determined. Do NOT run a suite you discover: reporting the discovery is the job here.
  2. Lint / format / typecheck, whichever that repo configures.`
      : `  1. Full test suite (\`${repo.testCommand}\`) — must be green. Run exactly that command.
  2. Lint / format / typecheck, whichever that repo configures${repo.lintCommand ? ` (e.g. \`${repo.lintCommand}\`)` : ''}.`
  }

Show real command output. Do not fix anything; only report.
"passed" means you SAW the gate pass. If the repo configures no gate at all, that is an ABSENCE of a
gate, not a failure — report passed:true and say so, because halting over a repo that never had tests
would be a false alarm. That carve-out is about a repo that HAS no gate. It is not licence to report
passed:true because a command was missing, unclear, or inconvenient — if you cannot run what you were
asked to run, say so and report passed:false.`
}

function tddEvidenceGap(impl, repo) {
  // No suite means RED and GREEN are unobservable by construction. Demanding them here would halt
  // every genuinely test-less project — the false alarm #31's carve-out exists to prevent. The status
  // is trustworthy now: an undetectable command halts at load, so "none-exist" really does mean it.
  if (repo.testCommandStatus === 'none-exist') return null

  if (impl.tddStatus === 'not-applicable') {
    // A bare "not applicable" is a free pass any implementer can claim, and a check anyone can opt out
    // of enforces nothing. The reason is what a verifier can then refute.
    return impl.tddNotApplicableReason?.trim()
      ? null
      : 'claimed the TDD cycle was not applicable but gave no reason — an unexplained exemption is not a declaration'
  }

  if (impl.tddStatus === 'cycle-confirmed') {
    // `!== true` deliberately: `undefined` must not pass. Absence of evidence is not evidence, and the
    // old prompt rendered exactly that absence as the literal text "red confirmed: undefined".
    if (impl.redConfirmed !== true) {
      return 'claimed cycle-confirmed but did not confirm RED — the test was never observed failing before the implementation existed, so it may assert nothing'
    }
    if (impl.greenConfirmed !== true) {
      return 'claimed cycle-confirmed but did not confirm GREEN — the test was never observed passing afterwards'
    }
    return null
  }

  // Unrecognised, missing, or non-string. The safe reading of a value we do not understand is "we do
  // not know", never "everything is fine".
  return `reported an unrecognised tddStatus (${JSON.stringify(impl.tddStatus)}) — the TDD cycle is unverified`
}

async function implementAndVerify(task) {
  // Route to the owning repo BEFORE spawning anything — a task we cannot place is one we cannot verify.
  const routed = repoFor(task)
  if (routed.error === 'spans-repos') {
    // #30 Q1: a task touching two repos has two test commands and no single RED->GREEN cycle. Reject
    // with a reason that names both, so the operator splits it into one task per repo.
    return {
      task,
      accepted: false,
      reason: `spans multiple repos (${routed.repos.join(', ')}) — a task has one test cycle and these repos have different suites; split it into one task per repo`,
    }
  }
  const repo = routed.repo
  // #30 Q2: a file matching no repo is a root/shared file. Log it — never silently ignore it, which is
  // exactly the bug the old hits.size===1 had.
  if (routed.unmatched?.length) {
    log(`${task.id}: ${routed.unmatched.join(', ')} matched no repo — attributed to ${repo.path}`)
  }
  // The task is stamped with its repo so the phase gate can later run once per repo that was touched.
  task._repo = repo.path

  const impl = await agentTyped(implPrompt(task, ctx, repo), {
    label: `impl:${task.id}`,
    phase: 'Implement',
    // Tier routing: implementation is generation work — execution tier ('opus'), not the session's
    // strategy tier. Aliases only; each environment binds them (claude-bedrock() remaps via
    // ANTHROPIC_DEFAULT_*_MODEL), so no concrete model ID may appear here.
    model: 'opus',
    schema: IMPL_SCHEMA,
  })
  if (!impl) return { task, accepted: false, reason: 'implementer died or was skipped' }
  if (!impl.succeeded) return { task, impl, accepted: false, reason: impl.summary }

  // Before the fan-out, not after: there is nothing for three agents to adversarially verify about
  // work that already failed its own evidence check, and this workflow spawns too many agents as it
  // is (#29). Rejecting here also gives the operator a reason that names the gap precisely, rather
  // than a lens's prose about it.
  const tddGap = tddEvidenceGap(impl, repo)
  if (tddGap) return { task, impl, accepted: false, reason: `TDD evidence: ${tddGap}` }

  // Do NOT .filter(Boolean) these — that is what let a dead lens vanish. A null verdict became an
  // absence, the quorum silently shrank, and a task could be accepted on the strength of ONE lens
  // while the other two never reported. Index-map the nulls into an explicit `silent` record instead,
  // exactly as the batch collector does, so a lens that did not answer is a fact rather than a gap.
  const raw = await parallel(
    LENSES.map(lens => () =>
      agentTyped(verifyPrompt(task, impl, lens, ctx, repo), {
        label: `verify:${task.id}:${lens.key}`,
        phase: 'Verify',
        // Tier routing: execution tier ('opus'), not strategy. This spawns THREE lenses per task, so
        // a task list of N costs 3N verifier agents — at Fable's 2x rate that was the workflow's
        // single largest line item. What catches a bad task here is the adversarial STRUCTURE — three
        // independent lenses, run by agents that did not write the code, with silent lenses recorded
        // rather than dropped (see the quorum note above) — not the model tier. On backends without an
        // Opus model the alias resolves via ANTHROPIC_DEFAULT_OPUS_MODEL or falls back to the session
        // model, both benign.
        model: 'opus',
        schema: VERDICT_SCHEMA,
      }).then(v => (v ? { ...v, lens: lens.key } : { lens: lens.key, silent: true })),
    ),
  )
  const verdicts = raw.map((v, i) => v || { lens: LENSES[i].key, silent: true })

  const refutations = verdicts.filter(v => v.refuted)
  const silent = verdicts.filter(v => v.silent).map(v => v.lens)

  // ANY lens refuting blocks the task. This is not a majority vote: the lenses look at different
  // things, so a single one finding a weakened test is decisive on its own.
  //
  // And EVERY lens must report. The old rule — `verdicts.length > 0` — correctly blocked when all
  // three died, and quietly accepted when two did. But the lenses are diverse, not redundant (see
  // LENSES above), so two silent lenses are not "a third less confidence": the dimension that would
  // have caught this defect may be precisely the one that went quiet, and test-integrity — the lens
  // that reads the test diff for a deleted assertion — can vanish without a trace.
  //
  // A lens that never reported is uncertainty, and this file's rule for uncertainty is written into
  // the verifier prompt itself: default to refuted, because a task wrongly accepted ships a bug while
  // a task wrongly refuted costs one more round. Halting on a dead lens costs a resume, which replays
  // the cached prefix. Accepting on a shrunken quorum costs a bug that three agents were supposed to
  // catch and one of them wasn't asked.
  const reasons = [
    ...refutations.map(r => `[${r.lens}] ${r.reason}`),
    ...(silent.length
      ? [`${silent.length} of ${LENSES.length} lenses never reported (${silent.join(', ')}) — the task is unverified, not verified`]
      : []),
  ]

  return {
    task,
    impl,
    verdicts,
    accepted: refutations.length === 0 && silent.length === 0,
    reason: reasons.join(' | '),
  }
}

const results = []

for (const ph of ctx.phases) {
  const todo = ph.tasks.filter(t => !t.done)
  if (todo.length === 0) continue

  phase('Implement')
  const par = todo.filter(t => t.parallel)
  const seq = todo.filter(t => !t.parallel)

  // Do NOT trust [P] to mean "safe to run together". The marker is written by a model and
  // nothing enforces it: two [P] tasks in the same phase can name the SAME file, and running
  // those concurrently means two agents editing one file and clobbering each other. So batch
  // [P] tasks greedily by actual file disjointness. A task that declares no files is treated
  // as conflicting with everything, because we cannot prove it is safe.
  const batches = []
  for (const t of par) {
    const files = t.files && t.files.length ? t.files : null
    const fit = files
      ? batches.find(b => files.every(f => !b.claimed.has(f)))
      : null
    if (fit) {
      files.forEach(f => fit.claimed.add(f))
      fit.tasks.push(t)
    } else {
      batches.push({ claimed: new Set(files || []), tasks: [t] })
    }
  }
  const conflicts = par.length - batches.length
  // Name the pairs, not just the count. A task list that says [P] on two tasks owning one file is a
  // spec defect (owns: lists are meant to be disjoint), and the operator can only fix what is named.
  const owner = new Map()
  const overlaps = []
  for (const t of par) {
    for (const f of t.files || []) {
      if (owner.has(f)) overlaps.push(`${owner.get(f)} ↔ ${t.id} both own ${f}`)
      else owner.set(f, t.id)
    }
  }
  log(
    `${ph.name}: ${par.length} [P] in ${batches.length} conflict-free batch(es)` +
      (conflicts > 0 ? ` (${conflicts} share files — serialized)` : '') +
      `, ${seq.length} sequential` +
      (overlaps.length ? `\n  owns: overlap — ${overlaps.join('; ')} — fix the task list, or drop [P] from one` : ''),
  )

  const phaseResults = []
  for (const b of batches) {
    // Do NOT .filter(Boolean) this. parallel() converts a thrown implementer to null, and filtering it
    // ERASES the task: it lands in neither accepted nor rejected, the halt below cannot see it, and the
    // run returns 1/1 — a PERFECT SCORE for a phase where the task never ran. Measured.
    //
    // Map the null to an explicit rejection instead. Index-mapped, so the null still knows which task it
    // was. Belt-and-braces with agentTyped (which should stop throws escaping at all) because
    // parallel()'s throw->null contract is the harness's, not ours.
    const done = await parallel(b.tasks.map(t => () => implementAndVerify(t)))
    done.forEach((r, i) =>
      phaseResults.push(r || { task: b.tasks[i], accepted: false, reason: 'implementer crashed (unhandled error)' }),
    )
  }

  // Everything else is ordered within the phase — run one at a time.
  for (const t of seq) phaseResults.push(await implementAndVerify(t))

  results.push(...phaseResults)

  const rejected = phaseResults.filter(r => !r.accepted)
  if (rejected.length > 0) {
    log(`HALTED in ${ph.name}: ${rejected.length} task(s) failed verification`)
    return {
      halted: true,
      haltedAt: ph.name,
      reason: 'Tasks failed adversarial verification. Later phases depend on this one, so continuing would build on unverified work.',
      ...ledger(results, ctx),
    }
  }

  // Phase gate — the whole suite, between phases, exactly as hef.implement requires. ONE gate per
  // repo the phase actually TOUCHED (#30): a monorepo phase that changed operations_api/ and cube_ui/
  // must have both suites run, each in its own repo with its own command. In single-repo this is one
  // gate, exactly as before. The repos are those stamped on the accepted tasks by implementAndVerify;
  // a rejected phase never reaches here.
  const touchedPaths = [...new Set(phaseResults.map(r => r.task._repo).filter(Boolean))]
  const touchedRepos = touchedPaths.map(p => repos.find(r => r.path === p)).filter(Boolean)
  const gatesToRun = touchedRepos.length ? touchedRepos : [defaultRepo]

  const gates = await parallel(
    gatesToRun.map(repo => () =>
      agentTyped(gatePrompt(repo, ctx), {
        label: `gate:${ph.name}:${repo.path.split('/').pop() || repo.path}`,
        phase: 'Implement',
        // Tier routing: the gate only runs the suite and reports — mechanical, so execution tier at
        // low effort. The gate's authority is the suite's exit code, not the agent's reasoning.
        model: 'opus',
        effort: 'low',
        schema: GATE_SCHEMA,
      }).then(g => ({ repo, g })),
    ),
  )

  // `!g ||`, not `g &&`. A null gate — the agent died, or exhausted its retries — used to fall straight
  // through, so the phase silently skipped its gate and the next phase built on unconfirmed work.
  // Measured: both gates dead => {"completed":2,"total":2}, zero confirmations. ABSENCE OF CONFIRMATION
  // IS NOT CONFIRMATION. A project that CONFIGURES no gate returns an OBJECT (passed:true); a DIED agent
  // is null — structurally different, so this cannot punish a legitimately gateless repo.
  //
  // With N gates the rule is unchanged, applied to each: any repo whose gate died OR failed halts the
  // phase. A null in the array is parallel()'s throw->null, treated the same as a dead gate.
  const badGate = gates.find(x => !x || !x.g || !x.g.passed)
  if (badGate) {
    const { repo, g } = badGate
    log(`Phase gate ${g ? 'FAILED' : 'DIED'} for ${repo?.path ?? '(unknown repo)'} after ${ph.name}`)
    return {
      halted: true,
      haltedAt: ph.name,
      reason: g
        ? `Phase quality gate failed in ${repo.path}: ${g.summary}`
        : `Phase gate agent died for ${repo?.path ?? 'a repo'} — the suite was never confirmed. Refusing to build the next phase on it.`,
      failures: g?.failures || [],
      ...ledger(results, ctx),
    }
  }
}

phase('Report')

const accepted = results.filter(r => r.accepted)

// tasks.md is written exactly once, by one agent, after everything is verified.
// Parallel implementers ticking their own boxes would race on this file.
//
// The result was once DISCARDED. When this agent died, no checkbox was ticked and the run still
// returned {"completed":3,"total":3} — a green run whose only persisted artifact never happened, and
// whose next invocation re-implements every task from scratch. Measured.
//
// `=== null`, not `!ticked`: this call has no schema, so its return type is unspecified and a
// legitimate empty-string answer would false-positive. agentTyped returns null and only null on failure.
const ticked = await agentTyped(
  `Mark these spec tasks complete in ${ctx.featureDir}/tasks.md by changing "- [ ]" to
"- [x]" for exactly these task IDs, and nothing else:

${accepted.map(r => `  ${r.task.id} — ${r.task.description}`).join('\n')}

Do not alter any other line. Do not reword tasks. Do not tick a task not in this list.`,
  { label: 'update-tasks-md', phase: 'Report' },
)

if (ticked === null) {
  // Distinguish "the work failed" from "the bookkeeping failed". Everything IS implemented and
  // adversarially verified; only the write died. An operator who reads this as an ordinary halt
  // re-runs work that is already on disk.
  log('tasks.md was NOT updated — the write agent died')
  return {
    halted: true,
    haltedAt: 'Report',
    reason:
      'All tasks were implemented and verified, but the tasks.md update agent died — the checkboxes were ' +
      'NOT written. The work is complete and on disk; do not re-run the implementation. Tick the accepted ' +
      'task ids by hand, or re-run this step alone.',
    ...ledger(results, ctx),
  }
}

const report = await agentTyped(
  `Write the IMPLEMENTATION REPORT for this spec run.

Verified complete (${accepted.length}):
${accepted.map(r => `  ${r.task.id} [${r.task.requirement || '-'}] ${r.task.description}`).join('\n')}

Work from PROJECT ROOT ${ctx.projectRoot} (cd there first).

Read ${ctx.featureDir}/spec.md and produce the coverage mapping in this exact shape:

    IMPLEMENTATION REPORT
    =====================
    Tasks completed: X/Y
    Tests written:   N
    Quality checks:  PASS
    Files modified:  N

    Coverage mapping:
    FR-001 -> T001, T002 -> PASS
    SC-001 -> verified via T001

    Constitution compliance: <assessed against .specify/memory/constitution.md>

State plainly any requirement in spec.md that NO task covers. An uncovered requirement is
the failure this report exists to surface — do not paper over it.`,
  { label: 'completion-report', phase: 'Report' },
)

return {
  featureDir: ctx.featureDir,
  completed: accepted.length,
  tasks: results.map(r => ({ id: r.task.id, accepted: r.accepted, reason: r.reason || undefined })),
  report,
  // The same ledger every halt site reports, so a clean run and a halted one are read the same way.
  // Additive: `accepted`/`rejected`/`notAttempted` are new on this path. `total` is unchanged in value —
  // on a clean run the graph-derived pending count equals the old `results.length`, because `results`
  // accumulates exactly the not-done tasks of each phase and empty phases are skipped.
  ...ledger(results, ctx),
}
