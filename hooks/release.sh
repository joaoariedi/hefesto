#!/bin/bash
# release.sh <X.Y.Z> [YYYY-MM-DD] — move every version declaration together, then scaffold the
# CHANGELOG entry for a human to edit.
#
# Six declarations used to be bumped BY HAND, with tests/smoke.sh as the only thing that noticed a
# half-bumped release (#19). This script is the other half of that guard: one command, every
# declaration, or none. It edits files in the plugin root and nothing else; it does not commit, tag,
# or push — those stay deliberate, visible steps (CHANGELOG.md "Releasing").
#
# The CHANGELOG scaffold groups the commits since the last tag by conventional-commit type. It is a
# DRAFT: a commit-derived changelog is "a cluttered list of technical steps rather than a summary of
# value", and an agent-written one hallucinates. Edit it before you tag. Never let an agent invent
# release notes without the diff in context.
set -euo pipefail

die() { echo "release.sh: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V="${1:-}"; DATE="${2:-$(date +%F)}"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: release.sh X.Y.Z [YYYY-MM-DD] — got '${V:-<none>}'"
[[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "date must be YYYY-MM-DD, got '$DATE'"
command -v jq >/dev/null 2>&1 || die "jq is required"

cd "$ROOT"
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json README.md .claude/CLAUDE.md CHANGELOG.md; do
  [ -f "$f" ] || die "missing $f — run from the plugin root"
done
grep -qE "^## \[$V\]" CHANGELOG.md && die "CHANGELOG.md already has an entry for $V"
CURRENT="$(jq -r '.version' .claude-plugin/plugin.json)"
[ "$CURRENT" = "$V" ] && die "plugin.json is already at $V"

# --- the declarations --------------------------------------------------------------------
tmp="$(mktemp)"
jq --arg v "$V" '.version = $v' .claude-plugin/plugin.json > "$tmp" && cat "$tmp" > .claude-plugin/plugin.json
jq --arg v "$V" '.metadata.version = $v | .plugins[0].version = $v' .claude-plugin/marketplace.json > "$tmp" && cat "$tmp" > .claude-plugin/marketplace.json
rm -f "$tmp"
sed -i -E "s/(\*\*Framework Version\*\*: )[0-9]+\.[0-9]+\.[0-9]+/\1$V/; s/(\*\*Last Updated\*\*: )[0-9]{4}-[0-9]{2}-[0-9]{2}/\1$DATE/" README.md
sed -i -E "s/^# Hefesto v[0-9]+\.[0-9]+/# Hefesto v${V%.*}/" .claude/CLAUDE.md

# --- the CHANGELOG scaffold ---------------------------------------------------------------
last_tag="$(git describe --tags --abbrev=0 2>/dev/null || true)"
range="${last_tag:+$last_tag..}HEAD"
added=""; fixed=""; changed=""
while IFS= read -r subj; do
  [ -z "$subj" ] && continue
  case "$subj" in
    feat*) added="$added- ${subj#*: }"$'\n' ;;
    fix*)  fixed="$fixed- ${subj#*: }"$'\n' ;;
    chore\(graph\)*|"chore(graph)"*) ;;   # graph rebuilds are noise in release notes
    *)     changed="$changed- ${subj#*: }"$'\n' ;;
  esac
done < <(git log --format='%s' "$range" 2>/dev/null || true)

entry="## [$V] - $DATE"$'\n\n'
entry+="**<one-sentence thesis of this release — written by a human, not derived from commits>**"$'\n\n'
[ -n "$added" ]   && entry+="### Added"$'\n\n'"$added"$'\n'
[ -n "$changed" ] && entry+="### Changed"$'\n\n'"$changed"$'\n'
[ -n "$fixed" ]   && entry+="### Fixed"$'\n\n'"$fixed"$'\n'
[ -z "$added$changed$fixed" ] && entry+="_No commits since ${last_tag:-the beginning}; write the entry by hand._"$'\n\n'

# Insert before the first existing version heading.
awk -v e="$entry" 'BEGIN{done=0} /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ && !done {printf "%s", e; done=1} {print}' CHANGELOG.md > "$tmp.md" && cat "$tmp.md" > CHANGELOG.md && rm -f "$tmp.md"

echo "release.sh: $CURRENT → $V ($DATE)"
echo "  bumped: plugin.json, marketplace.json (×2), README footer, .claude/CLAUDE.md title"
echo "  scaffolded: CHANGELOG.md [$V] from $(git rev-list --count "$range" 2>/dev/null || echo '?') commit(s) since ${last_tag:-the beginning} — EDIT IT before tagging"
echo "  next: tests/smoke.sh · review CHANGELOG.md · git commit · git tag -a v$V"
