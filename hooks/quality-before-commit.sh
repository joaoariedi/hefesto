#!/bin/bash
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only intercept git commit commands
if [[ "$COMMAND" != git\ commit* ]]; then
  exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -z "$CWD" ]; then
  exit 0
fi

ERRORS=""

# --- Universal: conventional commit message --------------------------------------------
#
# git-workflow.md prescribes `<type>: <description>`; hef.release's changelog scaffold groups
# commits BY that type. A message that ignores the format lands in the wrong section, or none —
# and a rule only prose enforces is the one that drifts first. Checked here, at the moment the
# message exists; CI cannot see a message before it is pushed.
#
# Only an INLINE message is inspected: `-m "…"` / `-m '…'`, or the repo's own heredoc style
# `-m "$(cat <<'EOF' … EOF)"` (subject = the line after the heredoc opener). `--amend --no-edit`,
# `-F file`, and merges have no inline message and are left alone. Visible bypass:
# CLAUDE_ALLOW_NONCONVENTIONAL=1 in the command.
SUBJECT=""
if [[ "$COMMAND" =~ cat[[:space:]]*\<\<[\'\"]?[A-Z_]+[\'\"]? ]]; then
  SUBJECT="$(printf '%s\n' "$COMMAND" | sed -n '2p')"
elif [[ "$COMMAND" =~ -m[[:space:]]+\"([^\"]+)\" ]] || [[ "$COMMAND" =~ -m[[:space:]]+\'([^\']+)\' ]]; then
  SUBJECT="${BASH_REMATCH[1]%%$'\n'*}"
fi
# The pattern lives in a variable: a `)` inside the bracket expression `[^)]` is a parse error when
# the regex is written inline in `[[ =~ ]]` (bash reads it as the end of the group). Quoting it
# would make it a literal match instead. A variable is the documented, portable form.
CONVENTIONAL_RE='^(feat|fix|docs|style|refactor|perf|test|chore|ci|build|revert)(\([^)]+\))?!?:[[:space:]].+'
if [ -n "$SUBJECT" ] && [[ "$COMMAND" != *"CLAUDE_ALLOW_NONCONVENTIONAL=1"* ]]; then
  if ! [[ "$SUBJECT" =~ $CONVENTIONAL_RE ]]; then
    ERRORS="${ERRORS}Commit subject '$SUBJECT' is not conventional (<type>(<scope>)?: <description>; types: feat fix docs style refactor perf test chore ci build revert — see git-workflow.md). "
  fi
fi

# Universal: Secrets detection (mandatory, runs first)
if command -v gitleaks &>/dev/null; then
  if ! gitleaks detect --staged --no-banner -q 2>/dev/null; then
    ERRORS="${ERRORS}Secrets detected in staged files! "
  fi
fi

# --- Universal: shell + markdown, on STAGED FILES ONLY ------------------------
#
# Every check below this block is gated behind a language manifest (package.json,
# pyproject.toml, Cargo.toml, go.mod, pom.xml). A repo made of shell scripts and
# markdown — like this framework itself — matches none of them, so the gate was a
# no-op against its own source. These two checks are manifest-free.
#
# Each has a ZERO-DEPENDENCY baseline that always runs, plus a real linter when one
# is installed. Guarding purely on `command -v` would have reproduced the original
# bug on any machine without the linter.
STAGED=$(git -C "$CWD" diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)

# Shell: bash -n always; shellcheck when present.
SH_FILES=$(echo "$STAGED" | grep -E '\.(sh|bash)$' || true)
if [ -n "$SH_FILES" ]; then
  while IFS= read -r f; do
    [ -f "$CWD/$f" ] || continue
    if ! bash -n "$CWD/$f" 2>/dev/null; then
      ERRORS="${ERRORS}Shell syntax error in $f. "
    fi
  done <<< "$SH_FILES"

  if command -v shellcheck &>/dev/null; then
    # shellcheck is advisory below `error` severity; only errors block a commit.
    while IFS= read -r f; do
      [ -f "$CWD/$f" ] || continue
      if ! shellcheck -S error "$CWD/$f" >/dev/null 2>&1; then
        ERRORS="${ERRORS}shellcheck errors in $f. "
      fi
    done <<< "$SH_FILES"
  fi
fi

# Markdown: unclosed code fences always; markdownlint when present.
MD_FILES=$(echo "$STAGED" | grep -E '\.md$' || true)
if [ -n "$MD_FILES" ]; then
  while IFS= read -r f; do
    [ -f "$CWD/$f" ] || continue
    FENCES=$(grep -c '^```' "$CWD/$f" 2>/dev/null || true)
    FENCES=${FENCES:-0}
    if [ $((FENCES % 2)) -ne 0 ]; then
      ERRORS="${ERRORS}Unclosed code fence in $f. "
    fi
  done <<< "$MD_FILES"

  if command -v markdownlint-cli2 &>/dev/null; then
    while IFS= read -r f; do
      [ -f "$CWD/$f" ] || continue
      if ! markdownlint-cli2 "$CWD/$f" >/dev/null 2>&1; then
        ERRORS="${ERRORS}markdownlint issues in $f. "
      fi
    done <<< "$MD_FILES"
  fi
fi

# --- Universal: complexity DELTA gate, when lizard is installed ------------------------
#
# code-quality.md's limits (50-line functions, complexity 10) are AGGREGATE rules: no single edit
# violates them, so in prose they are honoured ~70% of the time and a 31%-violation rate is the
# measured norm for such rules (heym.run, 2026). As a linter they are honoured. lizard is
# polyglot and its defaults ARE the framework's limits (-C 10 -L 50). The gate is a DELTA, not an
# absolute cap: a staged file may not have MORE over-limit functions than its HEAD version, so
# brownfield debt stays visible without blocking unrelated changes. Zero-dependency baseline: none
# exists for this check, so it runs only where lizard is present — and says nothing otherwise.
if command -v lizard &>/dev/null; then
  CX_FILES=$(echo "$STAGED" | grep -E '\.(py|js|jsx|ts|tsx|go|rs|java|kt|rb|c|cc|cpp|h|hpp|cs|swift|php|scala|lua)$' || true)
  if [ -n "$CX_FILES" ]; then
    while IFS= read -r f; do
      [ -f "$CWD/$f" ] || continue
      case "$f" in workflows/workflow.js) continue ;; esac   # the one documented exemption
      now=$(lizard -w -C 10 -L 50 "$CWD/$f" 2>/dev/null | grep -c ': warning:' || true)
      before=0
      if git -C "$CWD" cat-file -e "HEAD:$f" 2>/dev/null; then
        cx_tmp="$(mktemp --suffix=".${f##*.}")"
        git -C "$CWD" show "HEAD:$f" > "$cx_tmp" 2>/dev/null
        before=$(lizard -w -C 10 -L 50 "$cx_tmp" 2>/dev/null | grep -c ': warning:' || true)
        rm -f "$cx_tmp"
      fi
      if [ "${now:-0}" -gt "${before:-0}" ]; then
        ERRORS="${ERRORS}Complexity/length got worse in $f (${before} → ${now} functions over the limits in rules/code-quality.md). "
      fi
    done <<< "$CX_FILES"
  fi
fi

# --- Language checks, on STAGED FILES where the tool supports it ---------------
#
# Two rules govern everything below.
#
# 1. NEVER decide pass/fail by grepping output for the word "error". The previous
#    version did, and it blocked PASSING commits: `tsc` prints "Found 0 errors."
#    and eslint prints "0 errors" on success — both match. Use the EXIT CODE.
#
# 2. Scope to staged files ONLY where the tool can actually do it. Some cannot,
#    and pretending otherwise breaks them:
#      - a TYPE CHECKER needs the whole program graph. `tsc` on one file cannot
#        see the types it imports. Whole-project is correct, not lazy.
#      - `cargo clippy` analyses a crate, not a file.
#      - `go vet` works per-package, so it is scoped to the packages that own the
#        staged files rather than to the files themselves.
#    Linters (ruff, eslint, biome) take a file list and are scoped properly.

# JavaScript / TypeScript
if [ -f "$CWD/package.json" ]; then
  JS_FILES=$(echo "$STAGED" | grep -E '\.(js|jsx|ts|tsx|mjs|cjs)$' || true)

  if [ -n "$JS_FILES" ]; then
    # Prefer the linter binary directly: it accepts a file list, and resolving it
    # from node_modules/.bin avoids an npx network round-trip in a <5s hook.
    LINT_BIN=""
    if [ -x "$CWD/node_modules/.bin/biome" ]; then
      LINT_BIN="$CWD/node_modules/.bin/biome check"
    elif [ -x "$CWD/node_modules/.bin/eslint" ]; then
      LINT_BIN="$CWD/node_modules/.bin/eslint"
    fi

    if [ -n "$LINT_BIN" ]; then
      if ! (cd "$CWD" && echo "$JS_FILES" | xargs $LINT_BIN >/dev/null 2>&1); then
        ERRORS="${ERRORS}Lint errors in staged JS/TS. "
      fi
    else
      # No scopable binary — fall back to the project script, whole-project.
      if ! npm --prefix "$CWD" run lint --if-present >/dev/null 2>&1; then
        ERRORS="${ERRORS}Lint errors found. "
      fi
    fi
  fi

  # Typecheck is whole-project BY NATURE — tsc needs every file to resolve types.
  # Only run it when TS/JS is actually staged, so it costs nothing otherwise.
  if [ -n "$JS_FILES" ]; then
    if ! npm --prefix "$CWD" run typecheck --if-present >/dev/null 2>&1; then
      ERRORS="${ERRORS}Type errors found. "
    fi
  fi
fi

# Python — ruff takes an explicit file list.
if [ -f "$CWD/pyproject.toml" ] || [ -f "$CWD/setup.py" ]; then
  PY_FILES=$(echo "$STAGED" | grep -E '\.py$' || true)
  if [ -n "$PY_FILES" ] && command -v ruff &>/dev/null; then
    if ! (cd "$CWD" && echo "$PY_FILES" | xargs ruff check --quiet >/dev/null 2>&1); then
      ERRORS="${ERRORS}Ruff lint errors in staged Python. "
    fi
  fi
fi

# Rust — clippy analyses a CRATE. It cannot be scoped to files; whole-crate is the
# only correct invocation. Gate it on Rust actually being staged so it stays cheap.
if [ -f "$CWD/Cargo.toml" ]; then
  RS_FILES=$(echo "$STAGED" | grep -E '\.rs$' || true)
  if [ -n "$RS_FILES" ] && command -v cargo &>/dev/null; then
    if ! cargo clippy --manifest-path "$CWD/Cargo.toml" --quiet >/dev/null 2>&1; then
      ERRORS="${ERRORS}Clippy warnings found. "
    fi
  fi
fi

# Go — `go vet` works per-package, so scope it to the packages owning staged files.
if [ -f "$CWD/go.mod" ]; then
  GO_FILES=$(echo "$STAGED" | grep -E '\.go$' || true)
  if [ -n "$GO_FILES" ] && command -v go &>/dev/null; then
    GO_PKGS=$(echo "$GO_FILES" | xargs -n1 dirname 2>/dev/null | sort -u | sed 's|^|./|' | tr '\n' ' ')
    if [ -n "$GO_PKGS" ]; then
      # shellcheck disable=SC2086 # GO_PKGS is a deliberate list of package paths
      if ! (cd "$CWD" && go vet $GO_PKGS >/dev/null 2>&1); then
        ERRORS="${ERRORS}Go vet errors in staged packages. "
      fi
    fi
  fi
fi

# Java — Spotless can be scoped with -DspotlessFiles (a regex over absolute paths).
if [ -f "$CWD/pom.xml" ] || [ -f "$CWD/build.gradle" ] || [ -f "$CWD/build.gradle.kts" ]; then
  JAVA_FILES=$(echo "$STAGED" | grep -E '\.(java|kt)$' || true)
  if [ -n "$JAVA_FILES" ]; then
    SPOTLESS_RE=$(echo "$JAVA_FILES" | sed 's/[.[\*^$]/\\&/g' | paste -sd'|' -)
    if [ -f "$CWD/pom.xml" ] && command -v mvn &>/dev/null; then
      if ! mvn -f "$CWD/pom.xml" spotless:check -q "-DspotlessFiles=.*($SPOTLESS_RE)" >/dev/null 2>&1; then
        ERRORS="${ERRORS}Java formatting issues (run mvn spotless:apply). "
      fi
    elif [ -f "$CWD/gradlew" ]; then
      if ! "$CWD/gradlew" -p "$CWD" spotlessCheck -q >/dev/null 2>&1; then
        ERRORS="${ERRORS}Java formatting issues (run ./gradlew spotlessApply). "
      fi
    fi
  fi
fi

if [ -n "$ERRORS" ]; then
  echo "Pre-commit quality checks failed: ${ERRORS}Fix issues before committing." >&2
  exit 2
fi

exit 0
