# shellcheck shell=bash
# board-setup.sh — the two board-setup modes of status-board.sh, sourced by it (github-project-board, plan R1 #6:
# status-board.sh is at its 500-code-line limit). Functions only; they run after status-board.sh has resolved
# MODE, ROOT, CONFIG, BCTX and GH, and they exit the script as the inline blocks did.

# lanes-v3 trial 2026-10-22: --detect lists the boards a project already seems to use, one JSON object per
# line, so the orchestrator can ask which to adopt instead of creating its own. Read-only; the `github` candidate's
# `projects` is best-effort network (a note instead when gh cannot say), nothing else is.
# From a linked worktree the config's path is ABSOLUTE on purpose: it is the main checkout's file (#162), outside
# ROOT, and naming it relative would point at the worktree's copy, the one that does not decide.
board_detect() {
  local d n c f u r
  command -v jq >/dev/null 2>&1 || { echo "status-board --detect: jq not found" >&2; exit 1; }
  [ -f "$CONFIG" ] && jq -cn --arg c "${CONFIG#"$ROOT"/}" '{kind: "config", path: $c}'
  for d in tasks board kanban; do
    n=0; for c in TODO DOING DONE BACKLOG; do [ -f "$ROOT/$d/$c.md" ] && n=$((n + 1)); done
    [ "$n" -gt 0 ] && jq -cn --arg r "$d" --argjson n "$n" '{kind: "tasks-folder", root: $r, columns_found: $n}'
  done
  while IFS= read -r f; do
    n=$(grep -cE '^#{2,3} .*[A-Z][A-Z0-9]+-[0-9]+' "$f" 2>/dev/null || true)
    [ "${n:-0}" -ge 2 ] && jq -cn --arg p "${f#"$ROOT"/}" --argjson n "$n" '{kind: "items-file", path: $p, items: $n}'
  done < <(find "$ROOT" -maxdepth 2 -name '*.md' -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path "$ROOT/tasks/*" 2>/dev/null | sort)
  u="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
  case "$u" in *github.com[:/]*) r="${u#*github.com[:/]}"; detect_github "${r%.git}" ;; esac
  exit 0
}
detect_github() { # $1 owner/name → the `github` candidate, with the repo's Projects when gh can list them
  local p=""
  declare -F ghb_projects >/dev/null && p="$(ghb_projects "$1" 2>/dev/null)" || p=""
  if [ -n "$p" ]; then jq -cn --arg r "$1" --argjson p "$p" '{kind: "github", repo: $r, projects: $p, note: "a linked GitHub Project can be the lane board (source github-project)"}'
  else jq -cn --arg r "$1" '{kind: "github", repo: $r, note: "gh could not list the repo'"'"'s Projects (gh auth status; the read:project scope) — a GitHub Project can be the lane board"}'; fi
}

# lanes-v3 FR-024: --init creates what a board needs and is missing — never overwriting a file — so a single
# lane can start on a project with no board: the default config asks a person to approve every plan.
board_init() {
  local made troot c f rd
  { [ -n "$BCTX" ] && [ "$(jq -r .mode <<<"$BCTX")" = external ]; } && { echo "status-board --init: the board is external ($ROOT) — set it up there" >&2; exit 1; }
  made=""; troot="$ROOT/tasks"
  if [ ! -f "$CONFIG" ]; then
    mkdir -p "$(dirname "$CONFIG")" && jq -n '{source: "tasks-repo", root: "tasks", orchestrate: {plan_review: "human", plan_first: true, rfc_dir: "docs/rfcs"}}' > "$CONFIG" \
      || { echo "status-board --init: cannot write $CONFIG" >&2; exit 1; }
    made="$made ${CONFIG#"$ROOT"/}"
  else
    jq -e '.source == "tasks-repo"' "$CONFIG" >/dev/null 2>&1 || { echo "status-board --init: $CONFIG is not a tasks-repo board — nothing to create" >&2; exit 1; }
    troot="$ROOT/$(jq -r '.root // "tasks"' "$CONFIG")"
  fi
  for c in todo:TODO doing:DOING done:DONE backlog:BACKLOG; do
    f="$troot/$(jq -r --arg k "${c%%:*}" --arg d "${c#*:}.md" '.columns[$k] // $d' "$CONFIG")"
    [ -f "$f" ] || { mkdir -p "$(dirname "$f")" && printf '# %s\n' "${c#*:}" > "$f" && made="$made ${f#"$ROOT"/}"; }
  done
  rd="$ROOT/$(jq -r '.orchestrate.rfc_dir // "docs/rfcs"' "$CONFIG")"; [ -d "$rd" ] || { mkdir -p "$rd" && made="$made ${rd#"$ROOT"/}/"; }
  if [ -n "$made" ]; then echo "created:$made"; else echo "nothing to create: the board is in place"; fi
  exit 0
}
