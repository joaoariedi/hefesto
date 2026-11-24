#!/usr/bin/env bash
# Fixture: HEF-25 round 2's rejected change (run-survival) on feature/run-survival over its diff base — corpus defect
# D25-3, OOMPolicy=continue on a scope needs systemd 253 (exhaustive-review FR-016).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  7432f6faecd19be7dd444ad9c97676521bb81bd4 b615d3f2c0869e0f7f5d095438784a817489c4d3 run-survival
