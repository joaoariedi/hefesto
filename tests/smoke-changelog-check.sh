# shellcheck shell=bash
# shellcheck disable=SC2016  # literal backticks and $ARGUMENTS in the command-text phrases (part 7)
#
# lanes-parity (9.1) smoke checks, part 4 — hooks/changelog-check.sh: CHANGELOG placement against a base ref and the
# per-repo version (T019: FR-025, FR-026, NR-006; plan Sketch 9, note 22).
#
# SOURCED by tests/smoke.sh after the other lifecycle parts, never run on its own. Self-contained: throwaway git repos
# with a Keep-a-Changelog CHANGELOG.md (link references at the foot), checked with -C from a different directory.

if [ -z "${REPO:-}" ] || ! declare -F ok bad head_ >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-changelog-check.sh: source it from tests/smoke.sh (needs REPO, ok, bad, head_)"
  else echo "tests/smoke-changelog-check.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

head_ "CHANGELOG placement: released sections byte-identical, exit 2 when it cannot judge (FR-025, FR-026, NR-006)"
cc_fail=0
cc_t="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/smoke-cc.XXXXXX")" && pwd -P)"; cc_r="$cc_t/app"
CC="$REPO/hooks/changelog-check.sh"
cc_git() { git -C "$cc_r" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
cc_log() { # cc_log <unreleased line> <1.1.0 first line> <foot link for Unreleased>: a Keep-a-Changelog file
  printf '# Changelog\n\n## [Unreleased]\n%s\n\n## [1.1.0] - 2026-10-01\n### Added\n- %s\n\n## [1.0.0] - 2026-09-01\n### Added\n- first release\n\n[Unreleased]: https://example.test/compare/%s...HEAD\n[1.1.0]: https://example.test/compare/v1.0.0...v1.1.0\n[1.0.0]: https://example.test/releases/v1.0.0\n' "$1" "$2" "$3"
}
cc_run() { # cc_run <want exit> <label> <args…>: runs from $cc_t (not the repo) so only -C points it there
  local want="$1" label="$2" got; shift 2
  (cd "$cc_t" && bash "$CC" -C "$cc_r" "$@") > "$cc_t/out" 2>&1; got=$?
  [ "$got" = "$want" ] || { bad "changelog-check $label: want exit $want, got $got — $(head -c 400 "$cc_t/out")"; cc_fail=1; return 1; }
}
cc_says() { grep -qF -- "$1" "$cc_t/out" || { bad "changelog-check $2: output must name '$1' — got: $(head -c 400 "$cc_t/out")"; cc_fail=1; }; }

git init -q -b main "$cc_r"; cc_log "" "the second release" "v1.1.0" > "$cc_r/CHANGELOG.md"
cc_git add CHANGELOG.md; cc_git commit -qm base; cc_git switch -qc release

# 1. new entries under [Unreleased] only, and the [Unreleased] link reference rewritten: placed
cc_log "- a new entry" "the second release" "v1.1.0-rc" > "$cc_r/CHANGELOG.md"
cc_run 0 "with entries only under [Unreleased]" placement --base main

# 2. the cut: [Unreleased] moved into ## [1.2.0] with a new link reference — 0 with --cut 1.2.0, 1 without
printf '# Changelog\n\n## [Unreleased]\n\n## [1.2.0] - 2026-10-27\n- a new entry\n\n## [1.1.0] - 2026-10-01\n### Added\n- the second release\n\n## [1.0.0] - 2026-09-01\n### Added\n- first release\n\n[Unreleased]: https://example.test/compare/v1.2.0...HEAD\n[1.2.0]: https://example.test/compare/v1.1.0...v1.2.0\n[1.1.0]: https://example.test/compare/v1.0.0...v1.1.0\n[1.0.0]: https://example.test/releases/v1.0.0\n' > "$cc_r/CHANGELOG.md"
cc_run 0 "with --cut naming the new section" placement --base main --cut 1.2.0
cc_run 1 "with a new released section that is not --cut" placement --base main && cc_says '## [1.2.0]' "(new section)"
cc_run 1 "with --cut naming another version" placement --base main --cut 1.3.0 && cc_says '## [1.2.0]' "(wrong --cut)"

# 3. a stacked-train auto-merge that edits a released section: the next train branch merges in, rewriting 1.0.0
cc_log "- a new entry" "the second release" "v1.1.0" > "$cc_r/CHANGELOG.md"; cc_git commit -qam "release entry"
cc_git switch -qc train-2 main
sed 's/^- first release$/- first release (reworded by the train)/' "$cc_r/CHANGELOG.md" > "$cc_t/c" && cat "$cc_t/c" > "$cc_r/CHANGELOG.md"
cc_git commit -qam "train-2 rewords 1.0.0"; cc_git switch -q release; cc_git merge -q --no-edit train-2 >/dev/null
cc_run 1 "after a stacked-train auto-merge edits ## [1.0.0]" placement --base main \
  && { cc_says '## [1.0.0]' "(train merge)"; cc_says 'reworded by the train' "(train merge: the first differing line)"; }
# the same edit is caught even when that section is named by --cut for another version
cc_run 1 "with a released-section edit and --cut 1.2.0" placement --base main --cut 1.2.0 && cc_says '## [1.0.0]' "(edit + cut)"

# 4. a released section that vanished on the branch is a failure, not a pass
cc_log "- a new entry" "the second release" "v1.1.0" | awk '/^## \[1.0.0\]/{s=1} /^\[Unreleased\]: /{s=0} !s' > "$cc_r/CHANGELOG.md"
cc_run 1 "with ## [1.0.0] removed" placement --base main && cc_says '## [1.0.0]' "(removed section)"
# a heading-only change (the date of a release) is a change to that released section
cc_log "" "the second release" "v1.1.0" | sed 's/^## \[1.1.0\] - 2026-10-01$/## [1.1.0] - 2026-10-02/' > "$cc_r/CHANGELOG.md"
cc_run 1 "with a released heading's date changed" placement --base main && cc_says '## [1.1.0]' "(heading date)"

# 4b. the T019 verifier's bypasses (2026-10-27): new text outside [Unreleased]/the cut, wherever it hides
cc_log "" "the second release" "v1.1.0" | sed 's/^# Changelog$/# Changelog\n\n- an entry in the preamble/' > "$cc_r/CHANGELOG.md"
cc_run 1 "with an entry added to the preamble" placement --base main && cc_says '(preamble)' "(preamble)"
cc_log "" "the second release" "v1.1.0" | sed 's/^## \[1.1.0\] - 2026-10-01$/## [1.1.0-rc1]\n- a pre-release entry\n\n&/' > "$cc_r/CHANGELOG.md"
cc_run 1 "with a new ## [1.1.0-rc1] section" placement --base main && cc_says '## [1.1.0-rc1]' "(non-semver heading)"
cc_run 1 "with a new ## [1.1.0-rc1] section and --cut 1.2.0" placement --base main --cut 1.2.0 && cc_says '## [1.1.0-rc1]' "(non-semver + cut)"
cc_log "" "the second release" "v1.1.0" | sed 's/^## \[1.0.0\] - 2026-09-01$/## Notes\n- a note\n\n&/' > "$cc_r/CHANGELOG.md"
cc_run 1 "with a new ## Notes section" placement --base main && cc_says '## Notes' "(plain heading)"
cc_log "" "the second release" "v1.1.0" | sed 's/^- first release$/- first release (reworded under a cut)/' > "$cc_r/CHANGELOG.md"
cc_run 1 "with --cut naming a version already released on the base, reworded" placement --base main --cut 1.0.0 \
  && { cc_says '## [1.0.0]' "(cut of a released version)"; cc_says 'reworded under a cut' "(cut of a released version: the line)"; }
cc_log "" "the second release" "v1.1.0" > "$cc_r/CHANGELOG.md"
cc_run 0 "with --cut naming an unchanged released version" placement --base main --cut 1.0.0
# a body line shaped like a link reference ([X]: words) is text, not a link: rewording it in a released section fails
# (code review of PR B) — only a `[label]: <one target>` line is skipped
cc_prev="$(git -C "$cc_r" branch --show-current)"; cp "$cc_r/CHANGELOG.md" "$cc_t/prev"; cc_git checkout -q -- CHANGELOG.md; cc_git switch -qc lr-base main
cc_log "" "the second release" "v1.1.0" | sed 's/^- first release$/&\n[CVE-2026-1]: fixed the thing/' > "$cc_r/CHANGELOG.md"; cc_git commit -qam "a released note"
cc_git switch -qc lr
sed 's/^\[CVE-2026-1\]: fixed the thing$/[CVE-2026-1]: NOT fixed after all/' "$cc_r/CHANGELOG.md" > "$cc_t/c" && cat "$cc_t/c" > "$cc_r/CHANGELOG.md"
cc_run 1 "with a reworded '[X]: words' line in a released section" placement --base lr-base && cc_says 'NOT fixed after all' "(link-shaped body line)"
cc_git checkout -q -- CHANGELOG.md; cc_git switch -q "$cc_prev"; cat "$cc_t/prev" > "$cc_r/CHANGELOG.md"

# 5. cannot judge → 2, never 0 (note 22): no CHANGELOG on the base, an unreadable ref, no '## [' heading
cc_git checkout -q -- CHANGELOG.md
cc_git switch -q --orphan bare; : > "$cc_r/README"; cc_git add README; cc_git commit -qm bare
cc_git switch -qf release; cc_log "" "the second release" "v1.1.0" > "$cc_r/CHANGELOG.md"
cc_run 2 "against a base with no CHANGELOG.md" placement --base bare && cc_says 'CHANGELOG' "(no base CHANGELOG)"
cc_run 2 "against an unreadable ref" placement --base no-such-ref && cc_says 'no-such-ref' "(unreadable ref)"
printf '# Changelog\n\nnothing released yet\n' > "$cc_r/CHANGELOG.md"
cc_run 2 "with no '## [' heading" placement --base main && cc_says '## [' "(no heading)"
cc_run 2 "with no --base" placement
cc_run 2 "with a --cut that is not X.Y.Z" placement --base main --cut v1.2
(cd "$cc_t" && bash "$CC" -C "$cc_t/missing" placement --base main) >/dev/null 2>&1
[ $? = 2 ] || { bad "changelog-check -C at a missing directory must exit 2"; cc_fail=1; }

# 6. version: an X.Y.Z on the [Unreleased] heading wins; otherwise the latest released section; neither → 2
cc_log "- a new entry" "the second release" "v1.1.0" > "$cc_r/CHANGELOG.md"
cc_run 0 "version (no version on [Unreleased])" version && { [ "$(cat "$cc_t/out")" = 1.1.0 ] || { bad "version must print the latest released 1.1.0, got: $(cat "$cc_t/out")"; cc_fail=1; }; }
sed 's/^## \[Unreleased\]$/## [Unreleased] - 1.2.0/' "$cc_r/CHANGELOG.md" > "$cc_t/c" && cat "$cc_t/c" > "$cc_r/CHANGELOG.md"
cc_run 0 "version ([Unreleased] - 1.2.0)" version && { [ "$(cat "$cc_t/out")" = 1.2.0 ] || { bad "version must print the [Unreleased] heading's 1.2.0, got: $(cat "$cc_t/out")"; cc_fail=1; }; }
printf '# Changelog\n\n## [Unreleased]\n- x\n' > "$cc_r/CHANGELOG.md"
cc_run 2 "version with no version anywhere" version

rm -rf "$cc_t"
[ "$cc_fail" -eq 0 ] && ok "changelog-check: placement 0/1/2 (link refs skipped, cut, train merge, removed section, preamble, non-semver and plain headings, a --cut of a released version, cannot judge) and version (FR-025 FR-026 NR-006)"

# 7. /hef.release has a project path (T024, FR-026): a repo with no .claude-plugin/plugin.json takes its version from
# its OWN CHANGELOG through the helper (never another repo's), moves [Unreleased] into the new section, and then runs
# the placement check with --cut. Each phrase is one rule the model must be told, spelled as it runs.
head_ "/hef.release project path: version from the repo's own CHANGELOG, [Unreleased] moved, placement --cut (T024)"
cr_fail=0; cr_md="$REPO/commands/hef.release.md"
for cr_w in 'no `.claude-plugin/plugin.json`' 'hooks/changelog-check.sh -C <repo path> version' \
  "the repo's own" 'never from another repo' 'move the `## [Unreleased]` content into' '## [X.Y.Z] - YYYY-MM-DD' \
  'leave an empty `## [Unreleased]`' 'hooks/changelog-check.sh -C <repo path> placement --base <base> --cut X.Y.Z' \
  'exit 2' 'do not run `release.sh`'; do
  grep -qF -- "$cr_w" "$cr_md" || { bad "commands/hef.release.md must say: $cr_w (T024, US10 FR-026)"; cr_fail=1; }
done
# the project path must not reach the plugin's own bump script or its version-consistency smoke block
cr_pp="$(awk '/^## Project path/{f=1; next} /^## /{f=0} f' "$cr_md")"
[ -n "$cr_pp" ] || { bad "commands/hef.release.md needs a '## Project path' section (T024)"; cr_fail=1; }
grep -qE 'hooks/release\.sh \$ARGUMENTS|tests/smoke\.sh' <<<"$cr_pp" \
  && { bad "the project path must not run hooks/release.sh or tests/smoke.sh — those are this plugin's own (T024)"; cr_fail=1; }
[ "$cr_fail" -eq 0 ] && ok "/hef.release: a project path that derives its version from its own CHANGELOG and checks placement with --cut (FR-026)"
