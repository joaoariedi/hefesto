---
model: sonnet
description: "Management status brief — where we are, epic completion, at risk, bottom line — from the source .claude/project-status.json declares (a GitHub Project or a tasks repository)"
argument-hint: "[--detailed] [--check]"
---

# Status

Produce a **management-facing status brief** for this project from live numbers — never estimates.
The numbers come from one helper; this command adds the judgement. The source is whatever
`.claude/project-status.json` declares: a **GitHub Project** board, or a **tasks repository** whose
columns are markdown files (`TODO.md` / `DOING.md` / `DONE.md` / `BACKLOG.md`).

## Pre-Flight

> The commands in this section must be run with the Bash tool; they cannot be
> pre-executed in a `!` block. A `!` block is permission-checked before the
> CLAUDE_PLUGIN_ROOT variable is substituted, so it is rejected as "Contains
> expansion". Do not write that variable with a $ and braces here: it would be
> substituted into this note and the warning would read as nonsense.

Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/status-board.sh $ARGUMENTS`

If it exits non-zero, run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/status-board.sh --check`
and **stop**: report exactly which prerequisite is `[MISSING]` and the one-line fix it prints
(commonly no `.claude/project-status.json` yet — the helper prints an example for each source —
a missing `read:project` token scope, or a column file that moved). Do not guess numbers.

## Instructions

1. **Read the helper output.** It is the only source of figures in this brief. For a tasks
   repository it prints, per column, the item count and the sub-state distribution (📥 🔧 🧪 ✅ or
   the labels the config maps them to), the sections delivered this quarter, the quarter bounds and
   days left, and one bar per initiative scoreboard (plus feature directories only when the project
   opted in). For a GitHub Project it prints the board status distribution, one bar per epic from
   its sub-issue summary, and the roadmap quarter.

2. **Present, concisely, in four sections:**
   - **Where we are** — quarter, days left, delivered vs remaining, what is in flight now
     (`doing` items, or `In Progress` on the board).
   - **By epic / workstream** — each bar with done/total and, in a few words, what is left.
   - **At risk** — anything the numbers expose: an epic at 0 % with the quarter closing, items
     parked in `doing` with a sub-state that has not moved (e.g. still `on staging`), a backlog
     that outgrows todo, an initiative whose completed count has not changed since the last brief
     if you have one to compare with. Name the item ids.
   - **Bottom line** — one or two sentences a manager can repeat.

3. **`--detailed`** unfolds the columns (tasks repository: every item with id, sub-state, title) or
   the epics (GitHub Project: every sub-issue with marker, board phase, assignee). Reach for it when
   the ask is "what is left under X" or "who owns what", not for the summary.

4. **Configuration**, when the user asks how to point this at their project — the two shapes the
   helper accepts (only `source` is required; everything else has the default shown):

   ```json
   {"source":"github-project","owner":"<org>","project":103,"roadmap":"docs/product/roadmap.md","epic_prefix":"epic("}
   ```
   ```json
   {"source":"tasks-repo","root":"tasks",
    "columns":{"todo":"TODO.md","doing":"DOING.md","done":"DONE.md","backlog":"BACKLOG.md"},
    "item_heading":"^#{2,3} ","id_pattern":"[A-Z][A-Z0-9]+(-[A-Z0-9]+){1,4}",
    "done_section":"^## ([0-9]{4}-[0-9]{2}-[0-9]{2}) ",
    "epics":{"initiatives":"initiatives/*.md","specs":false},
    "states":{"📥":"intake","🔧":"in work","🧪":"on staging","✅":"shipped"},
    "quarter_start":null,"quarter_end":null}
   ```
   `epics.specs` stays `false` unless the project keeps its feature-directory checkboxes current —
   a shipped feature with open boxes would otherwise read as undelivered.

Cite the live numbers from the helper; keep it tight and factual.
