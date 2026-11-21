# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
#
# item-kind-downgrade (HEF-54) smoke checks — part 13b. A kind change away from incident/vulnerability is a person's
# signature (`record --item-kind <k> --reviewed-by-human --by <name>`) or the launcher's own record; `init` records
# the intake kind, and automerge requires the gate of BOTH kinds. Every merge assertion is on the fake gh's log.
#
# SOURCED by tests/smoke-automerge.sh right before its cleanup, never run on its own: it reuses that file's fixture
# (am, am_entry, am_pr, am_case, am_no, am_ok, am_grant, am_merged, am_ld, am_w, am_t, FakeGhPr) and creates its own
# branches ik1…ik4, since the fixture's feat* branches belong to the earlier cases. Entry ids start at HEF-40.

if ! declare -F am am_entry am_pr am_case am_no am_ok am_grant am_merged >/dev/null || [ -z "${am_ld:-}" ] || [ -z "${am_w:-}" ] || [ -z "${am_t:-}" ]; then
  if declare -F bad >/dev/null; then bad "tests/smoke-item-kind.sh: source it from tests/smoke-automerge.sh (needs its merge-auto fixture)"
  else echo "tests/smoke-item-kind.sh: source it from tests/smoke-automerge.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

for ik_b in ik1 ik2 ik3 ik4; do
  git -C "$am_w" checkout -q -b "$ik_b" dev && am_g "$am_w" commit -q --allow-empty -m "$ik_b" && git -C "$am_w" push -q origin "$ik_b" 2>/dev/null
done; git -C "$am_w" checkout -q dev
ik_inc='.item_kind = "incident" | .intake_kind = "incident"'
ik_refused() { # ik_refused <label> <text the refusal names> <id> <ledger args…> — refused, and the entry byte-identical
  local l="$1" need="$2" id="$3"; shift 3
  cp "$am_ld/$id.json" "$am_t/ik.before"
  am_no "$l" "$need" "$@"
  cmp -s "$am_t/ik.before" "$am_ld/$id.json" || { bad "$l: a refused call must leave the entry byte-identical (SC-002)"; x_fail=1; }
}
ik_ev() { # ik_ev <label> <id> <by> <note text> — the last event is item-kind-changed by <by>, its note naming the change
  jq -e --arg by "$3" --arg n "$4" '.events[-1] | .kind == "item-kind-changed" and .by == $by and (.note | contains($n)) and (.at | length) > 0' "$am_ld/$2.json" >/dev/null 2>&1 \
    || { bad "$1: the last event must be item-kind-changed by $3 naming '$4' — got $(jq -c '.events[-1]' "$am_ld/$2.json")"; x_fail=1; }
}

# --- FR-002, FR-004, FR-005: record --item-kind — the guard, the signature, the refusals -------------------------------
head_ "item-kind-downgrade: a kind change away from incident/vulnerability needs a person's signature or the launcher (HEF-54 FR-002 FR-004 FR-005)"
x_fail=0; am_cfg auto
# item-kind-downgrade/FR-002: unsigned downgrades are refused, naming the signed form; the file is byte-identical
am_entry HEF-40 40 ik4 "$ik_inc"
ik_refused "an unsigned incident → feature" "--reviewed-by-human --by" HEF-40 record HEF-40 --item-kind feature
am_entry HEF-41 41 ik4 '.item_kind = "vulnerability" | .intake_kind = "vulnerability"'
ik_refused "an unsigned vulnerability → incident (D2)" "--reviewed-by-human --by" HEF-41 record HEF-41 --item-kind incident
HEFESTO_LAUNCHER=1 CLAUDE_CODE_SESSION_ID=sid-ik-0001 ik_refused "the launcher marker with a session id (no launcher)" "--reviewed-by-human --by" HEF-40 record HEF-40 --item-kind feature
# item-kind-downgrade/FR-004: a signature is both flags and a well-formed name; never in a worker; only with --item-kind
am_entry HEF-45 45 ik4 "$ik_inc"
HEFESTO_WORKER=1 ik_refused "a signed downgrade inside a launched worker" "launched worker" HEF-45 record HEF-45 --item-kind feature --reviewed-by-human --by Ana
ik_refused "a signed downgrade with --by ''" "--reviewed-by-human --by" HEF-45 record HEF-45 --item-kind feature --reviewed-by-human --by ''
ik_refused "a signed downgrade with a tab in --by" "--reviewed-by-human --by" HEF-45 record HEF-45 --item-kind feature --reviewed-by-human --by $'a\tb'
ik_refused "a signature with no --item-kind" "--item-kind" HEF-45 record HEF-45 --reviewed-by-human --by Ana
ik_refused "--by Ana with no --reviewed-by-human" "--reviewed-by-human --by" HEF-45 record HEF-45 --item-kind feature --by Ana
ik_refused "--reviewed-by-human with no --by" "--reviewed-by-human --by" HEF-45 record HEF-45 --item-kind feature --reviewed-by-human
am_entry HEF-46 46 ik3 '.intake_kind = "feature"'
ik_refused "half a signature on a call that needs none (feature → incident --by Ana)" "--reviewed-by-human --by" HEF-46 record HEF-46 --item-kind incident --by Ana
# item-kind-downgrade/FR-005: the same kind, and an upgrade, stay open — from a worker too — and never touch intake_kind
am_ok "an unsigned incident → incident" record HEF-45 --item-kind incident
jq -e '.item_kind == "incident" and .intake_kind == "incident"' "$am_ld/HEF-45.json" >/dev/null 2>&1 || { bad "incident → incident must leave both kinds (FR-005)"; x_fail=1; }
HEFESTO_WORKER=1 am_ok "a worker's unsigned feature → incident" record HEF-46 --item-kind incident
jq -e '.item_kind == "incident" and .intake_kind == "feature" and (.events | length) == 0' "$am_ld/HEF-46.json" >/dev/null 2>&1 \
  || { bad "an unsigned upgrade must set item_kind only, with no event (FR-005) — got $(jq -c '{item_kind, intake_kind, events}' "$am_ld/HEF-46.json")"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "record --item-kind: unsigned incident → feature and vulnerability → incident refused naming the signed form, byte-identical; the marker with a session id is no launcher; a worker, an empty or tabbed --by, no --item-kind, either flag alone and half a signature on an upgrade are refused; same kind and upgrades stay open and leave intake_kind (item-kind-downgrade/FR-002 item-kind-downgrade/FR-004 item-kind-downgrade/FR-005)"

# --- FR-003: the signed and the launcher downgrade set both kinds and leave an event ----------------------------------
head_ "item-kind-downgrade: a signed or launcher kind change sets item_kind and intake_kind with an item-kind-changed event (HEF-54 FR-003)"
x_fail=0
# item-kind-downgrade/FR-003
am_entry HEF-42 42 ik1 "$ik_inc"
am_ok "a signed incident → feature" record HEF-42 --item-kind feature --reviewed-by-human --by Ana
jq -e '.item_kind == "feature" and .intake_kind == "feature"' "$am_ld/HEF-42.json" >/dev/null 2>&1 || { bad "a signed downgrade must set both kinds (FR-003)"; x_fail=1; }
ik_ev "the signed downgrade" HEF-42 Ana "incident → feature"
am_entry HEF-43 43 ik4 "$ik_inc"
AM_LAUNCHER=1 am_ok "the launcher's incident → feature" record HEF-43 --item-kind feature
jq -e '.item_kind == "feature" and .intake_kind == "feature"' "$am_ld/HEF-43.json" >/dev/null 2>&1 || { bad "the launcher's downgrade must set both kinds (FR-003)"; x_fail=1; }
ik_ev "the launcher's downgrade" HEF-43 launcher "incident → feature"
am_entry HEF-44 44 ik4 '.intake_kind = "incident"'
am_ok "a signed call that only rewrites intake_kind" record HEF-44 --item-kind feature --reviewed-by-human --by Ana
jq -e '.item_kind == "feature" and .intake_kind == "feature"' "$am_ld/HEF-44.json" >/dev/null 2>&1 || { bad "a signed call must rewrite intake_kind too (FR-003)"; x_fail=1; }
ik_ev "the intake-only change" HEF-44 Ana "intake_kind incident → feature"
[ "$x_fail" -eq 0 ] && ok "a signed (--by Ana) and a launcher downgrade set item_kind and intake_kind, with an item-kind-changed event naming who and from → to; a signed call that only rewrites intake_kind still leaves the event (item-kind-downgrade/FR-003)"

# --- FR-006, FR-007: automerge requires the gate of both kinds — the forged downgrade never merges --------------------------
head_ "item-kind-downgrade: automerge requires the incident gate of item_kind or intake_kind; a forged downgrade never merges (HEF-54 FR-006 FR-007 SC-001)"
x_fail=0; am_cfg auto; am_grant >/dev/null || { bad "the grant for the item-kind merge cases must pass"; x_fail=1; }
# item-kind-downgrade/FR-006 item-kind-downgrade/FR-007: the hand-edited item_kind under an incident intake
am_entry HEF-47 47 ik2 '.intake_kind = "incident"'; am_pr 47 ik2 "$(am_sha ik2)"
am_case "a hand-edited item_kind feature under an incident intake (SC-001)" HEF-47 2 human:merge "gate incident is not PASS"
# item incident, intake feature (the unsigned upgrade above): the item kind still counts
am_pr 46 ik3 "$(am_sha ik3)"
am_case "an incident item over a feature intake" HEF-46 2 human:merge "gate incident is not PASS"
# the signed downgrade (both feature, four gates PASS) merges
am_pr 42 ik1 "$(am_sha ik1)"
am_case "a signed downgrade, four gates PASS" HEF-42 0 none "merged"
[ "$x_fail" -eq 0 ] && ok "automerge: item feature over an incident intake and item incident over a feature intake each skip to human:merge with no gh pr merge; the signed downgrade merges (item-kind-downgrade/FR-006 item-kind-downgrade/FR-007)"

# --- FR-008: each guard half, mutated, turns the suite red -----------------------------------------------------------------
head_ "item-kind-downgrade mutations: the record guard, the launcher marker, the signature, and each kind in automerge's union (HEF-54 FR-008 SC-003)"
x_fail=0
# item-kind-downgrade/FR-008
ik_mutant() { # ik_mutant <name> <sed program> → IK_LG: a ledger.sh whose ledger-automerge.sh is mutated (a temp hooks folder)
  local d="$am_t/mut-$1" f
  mkdir -p "$d"; for f in "$REPO"/hooks/*; do ln -s "$f" "$d/${f##*/}"; done
  rm -f "$d/ledger.sh" "$d/ledger-automerge.sh"; cp "$REPO/hooks/ledger.sh" "$d/ledger.sh"
  sed "$2" "$REPO/hooks/ledger-automerge.sh" > "$d/ledger-automerge.sh"
  cmp -s "$REPO/hooks/ledger-automerge.sh" "$d/ledger-automerge.sh" && { bad "item-kind mutation $1 did not apply"; x_fail=1; }
  IK_LG="$d/ledger.sh"
}
ik_mut_records() { # ik_mut_records <label> <id> <ledger args…> — the mutant's own outcome: the call passes and the entry changes
  local l="$1" id="$2"; shift 2
  cp "$am_ld/$id.json" "$am_t/ik.before"
  if AM_LG="$IK_LG" am "$@" >/dev/null 2>&1 </dev/null && ! cmp -s "$am_t/ik.before" "$am_ld/$id.json"; then :
  else bad "mutation survived ($l): the mutant still refused it"; x_fail=1; fi
}
ik_mut_merges() { # ik_mut_merges <label> <id> — the mutant's own outcome: automerge exits 0 and gh pr merge ran
  local o; : > "$am_t/gh.log"
  if o="$(AM_LG="$IK_LG" am automerge "$2" 2>&1 </dev/null)" && am_merged; then :
  else bad "mutation survived ($1): the mutant still did not merge — got: $(head -c 300 <<<"$o")"; x_fail=1; fi
}
ik_mutant M1 '/drops the \$cur gate/d'
am_entry HEF-48 48 ik4 "$ik_inc"; ik_mut_records "M1: the record guard deleted" HEF-48 record HEF-48 --item-kind feature
ik_mutant M3 '/^am_is_launcher()/s/ && \[ -z "\${CLAUDE_CODE_SESSION_ID:-}" \]//'
am_entry HEF-48 48 ik4 "$ik_inc"
HEFESTO_LAUNCHER=1 CLAUDE_CODE_SESSION_ID=sid-ik-0001 ik_mut_records "M3: the session-id half of the launcher marker dropped" HEF-48 record HEF-48 --item-kind feature
ik_mutant M4 '/^item_kind_signer()/,/^}/s/\[ "\$REVIEWED" = 1 \] && //'
am_entry HEF-48 48 ik4 "$ik_inc"; ik_mut_records "M4: the --reviewed-by-human test dropped" HEF-48 record HEF-48 --item-kind feature --by Ana
ik_mutant M2 's/\[\.item_kind, \.intake_kind\]/[.item_kind]/'
am_pr 47 ik2 "$(am_sha ik2)"   # the fake holds one PR: the signed-downgrade case above left it MERGED
ik_mut_merges "M2: intake_kind dropped from automerge's union" HEF-47
ik_mutant M5 's/\[\.item_kind, \.intake_kind\]/[.intake_kind]/'
am_pr 46 ik3 "$(am_sha ik3)"
ik_mut_merges "M5: item_kind dropped from automerge's union" HEF-46
[ "$x_fail" -eq 0 ] && ok "item-kind mutations: the record guard, the launcher marker's session-id half, the --reviewed-by-human test, intake_kind and item_kind in automerge's union — each applied and caught (item-kind-downgrade/FR-008)"
