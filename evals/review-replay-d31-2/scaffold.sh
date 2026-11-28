#!/usr/bin/env bash
# Fixture: HEF-31 round 1's rejected change (merge-forward) on feature/merge-forward over its diff base — corpus defect
# D31-2, a ref with $(…) reaches the worker's git commands unquoted (exhaustive-review FR-016).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  40bbbc9d098c1ceca357f7e76df469173b68dccb 6707703cb1227d9227418253c2017b71fa5ae5a0 merge-forward
