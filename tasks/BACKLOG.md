# BACKLOG

Not yet dispatchable. Phase 2 of report 17 lives here until Phase 1 has numbers.


## HEF-13 — providers registry and arena runners

Report 18 addendum A4, phase 2 of the arena; gated on HEF-8's number. A `providers` block in
`.claude/project-status.json` declares what the user has and how it is reached (`claude`, `codex`,
`gemini`, `aws` for Bedrock models the `claude` binary cannot drive); `hooks/arena-run.sh
<provider> <prompt-file>` wraps each CLI's non-interactive mode, detected with `command -v`, never
installed, never in the manifest. `/hef.plan --arena` fans out over runners instead of tiers, same
K ≤ 3 and digest cap. Runs from the pane, never from a hook or a sandboxed worker. A foreign-vendor
model reviews only as `/hef.review --second-opinion <provider>`, never as the verifier of record.

