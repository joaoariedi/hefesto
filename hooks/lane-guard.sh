#!/bin/bash
# lane-guard.sh — PreToolUse on Bash and the file tools (lanes-interactive, 9.0). Registered with onFailure "block":
# a hook that errors or times out lets the call through otherwise (docs, 2026-10-23).
#
# File tools, every project: an Edit/Write whose real path (symlinks resolved) lies in hefesto's own state —
# ~/.cache/hefesto/{ledger,approvals,sessions} — is denied. The permission rules match the literal path only, so a
# lane could reach the ledger through a symlink it made (plan review round 2).
#
# Bash, in a project hefesto-setup.sh set up (the session has a record, lane-lib.sh):
#   - a command that starts an EXCLUDED command (one setup runs outside the sandbox: the launcher, ledger.sh, gh,
#     orchestrate.unsandboxed_commands) must be one plain word list — a redirection, pipe or chain would leave the
#     sandbox with it (review round 3). The orchestrator's answer/revise/direct heredoc is the one exception.
#   - nobody sets CLAUDE_CODE_SESSION_ID on a command line: ledger.sh's own check reads it.
#   - with --lanes: a person's decision is recorded only from the orchestrator lane; an action, a directive, a note
#     or a prepare/finish is the business of the lane it names.
# Anything else: no output, exit 0 — the normal permission rules decide.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lane-lib.sh
. "$HERE/lane-lib.sh"
IN="$(cat)"
deny() { jq -nc --arg r "hefesto lane-guard: $1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'; exit 0; }
allow() { jq -nc --arg r "hefesto lane-guard: $1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: $r}}'; exit 0; }
TOOL="$(jq -r '.tool_name // empty' <<<"$IN")"

# --- file tools ------------------------------------------------------------------------------------------------
real_path() { # $1 path → its physical path (symlinks of the file and of every ancestor resolved), or nothing
  local p="$1" n=0 d b t
  case "$p" in /*) ;; *) p="$(jq -r '.cwd // empty' <<<"$IN")/$p" ;; esac
  while [ -L "$p" ] && [ "$n" -lt 20 ]; do
    t="$(readlink "$p")"; case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac; n=$((n + 1))
  done
  d="$(dirname "$p")"; b="$(basename "$p")"
  while [ ! -d "$d" ] && [ "$d" != / ]; do b="$(basename "$d")/$b"; d="$(dirname "$d")"; done
  d="$(cd -P "$d" 2>/dev/null && pwd -P)" || return 0
  printf '%s/%s\n' "${d%/}" "$b"
}
protected() { # $1 physical path → 0 when it is hefesto's own state
  local base phys sub
  base="$(hef_cache)"; phys="$(cd -P "$base" 2>/dev/null && pwd -P)" || phys=""
  for sub in ledger approvals sessions; do
    case "$1" in "$base/$sub"|"$base/$sub/"*) return 0 ;; esac
    [ -n "$phys" ] && case "$1" in "$phys/$sub"|"$phys/$sub/"*) return 0 ;; esac
  done
  return 1
}
case "$TOOL" in
  Edit|Write|MultiEdit|NotebookEdit)
    f="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$IN")"; [ -n "$f" ] || exit 0
    rp="$(real_path "$f")"
    { [ -n "$rp" ] && protected "$rp"; } && deny "$f is hefesto's own state (it resolves to $rp) — the ledger, the approvals and the session records are written only by hefesto's helpers"
    exit 0 ;;
  Bash) ;;
  *) exit 0 ;;
esac

# --- Bash --------------------------------------------------------------------------------------------------------
SID="$(jq -r '.session_id // empty' <<<"$IN")"
valid_sid "$SID" && [ -f "$(session_file "$SID")" ] || exit 0          # not a set-up session: nothing to say
CMD="$(jq -r '.tool_input.command // empty' <<<"$IN")"; [ -n "$CMD" ] || exit 0
REC="$(cat "$(session_file "$SID")")"
LANES="$(jq -r '.lanes' <<<"$REC")"; ROLE="$(jq -r '.role // empty' <<<"$REC")"; NAME="$(jq -r '.name // empty' <<<"$REC")"

[[ "$CMD" =~ (^|[^A-Za-z0-9_])CLAUDE_CODE_SESSION_ID= ]] && deny "a command may not set CLAUDE_CODE_SESSION_ID — hefesto's helpers read it to know which lane is asking"

# The excluded commands' first words, from the settings setup wrote (the record holds them).
re_quote() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|/]/\\&/g'; }
EXCL_HIT=""
while IFS= read -r e; do
  [ -n "$e" ] || continue
  w="${e%% *}"; q="$(re_quote "$w")"
  wrap='(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|env|exec|command|builtin|nohup|sudo|xargs|nice|time|timeout[[:space:]]+[0-9]+[smhd]?)[[:space:]]+)*'
  re="(^|[;&|({\`]|\\\$\\(|"$'\n'")[[:space:]]*${wrap}${q}([[:space:]]|\$|[;&|)<>])"
  [[ "$CMD" =~ $re ]] && { EXCL_HIT="$w"; break; }
done < <(jq -r '.excluded[]? // empty' <<<"$REC")

# The orchestrator's person-only heredoc: `<ledger.sh> answer|revise|direct … <<'WORD'`, the body, then WORD alone.
heredoc_ok() {
  local first last word head
  first="${CMD%%$'\n'*}"; last="${CMD##*$'\n'}"
  [[ "$first" =~ \<\<\'([A-Za-z_][A-Za-z0-9_]{3,40})\'[[:space:]]*$ ]] || return 1
  word="${BASH_REMATCH[1]}"; [ "$last" = "$word" ] || return 1
  head="${first%<<*}"; plain_words "$head" || return 1
  [ "$(first_word "$head")" = "$EXCL_HIT" ] || return 1
  case "$EXCL_HIT" in */ledger.sh) ;; *) return 1 ;; esac
  case "$(words "$head" | sed -n 2p)" in answer|revise|direct) ;; *) return 1 ;; esac   # all person-only: the
  # --lanes rule below then lets only the orchestrator through
}
words() { printf '%s' "$1" | xargs printf '%s\n' 2>/dev/null; }   # split quoted words without a shell

if [ -n "$EXCL_HIT" ]; then
  if ! { plain_words "$CMD" && [ "$(first_word "$CMD")" = "$EXCL_HIT" ]; } && ! heredoc_ok; then
    case "$EXCL_HIT" in
      gh) deny "gh runs outside the sandbox in this project, so its command must be one plain word list — no pipe, redirect, chain, \$(…) or wrapper. Use gh's own --jq/-q to filter, and the Write tool to save output" ;;
      *) deny "$EXCL_HIT runs outside the sandbox in this project, so the call must be one plain word list exactly as the guide writes it — no pipe, redirect, chain, \$(…), wrapper or leading assignment (pass text with a file argument)" ;;
    esac
  fi
fi

# --- with --lanes: who may record what, then the grants ---------------------------------------------------------
[ "$LANES" = true ] || exit 0
if [ -n "$EXCL_HIT" ]; then case "$EXCL_HIT" in */ledger.sh|*/session-launch.sh)
W="$(words "${CMD%%$'\n'*}")"; SUB="$(sed -n 2p <<<"$W")"; ARGS=" $(tr '\n' ' ' <<<"$W")"
case "$EXCL_HIT" in
  */session-launch.sh)
    case "$ARGS" in *" --prepare "*|*" --finish "*)
      L="$(awk 'p {print; exit} $0 == "--lane" {p = 1}' <<<"$W")"
      [ -n "$NAME" ] && [ "$L" = "$NAME" ] || deny "--prepare/--finish run only in the lane they name, as --lane <its own name> (this session is '${NAME:-not a lane}', the call names '${L:-no lane}')" ;;
    esac ;;
  *)
    IFS=$'\n' read -r -d '' -a WA <<<"$W" || true
    is_person_sub "${WA[@]:1}" && [ "$ROLE" != orchestrator ] && deny "'ledger.sh $SUB' records a person's decision, so it runs only in the orchestrator lane (this session is the ${ROLE:-unnamed} lane '${NAME:-$(jq -r .title <<<"$REC")}') — decisions are made there, as a form"
    case "$SUB" in
      action|directive|note)
        target=""; ID3="$(sed -n 3p <<<"$W")"; ID4="$(sed -n 4p <<<"$W")"; LD="$(jq -r '.ledger // empty' <<<"$REC")"
        case "$SUB" in
          action) [ "$ID3" = show ] && exit 0
                  [[ "$ID4" =~ ^[A-Za-z][A-Za-z0-9_-]*-A[0-9]+$ ]] && target="$(jq -r '.to // empty' "$LD/actions/$ID4.json" 2>/dev/null)" ;;
          directive) [[ "$ID3" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] && [[ "$ID4" =~ ^[0-9]+$ ]] \
                       && target="$(jq -r --argjson n "$ID4" '.directives[]? | select(.n == $n) | .to // empty' "$LD/$ID3.json" 2>/dev/null)" ;;
          note) [[ "$ID3" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] && target="$(jq -r '.owner.session_name // empty' "$LD/$ID3.json" 2>/dev/null)" ;;
        esac
        [ -n "$target" ] && [ -n "$NAME" ] && [ "$target" = "$NAME" ] \
          || deny "'ledger.sh $SUB' acts for one lane — '${target:-unknown}' — and this session is '${NAME:-not a lane}'" ;;
    esac ;;
esac
exit 0 ;; esac; fi

# Grants (FR-011, #138): a command of an action this lane has taken runs without a dialog in its pane — only while
# the approval in the store is valid (same hash, this lane, not used up) and, for a scope with heads, the heads were
# checked since the take (and within 30 minutes). A pattern is literal text; its `*` matches no shell operator.
[ -n "$NAME" ] || exit 0
[[ "$CMD" == *$'\n'* ]] && exit 0
LD="$(jq -r '.ledger // empty' <<<"$REC")"; [ -d "$LD/actions" ] || exit 0
set -- "$LD"/actions/*.json; [ -f "$1" ] || exit 0
glob_re() { # $1 pattern → an anchored ERE
  local out="" ch i
  for ((i = 0; i < ${#1}; i++)); do ch="${1:i:1}"
    case "$ch" in '*') out+='[^;&|`$()<>{}]*' ;; [][\.^\$+?\(\)\{\}\|]) out+="\\$ch" ;; *) out+="$ch" ;; esac
  done; printf '^%s$' "$out"
}
while IFS= read -r a; do
  aid="$(jq -r .aid <<<"$a")"; st="$(cat "$(hef_cache)/approvals/$(basename "$LD")/$aid.json" 2>/dev/null)" || continue
  h="$(jq -cS '{entry, to, scope}' <<<"$a" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-64)"
  [ "$h" = "$(jq -r .sha256 <<<"$a")" ] && [ "$h" = "$(jq -r '.sha256 // empty' <<<"$st")" ] || continue
  [ "$(jq -r '.to // empty' <<<"$st")" = "$NAME" ] && [ -z "$(jq -r '.consumed_at // empty' <<<"$st")" ] || continue
  if [ "$(jq -r '.scope.heads | length' <<<"$a")" -gt 0 ]; then
    jq -e '(.heads_ok_at // "") as $h | $h != "" and $h >= .taken_at and (now - ($h | fromdateiso8601)) < 1800' <<<"$a" >/dev/null 2>&1 || continue
  fi
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue; re="$(glob_re "$pat")"
    [[ "$CMD" =~ $re ]] && allow "approved action $aid ($(jq -r .scope.title <<<"$a" | cut -c1-80)), approved by $(jq -r .by <<<"$st")"
  done < <(jq -r '.scope.commands[]?' <<<"$a")
done < <(jq -c --arg n "$NAME" 'select(.to == $n and .status == "taken")' "$@" 2>/dev/null)
exit 0
