#!/bin/bash
# context-gauge.sh — a status-line segment: this session's context use, and a /compact nudge past the lane's
# threshold (lanes-v2 FR-003). Claude Code lets no plugin set where the main conversation auto-compacts or what
# that summary keeps, and only a status-line script sees context usage — so the configurable part is WHEN the
# person is told to run the lane's own /compact prompt.
#
#   stdin: Claude Code's status-line JSON (context_window.used_percentage, workspace.current_dir)
#   threshold: .context.compact_at in <current_dir>/.claude/project-status.json — a number, or an object of
#     lane → number (orchestrator, plan, build, deploy, general); 0 = never nudge; missing or invalid → 40
#   lane: HEFESTO_LANE (set by lane-launch.sh); unset → "general"
#
# A status line runs on every refresh and must never fail: bad input, no usage yet, or no jq → no output, exit 0.
# No ledger, board-lib or git call, for the same reason. To keep your own status line, print this segment from
# it: `… "$(printf '%s' "$INPUT" | <hefesto>/hooks/context-gauge.sh)"`. Not a hook — a helper.
command -v jq >/dev/null 2>&1 || exit 0
in="$(cat)"
pct="$(jq -r '.context_window.used_percentage // empty | if type == "number" then floor else empty end' <<<"$in" 2>/dev/null)"
[[ "$pct" =~ ^[0-9]+$ ]] || exit 0
lane="${HEFESTO_LANE:-general}"
dir="$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$in" 2>/dev/null)"
at=""
if [ -n "$dir" ] && [ -f "$dir/.claude/project-status.json" ]; then
  at="$(jq -r --arg l "$lane" '.context.compact_at // empty
    | if type == "number" then . elif type == "object" then (.[$l] // .general // empty) else empty end
    | if type == "number" and . >= 0 then floor else empty end' "$dir/.claude/project-status.json" 2>/dev/null)"
fi
[[ "$at" =~ ^[0-9]+$ ]] || at=40
if [ "$at" -gt 0 ] && [ "$pct" -ge "$at" ]; then echo "ctx ${pct}% · /compact (${lane})"; else echo "ctx ${pct}%"; fi
exit 0
