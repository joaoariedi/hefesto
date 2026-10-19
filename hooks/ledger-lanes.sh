#!/bin/bash
# ledger-lanes.sh — the lanes-v2 helpers (register, the person-only plan approval, the RFC pin), SOURCED by
# ledger.sh; never run on its own. Kept apart because ledger.sh is past the 500-code-line limit
# (rules/code-quality.md), the same way board-lib.sh was. Uses ledger.sh's globals: ID, E, DIR, HERE,
# SPEC_DIR, REVIEWED, RBY, and its die / write_entry / is_external.

lanes_sha256() { { sha256sum 2>/dev/null || shasum -a 256; } < "$1" | cut -c1-64; }

# register (FR-005): /hef.orchestrate step 1 in ONE call — routing, kind, the raw body's hash, init — so the
# lanes' allowlist can match it (a rule must match every part of a compound shell line). It runs with no
# dialog, so it may never stand in for the person's `record --body-file`: an existing entry is left untouched
# (ledger init is idempotent as well; the check here says so instead of re-reading the item).
REG_TMP=""; REG_ERR=""
register_item() { # $1 id, $2 ref
  local id="$1" ref="$2" sb="$HERE/status-board.sh" r="" k
  [ -n "$ref" ] || die "ledger register $id: --ref <column>#<id> is required"
  if [ -f "$DIR/$id.json" ]; then echo "$id already registered (left untouched)"; return 0; fi
  REG_TMP=$(mktemp) && REG_ERR=$(mktemp) || die "ledger register $id: mktemp failed"
  trap 'rm -f "$REG_TMP" "$REG_ERR"' EXIT
  if is_external; then
    r=$("$sb" --item-repo "$id" 2>"$REG_ERR") || die "$(cat "$REG_ERR")"
    r="${r%%$'\t'*}"
  fi
  k=$("$sb" --item-kind "$id" 2>"$REG_ERR") || die "$(cat "$REG_ERR")"
  "$sb" --item-raw "$id" > "$REG_TMP" 2>"$REG_ERR" || die "$(cat "$REG_ERR")"
  if [ -n "$r" ]; then
    bash "$HERE/ledger.sh" init "$id" --kind tasks-repo --ref "$ref" --body-file "$REG_TMP" --item-kind "$k" --repo "$r" >/dev/null || exit 1
    echo "$id registered (kind $k, repo $r)"
  else
    bash "$HERE/ledger.sh" init "$id" --kind tasks-repo --ref "$ref" --body-file "$REG_TMP" --item-kind "$k" >/dev/null || exit 1
    echo "$id registered (kind $k)"
  fi
}

# The intake gate's rules for any person-only clear: never from inside a launched worker, and a name. The
# dialog is the gate — this command is never allowlisted (lane-launch.sh puts it in `ask`).
person_gate() { # $1 kind
  [ -z "${HEFESTO_WORKER:-}" ] || [ "$HEFESTO_WORKER" = 0 ] \
    || die "ledger unblock $ID: $1 is never cleared from inside a launched worker — a person runs it from their own session"
  [ -z "$RBY" ] && [ "$REVIEWED" = 1 ] && [ -t 0 ] && RBY="${USER:-$(id -un 2>/dev/null)}"
  [ "$REVIEWED" = 1 ] && [[ "$RBY" =~ ^[A-Za-z0-9]([A-Za-z0-9._@\ -]{0,62}[A-Za-z0-9._@-])?$ ]] \
    || die "ledger unblock $ID: $1 needs --reviewed-by-human --by <your name> — a person read it and answers the permission prompt for this command; never allowlist it"
}

# human:plan-approval (FR-006): a person approves a background plan. The planner's own /hef.review writes
# '## Reviewed', so that file can never be the evidence here — only a named person, recorded. Approving at
# phase plan-review moves the entry to tasks; at tasks (an RFC changed after approval) it clears in place.
plan_approval_clear() {
  local p pin now=""
  person_gate human:plan-approval
  { [ -n "$SPEC_DIR" ] && [ -f "$SPEC_DIR/tasks.md" ]; } \
    || die "ledger unblock $ID: human:plan-approval needs the plan's spec folder with tasks.md (spec_dir: '${SPEC_DIR:-none}') — the plan run did not finish"
  p=$(jq -r '.source.rfc.path // empty' <<<"$E"); pin=$(jq -r '.source.rfc.sha256 // empty' <<<"$E")
  if [ -n "$p" ]; then
    [ -f "$p" ] || die "ledger unblock $ID: the item's RFC $p is gone — restore it, or drop the rfc: line and re-plan"
    now=$(lanes_sha256 "$p")
    [ "$now" = "$pin" ] || die "ledger unblock $ID: the RFC $p changed since the plan was made from it — bring spec, plan and tasks in line with it in the item's folder, re-pin it (ledger.sh record $ID --rfc), then approve"
  fi
  jq --arg by "$RBY" --arg s "$now" '.blocked_on = null
    | .reviewed = ((.reviewed // []) + [{kind: "human:plan-approval", by: $by, at: (now | todate)} + (if $s != "" then {rfc_sha: $s} else {} end)])
    | if .phase == "plan-review" then .phase = "tasks" else . end' <<<"$E" | write_entry "$ID" || exit 1
  echo "$ID plan approved by $RBY — phase $(jq -r 'if .phase == "plan-review" then "tasks" else .phase end' <<<"$E")"
}

# record --rfc (FR-007): pin the item's RFC — its path and the hash of what the plan is made from.
rfc_pin() {
  local p
  p=$("$HERE/status-board.sh" --item-rfc "$ID" 2>&1) || die "$p"
  [ -n "$p" ] || die "ledger record $ID --rfc: the item has no rfc: line"
  E=$(jq --arg p "$p" --arg s "$(lanes_sha256 "$p")" '.source.rfc = {path: $p, sha256: $s}' <<<"$E") || die "ledger record $ID --rfc: cannot write the pin"
}
