#!/bin/bash
# ledger-publish.sh — `ledger.sh publish` commits the marked column on an external board (publish-commit, HEF-16).
# SOURCED by ledger.sh behind `[ -f ] || die`; never run on its own. Uses ledger.sh's globals and helpers (DIR, BCTX,
# die, cfgp, is_external).
#
# Opt-in: orchestrate.publish_commit exactly `true` (spec D2). Order: lock → locate → guards → mark → the path --mark
# reported equals the located one → commit (or nothing to commit) → re-hash → record `published` (D4, FR-006). The
# commit is one path, on the board repo's checked-out branch, never pushed, unsigned, under hef_git_neutral's pins
# (the board repo's hooks are NOT run, D5). Every git call is `git -C <board_top>` — never another repository.
#
# ledger.sh is over the file limit, so the logic lives here and ledger.sh keeps only the call-site lines.

# A boolean comparison: `// false` would print `true` for the STRING "true" too (plan review round 3, change 1).
publish_commit_flag() { [ "$(cfgp '.orchestrate.publish_commit == true')" = true ]; }
publish_commit_on() { is_external && publish_commit_flag; }

# One publish at a time per ledger (D8): the claim_lock pattern, stale after one minute. The EXIT trap also removes
# the arm's temp file, so a guard's die leaves nothing behind. Waits ~5 s (50 × 0.1 s) before refusing.
publish_lock() { # $1 the arm's temp file
  local i=0; PUB_LOCK="$DIR/.publish.lock"; PUB_T="${1:-}"
  until mkdir "$PUB_LOCK" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 50 ]; then
      [ -n "$(find "$PUB_LOCK" -maxdepth 0 -mmin +1 2>/dev/null)" ] && rmdir "$PUB_LOCK" 2>/dev/null && continue
      [ -z "$PUB_T" ] || rm -f "$PUB_T"
      die "ledger publish: $PUB_LOCK is held — another publish is running; retry (remove it only if no ledger.sh is running)"
    fi
    sleep 0.1
  done
  trap publish_unlock EXIT
}
publish_unlock() { rmdir "${PUB_LOCK:-}" 2>/dev/null; [ -z "${PUB_T:-}" ] || rm -f "$PUB_T"; }

# Every refusal happens before a byte is written, cheap to expensive, with the evidence in the message (FR-002..004).
# The outside-repo `case` runs before any git call, so a column outside the board repo never reaches git (US4).
publish_guard() { # $1 id, $2 btop, $3 abs → 0, or die
  local g s
  case "$3/" in "$2"/*) ;; *) die "ledger publish $1: $3 is outside the board repo $2 — publish_commit commits only inside it; nothing written" ;; esac
  git -C "$2" ls-files --error-unmatch -- "$3" >/dev/null 2>&1 || die "ledger publish $1: $3 is not tracked in the board repo — commit it once by hand; nothing written"
  for s in MERGE_HEAD:merge rebase-merge:rebase rebase-apply:rebase CHERRY_PICK_HEAD:cherry-pick REVERT_HEAD:revert; do
    g=$(git -C "$2" rev-parse --path-format=absolute --git-path "${s%%:*}") || die "ledger publish $1: cannot read the board repo's git dir in $2 (git ≥ 2.31 needed); nothing written"
    [ ! -e "$g" ] || die "ledger publish $1: the board repo has a ${s#*:} in progress — finish it first; nothing written"
  done
  git -C "$2" symbolic-ref -q --short HEAD >/dev/null || die "ledger publish $1: the board repo's HEAD is detached — check out a branch; nothing written"
  # A clean/process filter runs a program on commit that no GIT_CONFIG_* pin reaches (D5); `unset` is `-filter`.
  s=$(git -C "$2" check-attr filter -- "$3") || die "ledger publish $1: git check-attr failed in $2; nothing written"
  s=${s##*: }
  case "$s" in unspecified|unset) ;; *) die "ledger publish $1: $3 has a git filter ($s) — a filter runs a program on commit; remove the attribute or leave publish_commit off; nothing written" ;; esac
  s=$(git -C "$2" status --porcelain=v1 -- "$3") || die "ledger publish $1: git status failed in $2; nothing written"
  [ -z "$s" ] || die "ledger publish $1: $3 has uncommitted changes (${s:0:2}) — commit or discard them first; nothing written"
}

# Before --mark: take the lock, locate the column (writes nothing) and guard it. Sets LOC ("<file>\t<abs>" | "done\t-").
publish_before_mark() { # $1 id, $2 status-board.sh, $3 btop, $4 the arm's temp file
  publish_lock "$4"
  LOC=$(bash "$2" --locate "$1") || exit 1
  [ "${LOC%%$'\t'*}" = 'done' ] || publish_guard "$1" "$3" "${LOC#*$'\t'}"
}

# After --mark: commit exactly the path --mark reported. Runs inside $(…): a die exits only the subshell — the
# caller's `|| exit` carries it. Prints "<sha12> on <branch>", "nothing", or "done" (the item is in DONE).
publish_after_mark() { # $1 id, $2 marker, $3 btop, $4 LOC, $5 --mark's output
  local p la="${4#*$'\t'}"
  [ "${4%%$'\t'*}" != 'done' ] || { echo 'done'; return 0; }
  p=$(sed -n 's/^path: //p' <<<"$5")
  # A mismatch touches NEITHER file: rolling back the located path could discard a change made through the other.
  [ "$p" = "$la" ] || die "ledger publish $1: --mark wrote $p, located $la — nothing committed or recorded; check both files by hand"
  publish_commit_file "$1" "$2" "$3" "$p"
}

# The commit, or its rollback (D4, D5, D6, D7). The pathspec IS git's --only mode: anything else staged stays staged.
publish_commit_file() { # $1 id, $2 marker, $3 btop, $4 abs → "<sha12> on <branch>" | "nothing", or rollback + die
  local out br
  # the mark was a no-op (the heading already showed it): no commit, so no rollback and no retry loop
  # --no-ext-diff/--no-textconv: a repo-configured diff program must not run either (D5; code review 2026-11-21)
  git -C "$3" diff --quiet --no-ext-diff --no-textconv HEAD -- "$4" && { echo nothing; return 0; }
  # hef_git_neutral already pinned core.hooksPath/core.fsmonitor for this process; never unset them here (D5)
  if ! out=$(git -C "$3" -c commit.gpgsign=false commit -q -m "board: $1 ${2:-no marker}" -- "$4" 2>&1); then
    git -C "$3" checkout -q HEAD -- "$4" 2>/dev/null || die "ledger publish $1: git commit failed in $3 AND the rollback of $4 failed — restore it by hand ($(tail -n1 <<<"$out"))"
    die "ledger publish $1: git commit failed in $3: $(tail -n1 <<<"$out") — the mark is rolled back; publish again once fixed"
  fi
  br=$(git -C "$3" symbolic-ref --short HEAD)
  echo "$(git -C "$3" rev-parse --short=12 HEAD) on $br"
}

# The success line's parenthesis (FR-007).
publish_where() { # $1 publish_after_mark's output
  case "$1" in
    nothing) echo "the board; nothing to commit — the heading already showed it" ;;
    'done') echo "not marked — the item is in DONE" ;;
    *) echo "the board; committed $1, not pushed" ;;
  esac
}

# An in-repo board's column lives in the code repo the person works in: no commit there, said in one line (D1).
publish_inrepo_note() { # $1 id
  is_external || ! publish_commit_flag || echo "$1 publish: publish_commit applies to an external board only — not committed"
}
