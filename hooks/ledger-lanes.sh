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
# dialog is the gate — this command is never allowlisted (hefesto-setup.sh puts it in `ask`).
person_gate() { # $1 kind, $2 verb (default unblock)
  local v="${2:-unblock}"
  [ -z "${HEFESTO_WORKER:-}" ] || [ "$HEFESTO_WORKER" = 0 ] \
    || die "ledger $v $ID: $1 is never cleared from inside a launched worker — a person runs it from their own session"
  [ -z "$RBY" ] && [ "$REVIEWED" = 1 ] && [ -t 0 ] && RBY="${USER:-$(id -un 2>/dev/null)}"
  [ "$REVIEWED" = 1 ] && [[ "$RBY" =~ ^[A-Za-z0-9]([A-Za-z0-9._@\ -]{0,62}[A-Za-z0-9._@-])?$ ]] \
    || die "ledger $v $ID: $1 needs --reviewed-by-human --by <your name> — a person read it and answers the permission prompt for this command; never allowlist it"
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

# record --rfc (FR-007): pin the item's RFC — its path and the hash of what the plan is made from. With
# $1 (the launcher's --rfc-snapshot) the hash is of that copy: exactly the text the planner received.
rfc_pin() { # [$1 snapshot file]
  local p err
  err=$(mktemp) || die "ledger record $ID --rfc: mktemp failed"
  p=$("$HERE/status-board.sh" --item-rfc "$ID" 2>"$err") || { local m; m=$(cat "$err"); rm -f "$err"; die "$m"; }
  rm -f "$err"
  [ -n "$p" ] || die "ledger record $ID --rfc: the item has no rfc: line"
  E=$(jq --arg p "$p" --arg s "$(lanes_sha256 "${1:-$p}")" '.source.rfc = {path: $p, sha256: $s}' <<<"$E") || die "ledger record $ID --rfc: cannot write the pin"
}

# --- lanes-v3: the decisions the orchestrator lane asks as forms (FR-012..014) ---------------------------
# The planner's questions go to the person as data; the person's answers and change notes come back as files
# copied into the ledger dir with their hash, so the planner gets exactly what was recorded. The dialog of
# `answer` / `revise` (both in the lanes' `ask` rules) is the consent; --by is a record of who gave it.
lanes_strip() { sed -E 's/<!--([^-]|-[^-])*-->//g' | sed '/<!--/,/-->/d'; }
questions_item() {
  local k sd qp body="" nonce
  k=$(jq -r '.blocked_on.kind // empty' <<<"$E")
  case "$k" in human:clarify|human:plan-review) ;; *) die "ledger questions $ID: it waits on ${k:-nothing} — questions come with human:clarify or human:plan-review" ;; esac
  sd=$(jq -r '.spec_dir // empty' <<<"$E"); qp=$(jq -r '.blocked_on.question_path // empty' <<<"$E")
  [ -n "$sd" ] && [ -f "$sd/spec.md" ] && body="$(lanes_strip < "$sd/spec.md" | grep -n 'NEEDS CLARIFICATION' | head -40)"
  [ -n "$qp" ] && [ -f "$qp" ] && body="$body${body:+$'\n'}$(lanes_strip < "$qp" | head -c 8000)"
  [ -n "$body" ] || die "ledger questions $ID: no open question found (spec_dir '${sd:-none}', question file '${qp:-none}') — read the item's folder"
  nonce="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8)"
  printf '<<<untrusted-questions-begin %s %s\n%s\nuntrusted-questions-end %s>>>\n' "$ID" "$nonce" "$body" "$nonce"
}
lanes_take_text() { # $1 file, or "" / "-" for stdin; $2 destination; $3 verb
  if [ -n "$1" ] && [ "$1" != - ]; then [ -f "$1" ] || die "ledger $3 $ID: file not found: '$1'"; cat -- "$1" > "$2"
  else cat > "$2"; fi || { rm -f "$2"; die "ledger $3 $ID: cannot store the text"; }
  [ -s "$2" ] || { rm -f "$2"; die "ledger $3 $ID: the text is empty — pass it on stdin (a heredoc inside the command) or with --file"; }
  [ "$(wc -c < "$2" | tr -d ' ')" -le 32768 ] || { rm -f "$2"; die "ledger $3 $ID: over 32 KB — keep it to the answers"; }
}
answer_item() { # $1 file|-
  local k n dst
  k=$(jq -r '.blocked_on.kind // empty' <<<"$E")
  case "$k" in human:clarify|human:plan-review) ;; *) die "ledger answer $ID: it waits on ${k:-nothing} — answers clear human:clarify or human:plan-review only" ;; esac
  person_gate "$k" answer
  n=$(( $(jq '.answers // [] | length' <<<"$E") + 1 )); dst="$DIR/$ID.answers-$n.md"
  lanes_take_text "$1" "$dst" answer
  jq --arg p "$dst" --arg s "$(lanes_sha256 "$dst")" --arg by "$RBY" --arg k "$k" \
    '.blocked_on = null | .answers = ((.answers // []) + [{path: $p, sha256: $s, by: $by, kind: $k, at: (now | todate)}])' <<<"$E" | write_entry "$ID" || exit 1
  echo "$ID answered by $RBY ($k cleared) — the planner resumes with the answers on its next pass"
}
revise_item() { # $1 file|-
  local k ph n dst
  k=$(jq -r '.blocked_on.kind // empty' <<<"$E"); ph=$(jq -r '.phase' <<<"$E")
  [ "$k" = human:plan-approval ] || die "ledger revise $ID: it waits on ${k:-nothing} — revise answers a plan waiting on human:plan-approval"
  case "$ph" in plan-review|tasks) ;; *) die "ledger revise $ID: phase $ph — a build has started; revise applies before it (plan-review or tasks)" ;; esac
  person_gate "$k" revise
  n=$(( $(jq '.revisions // [] | length' <<<"$E") + 1 )); dst="$DIR/$ID.notes-$n.md"
  lanes_take_text "$1" "$dst" revise
  jq --arg p "$dst" --arg s "$(lanes_sha256 "$dst")" --arg by "$RBY" \
    '.blocked_on = null | .phase = "intake" | .revisions = ((.revisions // []) + [{path: $p, sha256: $s, by: $by, at: (now | todate)}])' <<<"$E" | write_entry "$ID" || exit 1
  echo "$ID sent back to the planner by $RBY — it revises spec, plan and tasks to the notes, then waits for approval again"
}

# --- a claim whose launcher is gone (lanes-v3 trial 2026-10-22, reviews round 5-6) -----------------------
# A launch cut off mid-run (a crash, a closed terminal) never reaches `ledger run`, so its owner stayed forever:
# the item looked owned and the whole repository busy. The launcher keeps a LEASE while it runs — it touches
# <ledger>/<id>.lease every 20 s, while it or its worker lives — and a claim is released when that lease is older
# than five minutes (or, past a five-minute grace after the claim, missing): long against the renewal, so a
# laptop waking from sleep does not lose a live claim before the next renewal. A file's age reads the same inside and outside a sandbox, where
# a pid check does not: a sandboxed process lives in its own pid namespace and sees every launcher as dead.
# Never from a launched worker. The released run is recorded as failed (exit 125).
lease_stale() { # $1 entry file → 0 when its owner's lease (or the grace after the claim) has run out
  local id lease
  id=$(basename "$1" .json); lease="$DIR/$id.lease"
  if [ -f "$lease" ]; then [ -n "$(find "$lease" -mmin +5 2>/dev/null)" ]; return; fi
  # the claim's age, computed by jq (fromdateiso8601): no GNU/BSD date parsing to keep apart
  [ "$(jq -r '((.owner.started // "") | try (now - fromdateiso8601) catch -1) > 300' "$1" 2>/dev/null)" = true ]
}
reap_dead_owners() { # every owned entry whose lease ran out → owner released (call under claim_lock)
  local f e
  [ -z "${HEFESTO_WORKER:-}" ] || [ "$HEFESTO_WORKER" = 0 ] || return 0
  for f in "$DIR"/*.json; do
    [ -f "$f" ] || continue
    [ "$(jq -r '.owner != null' "$f" 2>/dev/null)" = true ] || continue
    lease_stale "$f" || continue
    e=$(jq '.runs = ((.runs // []) + [{role: .owner.role, session_name: .owner.session_name, session_id: "", exit: 125, usd: 0, at: (now | todate), note: "the launcher stopped renewing its lease — the run was cut off"}]) | .owner = null' "$f") || continue
    write_entry "$(basename "$f" .json)" <<<"$e" && rm -f "$DIR/$(basename "$f" .json).lease" \
      && echo "ledger: released $(basename "$f" .json) — its launcher stopped renewing the lease over five minutes ago; the run is recorded as failed (exit 125)" >&2
  done
}
