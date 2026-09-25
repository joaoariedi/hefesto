#!/bin/bash
# spec-cite-probe.sh — when a test that a spec relies on changes outside an implement phase, say so.
#
# PostToolUse on Edit|Write, advisory (exit 0, stderr), throttled to once a minute per file.
#
# The traceability chain is FR-NNN in spec.md → the token FR-NNN in a test file (req-coverage,
# /hef.verify). That check runs ONCE, at implementation. Afterwards nothing watches the other
# direction: a hotfix, a /hef.fix, or a refactor that edits a test citing FR-004 can change what
# the requirement means in practice while spec.md still claims the old behaviour. That is the
# "spec rot" the SDD critics measure (Scott Logic 2025-11; Thoughtworks *Assess*), and the reason
# this framework never calls the spec the source of truth: the tests are. So when the tests move,
# the spec's owner should hear about it — at the edit, not at the next audit.
#
# During /hef.implement the marker is set and citing tests are expected to change: silent then.
set -uo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$CWD" ] || [ -z "$FILE" ] && exit 0
[ -f "$CWD/.specify/.implement-in-progress" ] && exit 0
[ -d "$CWD/.specify/specs" ] || exit 0

# Same test-file notion as implement-phase-test-guard.sh; .specify/ itself never counts.
case "$FILE" in
  *"/.specify/"*) exit 0 ;;
  *"/tests/"*|*"/test/"*|*"/__tests__/"*|*"/spec/"*|*_test.go|*_test.py|*_test.rs|*_test.rb|*.bats) ;;
  *) case "$(basename "$FILE")" in *test*|*spec*) ;; *) exit 0 ;; esac ;;
esac
[ -f "$FILE" ] || exit 0

ids="$(grep -ohwE 'FR-[0-9]+' "$FILE" 2>/dev/null | sort -u)"
[ -z "$ids" ] && exit 0

STAMP="${TMPDIR:-/tmp}/.hefesto-spec-cite-$(printf '%s' "$FILE" | md5sum | cut -d' ' -f1)"
NOW=$(date +%s)
if [ -f "$STAMP" ] && [ $((NOW - $(cat "$STAMP" 2>/dev/null || echo 0))) -lt 60 ]; then exit 0; fi
echo "$NOW" > "$STAMP"

rel="${FILE#"$CWD"/}"
found=0
for d in "$CWD"/.specify/specs/*/; do
  [ -f "$d/spec.md" ] || continue
  name="${d%/}"; name="${name##*/}"
  hits="$(printf '%s\n' "$ids" | while read -r id; do grep -qwF "$id" "$d/spec.md" && printf '%s ' "$id"; done)"
  [ -z "$hits" ] && continue
  found=1
  echo "hefesto: $rel cites ${hits% } — declared by spec '$name' — and this edit is outside an implement phase." >&2
done
if [ "$found" -eq 1 ]; then
  echo "  If the behaviour changed, update the spec (.specify/specs/<name>/spec.md) or re-run /hef.verify; a test that moves while the spec stands still is how a spec rots." >&2
fi
exit 0
