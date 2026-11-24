#!/bin/bash
# review-replay.sh <base-sha> <head-sha> <spec> — the shared scaffold of the review replay evals (HEF-58
# exhaustive-review, FR-016/FR-017): builds, in the eval's empty CWD, a two-commit repository — `main` holds the whole
# tree of <base-sha>, `feature/<spec>` the whole tree of <head-sha> — so `/hefesto:hef.review code` resolves the spec
# from the branch and reviews exactly the change the original verify round rejected.
#
# Whole tree, deliberately (plan round 2, change 11): `.claude/` and CLAUDE.md included — the original reviews ran
# under that project config, so the replay keeps it. The eval sandbox denies the `git` binary to the model
# (evals/README.md), so the change is also written to .git/hef-review.diff, which the finder brief names.
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[ $# -eq 3 ] || { echo "review-replay: usage: review-replay.sh <base-sha> <head-sha> <spec> (got $# arguments)" >&2; exit 2; }
base=$1 head=$2 spec=$3
for c in "$base" "$head"; do
  git -C "$R" cat-file -e "$c^{commit}" 2>/dev/null \
    || { echo "review-replay: commit $c is not in $R — a shallow clone? fetch main's full history" >&2; exit 1; }
done
# Amendment A4: the eval home is fresh, and review-repro.sh refuses without $HOME/.cache/hefesto to probe the sandbox
# with — the scaffold runs as the person (--scaffold), so it can make it.
mkdir -p "$HOME/.cache/hefesto"
export GIT_AUTHOR_NAME=hefesto-eval GIT_AUTHOR_EMAIL=eval@example.invalid \
       GIT_COMMITTER_NAME=hefesto-eval GIT_COMMITTER_EMAIL=eval@example.invalid
git init -q -b main .
git -C "$R" archive "$base" | tar -x
git add -A && git commit -qm base
git checkout -qb "feature/$spec"
git ls-files -z | xargs -0 rm -f
git -C "$R" archive "$head" | tar -x
git add -A && git commit -qm "change under review"
git diff main...HEAD > .git/hef-review.diff
