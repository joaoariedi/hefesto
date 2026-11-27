#!/bin/bash
# review-repro.sh — run ONE reproduction recipe of the exhaustive code-review round (HEF-58 exhaustive-review FR-006).
#
#   <hooks>/review-repro.sh '<the recipe>'           — one single-quoted argument (amendment A3)
#   <hooks>/review-repro.sh <<'HEF_REPRO_RECIPE_END'   — or on stdin, where the shell can make a heredoc
#   <the recipe>
#   HEF_REPRO_RECIPE_END
#
# Amendment A3 (HEF-58, eval probe 2): in the eval sandbox the temp folder is read-only, so the shell cannot create a
# heredoc's temporary file and this helper never starts. The argument form needs no temporary file of the shell's.
#
# The verifier works read-only on the worktree, and a verify worker may not `bash -c`, write a fixture or mkdir a
# scratch folder (plan, truth map): this helper is its one channel. The recipe runs with stdin from /dev/null, in a
# fresh copy of the worktree's tracked and unignored files under $TMPDIR (or, when it is read-only, a writable folder
# under the cache — amendment A4) with its OWN repository — a recipe's
# `git config`/`git commit` act on the copy, never the worktree's .git — and is never told where the real worktree is.
#
# Stdout: `exit: <n>` then the output, capped at 60 lines and 8 KiB. Exit 0 after a run, whatever the recipe's status
# (the status is data); 2 = refused (not inside the OS sandbox, no cache folder to probe, empty recipe, no scratch
# folder); 3 = the worktree changed during the run, each path on stderr as `created|modified|deleted <path>`.
# The scratch copy is removed on every exit path (trap right after mktemp).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lane-lib.sh
. "$HERE/lane-lib.sh"
refuse() { echo "review-repro.sh: $*" >&2; exit 2; }

# The sandbox check, as lane-build.sh does it: a missing folder is never read as "sandboxed", and a write that succeeds
# where no sandbox lets anything write ($(hef_cache) itself — a worker writes only worker-cache/<repo>, a lane only
# lane-cache/<key>) means this call is NOT sandboxed. A caller who controls the environment and runs unsandboxed can
# defeat it; it stops the careless path (a retry with the sandbox off), and lane-guard.sh refuses
# dangerouslyDisableSandbox on this helper's heredoc and argument forms.
CACHE="$(hef_cache)"
[ -d "$CACHE" ] || refuse "$CACHE is missing, so the sandbox cannot be probed — run hefesto-setup.sh"
PROBE="$CACHE/.repro-probe.$$"
if ( : >"$PROBE" ) 2>/dev/null; then rm -f "$PROBE"; refuse "not running inside the OS sandbox — recipes run sandboxed only"; fi

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
TOP="$(git rev-parse --show-toplevel 2>/dev/null)" && USE_GIT=1 || { TOP="$(pwd -P)"; USE_GIT=0; }
[ -d "$TOP" ] || refuse "no worktree to copy (cwd: $PWD)"
# Amendment A4 (HEF-58, the second eval probe 2): the eval sandbox's temp folder is read-only, so the scratch copy falls
# back to a writable folder under the cache — after the probe, $CACHE itself is not writable, but a worker's
# worker-cache/<repo> or a lane's lane-cache/<key> is. Neither writable → refused, naming both.
rr_scratch() {
  local d
  for d in "${TMPDIR:-/tmp}" "$CACHE" "$CACHE"/*/ "$CACHE"/*/*/; do
    [ -d "$d" ] || continue
    mktemp -d "${d%/}/hef-repro.XXXXXXXX" 2>/dev/null && return 0
  done
  return 1
}
SCRATCH="$(rr_scratch)" || refuse "cannot make a scratch folder — neither ${TMPDIR:-/tmp} nor any folder under $CACHE is writable here"
trap 'chmod -R u+w "$SCRATCH" 2>/dev/null; rm -rf "$SCRATCH"' EXIT
# The recipe's own heredocs and mktemp need a writable temp folder too: when $TMPDIR was not, it gets one in the copy.
case "$SCRATCH" in "${TMPDIR:-/tmp}"/*) ;; *) mkdir "$SCRATCH/tmp" && export TMPDIR="$SCRATCH/tmp" ;; esac
case $# in
  0) cat >"$SCRATCH/.hef-recipe.sh" ;;
  1) printf '%s\n' "$1" >"$SCRATCH/.hef-recipe.sh" ;;
  *) refuse "$# arguments — pass the recipe as ONE single-quoted argument (or on stdin), nothing else" ;;
esac
grep -q '[^[:space:]]' "$SCRATCH/.hef-recipe.sh" || refuse "empty recipe — pass it as one single-quoted argument or a quoted heredoc"

rr_files() { # NUL-separated paths relative to $TOP: tracked + unignored (never .git, never an ignored build output)
  if [ "$USE_GIT" = 1 ]; then git -C "$TOP" ls-files -z --cached --others --exclude-standard
  else (cd "$TOP" && find . -name .git -prune -o \( -type f -o -type l \) -print0) \
    | while IFS= read -r -d '' f; do printf '%s\0' "${f#./}"; done
  fi
}
rr_listing() { # → "<path><TAB><checksum> <size>" per file, sorted; a tracked file gone from disk is simply absent
  (cd "$TOP" && rr_files | xargs -0 cksum 2>/dev/null) \
    | sed -E "s/^([0-9]+) ([0-9]+) (.*)\$/\\3$(printf '\t')\\1 \\2/" | LC_ALL=C sort
}
rr_copy() { # the files into $SCRATCH/w, then its own repository with a fixed identity (no hooks, no signing)
  mkdir "$SCRATCH/w" || refuse "cannot make $SCRATCH/w"
  (cd "$TOP" && rr_files | tar --null -T - -cf - 2>/dev/null) | (cd "$SCRATCH/w" && tar -xf - 2>/dev/null)
  [ "$USE_GIT" = 1 ] || return 0
  (cd "$SCRATCH/w" && git init -q . && git config user.name hefesto-repro && git config user.email repro@example.invalid \
    && git config core.hooksPath /dev/null && git config commit.gpgsign false \
    && git add -A && git commit -qm "review-repro scratch copy" --allow-empty) >/dev/null 2>&1
}
rr_changes() { # before after → "created|modified|deleted <path>" per changed path, on stdout
  local b="$1" a="$2" p
  cut -f1 "$b" >"$SCRATCH/pb"; cut -f1 "$a" >"$SCRATCH/pa"
  LC_ALL=C comm -13 "$SCRATCH/pb" "$SCRATCH/pa" | while IFS= read -r p; do echo "created $p"; done
  LC_ALL=C comm -23 "$SCRATCH/pb" "$SCRATCH/pa" | while IFS= read -r p; do echo "deleted $p"; done
  LC_ALL=C comm -3 "$b" "$a" | sed "s/^$(printf '\t')//" | cut -f1 | LC_ALL=C sort -u >"$SCRATCH/pc"
  LC_ALL=C comm -12 "$SCRATCH/pc" <(LC_ALL=C comm -12 "$SCRATCH/pb" "$SCRATCH/pa") | while IFS= read -r p; do echo "modified $p"; done
}
rr_print() { # $1 status, $2 output file → `exit: <n>` and the output, capped at 60 lines and 8 KiB
  local lines bytes shown
  echo "exit: $1"
  head -n 60 "$2" | head -c 8192 >"$SCRATCH/shown"; cat "$SCRATCH/shown"
  lines="$(wc -l <"$2" | tr -d ' ')"; bytes="$(wc -c <"$2" | tr -d ' ')"; shown="$(wc -c <"$SCRATCH/shown" | tr -d ' ')"
  [ "$bytes" -gt "$shown" ] || return 0
  [ -n "$(tail -c 1 "$SCRATCH/shown")" ] && echo   # a cut mid-line: the notice starts on its own line
  printf '… +%s lines / %s bytes cut\n' "$((lines - $(wc -l <"$SCRATCH/shown" | tr -d ' ')))" "$((bytes - shown))"
  return 0
}

rr_listing >"$SCRATCH/before"
rr_copy
TO=(); if command -v timeout >/dev/null 2>&1; then TO=(timeout 60); else echo "review-repro.sh: no timeout(1) here — the recipe runs untimed" >&2; fi
# unset OLDPWD: cd sets it to the real worktree, a path the recipe could write through (verify-HEF-58 scan)
rc=0; (cd "$SCRATCH/w" && unset OLDPWD && ${TO[@]+"${TO[@]}"} bash "$SCRATCH/.hef-recipe.sh" </dev/null >"$SCRATCH/out" 2>&1) || rc=$?
rr_listing >"$SCRATCH/after"
rr_print "$rc" "$SCRATCH/out"
CHANGED="$(rr_changes "$SCRATCH/before" "$SCRATCH/after")"
[ -z "$CHANGED" ] && exit 0
printf '%s\n' "$CHANGED" >&2
echo "review-repro.sh: the recipe wrote into the worktree — record the candidate UNREPRODUCED with these paths" >&2
exit 3
