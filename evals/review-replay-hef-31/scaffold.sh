#!/usr/bin/env bash
# Fixture: HEF-31's first rejected change (merge-forward, round 1) on feature/merge-forward over its diff base — the
# corpus defects present there: D31-1, D31-2, D31-3, D31-4, D31-5 (exhaustive-review FR-017).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  40bbbc9d098c1ceca357f7e76df469173b68dccb 6707703cb1227d9227418253c2017b71fa5ae5a0 merge-forward
