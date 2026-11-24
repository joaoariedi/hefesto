#!/usr/bin/env bash
# Fixture: HEF-25's merged head (run-survival; the second parent of PR #213's merge — the head the last verify passed)
# on feature/run-survival over its diff base; a control, measurement only (exhaustive-review FR-017).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  7432f6faecd19be7dd444ad9c97676521bb81bd4 c8834e66462ba0735e354febaf98ca081a40aa5c run-survival
