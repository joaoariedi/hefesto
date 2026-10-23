#!/bin/bash
# context-gauge.sh — a status-line segment: this session's context use, and a /compact nudge past the lane's
# threshold (lanes-v2 FR-003). Claude Code lets no plugin set where the main conversation auto-compacts or what
# that summary keeps, and only a status-line script sees context usage — so the configurable part is WHEN the
# person is told to run the lane's own /compact prompt.
#
#   stdin: Claude Code's status-line JSON (context_window.used_percentage, workspace.current_dir)
#   threshold: .context.compact_at in <current_dir>/.claude/project-status.json — a number, or an object of
#     lane → number (orchestrator, plan, build, deploy, general); 0 = never nudge; missing or invalid → 40
#   lane: HEFESTO_LANE when set; else the session name's suffix (session_name: `claude --name <repo>-<lane>` or
#     /rename) — orchestrator, plan|planner, build|builder, deploy|deployer; anything else → "general"
#
# A status line runs on every refresh and must never fail: bad input, no usage yet, or no jq → no output, exit 0.
# No ledger, board-lib or git call, for the same reason. Not a hook — a helper.
#   tokens: `ctx 45% · 90k/200k` — context_window.total_input_tokens over context_window_size, when both are there
#   --with-user: first run the status line the session's own profile defines (statusLine.command in
#     ${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json — a profile wrapper sets CLAUDE_CONFIG_DIR, and the status
#     line inherits it) with the same input, and print the gauge after it: `<yours> · ctx …`. hefesto-setup.sh
#     writes the gauge this way, so a project-level status line never hides a profile's own (live trial
#     2026-10-23). A command that is itself this gauge is skipped.
WITH_USER=0; [ "${1:-}" = --with-user ] && WITH_USER=1
command -v jq >/dev/null 2>&1 || exit 0
in="$(cat)"
user_line() { # the profile's own status line, first line only; nothing on any failure
  local cmd
  cmd="$(jq -r 'if (.statusLine.type // "command") == "command" then (.statusLine.command // empty) else empty end' \
    "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null)" || return 0
  [ -n "$cmd" ] || return 0
  case "$cmd" in *context-gauge.sh*) return 0 ;; esac
  printf '%s' "$in" | bash -c "$cmd" 2>/dev/null | head -1
}
U=""; [ "$WITH_USER" = 1 ] && U="$(user_line)"
emit() { if [ -n "$U" ]; then printf '%s \033[2m·\033[0m %s\n' "$U" "$1"; else printf '%s\n' "$1"; fi; }
pct="$(jq -r '.context_window.used_percentage // empty | if type == "number" then floor else empty end' <<<"$in" 2>/dev/null)"
[[ "$pct" =~ ^[0-9]{1,5}$ ]] || { [ -n "$U" ] && printf '%s\n' "$U"; exit 0; }   # bounded: [ -ge ] errors on a number past 2^63
# tokens in the context over the window, in thousands (k) or millions (M): "90k/200k", "1.2M/1M"
tok="$(jq -r '.context_window | ((.total_input_tokens // empty) | if type == "number" and . > 0 then . else empty end) as $u
  | ((.context_window_size // empty) | if type == "number" and . > 0 then . else empty end) as $w
  | def h: if . >= 1000000 then ((. / 100000 | floor) / 10 | tostring) + "M" else ((. / 1000 | floor) | tostring) + "k" end;
    "\($u | h)/\($w | h)"' <<<"$in" 2>/dev/null)"
[[ "$tok" =~ ^[0-9.]+[kM]/[0-9.]+[kM]$ ]] && tok=" · $tok" || tok=""
name="$(jq -r '.session_name // empty' <<<"$in" 2>/dev/null)"
case "${name##*-}" in orchestrator) nl=orchestrator ;; plan|planner) nl=plan ;; build|builder) nl=build ;; deploy|deployer) nl=deploy ;; *) nl=general ;; esac
lane="${HEFESTO_LANE:-$nl}"
dir="$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$in" 2>/dev/null)"
at=""
if [ -n "$dir" ] && [ -f "$dir/.claude/project-status.json" ]; then
  at="$(jq -r --arg l "$lane" '.context.compact_at // empty
    | if type == "number" then . elif type == "object" then (.[$l] // .general // empty) else empty end
    | if type == "number" and . >= 0 then floor else empty end' "$dir/.claude/project-status.json" 2>/dev/null)"
fi
[[ "$at" =~ ^[0-9]{1,5}$ ]] || at=40
if [ "$at" -gt 0 ] && [ "$pct" -ge "$at" ]; then emit "ctx ${pct}%${tok} · /compact (${lane})"; else emit "ctx ${pct}%${tok}"; fi
exit 0
