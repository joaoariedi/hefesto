#!/usr/bin/env bash
# Fixture: HEF-25 round 1's rejected change (run-survival) on feature/run-survival over its diff base — corpus defect
# D25-1, a busy-refused plan launch (rc 75) still writes source.rfc (exhaustive-review FR-016).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  7432f6faecd19be7dd444ad9c97676521bb81bd4 ddc4130c5a42d0666cd2e6d5db1f723c9fc01a0a run-survival
