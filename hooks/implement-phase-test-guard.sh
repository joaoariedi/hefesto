#!/bin/bash
# implement-phase-test-guard.sh — tests may GROW during /hef.implement; they may not SHRINK.
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
# tests to make them pass. hef.implement already says "never modify the test to make it pass" —
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

# The command split into simple commands, one per line, tokens joined by \034, quotes removed (#164). Before, a
# runner word and a `-u` were matched ANYWHERE, each on its own: `env -u X pytest`, `… | sort -u`, `shred -u` in an
# ssh heredoc, heredoc TEXT quoting `env -u` — six false positives in two days — while `bash -c "vitest -u"` passed
# (the quote after -u is not a space). So: quotes keep a string one token; `$(…)`, backticks and the strings a
# shell runs (`bash -c "…"`) are lexed as commands; a heredoc body is lexed only when a local shell consumes it,
# never for ssh (a remote host) or `python3 -` (text). POSIX awk: it runs on macOS's awk too.
# shellcheck disable=SC2016
SEG_AWK='
function base(w) { sub(/.*\//, "", w); return w }
function isshell(w) { w = base(w); return w == "bash" || w == "sh" || w == "zsh" || w == "dash" || w == "ksh" }
function flushtok(d) {
  if (TOK[d] != "" || HQ[d]) { gsub(/\n/, " ", TOK[d]); SEG[d] = SEG[d] (NT[d] ? "\034" : "") TOK[d]; NT[d]++ }
  TOK[d] = ""; HQ[d] = 0
}
function flushseg(d,   w, nw, k, fw, s) {
  flushtok(d); if (!NT[d]) return
  s = SEG[d]; SEG[d] = ""; NT[d] = 0; nw = split(s, w, "\034"); fw = 0
  for (k = 1; k <= nw; k++) { if (isshell(w[k])) LS[d] = 1; if (!fw && w[k] !~ /^[A-Za-z_][A-Za-z0-9_]*=/) fw = k }
  print s
  if (!fw) return
  if (base(w[fw]) == "ssh") { LR[d] = 1; return }
  for (k = fw; k <= nw; k++) if (isshell(w[k]) || w[k] == "eval") break   # `timeout 120 bash -c …`: the shell, wherever
  for (k++; k <= nw; k++) if (w[k] ~ /[ \t;|&]/) lex(w[k], d + 1)
}
function closing(s, i, n,   dp, c, q) {
  dp = 1
  for (; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == q) q = ""; else if (c == "\\" && q == "\"") i++; continue }
    if (c == "\047" || c == "\"") q = c; else if (c == "\\") i++; else if (c == "(") dp++; else if (c == ")" && --dp == 0) return i
  }
  return n + 1
}
function hdmark(s, j, n, d,   st, dl, c, qq) {
  flushtok(d); if (substr(s, j, 1) == "-") { st = 1; j++ }
  while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
  for (; j <= n; j++) {
    c = substr(s, j, 1)
    if (qq != "") { if (c == qq) qq = ""; else dl = dl c; continue }
    if (c == "\047" || c == "\"") { qq = c; continue }
    if (c == "\\") continue
    if (index(" \t\n;|&<>()", c)) break
    dl = dl c
  }
  HN[d]++; HDD[d, HN[d]] = dl; HDS[d, HN[d]] = st
  return j - 1
}
function flat(s) { gsub(/[ \t\n]+/, "\034", s); print s }   # the old flat word match: what fails closed falls back to
function pipeend(d,   k) {   # a heredoc runs locally when its own pipeline has a shell and no ssh (`cat <<EOF | bash`)
  for (k = HP[d] + 1; k <= HN[d]; k++) HDX[d, k] = LS[d] && !LR[d]
  HP[d] = HN[d]; LS[d] = 0; LR[d] = 0
}
function hdbodies(s, p, n, d,   k, e, ln, t, body, found) {
  for (k = 1; k <= HN[d]; k++) {
    body = ""; found = 0
    while (p <= n) {
      for (e = p; e <= n && substr(s, e, 1) != "\n"; e++) ;   # a scan, not index(substr(s, p)): that copied per line
      ln = substr(s, p, e - p); p = e + 1
      t = ln; if (HDS[d, k]) sub(/^\t+/, "", t)
      if (t == HDD[d, k]) { found = 1; break }
      body = body ln "\n"
    }
    if (HDX[d, k]) lex(body, d + 1); else if (!found) flat(body)   # no terminator: fail closed
  }
  HN[d] = 0; HP[d] = 0
  return p
}
function lex(s, d,   i, n, c, nx, e, q) {
  if (d > 8) { flat(s); return }   # too deep: the flat word list, never nothing
  n = length(s); TOK[d] = ""; SEG[d] = ""; NT[d] = 0; HQ[d] = 0; HN[d] = 0; HP[d] = 0; LS[d] = 0; LR[d] = 0; AR[d] = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1); nx = substr(s, i + 1, 1)
    if (q == "\047") { if (c == "\047") q = ""; else TOK[d] = TOK[d] c; continue }
    if (c == "$" && nx == "(") { e = closing(s, i + 2, n); lex(substr(s, i + 2, e - i - 2), d + 1); i = e; continue }
    if (c == "`") { e = index(substr(s, i + 1), "`"); e = e ? i + e : n + 1; lex(substr(s, i + 1, e - i - 1), d + 1); i = e; continue }
    if (q == "\"") { if (c == "\\") { TOK[d] = TOK[d] nx; i++ } else if (c == "\"") q = ""; else TOK[d] = TOK[d] c; continue }
    if (c == "\\") { if (nx != "\n") TOK[d] = TOK[d] nx; i++; continue }
    if (c == "\047" || c == "\"") { q = c; HQ[d] = 1; continue }
    if (c == " " || c == "\t") { flushtok(d); continue }
    if (c == "#" && TOK[d] == "") { while (i < n && substr(s, i + 1, 1) != "\n") i++; continue }
    if (c == "(" && nx == "(") { AR[d]++; flushseg(d); i++; continue }   # (( … )): `<<` is a shift there, not a heredoc
    if (c == ")" && nx == ")" && AR[d] > 0) { AR[d]--; flushseg(d); i++; continue }
    if (c == "<" && nx == "<" && substr(s, i + 2, 1) != "<" && !AR[d]) { i = hdmark(s, i + 2, n, d); continue }
    if (c == "\n") { flushseg(d); pipeend(d); i = hdbodies(s, i + 1, n, d) - 1; continue }
    if (c == "&" && (nx == ">" || substr(s, i - 1, 1) == ">")) { TOK[d] = TOK[d] c; continue }   # 2>&1, &>: a redirect
    if (c == "&" && substr(s, i - 1, 1) == "|") continue   # |& is a pipe (stderr too), not a list
    if (index(";|&()", c)) { flushseg(d); if (c != "|" || nx == "|" || substr(s, i - 1, 1) == "|") pipeend(d); continue }
    TOK[d] = TOK[d] c
  }
  flushseg(d)
  if (q != "") flat(s)   # an unterminated quote: fail closed
}
{ s = s $0 "\n" }
END { lex(s, 0) }'

# One simple command's tokens → 0 when it asks its test runner to rewrite snapshots. An ambiguous flag (-u,
# --update) counts only AFTER the runner in the same command; a runner named as a package (`npm update vitest`,
# `pip install pytest`) is not a runner. Sets SNAP_RUNNER / SNAP_ENV for the UPDATE_SNAPSHOTS=1 forms.
seg_snapshot_update() {
  local runner=0 pm=0 prev="" tok
  for tok in "$@"; do
    case "$tok" in
      UPDATE_SNAPSHOTS=1|SNAPSHOT_UPDATE=1) SNAP_ENV=1 ;;
      --update-snapshot|--update-snapshots|--snapshot-update|--force-update-snapshot|--force-update-snapshots|--updateSnapshot) return 0 ;;
      -u|--update) [ "$runner" = 1 ] && return 0 ;;
    esac
    case "${prev##*/}" in
      npm|yarn|pnpm|bun|pip|pip3|uv|poetry|pipx)
        case "$tok" in install|i|add|update|up|upgrade|remove|rm|uninstall|un|outdated|why|info|view|ci) pm=1 ;; esac ;;
    esac
    if [ "$pm" = 0 ]; then
      case "${tok##*/}" in
        jest|jest@*|jest.js|jest-cli|jest-cli@*|vitest|vitest@*|vitest.mjs|pytest|py.test|ava|ava@*|--snapshot*) runner=1 ;;
      esac
      case "${prev##*/}:$tok" in npm:test*|npm:t|yarn:test*|pnpm:test*|bun:test*|run:test*) runner=1 ;; esac
    fi
    prev="$tok"
  done
  [ "$runner" = 0 ] || SNAP_RUNNER=1
  return 1
}

snapshot_update_cmd() { # $1 the Bash command → 0 when a test runner in it is asked to rewrite its snapshots
  local line segs
  local -a t
  SNAP_RUNNER=0; SNAP_ENV=0
  # On stdin, not in the environment: one env string over 128 KiB makes awk fail to exec on Linux (#164 review).
  # Fail closed: the pre-filter already matched, so an awk that cannot run is a block, never a pass.
  segs="$(printf '%s' "$1" | awk "$SEG_AWK")" || return 0
  while IFS= read -r line; do
    IFS=$'\034' read -r -a t <<<"$line"
    seg_snapshot_update ${t[@]+"${t[@]}"} && return 0
  done <<<"$segs"
  [ "$SNAP_RUNNER" = 1 ] && [ "$SNAP_ENV" = 1 ]
}

case "$TOOL" in
  Bash)
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    [ -z "$CMD" ] && exit 0

    # --- Unconditional: snapshot-update flags on a test runner ---
    # The broad match is only a pre-filter, so most commands never start awk; the lexer decides (#164).
    if [[ "$CMD" != *"CLAUDE_ALLOW_SNAPSHOT_UPDATE=1"* ]] \
       && [[ "$CMD" =~ (jest|vitest|pytest|ava|(npm|yarn|pnpm|bun)[[:space:]]+(run[[:space:]]+)?t|--snapshot) ]] \
       && [[ "$CMD" =~ -u|--update|--snapshot-update|--updateSnapshot|UPDATE_SNAPSHOTS=1|SNAPSHOT_UPDATE=1 ]] \
       && snapshot_update_cmd "$CMD"; then
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
          echo "Blocked: /hef.implement is active and this removes a test file ($tok)." >&2
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
        echo "Blocked: /hef.implement is active and Write would OVERWRITE the existing test file $FILE." >&2
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
      echo "Blocked: /hef.implement is active and this edit removes assertions from $FILE ($before → $after)." >&2
      echo "  A test that asserts less to go green is the failure this phase exists to prevent." >&2
      echo "  If the assertion is genuinely wrong, say so to the user, or end the phase: speckit-helper.sh implement-phase-end" >&2
      exit 2
    fi
    exit 0
    ;;
esac
exit 0
