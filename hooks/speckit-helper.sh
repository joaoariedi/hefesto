#!/bin/bash
# speckit-helper.sh - Pre-flight helper for the hef.* commands
# Centralizes all pre-flight shell logic to avoid Claude Code permission
# issues with $(), ||, &&, and | operators in !` ` commands.
#
# ---------------------------------------------------------------------------------------------
# THE CONTRACT. Every subcommand is one of two kinds, and the difference is the exit code.
#
#   FETCHER  — "give me X". Prints X on stdout, exit 0. If X does not exist that is a FAILURE:
#              the reason goes to STDERR and the exit code is NON-ZERO. It must be impossible for
#              a caller to mistake the reason for the answer.
#
#   PREDICATE — "is X true?". Prints the answer on stdout AND returns it as the exit code
#              (0 = yes, 1 = no). Both, deliberately: a shell caller writes `helper foo && ...`,
#              a model reads the string. Neither contract is privileged, so neither breaks.
#
# This used to be one undifferentiated pile that printed a sentinel and exited 0 for everything,
# and it cost real work twice:
#
#   * `spec` printed the six characters NO_SPEC at exit 0 when the artifact was missing. A command
#     told to "load spec.md" loaded that string and carried on. It happened during the 5.1.0 run —
#     the spec directory did not match the branch, every artifact subcommand reported NO_SPEC at
#     exit 0, and nothing noticed until a human read the output. (#27)
#   * `rtk-available` printed RTK_MISSING at exit 0, while quality-tooling.md documented
#     `helper rtk-available && rtk pytest || pytest`. The && branch ALWAYS ran. The guard did not
#     guard; the pattern only fell back because rtk itself then died with 127 — which is what plain
#     `rtk pytest || pytest` does, except noisier, in a rule that calls rtk "a silent, non-blocking
#     enhancement". The helper's contract was "branch on the string"; the rule's was "branch on the
#     exit code"; they disagreed and the failure was silent. (#27, same class)
#
# Constitution principle 5: helpers fail loudly; no exit-0 sentinel a caller can ignore.
# ---------------------------------------------------------------------------------------------

# A fetcher could not fetch. STDERR, never stdout — a caller redirecting stdout into a variable
# must get nothing, not an explanation it might use as the answer.
die() {
  echo "$*" >&2
  exit 1
}

BRANCH=$(git branch --show-current 2>/dev/null | sed 's|^feature/||')

# The spec directory name and the branch name are ONE contract, not two: artifacts live at
# .specify/specs/$(git branch --show-current | sed 's|^feature/||')/. Nothing states this — not
# /hef.spec, which asks for a 2-4 word kebab-case name and separately says to branch
# `feature/<name>`, leaving the equality implied by juxtaposition. When they diverge, every artifact
# is missing for a reason that has nothing to do with the artifacts. Say so specifically.
missing_artifact() {  # $1 = artifact filename, e.g. spec.md
  local want=".specify/specs/$BRANCH/$1"
  local found
  found="$(ls -d .specify/specs/*/ 2>/dev/null | sed 's|.specify/specs/||; s|/$||' | tr '\n' ' ')"
  if [ -z "$found" ]; then
    die "no $1: $want does not exist, and .specify/specs/ holds no feature directories at all. Run /hef.spec first."
  fi
  die "no $1: expected it at $want (the spec directory MUST be named after the branch, minus any 'feature/' prefix). Existing spec directories: ${found% }. Either rename the directory to '$BRANCH', or switch to the branch that matches it."
}

# Resolve what a PR is diffed against, and never fail doing it. Prints a ref, or nothing
# when HEAD is the root commit (no parent to compare with).
#
# The old chain was `main...HEAD || HEAD~1` with nothing after it, so a repo whose first
# commit is also its only commit — a fresh project, or a test fixture — exited 128. A
# helper that exits non-zero inside a command produces no data, and the command silently
# degrades. Every arm below is guarded; the caller handles the empty case.
# integration_base — branch-model FR-004: ONLY when the project config declares a `branches` block,
# the merge-base of HEAD with its integration branch (local, then origin/). Otherwise nothing, and the
# callers keep their historical order exactly (semver). Placed BEFORE @{u}: for a pushed feature
# branch @{u} is the branch's own remote copy, and on a dev-integrating repo `main` is the far end of
# the release train (plan review 2026-10-05).
# Failure semantics: unconfigured → nothing (today's chain); a MALFORMED block → exit 1 with the reason,
# which the callers propagate (diffing the whole train silently is the failure this exists to stop);
# an integration ref that resolves nowhere → nothing (fall through to today's chain).
integration_base() {
  local led i r
  led="$(dirname "${BASH_SOURCE[0]}")/ledger.sh"
  [ -f "$led" ] || return 0             # a lone copy (a mutation-test fixture) has no model: today's chain
  local rc mb best=""
  bash "$led" branches --configured 2>/dev/null; rc=$?
  [ "$rc" -eq 1 ] && return 0          # no branches block: today's chain
  [ "$rc" -eq 0 ] || return 1          # invalid config JSON: malformed, never "unconfigured"
  i=$(bash "$led" branches | jq -r '.integration // empty') || return 1
  [ -n "$i" ] || return 1
  # The NEWER of the two merge-bases: a stale local `dev` behind origin/dev would otherwise pull dev's
  # own commits into the item's diff (plan review round 3, reproduced) — a merge-base is not an
  # ancestry check, where either ref would do.
  for r in "origin/$i" "$i"; do
    git rev-parse --verify -q "$r^{commit}" >/dev/null 2>&1 || continue
    mb=$(git merge-base HEAD "$r" 2>/dev/null) || continue
    if [ -z "$best" ] || git merge-base --is-ancestor "$best" "$mb" 2>/dev/null; then best="$mb"; fi
  done
  [ -n "$best" ] && echo "$best"
  return 0
}
pr_base() {
  local ib; ib=$(integration_base) || return 1; [ -n "$ib" ] && { echo "$ib"; return; }
  git rev-parse --verify -q '@{u}' >/dev/null 2>&1 && { git rev-parse --abbrev-ref '@{u}'; return; }
  for b in main master; do
    git rev-parse --verify -q "$b" >/dev/null 2>&1 && { echo "$b"; return; }
  done
  git rev-parse --verify -q 'HEAD~1' >/dev/null 2>&1 && { echo 'HEAD~1'; return; }
  echo ""   # root commit: the caller diffs against the commit itself
}

# --- dependency parsers (feature dependency-audit FR-001): manifest text on stdin → name<TAB>spec ---
# Manifests, not lockfiles: the review item is the DIRECT dependency a person or an agent chose
# (llm-security.md — 5–22 % of LLM-suggested package names do not exist and are squattable).
# A package.json that does not parse dies — an empty list would read as "every dependency removed".
npm_deps() {
  local doc; doc=$(cat)
  [ -n "$doc" ] || return 0
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$doc" || { echo "deps-diff: a package.json is not a JSON object — fix it before diffing" >&2; return 1; }
  jq -r '[.dependencies, .devDependencies, .optionalDependencies, .peerDependencies] | map(. // {}) | add | to_entries[] | "\(.key)\t\(.value)"' <<<"$doc"
}
# requirements files: every non-option, non-comment line ("-r base.txt", "--hash" are options, not names).
# A URL or VCS requirement is named by its #egg= (else the URL itself); a local path by the path.
py_req_deps() {
  sed -E 's/[[:space:]]+#.*//; s/^#.*//; s/^[[:space:]]+//; s/[[:space:]]+$//' | awk 'NF && !/^-/' | awk '
    /^[a-z][a-z0-9+.-]*:\/\// || /^(git|hg|svn|bzr)\+/ { n = $0; if (match($0, /#egg=[A-Za-z0-9_.-]+/)) n = substr($0, RSTART + 5, RLENGTH - 5); print n "\t" $0; next }
    /^[.\/~]/ { print $0 "\t" $0; next }
    { print }' | sed -E '/\t/!s/^([A-Za-z0-9_.-]+)(\[[^]]*\])?[[:space:]]*(.*)$/\1\t\3/'
}
# Strip a # comment that sits OUTSIDE quotes (awk; q = the single-quote character).
TOML_UNCOMMENT='function uncomment(l,   s, inq, i, c) { s = ""; inq = ""; for (i = 1; i <= length(l); i++) { c = substr(l, i, 1); if (inq == "" && c == "#") break; if (inq == "" && (c == "\"" || c == q)) inq = c; else if (c == inq) inq = ""; s = s c }; return s }
function header(l,   h) { h = uncomment(l); sub(/[[:space:]]+$/, "", h); return h }'
# pyproject.toml: ONLY the [project] table's dependencies array — every other table is not a dependency
# list. The array ends at a `]` OUTSIDE quotes and outside a comment (an extras bracket like
# "rich[jupyter]" is inside quotes); items are the quoted strings themselves (extras may hold commas).
py_toml_deps() {
  awk -v q="'" "$TOML_UNCOMMENT"'
    /^[[:space:]]*\[/ { p = (header($0) == "[project]"); a = 0; next }
    p && /^dependencies[[:space:]]*=/ { a = 1; sub(/^[^=]*=[[:space:]]*/, "") }
    a {
      line = uncomment($0); bare = line; gsub("\"[^\"]*\"|" q "[^" q "]*" q, "", bare)
      while (match(line, "\"[^\"]*\"|" q "[^" q "]*" q)) { print substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH) }
      if (bare ~ /\]/) a = 0
    }' | sed -E 's/^[[:space:]]+//; s/^([A-Za-z0-9_.-]+)(\[[^]]*\])?[[:space:]]*(.*)$/\1\t\3/'
}
# Cargo.toml: [dependencies], [dev-dependencies], [build-dependencies], their [target.<cfg>.…] and
# [workspace.dependencies] forms (a table of name = spec), and the [<section>.<name>] sub-table form (one
# dependency, spec = its version). `name="1"` needs no spaces; a multi-line inline table is joined.
cargo_deps() {
  awk -v q="'" "$TOML_UNCOMMENT"'
    function flush() { if (sub_name != "") { print sub_name "\t" (sub_ver != "" ? sub_ver : "{table}"); sub_name = ""; sub_ver = "" } }
    function key(k) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", k); gsub(/^["\x27]|["\x27]$/, "", k); return k }
    /^[[:space:]]*\[/ {
      flush(); h = header($0); s = 0
      if (h ~ /^\[(target\.[^]]+\.|workspace\.)?(dev-|build-)?dependencies\]$/) s = 1
      else if (h ~ /^\[(target\.[^]]+\.)?(dev-|build-)?dependencies\.[^]]+\]$/) { n = h; sub(/^.*dependencies\./, "", n); sub(/\]$/, "", n); sub_name = key(n) }
      next }
    sub_name != "" { l = uncomment($0); if (l ~ /^[[:space:]]*version[[:space:]]*=/) { v = l; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/[[:space:]]+$/, "", v); sub_ver = v }; next }
    s {
      l = uncomment($0); if (l !~ /=/ && cont == "") next
      if (cont != "") { cont = cont " " l; if (l ~ /}/) { print cname "\t" cont; cont = "" }; next }
      eq = index(l, "="); n = key(substr(l, 1, eq - 1)); v = substr(l, eq + 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      if (n == "") next
      if (v ~ /^\{/ && v !~ /}/) { cname = n; cont = v; next }
      print n "\t" v }
    END { flush() }'
}
# go.mod: require entries, block and single-line; `// indirect` lines are tidy's, not a person's choice;
# a comment line inside a block is not a dependency.
go_deps() { awk '/^require[[:space:]]*\(/{b = 1; next} b && /^\)/{b = 0} b && NF >= 2 && !/\/\/ indirect/ && !/^[[:space:]]*\/\//{print $1 "\t" $2} /^require[[:space:]]+[^(]/ && !/\/\/ indirect/{print $2 "\t" $3}'; }
deps_parser() { # basename → "<ecosystem> <function>", or nothing
  case "$1" in
    package.json) echo "npm npm_deps" ;; requirements*.txt) echo "pypi py_req_deps" ;; pyproject.toml) echo "pypi py_toml_deps" ;;
    Cargo.toml) echo "crates cargo_deps" ;; go.mod) echo "go go_deps" ;;
  esac
}
DEPS_MANIFEST_RE='(^|/)(package\.json|requirements[^/]*\.txt|pyproject\.toml|Cargo\.toml|go\.mod)$'
# One auditor run (FR-002): the count is a number ONLY when the exit is in the tool's valid set AND the
# expression yields a number — an ENOLOCK error document or a no-lockfile exit is never "clean".
run_auditor() { # $1 tool label, $2 valid exits ("0 1"), $3 jq count expr, $4 jq slurp (0|1), $@:5 command
  local tool="$1" valid="$2" expr="$3" slurp="$4" out rc n=unknown; shift 4
  out="$DEPS_DIR/$tool.json"
  "$@" > "$out" 2>"$out.err"; rc=$?
  if [[ " $valid " == *" $rc "* ]]; then
    # an integer or nothing: a float, a string or null is not a count
    if [ "$slurp" = 1 ]; then n=$(jq -es "$expr | numbers | select(. == floor and . >= 0)" "$out" 2>/dev/null) || n=unknown
    else n=$(jq -e "$expr | numbers | select(. == floor and . >= 0)" "$out" 2>/dev/null) || n=unknown; fi
    [[ "$n" =~ ^[0-9]+$ ]] || n=unknown
  fi
  echo "$tool exit $rc findings $n report $out"
  AUDIT_RAN=1
  if [ "$n" = unknown ] || [ "$n" -gt 0 ]; then AUDIT_FOUND=1; fi
}

case "$1" in
  # --- Branch & git ---
  branch)
    git branch --show-current 2>/dev/null || echo "NO_GIT"
    ;;
  check-git-root)
    git rev-parse --show-toplevel 2>/dev/null || echo "NOT_A_GIT_REPO"
    ;;

  # --- Spec artifacts (branch-scoped) ---
  # --- FETCHERS: absence is a failure, and it goes to stderr with a non-zero exit ---
  spec)
    cat ".specify/specs/$BRANCH/spec.md" 2>/dev/null || missing_artifact spec.md
    ;;
  plan)
    cat ".specify/specs/$BRANCH/plan.md" 2>/dev/null || missing_artifact plan.md
    ;;
  # --- PREDICATE: the answer is the exit code AND the string ---
  check-spec)
    if [ -f ".specify/specs/$BRANCH/spec.md" ]; then
      echo "SPEC_FOUND: $BRANCH"
    else
      echo "NO_SPEC_FOR_BRANCH: $BRANCH"
      exit 1
    fi
    ;;
  check-plan)
    if [ -f ".specify/specs/$BRANCH/plan.md" ]; then
      echo "PLAN_FOUND: $BRANCH"
    else
      echo "NO_PLAN_FOR_BRANCH: $BRANCH"
      exit 1
    fi
    ;;
  check-artifacts)
    for f in tasks.md plan.md spec.md; do
      test -f ".specify/specs/$BRANCH/$f" && echo "$f: FOUND" || echo "$f: MISSING"
    done
    ;;
  all-artifacts)
    for f in spec.md plan.md tasks.md; do
      echo "--- $f ---"
      cat ".specify/specs/$BRANCH/$f" 2>/dev/null || echo "MISSING"
    done
    ;;
  clarifications)
    # Two different absences, and they are not the same news: no spec at all is a broken
    # precondition; a spec with no Clarifications section is a normal, expected state that
    # /speckit.clarify exists to fix.
    [ -f ".specify/specs/$BRANCH/spec.md" ] || missing_artifact spec.md
    grep -A 100 "## Clarifications" ".specify/specs/$BRANCH/spec.md" 2>/dev/null || echo "NO_CLARIFICATIONS_SECTION"
    ;;

  # --- Checklists (branch-scoped) ---
  checklists)
    ls ".specify/specs/$BRANCH/checklists/"*.md 2>/dev/null || echo "NO_CHECKLISTS"
    ;;
  checklists-dir)
    ls ".specify/specs/$BRANCH/checklists/" 2>/dev/null || echo "NO_CHECKLISTS_DIR"
    ;;
  checklists-content)
    found=0
    for f in ".specify/specs/$BRANCH/checklists/"*.md; do
      [ -f "$f" ] || continue
      found=1
      echo "--- $(basename "$f") ---"
      cat "$f"
    done
    [ "$found" -eq 0 ] && echo "NO_CHECKLISTS"
    ;;

  # --- Global spec-kit resources ---
  constitution)
    cat .specify/memory/constitution.md 2>/dev/null || die "no constitution: .specify/memory/constitution.md does not exist. Run /hef.init to scaffold it, or /hef.constitution to populate it."
    ;;
  list-specs)
    ls -d .specify/specs/*/ 2>/dev/null || die "no specs: .specify/specs/ holds no feature directories. Run /hef.spec first."
    ;;
  list-specs-dir)
    ls .specify/specs/ 2>/dev/null || echo "NO_SPECS_DIR"
    ;;
  check-specify-dir)
    # PREDICATE. /hef.init asks this precisely to learn the answer, so NOT_FOUND is a normal
    # reply, never a failure — it is the whole reason init exists.
    if [ -d .specify ]; then echo "EXISTS"; else echo "NOT_FOUND"; exit 1; fi
    ;;

  # --- Project detection ---
  detect-stack)
    find . -maxdepth 2 -type f \( -name "package.json" -o -name "pyproject.toml" -o -name "Cargo.toml" -o -name "go.mod" -o -name "Makefile" \) 2>/dev/null | head -10
    ;;
  detect-test-framework)
    ls package.json pyproject.toml Cargo.toml go.mod 2>/dev/null | head -1
    ;;
  list-config-files)
    ls package.json pyproject.toml Cargo.toml go.mod Makefile docker-compose.yml 2>/dev/null || echo "No config files found"
    ;;
  list-rules)
    ls .claude/rules/ 2>/dev/null || echo "No .claude/rules/ found"
    ;;
  readme-head)
    cat README.md 2>/dev/null | head -50 || echo "NO_README"
    ;;

  # --- Context & PR commands ---
  recent-commits)
    git log --oneline -10 2>/dev/null || echo "Not a git repository"
    ;;
  project-files)
    find . -maxdepth 2 -type f \( -name "package.json" -o -name "pyproject.toml" -o -name "Cargo.toml" -o -name "go.mod" -o -name "Makefile" -o -name "*.config.*" -o -name "tsconfig*" -o -name ".eslintrc*" -o -name "Dockerfile" \) 2>/dev/null | head -20
    ;;
  pr-commits)
    base=$(pr_base) || die "speckit-helper: .branches in .claude/project-status.json is malformed — run ledger.sh branches for the reason"
    if [ -n "$base" ]; then
      git log --oneline "$base..HEAD" 2>/dev/null || echo "Not a git repository"
    else
      git log --oneline -10 2>/dev/null || echo "Not a git repository"
    fi
    ;;
  pr-files)
    base=$(pr_base) || die "speckit-helper: .branches in .claude/project-status.json is malformed — run ledger.sh branches for the reason"
    if [ -n "$base" ]; then
      git diff --name-status "$base...HEAD" 2>/dev/null || echo "Not a git repository"
    else
      # Root commit — show what it introduced rather than exiting 128.
      git show --name-status --format= HEAD 2>/dev/null || echo "Not a git repository"
    fi
    ;;
  pr-stats)
    base=$(pr_base) || die "speckit-helper: .branches in .claude/project-status.json is malformed — run ledger.sh branches for the reason"
    if [ -n "$base" ]; then
      git diff --stat "$base...HEAD" 2>/dev/null || echo "Not a git repository"
    else
      git show --stat --format= HEAD 2>/dev/null || echo "Not a git repository"
    fi
    ;;

  # --- New commands for speckit.review, speckit.baseline, hef.fix ---
  check-plan-review)
    test -f ".specify/specs/$BRANCH/plan.md" && echo "PLAN_EXISTS: $BRANCH" || echo "NO_PLAN"
    grep -q "^## Reviewed" ".specify/specs/$BRANCH/plan.md" 2>/dev/null && echo "PLAN_REVIEWED" || echo "PLAN_NOT_REVIEWED"
    ;;
  detect-existing-code)
    SRC_COUNT=$(find . -maxdepth 4 -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.rs" -o -name "*.go" -o -name "*.java" -o -name "*.rb" -o -name "*.kt" -o -name "*.swift" -o -name "*.c" -o -name "*.cpp" \) ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/vendor/*" ! -path "*/target/*" 2>/dev/null | wc -l)
    echo "SOURCE_FILES: $SRC_COUNT"
    find . -maxdepth 2 -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.rs" -o -name "*.go" -o -name "*.java" -o -name "*.rb" \) ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null | sed 's|/[^/]*$||' | sort -u | head -10
    ;;
  trivial-change-check)
    STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l)
    UNSTAGED=$(git diff --name-only 2>/dev/null | wc -l)
    TOTAL=$((STAGED + UNSTAGED))
    echo "STAGED_FILES: $STAGED"
    echo "UNSTAGED_FILES: $UNSTAGED"
    echo "TOTAL_CHANGED: $TOTAL"
    git diff --name-only 2>/dev/null | head -10
    git diff --cached --name-only 2>/dev/null | head -10
    ;;

  # --- Plan phase marker (RIPER-style write-block) ---
  # The marker file .specify/.plan-in-progress activates plan-phase-write-block.sh,
  # which mechanically blocks Edit/Write to paths outside .specify/ while the plan
  # is being generated. hef.plan sets it in pre-flight and clears it after
  # plan.md is written.
  plan-phase-start)
    mkdir -p .specify
    touch .specify/.plan-in-progress
    echo "PLAN_PHASE_STARTED: write-block active for paths outside .specify/"
    ;;
  plan-phase-end)
    rm -f .specify/.plan-in-progress
    echo "PLAN_PHASE_ENDED: write-block cleared"
    ;;
  plan-phase-status)
    if [ -f .specify/.plan-in-progress ]; then
      echo "PLAN_PHASE_ACTIVE"
    else
      echo "PLAN_PHASE_INACTIVE"
    fi
    ;;

  # --- Implement phase marker (test guard) ---
  # .specify/.implement-in-progress arms implement-phase-test-guard.sh: while it exists, test files
  # may grow but not shrink (no assertion-removing edits, no overwrites, no rm). hef.implement
  # sets it in pre-flight and clears it in the completion step.
  implement-phase-start)
    mkdir -p .specify
    touch .specify/.implement-in-progress
    echo "IMPLEMENT_PHASE_STARTED: test guard active — tests may grow, not shrink"
    ;;
  implement-phase-end)
    rm -f .specify/.implement-in-progress
    echo "IMPLEMENT_PHASE_ENDED: test guard cleared"
    ;;
  implement-phase-status)
    if [ -f .specify/.implement-in-progress ]; then
      echo "IMPLEMENT_PHASE_ACTIVE"
    else
      echo "IMPLEMENT_PHASE_INACTIVE"
    fi
    ;;

  # --- Requirement traceability ---
  # PREDICATE. Prints the FR → test matrix on stdout AND answers with the exit code: 0 when every
  # FR-NNN in spec.md is cited by at least one test file and no test cites an id the spec does not
  # declare; 1 otherwise. A missing spec is a fetcher failure (stderr, non-zero), per principle 5.
  #
  # "Cites" is lexical: the token FR-NNN appears in a test file — a pytest marker, a describe()
  # title, or a comment all count. Zero-dependency and language-agnostic on purpose; and because
  # nobody types FR-007 into a test by accident, a hit is a claim someone made.
  #
  # This is the half of the traceability chain nothing checked before: /speckit.analyze maps FR →
  # tasks BEFORE code exists; the implement report's "coverage mapping" was prose the model wrote.
  # req-coverage [<spec-name>|--all] — no argument: the current branch's spec (the /hef.verify
  # case). A name: that spec, whatever the branch (CI on main has no feature branch). --all: every
  # spec whose tasks.md has no open task — the SHIPPED ones — each run as its own predicate; specs
  # still in progress are listed and skipped, because their uncovered requirements are the work
  # that has not happened yet, not drift. Post-ship drift is the case nothing checked: /hef.verify
  # runs once, at implementation, and a later hotfix that breaks a cited test rots the spec silently.
  req-coverage)
    target="${2:-}"
    if [ "$target" = "--all" ]; then
      ls -d .specify/specs/*/ >/dev/null 2>&1 || die "req-coverage --all: no .specify/specs/ directories here"
      failed=0; ran=0; skipped=0
      for d in .specify/specs/*/; do
        name="${d#.specify/specs/}"; name="${name%/}"
        [ -f "$d/spec.md" ] || continue
        if [ -f "$d/tasks.md" ] && grep -qE '^\s*- \[[ ~]\]' "$d/tasks.md"; then
          echo "== $name: IN PROGRESS (open tasks) — skipped"; skipped=$((skipped + 1)); continue
        fi
        ran=$((ran + 1))
        if ! "$0" req-coverage "$name"; then failed=$((failed + 1)); fi
      done
      echo "req-coverage --all: $ran shipped spec(s) checked, $failed failing, $skipped in progress"
      [ "$failed" -eq 0 ] && [ "$ran" -gt 0 ]
      exit $?
    fi
    label="${target:-$BRANCH}"
    spec=".specify/specs/$label/spec.md"
    if [ -n "$target" ]; then
      [ -f "$spec" ] || die "req-coverage: no spec at $spec (named spec '$target' does not exist)"
    else
      [ -f "$spec" ] || missing_artifact spec.md
    fi
    ids="$(grep -oE '\bFR-[0-9]+\b' "$spec" | sort -u)"
    [ -n "$ids" ] || die "req-coverage: $spec declares no FR-NNN ids — nothing to trace. Add functional requirements to the spec first."
    # Test files: code extensions only, inside a test location or with a test-ish name. Excludes
    # .specify/ (spec.md would otherwise self-cite every id) and vendored trees.
    files="$(find . -type f \
      \( -name '*.py' -o -name '*.js' -o -name '*.jsx' -o -name '*.ts' -o -name '*.tsx' -o -name '*.go' \
         -o -name '*.rs' -o -name '*.java' -o -name '*.kt' -o -name '*.rb' -o -name '*.sh' -o -name '*.bats' \) \
      \( -path '*/tests/*' -o -path '*/test/*' -o -path '*/__tests__/*' -o -path '*/spec/*' \
         -o -name '*test*' -o -name '*spec*' \) \
      -not -path '*/.specify/*' -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' \
      -not -path '*/target/*' -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.venv/*' \
      -not -path '*/graphify-out/*' 2>/dev/null | sort)"
    echo "REQUIREMENT COVERAGE — $label"
    echo "spec: $spec · test files scanned: $(printf '%s\n' "$files" | grep -c . || true)"
    uncovered=0; total=0
    while read -r id; do
      [ -z "$id" ] && continue
      total=$((total + 1))
      hits=""
      [ -n "$files" ] && hits="$(printf '%s\n' "$files" | xargs grep -nHwF -- "$id" 2>/dev/null | cut -d: -f1,2 | head -5 | tr '\n' ' ')"
      if [ -n "$hits" ]; then
        printf '%-8s COVERED    %s\n' "$id" "$hits"
      else
        printf '%-8s UNCOVERED  —\n' "$id"
        uncovered=$((uncovered + 1))
      fi
    done <<<"$ids"
    unknown=0; elsewhere=0
    # A test suite is shared across feature branches while FR ids are per spec, so an id this
    # spec does not declare may be another spec's (measured 2026-09-25 on the second feature
    # branch this repo ran: the suite cited the first spec's FR-016..FR-019). That is ELSEWHERE —
    # reported, not failing. UNKNOWN is an id no spec directory declares: a typo, or a claim
    # about a requirement that does not exist.
    others="$(cat .specify/specs/*/spec.md 2>/dev/null | grep -oE '\bFR-[0-9]+\b' | sort -u)"
    if [ -n "$files" ]; then
      cited="$(printf '%s\n' "$files" | xargs grep -ohwE 'FR-[0-9]+' 2>/dev/null | sort -u)"
      while read -r c; do
        [ -z "$c" ] && continue
        grep -qxF "$c" <<<"$ids" && continue
        where="$(printf '%s\n' "$files" | xargs grep -nHwF -- "$c" 2>/dev/null | cut -d: -f1,2 | head -3 | tr '\n' ' ')"
        if grep -qxF "$c" <<<"$others"; then
          printf '%-8s ELSEWHERE  %s(declared by another spec)\n' "$c" "$where"
          elsewhere=$((elsewhere + 1))
        else
          printf '%-8s UNKNOWN    %s(not declared by any spec)\n' "$c" "$where"
          unknown=$((unknown + 1))
        fi
      done <<<"$cited"
    fi
    echo "summary: $((total - uncovered))/$total requirements covered, $unknown unknown id(s) cited, $elsewhere declared by other specs"
    [ "$uncovered" -eq 0 ] && [ "$unknown" -eq 0 ]
    ;;

  # --- Mutation-score ratchet ---
  # The mark lives at .specify/mutation-score (an integer percent), committed with the code.
  # mutation-score  — PREDICATE: prints the mark (exit 0) or NO_MARK (exit 1; a normal first-run
  #                   state, which is why it is not a fetcher failure).
  # mutation-ratchet <score> — PREDICATE: exit 0 when score ≥ mark − 5, else 1. Raise-only marks
  #                   with a fixed floor: a fixed threshold drifts to aspirational; a PR-driven
  #                   ratchet cascades failures across concurrent PRs; this is the middle.
  # mutation-raise <score> — writes the mark when score > mark. The COMMAND decides whether the
  #                   branch is allowed to raise (default branch only); the helper only writes.
  mutation-score)
    if [ -f .specify/mutation-score ]; then cat .specify/mutation-score; else echo "NO_MARK"; exit 1; fi
    ;;
  mutation-ratchet)
    score="${2:-}"
    [[ "$score" =~ ^[0-9]+$ ]] || die "mutation-ratchet: usage: mutation-ratchet <integer percent>, got '${score:-<none>}'"
    mark="$(cat .specify/mutation-score 2>/dev/null || echo 0)"
    [[ "$mark" =~ ^[0-9]+$ ]] || mark=0
    floor=$((mark - 5)); [ "$floor" -lt 0 ] && floor=0
    if [ "$score" -ge "$floor" ]; then
      echo "RATCHET_PASS: score=$score mark=$mark floor=$floor"
    else
      echo "RATCHET_FAIL: score=$score mark=$mark floor=$floor — the tests noticed less than they used to"
      exit 1
    fi
    ;;
  mutation-raise)
    score="${2:-}"
    [[ "$score" =~ ^[0-9]+$ ]] || die "mutation-raise: usage: mutation-raise <integer percent>, got '${score:-<none>}'"
    mark="$(cat .specify/mutation-score 2>/dev/null || echo 0)"
    [[ "$mark" =~ ^[0-9]+$ ]] || mark=0
    if [ "$score" -gt "$mark" ]; then
      mkdir -p .specify && printf '%s\n' "$score" > .specify/mutation-score
      echo "RAISED: $mark → $score (.specify/mutation-score)"
    else
      echo "NOT_RAISED: score=$score mark=$mark (the mark only moves up)"
    fi
    ;;

  # --- Doctor: which copy is actually running ---
  # doctor-copies — FETCHER. Prints the profile, the RUNNING copy (from the profile's plugin
  #                 registry), the clone it was installed from, and a status line. Exit non-zero
  #                 only when the registry has no hefesto entry — every other state is an answer.
  #
  # Measured 2026-09-23: `plugin install` COPIES the directory-marketplace clone into
  # $CLAUDE_CONFIG_DIR/plugins/cache/hefesto/hefesto/<version>/, and sessions load from there.
  # /hef.doctor used to `git rev-parse` CLAUDE_PLUGIN_ROOT — which IS that cache, and is not a git
  # clone — so it reported "staleness cannot be measured" for the one copy that matters, while the
  # clone it did measure was not what ran. Three profiles: two on 7.0.1, one still on 6.0.0, and
  # the doctor would have called all three in sync.
  doctor-copies)
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    case "$root" in
      */plugins/cache/*) cfg="${root%%/plugins/cache/*}" ;;   # running from a cache: its profile
      *) cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ;;         # dev checkout: the env's profile
    esac
    reg="$cfg/plugins/installed_plugins.json"; mk="$cfg/plugins/known_marketplaces.json"
    [ -f "$reg" ] || die "doctor-copies: no plugin registry at $reg — hefesto is not installed in this profile"
    run_ver="$(jq -r '.plugins["hefesto@hefesto"][0].version // empty' "$reg" 2>/dev/null)"
    run_sha="$(jq -r '.plugins["hefesto@hefesto"][0].gitCommitSha // empty' "$reg" 2>/dev/null)"
    run_path="$(jq -r '.plugins["hefesto@hefesto"][0].installPath // empty' "$reg" 2>/dev/null)"
    [ -n "$run_ver" ] || die "doctor-copies: hefesto@hefesto has no entry in $reg — installed under another name, or not at all"
    echo "profile: $cfg"
    echo "running: $run_ver ${run_sha:0:7} ($run_path)"
    clone="$(jq -r '.hefesto.installLocation // .hefesto.source.path // empty' "$mk" 2>/dev/null)"
    if [ -z "$clone" ] || ! git -C "$clone" rev-parse --show-toplevel >/dev/null 2>&1; then
      echo "clone: NOT-A-GIT-CLONE (${clone:-no 'hefesto' marketplace record}) — staleness cannot be measured"
      echo "status: UNMEASURABLE"
      exit 0
    fi
    clone_sha="$(git -C "$clone" rev-parse HEAD 2>/dev/null)"
    clone_ver="$(jq -r '.version // "?"' "$clone/.claude-plugin/plugin.json" 2>/dev/null)"
    if git -C "$clone" fetch -q origin 2>/dev/null; then
      behind="$(git -C "$clone" rev-list --count HEAD..origin/main 2>/dev/null || echo '?')"
    else
      # No network, or the sandbox cannot write FETCH_HEAD: measure against the last fetched ref.
      behind="$(git -C "$clone" rev-list --count HEAD..origin/main 2>/dev/null || echo '?') (as of the last fetch — fetch failed)"
    fi
    mods="$(git -C "$clone" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    echo "clone: $clone_ver ${clone_sha:0:7} ($clone) — $behind behind origin/main, $mods local modification(s)"
    if [ "$run_sha" = "$clone_sha" ]; then
      echo "status: RUNNING_MATCHES_CLONE"
    elif [ "$run_ver" = "$clone_ver" ]; then
      echo "status: RUNNING_BEHIND_CLONE_SAME_VERSION — 'claude plugin update' will say up to date (it keys off the manifest version); to run the clone's HEAD: claude plugin uninstall hefesto@hefesto && claude plugin install hefesto@hefesto (CLAUDE_CONFIG_DIR=$cfg), then restart"
    else
      echo "status: RUNNING_BEHIND_CLONE — run: claude plugin update hefesto@hefesto (CLAUDE_CONFIG_DIR=$cfg), then restart"
    fi
    ;;

  # --- RTK CLI output compression (optional, auto-detected) ---
  # --- /hef.plan --arena (feature plan-arena FR-006, FR-008) ---------------------------------------
  # arena-cite-check: every `path:line` a truth-scout cited must exist in the checkout — verified here
  # in ONE call so the planner never reads up to 36 cited lines into its own context. A missing
  # citation is printed, never silently dropped (constitution 5).
  arena-cite-check)
    target="${2:-}"
    [ -f "$target" ] || { echo "arena-cite-check: no digest file '$target' (expected the saved <truth-digest> block)" >&2; exit 2; }
    # Only the citation token of a claim line (`- C<n> <path>:<line> — …`) is scanned: prose in the digest
    # (times, ratios, host:port, FR-001:2) is not a citation. The path keeps its leading dot — a citation
    # into .claude/ or .specify/ is routine here (code review 2026-09-30) — and anything with `..` or an
    # absolute path is outside the checkout by definition.
    cites="$(grep -oE '^- C[0-9]+ +[^ ]+:[0-9]+' "$target" | sed -E 's/^- C[0-9]+ +//' | sort | uniq)"
    [ -n "$cites" ] || { echo "arena-cite-check: no claim citation (- C<n> <path>:<line>) in $target — a digest without citations has no claims" >&2; exit 1; }
    bad=0
    while read -r c; do
      p="${c%:*}"; n="${c##*:}"
      case "/$p/" in */../*|//*) echo "missing $c — outside the checkout"; bad=1; continue ;; esac
      if [ "$n" -lt 1 ]; then echo "missing $c — line numbers start at 1"; bad=1
      elif [ ! -f "$p" ]; then echo "missing $c — no such file"; bad=1
      elif [ "$(awk 'END{print NR}' "$p")" -lt "$n" ]; then echo "missing $c — file has $(awk 'END{print NR}' "$p") lines"; bad=1   # NR counts a last line without \n; wc -l does not
      else echo "ok $c"; fi
    done <<<"$cites"
    exit "$bad"
    ;;
  # arena-metrics: the number the arena exists for, read back from research.md's footer and plan.md's
  # [C<n>] citations. Lexical on purpose: nobody types `<!-- arena K=` or `[C7]` by accident. The footer
  # may not claim more disagreements than ### Disagreements lists — the metric must be self-consistent.
  arena-metrics)
    dir="${2:-.specify/specs/$BRANCH}"; r="$dir/research.md"; p="$dir/plan.md"
    [ -f "$r" ] || { [ -n "${2:-}" ] && die "arena-metrics: no $r" || missing_artifact research.md; }
    foot="$(grep -oE '<!-- arena K=[^>]*-->' "$r" | tail -1)"
    [ -n "$foot" ] || die "arena-metrics: no arena footer in $r (Phase 0 ran without --arena?)"
    for k in K tiers claims agreed disagreements unverified; do
      v="$(grep -oE "\b$k=[A-Za-z0-9,]+" <<<"$foot" | head -1 | cut -d= -f2)"
      [ -n "$v" ] || die "arena-metrics: footer lacks $k= in: $foot"
      if [ "$k" != tiers ] && ! [[ "$v" =~ ^[0-9]+$ ]]; then die "arena-metrics: footer field $k=$v is not a number in: $foot"; fi
      echo "$k=$v"
    done
    dis="$(awk '/^### Disagreements/{f=1;next} /^#/{f=0} f' "$r" | grep -oE '^- C[0-9]+' | sed 's/^- //' | sort | uniq)"
    nd="$(grep -c . <<<"${dis:-}")"; fd="$(grep -oE '\bdisagreements=[0-9]+' <<<"$foot" | cut -d= -f2)"
    [ "$nd" -eq "$fd" ] || die "arena-metrics: footer says disagreements=$fd but ### Disagreements lists $nd entries in $r"
    cited="$( [ -f "$p" ] && grep -oE '\[C[0-9]+\]' "$p" | tr -d '[]' | sort | uniq || true)"
    echo "cited=$(grep -c . <<<"${cited:-}")"
    echo "cited_from_disagreements=$(comm -12 <(printf '%s\n' "$cited") <(printf '%s\n' "$dis") | grep -c .)"
    ;;

  # --- dependencies (feature dependency-audit FR-001, FR-002) ------------------------------------------
  deps-diff)
    shift; staged=0; base=""
    for a in "$@"; do case "$a" in --staged) staged=1 ;; -*) die "deps-diff: unknown option '$a' (expected --staged or a base ref)" ;; *) base="$a" ;; esac; done
    git rev-parse --git-dir >/dev/null 2>&1 || die "deps-diff: not a git repository ($PWD)"
    # git prints root-relative paths: read every manifest from the toplevel, or a subdirectory run reads
    # the wrong file (code review 2026-10-02).
    cd "$(git rev-parse --show-toplevel)" || die "deps-diff: cannot enter the repository toplevel"
    if [ "$staged" = 1 ]; then
      old="HEAD"; git rev-parse --verify -q HEAD >/dev/null 2>&1 || old=""
      files=$(git diff --cached --name-only --no-renames 2>/dev/null)
    else
      [ -n "$base" ] || base=$(integration_base) || die "deps-diff: .branches in .claude/project-status.json is malformed (ledger.sh branches says why)"
      if [ -z "$base" ]; then
        for b in main master; do git rev-parse --verify -q "$b" >/dev/null 2>&1 && { base=$(git merge-base HEAD "$b" 2>/dev/null); break; }; done
        [ -n "$base" ] || base=$(pr_base)
      fi
      [ -n "$base" ] || die "deps-diff: no base to compare with (no main/master, no upstream, no parent) — pass one: deps-diff <ref>"
      git rev-parse --verify -q "$base^{commit}" >/dev/null 2>&1 || die "deps-diff: base '$base' does not resolve to a commit"
      old="$base"; files=$(git diff --name-only --no-renames "$base" 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)
    fi
    # The loop is not a pipeline stage: a parser that fails (an invalid package.json) must fail the arm,
    # never yield an empty side that reads as "every dependency removed".
    DEPS_OUT=$(while IFS= read -r f; do
      read -r eco fn <<<"$(deps_parser "$(basename "$f")")"; [ -n "${fn:-}" ] || continue
      o=""; n=""
      if [ -n "$old" ] && git cat-file -e "$old:$f" 2>/dev/null; then o=$(git show "$old:$f" | tr -d '\r' | "$fn") || exit 1; fi
      if [ "$staged" = 1 ]; then
        if git cat-file -e ":$f" 2>/dev/null; then n=$(git show ":$f" | tr -d '\r' | "$fn") || exit 1; fi
      elif [ -f "$f" ]; then n=$(tr -d '\r' < "$f" | "$fn") || exit 1; fi
      # NF on both sides: an absent side is an empty list, never one empty record (a phantom "removed").
      awk -F'\t' -v e="$eco" 'NR == FNR { if (NF) o[$1] = $2; next } NF { if (!($1 in o)) print "added " e " " $1 " " $2; else if (o[$1] != $2) print "changed " e " " $1 " " o[$1] " -> " $2; delete o[$1] } END { for (k in o) print "removed " e " " k " " o[k] }' \
        <(printf '%s\n' "$o") <(printf '%s\n' "$n")
    done < <(grep -E "$DEPS_MANIFEST_RE" <<<"$files" | sort | uniq)) || die "deps-diff: a manifest could not be parsed (see above) — nothing reported"
    [ -z "$DEPS_OUT" ] || sort <<<"$DEPS_OUT"
    ;;
  deps-audit)
    git rev-parse --git-dir >/dev/null 2>&1 || die "deps-audit: not a git repository ($PWD)"
    # The auditors read the ROOT's manifests (a nested package is listed by deps-diff and audited only by
    # osv-scanner, which walks the tree) — run from the toplevel whatever the cwd.
    cd "$(git rev-parse --show-toplevel)" || die "deps-audit: cannot enter the repository toplevel"
    DEPS_DIR="${HEFESTO_DEPS_DIR:-$(git rev-parse --path-format=absolute --git-common-dir)/hefesto/deps}"
    mkdir -p "$DEPS_DIR" || die "deps-audit: cannot create $DEPS_DIR"
    AUDIT_RAN=0; AUDIT_FOUND=0; MISSING=0
    have() { command -v "$1" >/dev/null 2>&1; }
    miss() { echo "missing $1: $2 ($3)"; MISSING=1; }
    if [ -f package.json ]; then
      if have npm; then run_auditor npm-audit "0 1" '.metadata.vulnerabilities.total' 0 npm audit --json
      else miss npm npm "install Node.js"; fi
    fi
    reqs=$(ls requirements*.txt 2>/dev/null)
    if [ -n "$reqs" ] || [ -f pyproject.toml ]; then
      # pip-audit RESOLVES by pip-installing into a temporary venv — which runs the build code of exactly
      # the package this audit exists to catch (a squatted `reqeusts`). So it runs only with --no-deps
      # --disable-pip, which reads pinned requirements without installing anything; an unpinned file then
      # exits outside {0,1} and reads `unknown`; a pyproject-only project is not audited (code review 2026-10-02).
      if have pip-audit; then
        if [ -n "$reqs" ]; then for r in $reqs; do run_auditor "pip-audit-${r%.txt}" "0 1" 'if any(.dependencies[]; has("skip_reason")) then null else ([.dependencies[].vulns | length] | add // 0) end' 0 pip-audit -f json --no-deps --disable-pip -r "$r"; done
        else echo "skipped pypi: pip-audit would install pyproject.toml's dependencies to resolve them — audit a pinned requirements file instead (pip-audit -r <file> --no-deps --disable-pip)"; MISSING=1; fi
      else miss pypi pip-audit "pipx install pip-audit"; fi
    fi
    if [ -f Cargo.toml ]; then
      if have cargo-audit; then run_auditor cargo-audit "0 1" '.vulnerabilities.count' 0 cargo-audit audit --json
      else miss crates cargo-audit "cargo install cargo-audit"; fi
    fi
    if [ -f go.mod ]; then
      # govulncheck -json is a STREAM of objects; exit 0 whether or not it finds — count distinct advisories.
      if have govulncheck; then run_auditor govulncheck "0" '[.[] | select(.finding) | .finding.osv] | unique | length' 1 govulncheck -json ./...
      else miss go govulncheck "go install golang.org/x/vuln/cmd/govulncheck@latest"; fi
    fi
    if have osv-scanner; then run_auditor osv-scanner "0 1" '[.results[].packages[].vulnerabilities[]] | length' 0 osv-scanner --format json -r .; fi
    [ "$AUDIT_RAN" = 1 ] || { [ "$MISSING" = 1 ] || echo "no manifest with a known auditor here"; exit 3; }
    [ "$AUDIT_FOUND" = 0 ] || exit 1
    ;;

  rtk-available)
    # PREDICATE. The answer is BOTH the string and the exit code.
    #
    # This used to always exit 0 — the comment said so on purpose, "so callers can branch on the
    # output". But the only caller is quality-tooling.md, which branches on the EXIT CODE:
    #
    #     helper rtk-available && rtk pytest -q || pytest -q
    #
    # With a constant 0 the && branch ALWAYS ran, rtk or no rtk. The guard did not guard: the
    # pattern only fell back because `rtk` itself then died with 127, which is exactly what a bare
    # `rtk pytest || pytest` does — except it prints a command-not-found error, in a rule whose
    # whole point is that rtk stays "a silent, non-blocking enhancement". Verified by running the
    # documented line with rtk off PATH: it took the rtk branch.
    #
    # The string still prints, so a model reading output loses nothing.
    if command -v rtk >/dev/null 2>&1; then
      echo "RTK_AVAILABLE"
    else
      echo "RTK_MISSING"
      exit 1
    fi
    ;;
  rtk-run)
    # Run a command through rtk if available, otherwise run it plain.
    # Usage: speckit-helper.sh rtk-run <cmd> [args...]
    shift
    if [ "$#" -eq 0 ]; then
      echo "rtk-run: no command provided" >&2
      exit 2
    fi
    if command -v rtk >/dev/null 2>&1; then
      exec rtk "$@"
    else
      exec "$@"
    fi
    ;;

  *)
    echo "Unknown command: $1"
    echo "Usage: speckit-helper.sh <command>"
    echo "Commands: branch, check-git-root, spec, plan, check-spec, check-plan,"
    echo "  check-artifacts, all-artifacts, clarifications, checklists, checklists-dir,"
    echo "  checklists-content, constitution, list-specs, list-specs-dir, check-specify-dir,"
    echo "  detect-stack, detect-test-framework, list-config-files, list-rules, readme-head,"
    echo "  check-plan-review, detect-existing-code, trivial-change-check,"
    echo "  plan-phase-start, plan-phase-end, plan-phase-status,"
    echo "  implement-phase-start, implement-phase-end, implement-phase-status, req-coverage [<spec>|--all],"
    echo "  mutation-score, mutation-ratchet <score>, mutation-raise <score>, doctor-copies,"
    echo "  arena-cite-check <digest-file>, arena-metrics [<spec-dir>], deps-diff [--staged] [<base>], deps-audit,"
    echo "  rtk-available, rtk-run"
    exit 1
    ;;
esac
