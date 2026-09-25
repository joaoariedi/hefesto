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
pr_base() {
  git rev-parse --verify -q '@{u}' >/dev/null 2>&1 && { git rev-parse --abbrev-ref '@{u}'; return; }
  for b in main master; do
    git rev-parse --verify -q "$b" >/dev/null 2>&1 && { echo "$b"; return; }
  done
  git rev-parse --verify -q 'HEAD~1' >/dev/null 2>&1 && { echo 'HEAD~1'; return; }
  echo ""   # root commit: the caller diffs against the commit itself
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
    base=$(pr_base)
    if [ -n "$base" ]; then
      git log --oneline "$base..HEAD" 2>/dev/null || echo "Not a git repository"
    else
      git log --oneline -10 2>/dev/null || echo "Not a git repository"
    fi
    ;;
  pr-files)
    base=$(pr_base)
    if [ -n "$base" ]; then
      git diff --name-status "$base...HEAD" 2>/dev/null || echo "Not a git repository"
    else
      # Root commit — show what it introduced rather than exiting 128.
      git show --name-status --format= HEAD 2>/dev/null || echo "Not a git repository"
    fi
    ;;
  pr-stats)
    base=$(pr_base)
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
    echo "  rtk-available, rtk-run"
    exit 1
    ;;
esac
