#!/usr/bin/env bash
# Fixture: HEF-25's first rejected change (run-survival, round 1) on feature/run-survival over its diff base — the
# corpus defects present there: D25-1, D25-2 (exhaustive-review FR-017).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  7432f6faecd19be7dd444ad9c97676521bb81bd4 ddc4130c5a42d0666cd2e6d5db1f723c9fc01a0a run-survival
