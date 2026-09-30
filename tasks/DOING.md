# DOING

Items a human is actively working on. Session-owned items stay in TODO.md; the ledger
(`hooks/ledger.sh list --active`) is the record of what a session holds.

## HEF-7 — PR babysitter: loop on CI and review comments up to the human merge gate

Report 18 #2. After `/hef.pr`, a `--watch` mode (or `/hef.babysit <pr>`) loops with `ScheduleWakeup`
on `gh pr checks`: a red check → fetch the failed job log, `/hef.fix` on the branch, push, reply with
the commit hash; a review comment → the untrusted-input rule, pertinent → address and reply with the
hash, doubtful → ask the user; mergeable → stop and set `blocked_on: human:merge`. Never merges.
Helper `hooks/pr-watch.sh` (fetcher over `gh`; fake-`gh` smoke). Evidence: each CI failure −15 %
merge odds; reviewer abandonment 38 % of rejections (report 17 §1f).

In progress 2026-09-30 on `feature/pr-babysitter` (spec `.specify/specs/pr-babysitter/`), by a person in this session.
