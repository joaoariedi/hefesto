# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs and sed scripts are single-quoted on purpose
#
# verify-fix-loop (HEF-57) smoke checks, part 18b — a finding the builder disputes is a person's question: the dispute
# recorded on the rework row (`record --rework-asked`), the person's answer paired with it (`rework_pairs`), stamped as a
# ruling (`record --rework-consumed`), handed to the next rework run and every later verify, and a ruled verify never
# recording a verified head.
#
# SOURCED by tests/smoke.sh after part 18, never run on its own. A stub until T018 writes the cases.

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ sld >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-rework-ruling.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_, sld)"
  else echo "tests/smoke-rework-ruling.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

head_ "Verify-fix loop: a disputed finding, the person's ruling, and the verify it reaches (verify-fix-loop FR-009..FR-012)"
