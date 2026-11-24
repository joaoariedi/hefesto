#!/usr/bin/env bash
# Fixture: HEF-22 round 4's rejected change (forge-setup) on feature/forge-setup over its diff base — corpus defect
# D22-6, an SSH pushurl gets a pushInsteadOf git ignores (exhaustive-review FR-016).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  21afbd6d39533daec5e8934bf6cdfdd81341b0ea c5e0e69443a3642cfdf93311d3b3accb9c17eb43 forge-setup
