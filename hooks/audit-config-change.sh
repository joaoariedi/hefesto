#!/bin/bash
# audit-config-change.sh — say out loud when settings change under a running session.
#
# A compromised skill, plugin, or MCP server has one high-value target: the permission allowlist
# and the hook list. Both live in settings files that can be rewritten mid-session, and a rewrite is
# silent. ConfigChange fires when Claude Code reloads a settings file; this hook makes it visible
# (stderr → the agent and the transcript) so the change is a fact to review, not a fact to miss.
#
# Advisory: exit 0. The event is not documented as blockable, and a wrong block here would lock the
# user out of their own settings.
set -uo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.file_path // .path // .source // "a settings file"')
echo "hefesto: configuration changed mid-session: $FILE — re-check permissions.allow and hooks before trusting new tool grants." >&2
exit 0
