#!/usr/bin/env bash
# Fixture: HEF-22 round 2's rejected change (forge-setup) on feature/forge-setup over its diff base — corpus defect
# D22-3, hooks/forge-lib.sh's internal-host deny list is case-sensitive (exhaustive-review FR-016).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  21afbd6d39533daec5e8934bf6cdfdd81341b0ea f95e13b2b821145154edf04f7e4693522e3b4604 forge-setup
