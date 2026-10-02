# BACKLOG

Not yet dispatchable. Phase 2 of report 17 lives here until Phase 1 has numbers.

## HEF-4 — ledger publish: write phase and blocked reason back to the board

Phase 2 of `reports/17-multi-agent-session-orchestration.md`. `ledger publish <id>` mirrors the
entry's `phase` and `blocked_on` to the board item (a sub-state marker on the kanban heading, or a
comment on the GitHub Project item), so the board becomes the cross-machine truth. Outward write
only; `gh` detected, never installed.

## HEF-5 — blocked-escalation message to the attended session

Phase 2 of report 17. When an entry sits in a `human:*` block longer than a configured time, the
orchestrator sends one `SendMessage` to a named attended session with the text
`ledger <id> blocked_on <kind> <path>` and nothing else. Pointer only; the receiver treats it as
data. Add only if Phase 1 shows blocked entries waiting longer than the target.

## HEF-6 — ledger handoff shortcut for hand-run items

A person working an item in a `<repo>-feature` pane goes through four ledger calls to hand it to
the release queue (`run --role implement --exit 0 --usd 0`, `record --pr … --branch …`,
`advance pr`, `block --kind human:merge`). Add `ledger.sh handoff <id> --pr <url>` that does exactly
those four, reading the branch from the current checkout, with the same guards and a smoke fixture.

## HEF-10 — board item kinds with kind-specific verifier gates

Report 18 #6 (deck slides 32–33). A heading marker the board already parses (🐞 incident,
🛡 vulnerability) becomes `kind` on the ledger entry; the verify prompt adds the kind's gate — a
regression test citing the incident id must exist and pass; a re-scan must be clean — as verdict
gates `incident` / `vulnerability`. Phase 2 of orchestrate.

## HEF-13 — providers registry and arena runners

Report 18 addendum A4, phase 2 of the arena; gated on HEF-8's number. A `providers` block in
`.claude/project-status.json` declares what the user has and how it is reached (`claude`, `codex`,
`gemini`, `aws` for Bedrock models the `claude` binary cannot drive); `hooks/arena-run.sh
<provider> <prompt-file>` wraps each CLI's non-interactive mode, detected with `command -v`, never
installed, never in the manifest. `/hef.plan --arena` fans out over runners instead of tiers, same
K ≤ 3 and digest cap. Runs from the pane, never from a hook or a sandboxed worker. A foreign-vendor
model reviews only as `/hef.review --second-opinion <provider>`, never as the verifier of record.

