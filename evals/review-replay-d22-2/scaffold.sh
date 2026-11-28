#!/usr/bin/env bash
# Fixture: HEF-22 round 2's rejected change (forge-setup) on feature/forge-setup over its diff base — corpus defect
# D22-2, tests/smoke-forge.sh calls an undefined fg_case_livelock (exhaustive-review FR-016).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  21afbd6d39533daec5e8934bf6cdfdd81341b0ea f95e13b2b821145154edf04f7e4693522e3b4604 forge-setup
