# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs and sed expressions are single-quoted on purpose
#
# publish-commit smoke checks, part 16: on an external board, `ledger.sh publish` with orchestrate.publish_commit
# commits the marked column — one path-limited commit on the board repo's branch, never pushed — behind the guards
# that keep it from sweeping a person's edit, committing into a sequencer state, writing outside the board repo or
# losing a failed commit (HEF-16; publish-commit FR-001..FR-009, SC-001..SC-005).
#
# SOURCED by tests/smoke.sh, never run on its own. Self-contained: every case builds a FRESH board repo (tasks/ with
# a bare origin) and code repo (a pointer to the board), so a case — and each mutant re-running it — starts from the
# same state. Assertions sit on git state (HEAD, `git log`, the column's sha256) and the ledger JSON, never on model
# output (constitution 3). Every guard has a mutant: a temp folder of links to every hook with the one mutated file
# copied in (PC_SRC), the case re-run against it, which must go red; each keeps the "did not apply" cmp guard.

if [ -z "${REPO:-}" ] || [ -z "${SMOKE_HOME:-}" ] || [ "$HOME" != "$SMOKE_HOME" ] || ! declare -F ok bad head_ sld >/dev/null; then
  if declare -F bad >/dev/null; then bad "tests/smoke-publish-commit.sh: source it from tests/smoke.sh (needs REPO, SMOKE_HOME as HOME, ok, bad, head_, sld)"
  else echo "tests/smoke-publish-commit.sh: source it from tests/smoke.sh" >&2; fi
  # shellcheck disable=SC2317  # reached when the file is executed instead of sourced
  return 0 2>/dev/null || exit 1
fi

pc_t="$(cd "$(mktemp -d)" && pwd -P)"
PC_BASE='{"source":"tasks-repo","root":"tasks","orchestrate":{"publish":true,"publish_commit":true},"repos":{"ops":"../ops"}}'
pcg() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
pcl() { (cd "$PO" && bash "${PC_SRC:-$REPO/hooks}/ledger.sh" "$@"); }
pcs() { (cd "$PO" && bash "${PC_SRC:-$REPO/hooks}/status-board.sh" "$@"); }
pcset() { local f="$PL/$1.json"; jq "$2" "$f" > "$f.t" && mv "$f.t" "$f"; }
pcj() { jq -e "$2" "$PL/$1.json" >/dev/null 2>&1; }
pch() { git -C "$PK" rev-parse HEAD; }
pcsum() { sha256sum < "$1" | cut -c1-64; }
pcgp() { git -C "$PK" rev-parse --path-format=absolute --git-path "$1"; }   # a path inside the board repo's git dir

# A fresh external board: PK (board repo, branch main, a bare origin), PO (code repo), PL (the central ledger).
# PC-1 is in TODO at phase implement (marker 🔨) and never published, so a publish has a state change to write.
pc_fixture() { # [$1 a jq program over the board config]
  local b; b="$(cd "$(mktemp -d "$pc_t/f.XXXXXX")" && pwd -P)"; PB="$b"; PK="$b/kanban"; PO="$b/ops"
  {
    git init -q --bare -b main "$b/o-kanban.git" && git init -q -b main "$PK" && git init -q -b main "$PO" \
      && mkdir -p "$PK/tasks" "$PK/.claude" "$PO/.claude" && printf '.claude/\n' >> "$PK/.git/info/exclude" && printf '.claude/\n' >> "$PO/.git/info/exclude" \
      && printf '# TODO\n\n## PC-1 — one\nrepo: ops\n\n## PC-2 — two\nrepo: ops\n' > "$PK/tasks/TODO.md" \
      && printf '# DOING\n' > "$PK/tasks/DOING.md" && printf '# BACKLOG\n' > "$PK/tasks/BACKLOG.md" \
      && printf '# DONE\n\n## 2026-11-01 shipped\n\n### PD-1 — done one\nrepo: ops\n' > "$PK/tasks/DONE.md" \
      && pcg "$PK" add tasks && pcg "$PK" commit -q -m board && pcg "$PK" remote add origin "$b/o-kanban.git" && pcg "$PK" push -q origin main \
      && printf 'ops\n' > "$PO/README" && pcg "$PO" add README && pcg "$PO" commit -q -m init \
      && jq "${1:-.}" <<<"$PC_BASE" > "$PK/.claude/project-status.json" && printf '{"board":"../kanban"}\n' > "$PO/.claude/project-status.json" \
      && git -C "$PK" config user.email t@example.invalid && git -C "$PK" config user.name t   # ledger.sh cannot pass -c like pcg (CI has no identity)
  } >/dev/null 2>&1 || { bad "publish-commit fixture: the board/code repos could not be built"; x_fail=1; return 1; }
  PL="$(sld "$PK")"
  pcl init PC-1 --kind tasks-repo --ref t --repo ops >/dev/null 2>&1 || { bad "publish-commit fixture: init PC-1 failed: $(pcl init PC-1 --kind tasks-repo --ref t --repo ops 2>&1)"; x_fail=1; return 1; }
  pcset PC-1 '.phase = "implement"'
}

# A refusal (SC-002): non-zero, its OWN contract message (a later guard or git itself cannot mask a dropped one), the
# column byte-identical, no new commit, `published` not recorded.
pc_refuse() { # $1 label, $2 the message fragment, [$3 the column file to hash, default tasks/TODO.md]
  local f="${3:-$PK/tasks/TODO.md}" s h o rc
  s=$(pcsum "$f"); h=$(pch)
  o=$(pcl publish PC-1 2>&1); rc=$?
  { [ "$rc" -ne 0 ] && grep -qF -- "$2" <<<"$o" && [ "$(pcsum "$f")" = "$s" ] && [ "$(pch)" = "$h" ] && pcj PC-1 'has("published") | not'; } \
    || { bad "publish_commit refusal ($1) must exit non-zero, say '$2' and leave the column, HEAD and published alone (rc=$rc): $o"; x_fail=1; }
}

# --- US1: the commit (FR-001, FR-005, FR-006, FR-007) ------------------------------------------------------------------
pc_success() { # publish-commit/FR-001 publish-commit/FR-005 publish-commit/FR-007; publish-commit/FR-006 nothing to commit
  local h0 o rc
  pc_fixture || return; h0=$(pch)
  o=$(pcl publish PC-1 2>&1); rc=$?
  { [ "$rc" -eq 0 ] && [ "$(git -C "$PK" rev-list --count "$h0..HEAD")" = 1 ] && [ "$(git -C "$PK" log -1 --name-only --format=)" = tasks/TODO.md ] \
    && [ "$(git -C "$PK" log -1 --format=%s)" = "board: PC-1 🔨" ] && grep -qxF '## 🔨 PC-1 — one' "$PK/tasks/TODO.md" && [ -z "$(git -C "$PK" status --porcelain)" ]; } \
    || { bad "publish_commit must add ONE commit on main naming only tasks/TODO.md, message 'board: PC-1 🔨' (rc=$rc): $o / $(git -C "$PK" log --oneline -3 | tr '\n' '|')"; x_fail=1; }
  grep -qxF "PC-1 published 🔨 (the board; committed $(git -C "$PK" rev-parse --short=12 HEAD) on main, not pushed)" <<<"$o" || { bad "the success line must name the commit and the branch, not pushed: $o"; x_fail=1; }
  pcj PC-1 '.published.state == "🔨"' || { bad "publish_commit must record published 🔨"; x_fail=1; }
  [ "$(jq -r .source.body_sha256 "$PL/PC-1.json")" = "$(pcs --item-raw PC-1 | sha256sum | cut -c1-64)" ] || { bad "publish_commit must re-hash the committed item"; x_fail=1; }
  [ "$(git --git-dir="$PB/o-kanban.git" rev-parse main)" = "$h0" ] || { bad "publish_commit must never push"; x_fail=1; }
  { [ -z "$(git -C "$PO" status --porcelain)" ] && [ "$(git -C "$PO" rev-list --count HEAD)" = 1 ]; } || { bad "publish_commit must leave the code repo untouched"; x_fail=1; }
  # the heading already shows the marker: the mark leaves the file equal to HEAD → no commit, published, no retry loop
  pcset PC-1 'del(.published)'; h0=$(pch)
  o=$(pcl publish PC-1 2>&1); rc=$?
  { [ "$rc" -eq 0 ] && [ "$(pch)" = "$h0" ] && grep -qxF 'PC-1 published 🔨 (the board; nothing to commit — the heading already showed it)' <<<"$o" && pcj PC-1 '.published.state == "🔨"'; } \
    || { bad "a mark that changes nothing must commit nothing and record published (rc=$rc): $o"; x_fail=1; }
  grep -qF 'publish: unchanged' <<<"$(pcl publish PC-1 2>&1)" || { bad "the pass after nothing-to-commit must say unchanged"; x_fail=1; }
}

# --- US4: --locate and the path line (FR-004) --------------------------------------------------------------------------
pc_locate() { # publish-commit/FR-004
  local s o
  pc_fixture || return; s=$(pcsum "$PK/tasks/TODO.md")
  [ "$(pcs --locate PC-1 2>&1)" = "TODO.md	$PK/tasks/TODO.md" ] || { bad "--locate PC-1 must print the column file name and its absolute path: $(pcs --locate PC-1 2>&1)"; x_fail=1; }
  [ "$(pcs --locate PD-1 2>&1)" = "done	-" ] || { bad "--locate of a DONE item must print done<TAB>-: $(pcs --locate PD-1 2>&1)"; x_fail=1; }
  o=$(pcs --locate NOPE-1 2>&1) && { bad "--locate of a missing item must exit non-zero"; x_fail=1; }
  grep -qF 'status-board --mark NOPE-1: no such item' <<<"$o" || { bad "--locate of a missing item must say what --mark says: $o"; x_fail=1; }
  [ "$(pcsum "$PK/tasks/TODO.md")" = "$s" ] && [ -z "$(git -C "$PK" status --porcelain)" ] || { bad "--locate must write nothing"; x_fail=1; }
  o=$(pcs --mark PC-1 🔨 2>&1)
  [ "$o" = "marked PC-1 🔨 in TODO.md
path: $PK/tasks/TODO.md" ] || { bad "--mark must print the marked line, then path: <absolute>: $o"; x_fail=1; }
  [ "$(pcs --mark PD-1 🔨 2>&1)" = "PD-1 is in DONE.md — the column says it; not marked" ] || { bad "--mark of a DONE item keeps its one line, no path: $(pcs --mark PD-1 🔨 2>&1)"; x_fail=1; }
}

# --- US2, US3, US4: the refusals (FR-002, FR-003, FR-004) --------------------------------------------------------------
pc_r_unstaged() { pc_fixture || return; printf 'edit\n' >> "$PK/tasks/TODO.md"; pc_refuse unstaged 'has uncommitted changes ( M)'; }   # publish-commit/FR-002
pc_r_staged() { pc_fixture || return; printf 'edit\n' >> "$PK/tasks/TODO.md"; git -C "$PK" add tasks/TODO.md; pc_refuse staged 'has uncommitted changes (M '; }   # publish-commit/FR-002
pc_r_untracked() { pc_fixture || return; git -C "$PK" rm -q --cached tasks/TODO.md; pc_refuse untracked 'is not tracked in the board repo — commit it once by hand'; }   # publish-commit/FR-002
pc_r_filter() { # publish-commit/FR-002: a filter runs a program on commit
  pc_fixture || return; printf 'tasks/TODO.md filter=x\n' > "$PK/.gitattributes"; pcg "$PK" add .gitattributes; pcg "$PK" commit -q -m attr
  pc_refuse filter 'has a git filter (x) — a filter runs a program on commit'
}
pc_r_merge() { pc_fixture || return; pch > "$(pcgp MERGE_HEAD)"; pc_refuse merge 'the board repo has a merge in progress'; }   # publish-commit/FR-003
pc_r_rebase() { pc_fixture || return; mkdir -p "$(pcgp rebase-merge)"; pc_refuse rebase-merge 'the board repo has a rebase in progress'; }   # publish-commit/FR-003
pc_r_rebase_apply() { pc_fixture || return; mkdir -p "$(pcgp rebase-apply)"; pc_refuse rebase-apply 'the board repo has a rebase in progress'; }   # publish-commit/FR-003
pc_r_cherry() { pc_fixture || return; pch > "$(pcgp CHERRY_PICK_HEAD)"; pc_refuse cherry-pick 'the board repo has a cherry-pick in progress'; }   # publish-commit/FR-003
pc_r_revert() { pc_fixture || return; pch > "$(pcgp REVERT_HEAD)"; pc_refuse revert 'the board repo has a revert in progress'; }   # publish-commit/FR-003
pc_r_detached() { pc_fixture || return; git -C "$PK" checkout -q --detach; pc_refuse detached "the board repo's HEAD is detached — check out a branch"; }   # publish-commit/FR-003
pc_r_outside() { # publish-commit/FR-004: a column symlinked to a file outside the board repo
  pc_fixture || return; mv "$PK/tasks/TODO.md" "$PB/outside.md"; ln -s "$PB/outside.md" "$PK/tasks/TODO.md"
  pc_refuse outside "$PB/outside.md is outside the board repo $PK" "$PB/outside.md"
}
# A held lock makes publish wait ~5 s (claim_lock's 50 × 0.1 s), then refuse — by design, not a slow test.
pc_r_lock() { pc_fixture || return; mkdir -p "$PL/.publish.lock"; pc_refuse lock 'is held — another publish is running'; rmdir "$PL/.publish.lock"; }   # publish-commit/FR-006

# --mark reports another path than --locate: a stub status-board.sh that DELEGATES to the real one (so --locate and
# the mark really run), then rewrites --mark's path: line. Nothing is touched: the located file KEEPS the mark.
pc_mismatch() { # publish-commit/FR-004
  local d f s h o rc
  pc_fixture || return; d="$(mktemp -d "$pc_t/mm.XXXXXX")"
  for f in "${PC_SRC:-$REPO/hooks}"/*.sh; do ln -s "$f" "$d/${f##*/}"; done; rm "$d/status-board.sh"
  printf '#!/bin/bash\nif [ "$1" != --mark ]; then exec bash "%s" "$@"; fi\nout=$(bash "%s" "$@"); rc=$?\nprintf "%%s\\n" "$out" | sed "s|^path: .*|path: %s|"; exit $rc\n' \
    "${PC_SRC:-$REPO/hooks}/status-board.sh" "${PC_SRC:-$REPO/hooks}/status-board.sh" "$PK/tasks/DOING.md" > "$d/status-board.sh"
  s=$(pcsum "$PK/tasks/DOING.md"); h=$(pch)
  o=$(cd "$PO" && bash "$d/ledger.sh" publish PC-1 2>&1); rc=$?
  { [ "$rc" -ne 0 ] && grep -qF -- "--mark wrote $PK/tasks/DOING.md, located $PK/tasks/TODO.md — nothing committed or recorded" <<<"$o"; } \
    || { bad "a --mark/--locate path mismatch must die naming both paths (rc=$rc): $o"; x_fail=1; }
  { grep -qxF '## 🔨 PC-1 — one' "$PK/tasks/TODO.md" && [ "$(pcsum "$PK/tasks/DOING.md")" = "$s" ] && [ "$(pch)" = "$h" ] && pcj PC-1 'has("published") | not'; } \
    || { bad "on a mismatch publish touches neither file (the located one keeps the mark), commits and records nothing"; x_fail=1; }
}

# --- US5: a failed commit is rolled back and retried (FR-006, SC-003) --------------------------------------------------
pc_fail() { # publish-commit/FR-006
  local h hash o rc
  pc_fixture || return; pcset PC-1 '.phase = "pr"'; pcl publish PC-1 >/dev/null 2>&1   # a recorded body hash to keep
  pcset PC-1 '.phase = "implement"'; git -C "$PK" config --unset user.email; git -C "$PK" config --unset user.name
  h=$(pch); hash=$(jq -c '[.source.body_sha256, .published.state]' "$PL/PC-1.json")
  o=$(export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true
      unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL EMAIL; pcl publish PC-1 2>&1); rc=$?
  { [ "$rc" -ne 0 ] && grep -qF "git commit failed in $PK" <<<"$o" && grep -qF 'the mark is rolled back' <<<"$o"; } || { bad "a failed commit must exit non-zero with git's reason (rc=$rc): $o"; x_fail=1; }
  { git -C "$PK" diff --quiet HEAD -- tasks/TODO.md && [ "$(pch)" = "$h" ] && [ "$(jq -c '[.source.body_sha256, .published.state]' "$PL/PC-1.json")" = "$hash" ]; } \
    || { bad "a failed commit must restore the column to HEAD and leave the body hash and published unchanged"; x_fail=1; }
  git -C "$PK" config user.email t@example.invalid; git -C "$PK" config user.name t
  o=$(pcl publish PC-1 2>&1); rc=$?
  { [ "$rc" -eq 0 ] && [ "$(git -C "$PK" rev-list --count "$h..HEAD")" = 1 ] && pcj PC-1 '.published.state == "🔨"'; } || { bad "with the identity back the next publish must commit (rc=$rc): $o"; x_fail=1; }
}

# --- what is still committed: -filter, an inside-repo symlink, another staged file, a failing hook -----------------------
pc_unset_filter() { # publish-commit/FR-002: `-filter` (unset) disables filters
  local h; pc_fixture || return; printf 'tasks/TODO.md -filter\n' > "$PK/.gitattributes"; pcg "$PK" add .gitattributes; pcg "$PK" commit -q -m attr; h=$(pch)
  pcl publish PC-1 >/dev/null 2>&1 && [ "$(git -C "$PK" rev-list --count "$h..HEAD")" = 1 ] || { bad "a -filter (unset) column must be committed: $(pcl publish PC-1 2>&1)"; x_fail=1; }
}
pc_inside_link() { # publish-commit/FR-004: a column symlinked INSIDE the board repo → the target is committed
  local h; pc_fixture || return
  { pcg "$PK" mv tasks/TODO.md tasks/real-todo.md && ln -s real-todo.md "$PK/tasks/TODO.md" && pcg "$PK" add tasks/TODO.md && pcg "$PK" commit -q -m link; } >/dev/null 2>&1; h=$(pch)
  pcl publish PC-1 >/dev/null 2>&1
  { [ "$(git -C "$PK" rev-list --count "$h..HEAD")" = 1 ] && [ "$(git -C "$PK" log -1 --name-only --format=)" = tasks/real-todo.md ] \
    && [ "$(readlink "$PK/tasks/TODO.md")" = real-todo.md ] && [ -z "$(git -C "$PK" status --porcelain)" ]; } \
    || { bad "a column symlinked inside the board repo must commit the target only, the link unchanged: $(git -C "$PK" log -1 --name-only --format= | tr '\n' ' ')"; x_fail=1; }
}
pc_other_staged() { # publish-commit/FR-005: the pathspec commit leaves another staged file staged
  local h; pc_fixture || return; printf 'x\n' > "$PK/other.txt"; git -C "$PK" add other.txt; h=$(pch)
  pcl publish PC-1 >/dev/null 2>&1
  { [ "$(git -C "$PK" rev-list --count "$h..HEAD")" = 1 ] && [ "$(git -C "$PK" log -1 --name-only --format=)" = tasks/TODO.md ] && [ "$(git -C "$PK" diff --cached --name-only)" = other.txt ]; } \
    || { bad "with another file staged the commit must name only tasks/TODO.md and leave other.txt staged: $(git -C "$PK" log -1 --name-only --format= | tr '\n' ' ')"; x_fail=1; }
}
pc_hook() { # publish-commit/FR-005: hef_git_neutral keeps the board repo's hooks off (spec D5)
  local h; pc_fixture || return; printf '#!/bin/sh\nexit 1\n' > "$PK/.git/hooks/pre-commit"; chmod +x "$PK/.git/hooks/pre-commit"; h=$(pch)
  pcl publish PC-1 >/dev/null 2>&1 && [ "$(git -C "$PK" rev-list --count "$h..HEAD")" = 1 ] || { bad "a failing pre-commit hook must not run (the publish commits): $(pcl publish PC-1 2>&1)"; x_fail=1; }
}

# --- the edges: DONE, off, in-repo (FR-001) ----------------------------------------------------------------------------
pc_done() { # publish-commit/FR-001
  local h s o; pc_fixture || return; pcl init PD-1 --kind tasks-repo --ref t --repo ops >/dev/null 2>&1; pcset PD-1 '.phase = "implement"'
  h=$(pch); s=$(pcsum "$PK/tasks/DONE.md"); o=$(pcl publish PD-1 2>&1)
  { [ "$o" = "PD-1 published 🔨 (not marked — the item is in DONE)" ] && [ "$(pch)" = "$h" ] && [ "$(pcsum "$PK/tasks/DONE.md")" = "$s" ] && pcj PD-1 '.published.state == "🔨"'; } \
    || { bad "a DONE item with publish_commit on: no commit, published recorded as today: $o"; x_fail=1; }
}
pc_off() { # publish-commit/FR-001: absent, false, the STRING "true" → today's behaviour exactly
  local c h o
  for c in 'del(.orchestrate.publish_commit)' '.orchestrate.publish_commit = false' '.orchestrate.publish_commit = "true"'; do
    pc_fixture "$c" || return; h=$(pch); o=$(pcl publish PC-1 2>&1)
    { [ "$o" = "PC-1 published 🔨 (the board)" ] && [ "$(pch)" = "$h" ] && [ "$(git -C "$PK" diff --name-only)" = tasks/TODO.md ]; } \
      || { bad "publish_commit $c must publish as today, uncommitted: $o"; x_fail=1; }
  done
}
pc_inrepo() { # publish-commit/FR-001: an in-repo board marks, never commits, and says so in one line
  local r h o; r="$(cd "$(mktemp -d "$pc_t/ir.XXXXXX")" && pwd -P)"
  { git init -q -b main "$r" && mkdir -p "$r/tasks" "$r/.claude" && printf '.claude/\n' >> "$r/.git/info/exclude" \
    && printf '# TODO\n\n## IR-1 — one\nbody\n' > "$r/tasks/TODO.md" && for f in DOING DONE BACKLOG; do printf '# %s\n' "$f" > "$r/tasks/$f.md"; done \
    && pcg "$r" add tasks && pcg "$r" commit -q -m board \
    && printf '{"source":"tasks-repo","root":"tasks","orchestrate":{"publish":true,"publish_commit":true}}\n' > "$r/.claude/project-status.json"; } >/dev/null 2>&1
  (cd "$r" && bash "${PC_SRC:-$REPO/hooks}/ledger.sh" init IR-1 --kind tasks-repo --ref t >/dev/null 2>&1)
  PL="$(sld "$r")"; pcset IR-1 '.phase = "implement"'; h=$(git -C "$r" rev-parse HEAD)
  o=$(cd "$r" && bash "${PC_SRC:-$REPO/hooks}/ledger.sh" publish IR-1 2>&1)
  { [ "$o" = "IR-1 published 🔨 (the board)
IR-1 publish: publish_commit applies to an external board only — not committed" ] && [ "$(git -C "$r" rev-parse HEAD)" = "$h" ] && grep -qxF '## 🔨 IR-1 — one' "$r/tasks/TODO.md"; } \
    || { bad "an in-repo board with publish_commit on must mark, not commit, and say so: $o"; x_fail=1; }
}

# --- run the cases ----------------------------------------------------------------------------------------------------
head_ "publish_commit: ledger.sh publish commits the marked column on an external board (HEF-16)"
x_fail=0; pc_success; pc_locate
[ "$x_fail" -eq 0 ] && ok "publish_commit: one commit on the board's branch naming only the column, fixed message, published + re-hash, never pushed, code repo untouched, nothing-to-commit records without a loop; --locate / --mark path: (publish-commit FR-001 FR-004 FR-005 FR-006 FR-007)"
x_fail=0; pc_r_unstaged; pc_r_staged; pc_r_untracked; pc_r_filter; pc_r_merge; pc_r_rebase; pc_r_rebase_apply; pc_r_cherry; pc_r_revert; pc_r_detached; pc_r_outside; pc_r_lock; pc_mismatch
[ "$x_fail" -eq 0 ] && ok "publish_commit refusals, each with its own message and the column/HEAD/published untouched: unstaged, staged, untracked, filter, merge, rebase ×2, cherry-pick, revert, detached HEAD, outside the board repo, a held lock, a --mark/--locate mismatch (publish-commit FR-002 FR-003 FR-004 FR-006)"
# publish-commit/FR-008: the person enabling it reads the contract in both docs, and the CHANGELOG has the entry
x_fail=0
for pc_w in 'orchestrate.publish_commit' 'never pushes' 'hooks do not run' 'git identity is needed' 'filter' '2.31'; do
  grep -qF -- "$pc_w" "$REPO/docs/install.md" || { bad "docs/install.md (external board) must state '$pc_w' for publish_commit (FR-008)"; x_fail=1; }
done
for pc_w in 'orchestrate.publish_commit' 'never pushed' 'hooks not run' 'git identity' '`filter` attribute' '--locate <id>' 'path: <absolute path>'; do
  grep -qF -- "$pc_w" "$REPO/docs/hooks.md" || { bad "docs/hooks.md must state '$pc_w' (FR-008)"; x_fail=1; }
done
sed -n '/^## \[Unreleased\]/,/^## \[[0-9]/p' "$REPO/CHANGELOG.md" | grep -qF 'publish_commit' || { bad "CHANGELOG.md [Unreleased] must carry the publish_commit entry (FR-008)"; x_fail=1; }
# publish-commit/FR-009: the logic is a sourced helper ledger.sh loads behind [ -f ] || die (tests/smoke-lifecycle.sh
# removes it and asserts the named stop)
grep -qF '[ -f "$HERE/ledger-publish.sh" ] || die' "$REPO/hooks/ledger.sh" || { bad "ledger.sh must source ledger-publish.sh behind [ -f ] || die (FR-009)"; x_fail=1; }
[ "$x_fail" -eq 0 ] && ok "publish_commit is documented in docs/install.md and docs/hooks.md and the CHANGELOG; its logic is the sourced ledger-publish.sh (publish-commit FR-008 FR-009)"
x_fail=0; pc_fail; pc_unset_filter; pc_inside_link; pc_other_staged; pc_hook; pc_done; pc_off; pc_inrepo
[ "$x_fail" -eq 0 ] && ok "publish_commit: a failed commit rolled back then retried; -filter, an inside-repo symlink, another staged file and a failing hook still commit as specified; DONE, off/false/\"true\", in-repo unchanged (publish-commit FR-001 FR-002 FR-004 FR-005 FR-006)"

# --- SC-005: every guard is mutation-tested ---------------------------------------------------------------------------
pc_mut() { # $1 label, $2 file under hooks/, $3 sed program, $4 the case that must go red on the mutant
  local d f red; d="$(mktemp -d "$pc_t/mut.XXXXXX")"
  for f in "$REPO"/hooks/*.sh; do ln -s "$f" "$d/${f##*/}"; done
  rm "$d/$2"; sed "$3" "$REPO/hooks/$2" > "$d/$2"
  if cmp -s "$REPO/hooks/$2" "$d/$2"; then bad "publish-commit mutant did not apply: $1"; x_fail=1; return; fi
  red="$(x_fail=0; PC_SRC="$d" "$4" >/dev/null 2>&1; echo "$x_fail")"
  [ "$red" = 1 ] || { bad "publish-commit mutation survived: $1"; x_fail=1; }
}
x_fail=0
pc_mut 'M1 outside-repo case' ledger-publish.sh '/^  case "\$3\/" in "\$2"\/\*) ;;/d' pc_r_outside
pc_mut 'M2 ls-files tracked check' ledger-publish.sh '/ls-files --error-unmatch/d' pc_r_untracked
pc_mut 'M3 sequencer loop' ledger-publish.sh 's/^  for s in MERGE_HEAD:merge .*; do$/  for s in; do/' pc_r_merge
pc_mut 'M4 detached HEAD' ledger-publish.sh '/symbolic-ref -q --short HEAD >\/dev\/null || die/d' pc_r_detached
pc_mut 'M5 dirty check' ledger-publish.sh '/has uncommitted changes/d' pc_r_unstaged
pc_mut 'M6 the -- path pathspec' ledger-publish.sh 's/ -- "\$4" 2>&1); then/ 2>\&1); then/' pc_other_staged
pc_mut 'M7 record before the commit' ledger.sh $'/CM=$(publish_after_mark/{\nh\nd\n}\n/\\.published = {state: /G' pc_fail
pc_mut 'M8 rollback' ledger-publish.sh 's/^    git -C "\$3" checkout -q HEAD -- "\$4" 2>\/dev\/null || die/    true || die/' pc_fail
pc_mut 'M9 re-hash before the commit' ledger.sh $'/CM=$(publish_after_mark/{\nh\nd\n}\n/"$0" record "$ID" --body-file "$T"/G' pc_fail
pc_mut 'M10 the string "true" as on' ledger-publish.sh 's/\.orchestrate\.publish_commit == true/.orchestrate.publish_commit \/\/ false/' pc_off
pc_mut 'M11 the lock' ledger-publish.sh 's/^  publish_lock "\$4"$/  :/' pc_r_lock
pc_mut 'M12 check-attr filter' ledger-publish.sh 's/case "\$s" in unspecified|unset) ;; \*) die/case "$s" in *) ;; x) die/' pc_r_filter
pc_mut 'M13 nothing-to-commit skip' ledger-publish.sh '/diff --quiet --no-ext-diff --no-textconv HEAD -- "\$4" && { echo nothing/d' pc_success
pc_mut 'M14 roll back the located path on a mismatch' ledger-publish.sh 's/^  \[ "\$p" = "\$la" \] || die/  [ "$p" = "$la" ] || git -C "$3" checkout -q HEAD -- "$la"; [ "$p" = "$la" ] || die/' pc_mismatch
[ "$x_fail" -eq 0 ] && ok "publish-commit mutations M1–M14: outside-repo, tracked, sequencer, detached, dirty, pathspec, record order, rollback, re-hash order, string true, lock, filter, nothing-to-commit, mismatch rollback — all caught (SC-005)"
rm -rf -- "${pc_t:?}"
