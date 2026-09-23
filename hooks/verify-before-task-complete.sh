#!/bin/bash
# TaskCompleted hook — mechanical enforcement of the Verification Iron Law.
#
# Exit 2 BLOCKS the task from being marked complete and feeds stderr back to the
# agent. This is the difference between a rule the model can rationalize past and
# a gate it cannot: "NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE"
# (rules/code-quality.md) is prose until something enforces it.
#
# Verification is treated as a pure function of the working tree: if the tree is
# byte-identical to the last state that passed, the result is reused rather than
# re-running the suite on every task completion.
#
# Escape hatch: CLAUDE_SKIP_VERIFY_GATE=1 disables the gate entirely.
set -uo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

[ -n "${CLAUDE_SKIP_VERIFY_GATE:-}" ] && exit 0
[ -z "$CWD" ] && exit 0
[ "$CWD" = "$HOME" ] || [ "$CWD" = "/" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# --- Detect the test runner. No runner means nothing to prove; never block. ----
#
# `command -v` is NOT sufficient: a version-manager shim (asdf, pyenv, mise) is on
# PATH but fails at exec time with "No version is set". Treating that as a test
# failure would block completion on a TOOLING fault. So each runner is probed with
# a cheap --version first; a runner that cannot execute means we cannot verify,
# and a gate that cannot verify must not block.
RUNNER=""
RUNNER_CMD=""
PROBE=""
if [ -f "$CWD/package.json" ] && jq -e '.scripts.test' "$CWD/package.json" >/dev/null 2>&1; then
  RUNNER="npm"; PROBE="npm --version"
  RUNNER_CMD="npm test --prefix '$CWD'"
  # `--passWithNoTests` is forwarded only when the project's own script neither sets it nor
  # delegates to one that might.
  #
  # Measured 2026-09-09: appending it unconditionally BLOCKS EVERY COMPLETION in a pnpm
  # workspace whose packages already pass it. `npm test -- --passWithNoTests` becomes
  # `pnpm -r --no-bail test --passWithNoTests`, pnpm forwards the extra arg to each package's
  # `vitest run --passWithNoTests`, and vitest's CAC parser rejects the repeat:
  #
  #     Error: Expected a single value for option "passWithNoTests", received [true, true]
  #
  # That exits 1, this gate reads it as a failing suite, and the task can never be completed —
  # on a tree whose tests are green. A gate that cannot verify must not block (see above); a
  # gate that misreads its own invocation as a failure is worse, because it looks like a finding.
  TEST_SCRIPT="$(jq -r '.scripts.test // ""' "$CWD/package.json" 2>/dev/null)"
  case "$TEST_SCRIPT" in
    # Already sets it, or hands off to per-package scripts we cannot see from here.
    *passWithNoTests*|*" -r "*|*--workspaces*|*turbo*|*lerna*|*nx\ *) : ;;
    # A direct runner that understands the flag and does not already carry it.
    *vitest*|*jest*) RUNNER_CMD="$RUNNER_CMD -- --passWithNoTests" ;;
  esac
elif [ -f "$CWD/pyproject.toml" ] || [ -f "$CWD/setup.py" ]; then
  RUNNER="pytest"; PROBE="cd '$CWD' && pytest --version"
  RUNNER_CMD="cd '$CWD' && pytest -q --tb=line --no-header"
elif [ -f "$CWD/Cargo.toml" ]; then
  RUNNER="cargo"; PROBE="cargo --version"
  RUNNER_CMD="cargo test --manifest-path '$CWD/Cargo.toml' --quiet"
elif [ -f "$CWD/go.mod" ]; then
  RUNNER="go"; PROBE="go version"
  RUNNER_CMD="cd '$CWD' && go test ./..."
fi
[ -z "$RUNNER" ] && exit 0

# The runner exists on PATH but cannot actually run -> cannot verify -> do not block.
if ! eval "$PROBE" >/dev/null 2>&1; then
  echo "verify-gate: '$RUNNER' is on PATH but not executable here; skipping the gate." >&2
  exit 0
fi

# --- Nothing changed in the working tree? Then there is nothing to verify. -----
git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1 || exit 0
TREE=$(git -C "$CWD" status --porcelain=v1 2>/dev/null)
[ -z "$TREE" ] && exit 0

# Only source changes warrant a gate. Docs and config cannot break a test suite.
if ! echo "$TREE" | grep -qE '\.(ts|tsx|js|jsx|py|rs|go|rb|java|c|h|cpp)$'; then
  exit 0
fi

# --- Reuse the last result if the tree is unchanged since it was computed. -----
KEY=$(printf '%s' "$CWD" | md5sum | cut -d' ' -f1)
CACHE="/tmp/.claude-verify-$KEY"
TREE_HASH=$(printf '%s' "$TREE" | md5sum | cut -d' ' -f1)

if [ -f "$CACHE" ]; then
  read -r CACHED_HASH CACHED_STATUS < "$CACHE" || true
  if [ "${CACHED_HASH:-}" = "$TREE_HASH" ] && [ "${CACHED_STATUS:-}" = "pass" ]; then
    exit 0
  fi
fi

# --- Run the suite. This is the evidence. -------------------------------------
OUTPUT=$(eval "$RUNNER_CMD" 2>&1)
STATUS=$?

if [ "$STATUS" -eq 0 ]; then
  printf '%s pass\n' "$TREE_HASH" > "$CACHE"
  exit 0
fi

printf '%s fail\n' "$TREE_HASH" > "$CACHE"

cat >&2 <<EOF
BLOCKED — Verification Iron Law (rules/code-quality.md).

This task cannot be marked complete: the test suite is failing.

  runner: $RUNNER
  $(echo "$OUTPUT" | tail -15)

Fix the failure, then mark the task complete. Do not rationalize past this:
a failing suite is not "unrelated", "pre-existing", or "out of scope" unless
you have confirmed that on this tree — and if you have, say so explicitly and
set CLAUDE_SKIP_VERIFY_GATE=1 deliberately rather than working around the gate.
EOF
exit 2
