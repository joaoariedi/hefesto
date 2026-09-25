# Plan: status-board
<!-- Light path: written without the plan-review gate (user decision 2026-09-25); design decisions
     were taken in the spec's clarifications. -->
<!-- Date: 2026-09-25 -->

## Approach
One helper, one command, two sources. `hooks/status-board.sh` is a fetcher in the
`speckit-helper.sh` sense: it prints the board on stdout at exit 0, or a reason on stderr at
non-zero, never a sentinel. `commands/hef.status.md` runs it with the Bash tool and adds the
judgement sections. The github-project source is batuta's `scripts/project-status.sh` with the
three constants (`OWNER`, `PROJECT`, `ROADMAP`) and the `epic(` prefix moved into the config; the
tasks-repo source is new.

## Config — `.claude/project-status.json`
```json
{ "source": "github-project", "owner": "Humanapis", "project": 103,
  "roadmap": "docs/product/roadmap.md", "epic_prefix": "epic(" }
```
```json
{ "source": "tasks-repo", "root": "tasks",
  "columns": { "todo": "TODO.md", "doing": "DOING.md", "done": "DONE.md", "backlog": "BACKLOG.md" },
  "item_heading": "^#{2,3} ", "id_pattern": "[A-Z][A-Z0-9]+(-[A-Z0-9]+){1,4}",
  "done_section": "^## ([0-9]{4}-[0-9]{2}-[0-9]{2}) ",
  "epics": { "initiatives": "initiatives/*.md", "specs": false },
  "states": { "📥": "intake", "🔧": "in work", "🧪": "on staging", "✅": "shipped" },
  "quarter_start": null, "quarter_end": null }
```
`root` is relative to the repo root; every other path is relative to `root`. Only `source` is
required; every other key has the default shown. Config is read with `jq`; a parse error is a
fetcher failure.

## Helper structure — `hooks/status-board.sh`
- CLI: `[--check|--detailed] [--config <path>]`; unknown option exits 2.
- `load_config` → validates `source` ∈ {github-project, tasks-repo}; missing file → stderr example
  for both sources, exit 1 (FR-001, FR-002).
- `preflight_<source>` → the `[ok]/[MISSING]` checklist; in run mode silent unless missing (FR-003).
- `render_header`, `bar` shared (batuta's 10-cell bar).
- `source_github` → batuta's logic parameterised (FR-004, FR-005).
- `source_tasks` → `column_items <file>` (headings matching `item_heading` with an `id_pattern`
  hit; leading marker = first token when it is not part of the id), `done_this_quarter`,
  `quarter_bounds` (calendar unless overridden), `initiative_epics` (dominant prefix per file;
  completed = `~~ID~~` or a line with ✅), `spec_epics` (only when `epics.specs` is true)
  (FR-006…FR-012).
- Bottom line: doing / todo / backlog counts, delivered this quarter, days left.
- Zero-install: bash, jq, git, grep/awk/sed/date; `gh` only for github-project (FR-014).

## Command — `commands/hef.status.md`
`model: sonnet` (mechanical: runs the helper, formats). Pre-flight runs the helper; on failure runs
`--check`, reports its findings, stops. Sections: where we are · by epic · at risk (items in DOING
with no movement marker, epics at 0 %, backlog growth, quarter days left vs remaining) · bottom line.
`--detailed` passes through (FR-013).

## Tests — `tests/smoke.sh`
- tasks-repo fixture: temp dir with the four files (headings with and without ids, markers,
  DONE sections dated in and out of the quarter), `initiatives/perf.md` (struck and unstruck ids),
  `.specify/specs/x/tasks.md` (mixed boxes), config with `specs: false` then `true`.
- github-project fixture: a fake `gh` on PATH that records argv and returns canned JSON for
  `project item-list`, `api graphql` (sub-issue summaries), `auth status`, `project view`; assert on
  the calls made and on the rendered totals (constitution 3: tool-call level).
- Failure cases: no config, unknown source, missing column file → non-zero, empty stdout.
- Mutations: id requirement removed (lane headings counted), quarter filter removed, strike-through
  detection removed, specs gate removed, missing-file check removed — each must go red.

## Files
`hooks/status-board.sh` (new) · `commands/hef.status.md` (new) · `tests/smoke.sh` ·
`docs/commands.md` · `docs/hooks.md` (helper row) · `README.md` (toolbox table) ·
`.claude/CLAUDE.md` (tier list: `hef.status` under sonnet) · `CHANGELOG.md` at release.

## Out of scope
Writing the two project configs (batuta, fxcube) — those land in their own repos, from their own
sessions, using the examples above. Retiring the dotfiles `project-status` command — the user's
dotfiles, after `/hef.status` is installed.

## Risks
- Heading heuristics on free-form kanban files: mitigated by configurable patterns and a hand
  count in SC-002.
- `gh` sub-issue GraphQL fields may change: same exposure batuta already carries; `--check` names it.
