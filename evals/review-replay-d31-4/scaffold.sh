#!/usr/bin/env bash
# Fixture: HEF-31 round 3's rejected change (merge-forward) on feature/merge-forward over its diff base — corpus defect
# D31-4, the pr_url guard applies only on outcome pr (exhaustive-review FR-016).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  40bbbc9d098c1ceca357f7e76df469173b68dccb 4e71a78c5b8d1e3f483ede0013bc3e298cad7b2d merge-forward
