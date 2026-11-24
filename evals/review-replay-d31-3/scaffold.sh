#!/usr/bin/env bash
# Fixture: HEF-31 round 2's rejected change (merge-forward) on feature/merge-forward over its diff base — corpus defect
# D31-3, the forward cap compares pr_url exactly (exhaustive-review FR-016).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  40bbbc9d098c1ceca357f7e76df469173b68dccb 0dec11dc4de3e1dd5e011f26e4fc76ce81bc17b8 merge-forward
