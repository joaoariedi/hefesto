#!/bin/bash
# arena-run.sh — run ONE prompt through a model provider the user declared, and print its answer.
# Board item HEF-13 (report 18 addendum A4, phase 2 of the arena): foreign readers for
# `/hef.plan --arena --via`, and a labelled second opinion for `/hef.review --second-opinion`. Never
# the verifier of record.
#
#   arena-run.sh --check                                   which declared providers can run here
#   arena-run.sh <provider> <prompt-file> [--purpose arena|review] [--timeout s]
#
# Providers live in .claude/project-status.json, written by the user:
#   "providers": {"codex": {"via": "codex"}, "gemini": {"via": "gemini", "model": "…"},
#                 "bedrock_llama": {"via": "aws", "model": "…", "region": "us-east-1", "max_tokens": 4096}}
# `via` is the runner: claude | codex | gemini | aws. Names are [a-z0-9_]+ — they become Arena columns
# and `tiers=` tokens. A concrete model id belongs in the USER's config, never in the framework's files.
#
# What is fixed here and why:
#   * Authentication is the CLI's own. This script reads no key, stores no key, passes no key.
#   * Detected with `command -v`, never installed, never in the plugin manifest (the optional lane).
#   * Refused inside a launched worker (HEFESTO_WORKER=1, exported by session-launch.sh): a call to a
#     second vendor from inside a sandboxed worker is exactly the egress the sandbox exists to stop.
#   * Refused from a sandboxed shell ($HOME not writable — session-launch.sh FR-020's test): a vendor CLI
#     there can neither reach its API nor save its state. Run it from an unsandboxed pane.
#   * The prompt goes on STDIN (or a file:// document for aws), never as an argument: a capped diff plus
#     a spec and a plan exceeds Linux's 128 KiB per-argument limit (measured, plan review 2026-10-02).
#   * Read-only where the CLI offers it: claude --permission-mode plan, codex --sandbox read-only. The
#     Gemini CLI's headless mode has no read-only flag; this script never passes --yolo/--approval-mode,
#     so a tool call that needs approval is not approved.
#   * codex relays only --output-last-message: its progress stdout carries path:line tokens that the
#     arena's cite check would read as claims.
#   * aws (Bedrock's converse API) cannot read the repository — refused for --purpose arena.
#
# FETCHER contract: the model's text on stdout at exit 0; the reason on stderr at non-zero. Empty output
# is not an answer. Zero-install: bash, jq, coreutils timeout.
set -uo pipefail

die() { echo "arena-run: $*" >&2; exit 1; }
usage() { echo "usage: arena-run.sh --check | <provider> <prompt-file> [--purpose arena|review] [--timeout seconds]" >&2; exit 2; }

[ "${HEFESTO_WORKER:-}" = 1 ] && die "runs from the pane, never from a launched worker — a second vendor called from inside a sandboxed worker is the egress the sandbox exists to stop"
command -v jq >/dev/null 2>&1 || die "jq not found — install jq: https://jqlang.org"
TOP="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG="$TOP/.claude/project-status.json"
host_ok() { [ -d "$HOME" ] && [ -w "$HOME" ]; }
HOST_MSG="\$HOME ($HOME) is not writable — this shell is running inside a sandbox, and a vendor CLI could neither reach its API nor save its state. Run it from an unsandboxed pane"

hint() { case "$1" in
  claude) echo "https://claude.com/claude-code" ;; codex) echo "npm i -g @openai/codex" ;;
  gemini) echo "npm i -g @google/gemini-cli" ;; aws) echo "AWS CLI v2: https://aws.amazon.com/cli/" ;; esac; }
bin_of() { case "$1" in claude) echo claude ;; codex) echo codex ;; gemini) echo gemini ;; aws) echo aws ;; *) return 1 ;; esac; }
providers() { # the providers object, or die
  [ -f "$CONFIG" ] || die "no $CONFIG — declare providers there (see docs/install.md, Providers)"
  local p; p=$(jq -ce '.providers | select(type == "object" and length > 0)' "$CONFIG" 2>/dev/null) || die "no providers declared in $CONFIG (.providers is missing, empty or not an object)"
  echo "$p"
}
check_name() { [[ "$1" =~ ^[a-z0-9_]+$ ]] || die "provider name '$1' must match [a-z0-9_]+ (it becomes an Arena column and a tiers= token)"; }

if [ "${1:-}" = --check ]; then
  [ $# -eq 1 ] || usage
  host_ok || die "$HOST_MSG"
  P=$(providers) || exit 1; USABLE=0
  while IFS=$'\t' read -r name via; do
    check_name "$name"
    b=$(bin_of "$via") || die "provider $name has via '$via' (expected claude, codex, gemini or aws)"
    if command -v "$b" >/dev/null 2>&1; then
      note=""; [ "$via" = aws ] && note=" (second-opinion only)"
      echo "$name via $via: ok$note"; USABLE=1
    else echo "$name via $via: missing ($(hint "$via"))"; fi
  done < <(jq -r 'to_entries[] | "\(.key)\t\(.value.via // "")"' <<<"$P")
  [ "$USABLE" = 1 ] || exit 1
  exit 0
fi

[ $# -ge 2 ] || usage
NAME="$1"; F="$2"; shift 2; PURPOSE=review; TO=540
while [ $# -gt 0 ]; do case "$1" in
  --purpose) PURPOSE="${2:-}"; shift ;; --timeout) TO="${2:-}"; shift ;; *) usage ;; esac; shift; done
case "$PURPOSE" in arena|review) ;; *) die "--purpose must be arena or review (got '$PURPOSE')" ;; esac
[[ "$TO" =~ ^[0-9]+$ ]] || die "--timeout takes seconds (got '$TO')"
[ -f "$F" ] || die "prompt file not found: '$F'"
check_name "$NAME"
host_ok || die "$HOST_MSG"
P=$(providers) || exit 1
PV=$(jq -ce --arg n "$NAME" '.[$n] | select(type == "object")' <<<"$P") || die "no provider '$NAME' in $CONFIG (.providers has: $(jq -r 'keys | join(", ")' <<<"$P"))"
VIA=$(jq -r '.via // ""' <<<"$PV"); MODEL=$(jq -r '.model // ""' <<<"$PV")
B=$(bin_of "$VIA") || die "provider $NAME has via '$VIA' (expected claude, codex, gemini or aws)"
[ "$VIA" = aws ] && [ "$PURPOSE" = arena ] && die "$NAME (aws) is a message API — it cannot read the repository; use it for --second-opinion"
command -v "$B" >/dev/null 2>&1 || die "$B not found for provider $NAME — $(hint "$VIA")"
TIMEOUT="$(command -v timeout || command -v gtimeout)" || die "timeout not found (coreutils)"

TMP=$(mktemp -d) || die "mktemp failed"; trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/out"; ERR="$TMP/err"
case "$VIA" in
  claude)
    CMD=(claude -p --permission-mode plan); [ -n "$MODEL" ] && CMD+=(--model "$MODEL")
    "$TIMEOUT" -k 10 "$TO" "${CMD[@]}" < "$F" > "$OUT" 2>"$ERR"; RC=$? ;;
  codex)
    CMD=(codex exec --sandbox read-only --output-last-message "$TMP/last"); [ -n "$MODEL" ] && CMD+=(-m "$MODEL"); CMD+=(-)
    "$TIMEOUT" -k 10 "$TO" "${CMD[@]}" < "$F" > "$TMP/progress" 2>"$ERR"; RC=$?
    [ -f "$TMP/last" ] && cp "$TMP/last" "$OUT" ;;
  gemini)
    CMD=(gemini -p "Answer the request on standard input."); [ -n "$MODEL" ] && CMD+=(-m "$MODEL")
    "$TIMEOUT" -k 10 "$TO" "${CMD[@]}" < "$F" > "$OUT" 2>"$ERR"; RC=$? ;;
  aws)
    [ -n "$MODEL" ] || die "provider $NAME via aws needs a model (the Bedrock model id, in your config)"
    jq -nc --rawfile t "$F" '[{role: "user", content: [{text: $t}]}]' > "$TMP/messages.json" || die "cannot build the messages document"
    CMD=(aws bedrock-runtime converse --model-id "$MODEL" --messages "file://$TMP/messages.json"
         --inference-config "maxTokens=$(jq -r '.max_tokens // 4096' <<<"$PV")" --output json --cli-read-timeout 0 --no-cli-pager)
    R=$(jq -r '.region // ""' <<<"$PV"); [ -n "$R" ] && CMD+=(--region "$R")
    "$TIMEOUT" -k 10 "$TO" "${CMD[@]}" > "$TMP/raw" 2>"$ERR"; RC=$?
    [ "$RC" -eq 0 ] && { jq -er '.output.message.content[0].text' "$TMP/raw" > "$OUT" 2>/dev/null || die "$NAME: no .output.message.content[0].text in the converse response"; } ;;
esac
[ "$RC" -ne 124 ] || die "$NAME timed out after ${TO}s"
[ "$RC" -eq 0 ] || die "$NAME ($B) exited $RC: $(tail -1 "$ERR" 2>/dev/null)"
[ -s "$OUT" ] && grep -q '[^[:space:]]' "$OUT" || die "$NAME ($B) returned nothing — an empty answer is not an answer"
cat "$OUT"
