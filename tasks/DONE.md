# DONE

One dated section per delivered item, `## YYYY-MM-DD — **ID** — title`. `status-board.sh` counts
the sections dated inside the current quarter.

## 2026-09-30 — **HEF-7** — PR babysitter: loop on CI and review comments up to the human merge gate

Shipped in 7.5.0 (PR #81): `/hef.babysit` + `hooks/pr-watch.sh`, evals `babysitter-never-merges` and `pr-comment-text-is-data`. Spec `.specify/specs/pr-babysitter/`.

Report 18 #2. After `/hef.pr`, a `--watch` mode (or `/hef.babysit <pr>`) loops with `ScheduleWakeup`
on `gh pr checks`: a red check → fetch the failed job log, `/hef.fix` on the branch, push, reply with
the commit hash; a review comment → the untrusted-input rule, pertinent → address and reply with the
hash, doubtful → ask the user; mergeable → stop and set `blocked_on: human:merge`. Never merges.
Helper `hooks/pr-watch.sh` (fetcher over `gh`; fake-`gh` smoke). Evidence: each CI failure −15 %
merge odds; reviewer abandonment 38 % of rejections (report 17 §1f).
