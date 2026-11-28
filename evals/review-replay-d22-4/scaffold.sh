#!/usr/bin/env bash
# Fixture: HEF-22 round 3's rejected change (forge-setup) on feature/forge-setup over its diff base — corpus defect
# D22-4, the pushInsteadOf rewrite is written twice (exhaustive-review FR-016).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  21afbd6d39533daec5e8934bf6cdfdd81341b0ea 772239f5d5dd6241cc2ec844181a920e3d109c53 forge-setup
