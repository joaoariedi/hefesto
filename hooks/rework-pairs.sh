# shellcheck shell=bash
# shellcheck disable=SC2034,SC2016  # REWORK_PAIRS_JQ is read by its loaders; a jq program, single-quoted on purpose
# rework-pairs.sh — the ONE rule "which answer of the person rules on which disputed finding" (verify-fix-loop, HEF-57
# FR-010, FR-012; plan P14). SOURCED, never run: by ledger-rework.sh (`record --rework-consumed` stamps the pairs on
# the row) and by session-launch-rework.sh (the rework prompt hands them in before anything is stamped). Two readers of
# one text cannot disagree — the repo's pattern for shared jq ($ENTRY_PRS, $JQ_LIVE_OWNER).
#
# The contract — prepend the text to a jq program whose input is ONE ledger entry:
#   rework_reopen_at → the `at` of the entry's last reopen event, or "" (no reopen)
#   rework_open_key  → the index in .reworks of the open row (unconsumed AND newer than the last reopen — a row left
#                      open across a reopen is closed, FR-013), the last such; null when there is none
#   rework_pairs     → an array, [] without an open row, of self-describing pairs
#                      {answer, answer_sha256, question_path, question_sha256}: the answer file and its hash as
#                      `ledger.sh answer` recorded them (.answers[i].path/.sha256), and the dispute question and its
#                      hash as `record --rework-asked dispute` recorded them (.reworks[k].asked[j].path/.sha256)
#
# The pairing: an unconsumed answer at index i is a ruling iff its kind is human:clarify AND the last asked[] entry of
# the open row with answers_before == i exists with dispute: true; it is paired with that entry.
# - Exact `== i`, never `<= i` (plan round 7, change 2): a blocked entry is never relaunched before it is answered, so
#   the block an answer clears is the one recorded with that answer's own index. A block whose asked[] record was lost
#   leaves its answer unpaired — never paired with an earlier dispute.
# - Ordinal, never by time: `at` has 1-second resolution and ties.
# - And by question (HEF-57 verify, review): the answer must name the dispute's own question file (`.question`, which
#   `ledger.sh answer` records from the block it clears). A same-kind block swapped in after the dispute, or an
#   answerless unblock that shifts the count, leaves the answer unpaired. An answer recorded before this field: none.
# - The kind test (round 6): an answer to a human:plan-review block a rework run reported is never a ruling, even
#   after a dispute; a worktree question (dispute: false) shields its own answer.
REWORK_PAIRS_JQ='
def rework_reopen_at: [(.events // [])[] | select(.kind == "reopen") | .at] | max // "";
def rework_open_key: rework_reopen_at as $r
  | [(.reworks // []) | to_entries[] | select(.value.consumed != true and (.value.at // "") > $r) | .key] | last;
def rework_pairs: rework_open_key as $k
  | if $k == null then [] else
      (.reworks[$k].asked // []) as $asked
      | [(.answers // []) | to_entries[]
         | select(.value.consumed != true and .value.kind == "human:clarify")
         | .key as $i | .value as $a
         | ([$asked[] | select(.answers_before == $i)] | last) as $q
         | select($q != null and $q.dispute == true and ($a.question // "") == $q.path)
         | {answer: $a.path, answer_sha256: $a.sha256, question_path: $q.path, question_sha256: $q.sha256}]
    end;
'
