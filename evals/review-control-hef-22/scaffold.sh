#!/usr/bin/env bash
# Fixture: HEF-22's merged head (forge-setup; the second parent of PR #212's merge — the head the last verify passed)
# on feature/forge-setup over its diff base; a control, measurement only (exhaustive-review FR-017).
exec bash "$(dirname "$0")/../../tests/fixtures/review-replay.sh" \
  21afbd6d39533daec5e8934bf6cdfdd81341b0ea 8365d759b04a38d4d42414ed26a09cd670eb2e5d forge-setup
