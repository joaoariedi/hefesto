#!/bin/bash
# implement-phase-test-guard.sh — tests may GROW during /speckit.implement; they may not SHRINK.
#
# Two guards, one file:
#
#   1. Phase-gated (only while .specify/.implement-in-progress exists — set by speckit-helper.sh
#      implement-phase-start, cleared by implement-phase-end):
#        * an Edit to a test file that leaves FEWER assertions than it found is blocked;
#        * a Write (whole-file overwrite) of a test file that already exists is blocked — add cases
#          with Edit, so the diff is visible;
#        * `rm` / `git rm` of a test file is blocked.
#   2. Unconditional: a test command carrying a snapshot-UPDATE flag (`-u`, `--update-snapshot`,
#      `--snapshot-update`, `UPDATE_SNAPSHOTS=1`…) is blocked. Regenerating a baseline to go green is
#      the same move as deleting the test, just quieter. Bypass, visible in the transcript:
#      prefix the command with CLAUDE_ALLOW_SNAPSHOT_UPDATE=1.
#
# Why a hook and not a rule: TDAD (arXiv 2603.17973) measured that TDD *instructions* without a
# mechanism made agent regressions WORSE (9.94% vs 6.08% baseline); Kent Beck reports agents deleting
# tests to make them pass. speckit.implement already says "never modify the test to make it pass" —
# this is the mechanism behind that sentence.
#
# Threat model, same as block-destructive-commands.sh: a careless or prompt-injected agent taking the
# obvious path. Not a sandbox.
set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0
[ "$CWD" = "$HOME" ] || [ "$CWD" = "/" ] && exit 0

MARKER="$CWD/.specify/.implement-in-progress"

# A test file, by path. Deliberately broad: a false positive costs one explanatory block; a false
# negative lets a test vanish. `.specify/` is excluded so spec artifacts named *spec.md never match.
is_test_file() {
  case "$1" in
    *"/.specify/"*) return 1 ;;
    *"/tests/"*|*"/test/"*|*"/__tests__/"*|*"/spec/"*) return 0 ;;
    *_test.go|*_test.py|*_test.rs|*_test.rb|*.bats) return 0 ;;
  esac
  local base
  base="$(basename "$1")"
  case "$base" in
    *test*|*spec*) return 0 ;;
  esac
  return 1
}

# Count assertion-shaped tokens across the major runners. Not exhaustive on purpose — it only has to
# notice when a block of them disappears.
count_asserts() {
  grep -oE 'assert[A-Za-z_]*\b|expect\(|\.should\b|\.to(Be|Equal|Throw|Have|Match)[A-Za-z]*\(|t\.(Error|Fatal|Errorf|Fatalf)\(|require\.[A-Za-z]+\(|assert_eq!|assert!' <<<"$1" 2>/dev/null | wc -l
}

case "$TOOL" in
  Bash)
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    [ -z "$CMD" ] && exit 0

    # --- Unconditional: snapshot-update flags on a test runner ---
    if [[ "$CMD" != *"CLAUDE_ALLOW_SNAPSHOT_UPDATE=1"* ]] \
       && [[ "$CMD" =~ (jest|vitest|pytest|ava|bun[[:space:]]+test|npm[[:space:]]+(run[[:space:]]+)?test|npx|yarn[[:space:]]+test|pnpm[[:space:]]+test|--snapshot) ]] \
       && [[ "$CMD" =~ (^|[[:space:]])(-u|--update-snapshots?|--snapshot-update|--force-update-snapshots?|--updateSnapshot)([[:space:]]|$) \
            || "$CMD" =~ (^|[[:space:]])(UPDATE_SNAPSHOTS|SNAPSHOT_UPDATE)=1 ]]; then
      echo "Blocked: this test command REGENERATES snapshots/baselines instead of checking them." >&2
      echo "  A snapshot updated to match new output is a test that can no longer fail. Review the diff first." >&2
      echo "  If the new baseline is genuinely intended, re-run with the bypass visible: CLAUDE_ALLOW_SNAPSHOT_UPDATE=1 <command>" >&2
      exit 2
    fi

    # --- Phase-gated: deleting a test file ---
    [ -f "$MARKER" ] || exit 0
    if [[ "$CMD" =~ (^|[[:space:]]|&&|;)(git[[:space:]]+)?rm[[:space:]] ]]; then
      for tok in $CMD; do
        if is_test_file "$tok"; then
          echo "Blocked: /speckit.implement is active and this removes a test file ($tok)." >&2
          echo "  Tests may grow during implementation, never shrink. End the phase first: speckit-helper.sh implement-phase-end" >&2
          exit 2
        fi
      done
    fi
    exit 0
    ;;

  Edit|Write|MultiEdit)
    [ -f "$MARKER" ] || exit 0
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    [ -z "$FILE" ] && exit 0
    is_test_file "$FILE" || exit 0

    if [ "$TOOL" = "Write" ]; then
      if [ -e "$FILE" ]; then
        echo "Blocked: /speckit.implement is active and Write would OVERWRITE the existing test file $FILE." >&2
        echo "  Add or change cases with Edit so the diff shows exactly what moved. New test files may still be created." >&2
        echo "  To leave the phase: speckit-helper.sh implement-phase-end" >&2
        exit 2
      fi
      exit 0
    fi

    OLD=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty')
    NEW=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
    if [ "$TOOL" = "MultiEdit" ]; then
      OLD=$(echo "$INPUT" | jq -r '[.tool_input.edits[]?.old_string // empty] | join("\n")')
      NEW=$(echo "$INPUT" | jq -r '[.tool_input.edits[]?.new_string // empty] | join("\n")')
    fi
    before=$(count_asserts "$OLD")
    after=$(count_asserts "$NEW")
    if [ "$before" -gt 0 ] && [ "$after" -lt "$before" ]; then
      echo "Blocked: /speckit.implement is active and this edit removes assertions from $FILE ($before → $after)." >&2
      echo "  A test that asserts less to go green is the failure this phase exists to prevent." >&2
      echo "  If the assertion is genuinely wrong, say so to the user, or end the phase: speckit-helper.sh implement-phase-end" >&2
      exit 2
    fi
    exit 0
    ;;
esac
exit 0
