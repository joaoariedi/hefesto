#!/usr/bin/env bash
# Fixture: HEF-31's merged head (merge-forward; the second parent of PR #220's merge — the head the last verify
# passed) on feature/merge-forward over its diff base; a control, measurement only (exhaustive-review FR-017).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  40bbbc9d098c1ceca357f7e76df469173b68dccb 3b5bfb55cfbb56ff2476cdd0b1b24c662e7b7786 merge-forward
