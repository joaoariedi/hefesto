# shellcheck shell=bash
# code-review-lib.sh — the exhaustive code-review round's two helpers (HEF-58 exhaustive-review):
#
#   crc_check  (speckit-helper.sh code-review-check, FR-010) — reads the merged report on stdin, checks its shape and
#              its content one rule per function, and DECIDES the verdict from the statuses (FR-007). The verdict is
#              computed, never written by an agent, so "a verdict that contradicts the statuses" cannot occur (plan
#              round 2, change 13). Exit 0 decided, 1 INCOMPLETE (each violation on stderr), 2 empty input.
#   crc_route  (speckit-helper.sh review-route, FR-021) — exhaustive round or the single reviewer, from the branch's
#              ledger entry or its spec folder; it never answers `single` at exit 0 when it could not look (US7).
#
# SOURCED by speckit-helper.sh (which defines BRANCH and SELF and sources spec-root-lib.sh), never run on its own.
# No awk (constitution 4): bash loops and grep/sed only.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then echo "code-review-lib.sh: source it from speckit-helper.sh" >&2; exit 2; fi

CRC_LENSES="input-and-security state-and-lifecycle spec-deviation test-integrity"
# - [F3] [BLOCKING] hooks/forge-lib.sh:33 — <defect> — raised by: <lenses> — <STATUS → evidence>
CRC_FIND_RE='^- \[F[0-9]+\] \[(BLOCKING|SUGGESTION)\] ([^[:space:]]+:[0-9]+) — (.+)$'
CRC_STATUS_RE='^(REPRODUCED|REFUTED|UNREPRODUCED)([^A-Z]|$)'

crc_violation() { printf 'code-review-check: [%s] %s: %s\n' "$1" "$2" "$(printf '%s' "$3" | head -c 160)" >&2; }
crc_trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

# The report with every recipe block removed — a recipe is data, so its lines are never read as findings or headings.
crc_strip_recipes() {
  local line fence=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*\`\`\` ]]; then fence=$((1 - fence)); continue; fi
    [ "$fence" = 0 ] && printf '%s\n' "$line"
  done <<<"$1"
}

# FR-008: the lens section exists and holds findings or exactly one `none — checked: <what>` line.
crc_lens_ok() {
  local line t in=0 seen=0 nf=0 nn=0 bare=0
  while IFS= read -r line; do
    if [ "$in" = 0 ]; then [ "$line" = "## Lens: $2" ] && { in=1; seen=1; }; continue; fi
    [[ "$line" == "## "* ]] && break
    t="$(crc_trim "$line")"; [ -n "$t" ] || continue
    if [[ "$t" =~ $CRC_FIND_RE ]]; then nf=$((nf + 1))
    elif [[ "$t" =~ ^none\ —\ checked:\ *[^[:space:]] ]]; then nn=$((nn + 1))
    elif [[ "$t" =~ ^none([[:space:]—:.-]*)$ || "$t" =~ ^none\ —\ checked:?[[:space:]]*$ ]]; then bare=1; fi
  done < <(crc_strip_recipes "$1")
  [ "$seen" = 1 ] || { crc_violation content "lens section missing" "## Lens: $2"; return 1; }
  [ "$bare" = 1 ] && { crc_violation content "bare none — say what was checked" "## Lens: $2"; return 1; }
  # A none line beside findings could carry a blocker in its free text; the section is one or the other.
  [ "$nf" -gt 0 ] && [ "$nn" -gt 0 ] && { crc_violation shape "a none — checked line beside findings" "## Lens: $2"; return 1; }
  [ "$nf" -gt 0 ] && return 0
  [ "$nn" = 1 ] && return 0
  [ "$nn" -gt 1 ] && { crc_violation shape "more than one none — checked line" "## Lens: $2"; return 1; }
  crc_violation content "lens section empty" "## Lens: $2"; return 1
}

CRC_FINDERS="$CRC_LENSES cross-tier"

# The report's one `Finders:` line, before the first heading. A second one, or one only under a later heading, is
# refused: a first-match read let a line anywhere in the report stand for the quorum (verify-HEF-58 review, round 3).
crc_finders_line() {
  local line fl="" n=0 pre=1
  while IFS= read -r line; do
    [[ "$line" == "## "* ]] && pre=0
    [[ "$line" == "Finders:"* ]] || continue
    n=$((n + 1)); [ "$pre" = 1 ] && [ -z "$fl" ] && fl="$line"
  done < <(crc_strip_recipes "$1")
  [ "$n" -gt 0 ] || { crc_violation content "no Finders: line" "the report must open with the five finders"; return 1; }
  [ "$n" = 1 ] || { crc_violation shape "more than one Finders: line" "$n found"; return 1; }
  [ -n "$fl" ] || { crc_violation shape "the Finders: line is not before the first lens" "it must open the report"; return 1; }
  printf '%s' "$fl"
}

# FR-009: one `Finders:` line, five entries `<finder>@<tier> ok|silent[: why]` — the four lenses and cross-tier, each
# once — none silent. Any other name is not the quorum (`a@x ok` × 5 approved: verify-HEF-58 review, round 3).
crc_finders_ok() {
  local fl e lens n=0 bad=0 seen=" "
  fl="$(crc_finders_line "$1")" || return 1
  fl="${fl#Finders:}"
  while IFS= read -r e; do
    e="$(crc_trim "$e")"; [ -n "$e" ] || continue; n=$((n + 1))
    if ! [[ "$e" =~ ^([a-z-]+)@[a-z0-9._-]+\ (ok|silent)(:.*)?$ ]]; then crc_violation shape "malformed finder entry" "$e"; bad=1; continue; fi
    lens="${BASH_REMATCH[1]}"
    # five DISTINCT finders: one finder named five times is not the quorum (verify-HEF-58 review, round 2)
    if [[ " $CRC_FINDERS " != *" $lens "* ]]; then crc_violation content "not one of the five finders ($CRC_FINDERS)" "$e"; bad=1
    elif [[ "$seen" == *" $lens "* ]]; then crc_violation content "a finder is listed twice" "$e"; bad=1
    elif [ "${BASH_REMATCH[2]}" = silent ]; then crc_violation content "a finder is silent" "$e"; bad=1; fi
    seen+="$lens "
  done <<<"${fl//;/$'\n'}"
  [ "$n" = 5 ] || { crc_violation content "Finders: needs five entries, has $n" "$fl"; bad=1; }
  return "$bad"
}

# Every finding in a lens section, one per line: severity<TAB>file:line<TAB>lens<TAB>defect<TAB>status
crc_findings() {
  local line t lens="" rest defect after status
  while IFS= read -r line; do
    if [[ "$line" == "## Lens: "* ]]; then lens="${line#\#\# Lens: }"; continue; fi
    [[ "$line" == "## "* ]] && { lens=""; continue; }
    t="$(crc_trim "$line")"; [ -n "$lens" ] && [[ "$t" =~ $CRC_FIND_RE ]] || continue
    rest="${BASH_REMATCH[3]}"; defect="${rest%% — raised by: *}"; status=""
    if [ "$defect" != "$rest" ]; then
      after="${rest#* — raised by: }"; [[ "$after" == *" — "* ]] && status="${after#* — }"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$lens" "$defect" "$status"
  done < <(crc_strip_recipes "$1")
}

# FR-005/FR-010: every [BLOCKING] finding carries one verifier status; a SUGGESTION needs none (never blocks).
crc_statuses_ok() {
  local sev loc lens defect status bad=0
  while IFS=$'\t' read -r sev loc lens defect status; do
    [ "$sev" = BLOCKING ] || continue
    [[ "$status" =~ $CRC_STATUS_RE ]] || { crc_violation content "blocking finding without a verifier status" "$loc $defect"; bad=1; }
  done < <(crc_findings "$1")
  return "$bad"
}

# A code block may only open as `\`\`\`recipe F<n>` right under finding F<n>. Any other opening is refused: a recipe
# holding a \`\`\` line flips the fence parity and would hide the next finding from every reader (verify-HEF-58 review).
crc_recipe_opens() { [[ "$1" =~ ^\`\`\`recipe\ (F[0-9]+)$ ]] && [ -n "$2" ] && [ "${BASH_REMATCH[1]}" = "$2" ]; }

# The only headings: the four lenses and `## Open questions`. Any other (`## Lens: ` with no name, `## Cross-tier`)
# would be a section no reader counts findings in (verify-HEF-58 review, round 1).
crc_heading_ok() {
  local n="${1#\#\# Lens: }"
  [ "$1" = "## Open questions" ] && return 0
  [ "$n" != "$1" ] && [[ "$n" =~ ^[a-z-]+$ ]] && [[ " $CRC_LENSES " == *" $n "* ]]
}

# The `none` lines crc_lens_ok recognises (a checked one, or a bare one it refuses); any other `none…` line is prose.
crc_none_line() {
  [[ "$1" =~ ^none\ —\ checked:\ *[^[:space:]] || "$1" =~ ^none([[:space:]—:.-]*)$ || "$1" =~ ^none\ —\ checked:?[[:space:]]*$ ]]
}

# A finding line parses, has one ` — raised by: ` (a second one lets the defect text forge the status) and no tab (the
# tab-separated finding rows would shift a field). Prints the F<n> id when it is well formed.
crc_finding_id() {
  [[ "$1" =~ $CRC_FIND_RE ]] && [[ "${BASH_REMATCH[3]}" == *" — raised by: "* ]] || return 1
  [[ "$1" != *" — raised by: "*" — raised by: "* && "$1" != *$'\t'* ]] || return 1
  [[ "$1" =~ ^-\ \[(F[0-9]+)\] ]] && printf '%s' "${BASH_REMATCH[1]}"
}

# Fail closed, so no blocker is skipped as prose (verify-HEF-58 review): before the first heading only the `Finders:`
# line; only the headings crc_heading_ok names; in a lens section, outside a recipe, a finding (as crc_finding_id
# parses it, with its recipe block) or a `none` line — `* [F2]`, `2. [F2]`, `- **[F2]**`, `- [BLOCKING]` are refused.
# Anywhere, an unclosed block. (Open questions may cite F<n> freely — only lens sections hold findings.)
crc_lines_ok() {
  local line t fence=0 bad=0 want="" in=pre
  while IFS= read -r line; do
    t="$(crc_trim "$line")"
    if [[ "$t" =~ ^\`\`\` ]]; then
      if [ "$fence" = 0 ]; then
        if crc_recipe_opens "$t" "$want"; then want=""
        else crc_violation shape "a code block that is not the recipe of the finding above it" "$t"; bad=1; fi
      fi
      fence=$((1 - fence)); continue
    fi
    [ "$fence" = 0 ] && [ -n "$t" ] || continue
    [ -n "$want" ] && { crc_violation content "finding without a recipe block" "$want"; bad=1; want=""; }
    if [[ "$line" == "## "* ]]; then
      crc_heading_ok "$line" || { crc_violation shape "a heading that is not a lens or Open questions" "$line"; bad=1; }
      [[ "$line" == "## Open questions" ]] && in=oq || in=lens; continue
    fi
    if [ "$in" = pre ]; then
      [[ "$line" == "Finders:"* ]] || { crc_violation shape "a line before the first lens that is not the Finders: line" "$t"; bad=1; }
      continue
    fi
    [ "$in" = lens ] || continue
    if [[ "$t" =~ ^-\ \[F[0-9]+\] ]]; then
      want="$(crc_finding_id "$t")" || { crc_violation shape "malformed finding line" "$t"; bad=1; }
    elif ! crc_none_line "$t"; then
      crc_violation shape "a lens-section line that is neither a finding nor a none line" "$t"; bad=1
    fi
  done <<<"$1"
  [ -n "$want" ] && { crc_violation content "finding without a recipe block" "$want"; bad=1; }
  [ "$fence" = 0 ] || { crc_violation shape "unclosed recipe block" "a \`\`\` fence is never closed"; bad=1; }
  return "$bad"
}

# The verdict and the BLOCKING line are this helper's output; a report carrying its own is rejected.
crc_no_verdict() {
  local hit
  hit="$(crc_strip_recipes "$1" | grep -m1 -E '^(## Verdict|BLOCKING [0-9]+:)')" || return 0
  crc_violation shape "the report carries its own verdict or BLOCKING line" "$hit"; return 1
}

# FR-007 (D6): REQUEST_CHANGES iff a [BLOCKING] finding is REPRODUCED or UNREPRODUCED; only REFUTED clears one.
crc_verdict() {
  if crc_findings "$1" | grep -qE $'^BLOCKING\t[^\t]*\t[^\t]*\t[^\t]*\t(REPRODUCED|UNREPRODUCED)([^A-Z]|$)'; then
    echo "## Verdict: REQUEST_CHANGES"
  else echo "## Verdict: APPROVE"; fi
}

# FR-012: `BLOCKING <n>: <file:line> (<lens>) <defect in ≤ 8 words>[ unreproduced]; …`, ≤ 500, cut with `… +k more`.
crc_blocking_line() {
  local sev loc lens defect status e out k i
  local -a es=() w
  while IFS=$'\t' read -r sev loc lens defect status; do
    [ "$sev" = BLOCKING ] && [[ "$status" =~ ^(REPRODUCED|UNREPRODUCED)([^A-Z]|$) ]] || continue
    read -ra w <<<"$defect"; e="$loc ($lens) ${w[*]:0:8}"
    [ "${BASH_REMATCH[1]}" = UNREPRODUCED ] && e="$e unreproduced"
    es+=("$e")
  done < <(crc_findings "$1")
  for ((k = ${#es[@]}; k >= 0; k--)); do
    out="BLOCKING ${#es[@]}:"
    for ((i = 0; i < k; i++)); do [ "$i" -gt 0 ] && out="$out;"; out="$out ${es[$i]}"; done
    [ "$k" -lt "${#es[@]}" ] && out="$out; … +$(( ${#es[@]} - k )) more"
    [ "${#out}" -le 500 ] && { printf '%s\n' "$out"; return 0; }
  done
  printf '%s\n' "${out:0:500}"
}

crc_check() {
  local r bad=0 lens
  r="$(cat)"; [ -n "$(crc_trim "$r")" ] || { echo "code-review-check: empty report — nothing to check" >&2; return 2; }
  for lens in $CRC_LENSES; do crc_lens_ok "$r" "$lens" || bad=1; done
  crc_finders_ok "$r" || bad=1
  crc_lines_ok "$r" || bad=1
  crc_statuses_ok "$r" || bad=1
  crc_no_verdict "$r" || bad=1
  if [ "$bad" = 1 ]; then echo "## Verdict: INCOMPLETE"; else crc_verdict "$r"; fi
  crc_blocking_line "$r"
  return "$bad"
}

# ---------------------------------------------------------------------------------------------------------------------
# review-route (FR-021)

# The branch from .git/HEAD when git cannot run (the eval sandbox denies it): the nearest .git upward, a linked
# worktree's `gitdir:` file followed; `feature/` stripped as BRANCH strips it. Detached or unreadable → 1, named.
crc_head_branch() {
  local d="$PWD" g gd h
  while [ ! -e "$d/.git" ]; do
    [ "$d" = / ] && { echo "review-route: cannot read the branch (git denied and no readable .git/HEAD)" >&2; return 1; }
    d="$(dirname "$d")"
  done
  g="$d/.git"
  if [ -f "$g" ]; then
    gd="$(sed -n 's/^gitdir: *//p' "$g" | head -n 1)"; case "$gd" in /*) ;; ?*) gd="$d/$gd" ;; esac; g="$gd"
  fi
  h="$(head -n 1 "$g/HEAD" 2>/dev/null)" || h=""
  [ -n "$h" ] || { echo "review-route: cannot read the branch (git denied and no readable .git/HEAD)" >&2; return 1; }
  case "$h" in
    "ref: refs/heads/"?*) h="${h#ref: refs/heads/}"; printf '%s\n' "${h#feature/}" ;;
    *) echo "review-route: detached HEAD ($h) — check out the branch under review" >&2; return 1 ;;
  esac
}

# A ledger entry decides: fix → the single reviewer; light/full → exhaustive with the entry's spec folder.
crc_route_from_entry() {
  local id="$1" e route top dir
  e="$("$(dirname "$SELF")/ledger.sh" show "$id" 2>&1)" || { echo "review-route: ledger entry $id unreadable: $e" >&2; return 1; }
  route="$(jq -r '.route // "fix"' <<<"$e" 2>/dev/null)" || { echo "review-route: ledger entry $id is not JSON" >&2; return 1; }
  case "$route" in
    light|full) ;;
    *) echo "single $route ledger:$id"; return 0 ;;
  esac
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || top="$(pwd -P)"
  dir="$(spec_dir_abs "$e" "$top")"
  [ -n "$dir" ] && [ -r "$dir/spec.md" ] \
    || { echo "review-route: ledger entry $id is $route but its spec folder '${dir:-<none recorded>}' holds no readable spec.md" >&2; return 1; }
  echo "exhaustive $route ledger:$id spec:$dir"
}

crc_route() {
  [ "${1:-}" = --inline ] && { echo "single - inline"; return 0; }
  local br="${BRANCH:-}" id d
  [ -n "$br" ] || br="$(crc_head_branch)" || return 1
  id="${br#worktree-}"
  if [ "$id" != "$br" ]; then   # only a worktree-<ID> branch asks the ledger (ledger.sh dir dies where git is denied)
    d="$("$(dirname "$SELF")/ledger.sh" dir 2>&1)" || { echo "review-route: ledger.sh dir failed for $id: $d" >&2; return 1; }
    [ -f "$d/$id.json" ] && { crc_route_from_entry "$id"; return; }
  fi
  # cwd is the spec root here (review-route is in the spec-root list in speckit-helper.sh, #172)
  if [ -f ".specify/specs/$br/spec.md" ]; then echo "exhaustive full spec:$(pwd -P)/.specify/specs/$br"
  else echo "single fix no-spec"; fi
}
