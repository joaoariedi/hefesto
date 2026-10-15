#!/bin/bash
# run-bounded.sh [-k KILL_AFTER] SECONDS COMMAND [ARG...] — the part of coreutils timeout(1) the helpers use,
# for a machine without it. macOS ships no `timeout`; asking every Mac user to `brew install coreutils`
# breaks the zero-install rule, so pr-watch.sh and arena-run.sh fall back to this when neither
# `timeout` nor `gtimeout` is on PATH.
#
# Same contract as timeout(1): the command's own exit code, or 124 when the time ran out — after a TERM,
# and with -k a KILL that many seconds later if it is still running. Bash 3.2 (macOS /bin/bash).
# Not a hook — a helper.
#
#   run-bounded.sh -k 10 540 claude -p … < prompt > out
set -u

die() { echo "run-bounded: $*" >&2; exit 125; }   # 125: timeout(1)'s own failure code
kill_after=""
if [ "${1:-}" = -k ]; then kill_after="${2:-}"; shift 2 || die "-k needs a number of seconds"; fi
secs="${1:-}"; shift || true
case "$secs" in ''|*[!0-9]*) die "SECONDS must be a whole number, got '${secs}'" ;; esac
case "$kill_after" in *[!0-9]*) die "-k must be a whole number, got '${kill_after}'" ;; esac
[ $# -gt 0 ] || die "no command given (usage: run-bounded.sh [-k N] SECONDS COMMAND [ARG...])"

fired="$(mktemp)" || die "mktemp failed"
trap 'rm -f "$fired"' EXIT

# A background job in a script reads /dev/null unless stdin is redirected explicitly, so hand it ours.
exec 3<&0
"$@" <&3 3<&- &
pid=$!
exec 3<&-

# The watchdog's stdio goes to /dev/null: a sleep left behind must not hold the caller's $(…) pipe open.
(
  sleep "$secs"
  kill -0 "$pid" 2>/dev/null || exit 0
  echo fired > "$fired"
  kill -TERM "$pid" 2>/dev/null
  if [ -n "$kill_after" ]; then sleep "$kill_after"; kill -KILL "$pid" 2>/dev/null; fi
) </dev/null >/dev/null 2>&1 &
watchdog=$!

wait "$pid"; rc=$?
kill "$watchdog" 2>/dev/null
if [ -s "$fired" ]; then exit 124; fi
exit "$rc"
