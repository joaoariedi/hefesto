#!/usr/bin/env bash
# Fixture: HEF-31 round 4's rejected change (merge-forward) on feature/merge-forward over its diff base — corpus defect
# D31-5, a reopen leaves forwards[] unconsumed (exhaustive-review FR-016).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  40bbbc9d098c1ceca357f7e76df469173b68dccb 3f70473937bebc08219fd1381b6f68369fc3f21a merge-forward
