# TODO

Items the orchestrator may claim (`/hef.orchestrate`). One heading per item: `## <ID> — title`,
then the body a worker receives as **data** (delimited and comment-stripped by
`status-board.sh --item`). Move a heading to DOING.md by hand only when a human is working on it;
the ledger, not this file, records what a session owns.

## HEF-1 — /hef.tasks accepts the light path without plan.md

`/hef.tasks` refuses to run when `plan.md` is missing, while `/hef.agent`'s light route says to
skip the plan. Found 2026-09-25 while building `/hef.status`; a throwaway plan was written to
unblock. Make the command accept the light path: when `spec.md` exists and `plan.md` does not,
generate tasks from the spec alone and say so in the tasks.md header. Keep the full path unchanged.
Add a smoke check: a spec dir with spec.md and no plan.md must not be rejected by the pre-flight
helper the command uses.

## HEF-2 — implement-phase-test-guard false positives on heredocs

`hooks/implement-phase-test-guard.sh` blocked a Bash command that *wrote* tests because its scan of
the command text saw `rm` tokens and the word `spec` inside a heredoc, and its `basename` call
chokes on tokens beginning with `---`. Both are false positives; the Edit-tool path is unaffected.
Fix both, keep every existing guard case green, and add the two false-positive commands as
fixtures that must pass. Mutation-check: reintroduce the token scan on heredoc bodies and confirm
the new fixtures go red.

## HEF-3 — namespace FR ids per spec in req-coverage

`FR-NNN` ids collide across specs: a test citing `FR-004` counts for every spec that declares an
`FR-004`. `speckit-helper.sh req-coverage` should scope citations to the spec that declares them,
for example by accepting `FR-004` only from tests under a path the spec names or by a
`<spec>/FR-004` form. Decide the form, document it in `docs/sdd.md`, update the smoke fixture that
covers `req-coverage --all` and `ELSEWHERE`, and keep the existing specs' coverage green.
