#!/bin/bash
# changelog-check.sh [-C <path>] placement --base <ref> [--cut <X.Y.Z>]
# changelog-check.sh [-C <path>] version
#
# A Keep-a-Changelog CHANGELOG.md, checked where -C points (a release train checks several repos, so a project
# names this helper by absolute path in orchestrate.merge.checks and its train steps — FR-025, FR-026).
#
# placement: every section on the base except `## [Unreleased]` (the preamble, any `## ` heading, heading included)
#   must be byte-identical on the branch. New text goes only under `## [Unreleased]` or the one section named by
#   --cut, which must be new on the branch. Keep-a-Changelog link references
#   (`[1.2.0]: https://…`) are skipped: the [Unreleased] link changes on every cut.
#   Exit 0 = placed; 1 = misplaced (names the section and prints the first differing line); 2 = cannot judge.
# version: prints the X.Y.Z on the `## [Unreleased]` heading, else the latest `## [X.Y.Z]` (newest first). 2 if none.
#
# Why exit 2 and never 0 when it cannot compare (NR-006, plan note 22, constitution 5): a base with no CHANGELOG is
# what `-C` pointed at the wrong repo looks like, and that must never read as a pass. A section present on the base
# and missing on the branch is a difference like any other — a stacked-train auto-merge that rewords an old entry is
# exactly the case this exists for.
set -uo pipefail
HEF_LL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lane-lib.sh"   # git here ignores core.fsmonitor/hooksPath (lane-lib.sh)
if [ -f "$HEF_LL" ]; then
  # shellcheck source=hooks/lane-lib.sh
  . "$HEF_LL"; hef_git_neutral
fi

cannot() { echo "changelog-check: $*" >&2; exit 2; }
SEMVER='^[0-9]+\.[0-9]+\.[0-9]+$'

# cl_versions <file>: the released versions, in file order
cl_versions() { sed -n -E 's/^## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/p' "$1"; }

# cl_tagged <file>: every line as "<key>\t<line>", link refs skipped. The key is the section a line sits in:
# `[label]` for a `## [label]` heading (any label, not only X.Y.Z), the heading itself for any other `## ` heading,
# and `(preamble)` above the first one. Keying every heading — not only strict `## [X.Y.Z]` — is what stops new text
# hiding in the preamble, a `## [1.1.0-rc1]` or a `## Notes` (T019 verifier, 2026-10-27).
cl_tagged() {
  awk 'BEGIN { k = "(preamble)" }
       /^## / { k = $0; if ($0 ~ /^## \[[^]]*\]/) { k = substr($0, 4); sub(/\].*/, "]", k) } }
       /^\[[^]]+\]: *[^ ]+ *$/ { next }   # a link reference has one target; "[CVE-1]: fixed it" is text
       { print k "\t" $0 }' "$1"
}
cl_keys() { cut -f1 <<<"$1" | awk '!seen[$0]++'; }        # <tagged text> → its section keys, in order
cl_body() { awk -F'\t' -v k="$2" '$1 == k' <<<"$1"; }     # <tagged text> <key> → that section's tagged lines
has() { grep -qxF -- "$1" <<<"$2"; }
cl_name() { case "$1" in '['*) echo "## $1" ;; *) echo "$1" ;; esac; }

# compare_kept <base tagged> <branch tagged>: 1 at the first base section other than [Unreleased] that differs on the
# branch (removed, reworded, heading changed). The --cut version is NOT exempt here: a cut names a section that is new
# on the branch, so one already on the base is released and must stay byte-identical.
compare_kept() {
  local k d
  while IFS= read -r k; do
    [ "$k" = "[Unreleased]" ] && continue
    d="$(diff <(cl_body "$1" "$k" | cut -f2-) <(cl_body "$2" "$k" | cut -f2-))" && continue
    echo "changelog-check: released section changed: $(cl_name "$k")"
    grep -m1 '^<' <<<"$d"; grep -m1 '^>' <<<"$d"   # the base's line, then the branch's (a removal has no '>')
    return 1
  done < <(cl_keys "$1")
}

# new_sections <base tagged> <branch tagged> <cut>: 1 when the branch has a section the base lacks that is neither
# [Unreleased] nor the --cut version
new_sections() {
  local base_ks k; base_ks="$(cl_keys "$1")"
  while IFS= read -r k; do
    { [ "$k" = "[Unreleased]" ] || [ "$k" = "[$3]" ]; } && continue
    has "$k" "$base_ks" && continue
    echo "changelog-check: a section that is not on the base and not --cut: $(cl_name "$k")"
    return 1
  done < <(cl_keys "$2")
}

placement() {
  local base="" cut="" tmp rc bt nt
  while [ $# -gt 0 ]; do
    case "$1" in
      --base) base="${2:-}"; shift 2 || cannot "--base needs a ref" ;;
      --cut) cut="${2:-}"; shift 2 || cannot "--cut needs X.Y.Z" ;;
      *) cannot "placement: unknown argument '$1' (want --base <ref> [--cut <X.Y.Z>])" ;;
    esac
  done
  [ -n "$base" ] || cannot "placement needs --base <ref>"
  [ -z "$cut" ] || [[ "$cut" =~ $SEMVER ]] || cannot "--cut must be X.Y.Z, got '$cut'"
  [ -f CHANGELOG.md ] || cannot "no CHANGELOG.md in $PWD"
  git rev-parse -q --verify "$base^{commit}" >/dev/null 2>&1 || cannot "cannot read $base in $PWD"
  tmp="$(mktemp "${TMPDIR:-/tmp}/changelog-check.XXXXXX")" || cannot "mktemp failed"
  git show "$base:./CHANGELOG.md" > "$tmp" 2>/dev/null || { rm -f "$tmp"; cannot "$base has no CHANGELOG.md in $PWD — cannot judge"; }
  grep -q '^## \[' CHANGELOG.md || { rm -f "$tmp"; cannot "CHANGELOG.md has no '## [' heading"; }
  grep -q '^## \[' "$tmp" || { rm -f "$tmp"; cannot "$base's CHANGELOG.md has no '## [' heading"; }
  bt="$(cl_tagged "$tmp")"; nt="$(cl_tagged CHANGELOG.md)"
  compare_kept "$bt" "$nt" && new_sections "$bt" "$nt" "$cut"; rc=$?
  rm -f "$tmp"
  [ "$rc" -eq 0 ] && echo "changelog-check: placed (against $base${cut:+, cutting $cut})"
  return "$rc"
}

version() {
  local v
  [ -f CHANGELOG.md ] || cannot "no CHANGELOG.md in $PWD"
  v="$(sed -n -E '/^## \[Unreleased\]/{s/.*[^0-9.]([0-9]+\.[0-9]+\.[0-9]+)[^0-9.]*$/\1/p;q;}' CHANGELOG.md)"
  [[ "$v" =~ $SEMVER ]] || v="$(cl_versions CHANGELOG.md | head -1)"
  [ -n "$v" ] || cannot "CHANGELOG.md has no version on [Unreleased] and no '## [X.Y.Z]' section"
  echo "$v"
}

if [ "${1:-}" = "-C" ]; then
  if [ -z "${2:-}" ] || ! cd -- "$2" 2>/dev/null; then cannot "-C: cannot enter '${2:-}'"; fi
  shift 2
fi
case "${1:-}" in
  placement) shift; placement "$@" ;;
  version) shift; version ;;
  *) cannot "usage: changelog-check.sh [-C <path>] placement --base <ref> [--cut <X.Y.Z>] | version" ;;
esac
