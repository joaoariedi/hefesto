#!/bin/bash
# doctor-tmp.sh — /hef.doctor's check of Claude Code's temp directory. Read-only; prints one line and a status.
#
# Claude Code keeps every session's scratch, background-task output and the sandbox's TMPDIR under one directory:
# CLAUDE_CODE_TMPDIR, else /tmp/claude-<uid>. On a machine whose /tmp is a RAM-backed tmpfs with a user quota, a day
# of sessions fills it (2026-10-30: 8 GB of 12, then EDQUOT — every command's output lost, commits and pushes
# failing). Pointing CLAUDE_CODE_TMPDIR at a directory on disk is the fix; this check says when it is needed.
#
#   doctor-tmp.sh            → "claude-tmp: <dir> on <fs>, <n>% used" then "status: OK | WARN <why>"
#   HEFESTO_TMP_WARN_PCT     the use above which a tmpfs is a warning (default 80)
# Exit 0 always (a doctor line, never a gate); 2 on bad usage.
set -uo pipefail

dir="${CLAUDE_CODE_TMPDIR:-/tmp/claude-$(id -u)}"; pending=""
# CLAUDE_CODE_TMPDIR set in a startup file reaches new sessions only: a running one still writes its sandbox TMPDIR.
# Judge the directory this session uses, and say the setting is not in effect yet (code review of 9.1.3).
if [ -n "${CLAUDE_CODE_TMPDIR:-}" ] && [ -n "${TMPDIR:-}" ]; then
  case "${TMPDIR%/}/" in "${CLAUDE_CODE_TMPDIR%/}/"*) ;; *) pending="$CLAUDE_CODE_TMPDIR"; dir="$TMPDIR" ;; esac
fi
warn_pct="${HEFESTO_TMP_WARN_PCT:-80}"
case "$warn_pct" in ''|*[!0-9]*) echo "doctor-tmp: HEFESTO_TMP_WARN_PCT must be a whole number (got '$warn_pct')" >&2; exit 2 ;; esac
probe="$dir"; [ -d "$probe" ] || probe="$(dirname "$dir")"   # not created yet: judge the filesystem it would land on

# The filesystem type: GNU stat names it; BSD/macOS stat has no -c, and its tmpfs-like volumes are not the case here.
fs="$(stat -f -c %T "$probe" 2>/dev/null)" || fs="unknown"
# Use%, POSIX df: the fifth column of the second line (`df -P` keeps one filesystem on one line).
pct="$(df -P "$probe" 2>/dev/null | awk 'NR == 2 { sub(/%/, "", $5); print $5 }')"
case "$pct" in ''|*[!0-9]*) pct="?" ;; esac

if [ -n "$pending" ]; then echo "claude-tmp: $dir on ${fs}, ${pct}% used (CLAUDE_CODE_TMPDIR is set to $pending, not yet in effect here — restart the sessions)"
else echo "claude-tmp: $dir on ${fs}, ${pct}% used${CLAUDE_CODE_TMPDIR:+ (CLAUDE_CODE_TMPDIR)}"; fi
if [ "$fs" = tmpfs ] && [ "$pct" != "?" ] && [ "$pct" -ge "$warn_pct" ]; then
  echo "status: WARN a RAM-backed tmpfs at ${pct}% — a full one loses every command's output (EDQUOT). Point Claude Code at a disk directory: mkdir -p ~/.cache/claude-tmp && export CLAUDE_CODE_TMPDIR=\"\$HOME/.cache/claude-tmp\" in your shell's startup file (docs/install.md, Optional Configuration), then restart the sessions"
elif [ "$fs" = tmpfs ]; then
  echo "status: OK (a tmpfs, ${pct}% used — RAM-backed: if it fills, see docs/install.md on CLAUDE_CODE_TMPDIR)"
else
  echo "status: OK"
fi
