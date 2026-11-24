#!/usr/bin/env bash
# Fixture: HEF-25 round 3's rejected change (run-survival) on feature/run-survival over its diff base — corpus defect
# D25-4, plan <id> --prepare no longer pins the RFC (exhaustive-review FR-016).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  7432f6faecd19be7dd444ad9c97676521bb81bd4 ad3bf2775db846dc5fcee4b3ec4c247be803d30f run-survival
