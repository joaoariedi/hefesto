#!/usr/bin/env bash
# Fixture for eval probe 2 (exhaustive-review plan, "Probes first"): the same tree as review-replay-d22-3 (HEF-22
# round 2, feature/forge-setup), plus the probe's step list with the plugin's absolute hooks path written in — an eval
# prompt is user text, so the plugin-root variable is never substituted there. The list sits under .git/, outside the
# worktree copy review-repro.sh makes.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bash "$here/../../tests/fixtures/review-replay.sh" \
  21afbd6d39533daec5e8934bf6cdfdd81341b0ea f95e13b2b821145154edf04f7e4693522e3b4604 forge-setup
H="$(cd "$here/../.." && pwd)/hooks"
cat > .git/hef-probe.md <<PROBE
Run each step as ONE Bash call, exactly as written, and quote each call's full output and its exit status:

1. git --version
2. $H/speckit-helper.sh review-route
3. $H/speckit-helper.sh branch
4. $H/speckit-helper.sh pr-files
5. this call, as one command (the recipe is ONE single-quoted argument — amendment A3):
$H/review-repro.sh '. hooks/forge-lib.sh; forge_public_host metadata.google.INTERNAL && echo allowed || echo denied'
6. Read the file $H/review-repro.sh with the Read tool and say whether it was readable.
PROBE
