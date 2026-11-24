#!/usr/bin/env bash
# Fixture: HEF-22 round 1's rejected change (forge-setup) on feature/forge-setup over its diff base — corpus defect
# D22-1, a push rewrite recorded though its .git/config write failed; --remove removes a hand-added rewrite
# (exhaustive-review FR-016).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  21afbd6d39533daec5e8934bf6cdfdd81341b0ea ad63db844a79aeb2c94c0f7a3046cda55f416af2 forge-setup
