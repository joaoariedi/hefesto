#!/usr/bin/env bash
# Fixture: HEF-22's first rejected change (forge-setup, round 1) on feature/forge-setup over its diff base — the
# corpus defects present there: D22-1, D22-3, D22-6 (exhaustive-review FR-017).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  21afbd6d39533daec5e8934bf6cdfdd81341b0ea ad63db844a79aeb2c94c0f7a3046cda55f416af2 forge-setup
