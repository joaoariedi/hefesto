# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs and sed scripts are single-quoted on purpose
#
# verify-fix-loop (HEF-57) smoke checks, part 18 — a verify FAIL goes back to the build stage: `ledger.sh rework` (the
# launcher-only move verify → implement with a generated, hashed brief), its refusals, the verify_rounds cap and its
# findings question, the person-only --past-cap, and the launcher's FAIL → rework routing, headless and in a lane.
#
# SOURCED by tests/smoke.sh after part 17b, never run on its own. A stub until T017 writes the cases.

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ sld >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-rework.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_, sld)"
  else echo "tests/smoke-rework.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

head_ "Verify-fix loop: a verify FAIL goes back to the build stage with its findings (verify-fix-loop FR-001..FR-008)"
