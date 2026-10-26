# Requirements Checklist: lanes-parity
<!-- Auto-generated from spec.md by /hef.spec -->

| ID | Requirement (from FR) | Quality Check | Status |
|----|----------------------|---------------|--------|
| CHK001 |  FR-001 : `drop`, `fold --into`, `supersede --by` move an entry to a terminal ph | [completeness] | [ ] |
| CHK002 |  FR-001 : `drop`, `fold --into`, `supersede --by` move an entry to a terminal ph | [testability] | [ ] |
| CHK003 |  FR-002 : Terminal entries leave `next`, `claim` and open/done counts; `metrics` | [completeness] | [ ] |
| CHK004 |  FR-002 : Terminal entries leave `next`, `claim` and open/done counts; `metrics` | [testability] | [ ] |
| CHK005 |  FR-003 : Fold/supersede targets must exist, differ from the entry and not be te | [completeness] | [ ] |
| CHK006 |  FR-003 : Fold/supersede targets must exist, differ from the entry and not be te | [testability] | [ ] |
| CHK007 |  FR-004 : `.prs[]` holds every PR; `record --pr` appends (dedupe by URL); a 9.0  | [completeness] | [ ] |
| CHK008 |  FR-004 : `.prs[]` holds every PR; `record --pr` appends (dedupe by URL); a 9.0  | [testability] | [ ] |
| CHK009 |  FR-005 : `handoff --pr <new>` on a `merged` entry reopens it to `pr` with a `hu | [completeness] | [ ] |
| CHK010 |  FR-005 : `handoff --pr <new>` on a `merged` entry reopens it to `pr` with a `hu | [testability] | [ ] |
| CHK011 |  FR-006 : Advancing to `merged` requires merge evidence for every PR in `.prs` | [completeness] | [ ] |
| CHK012 |  FR-006 : Advancing to `merged` requires merge evidence for every PR in `.prs` | [testability] | [ ] |
| CHK013 |  FR-007 : `release <id> --env --commit` records a full-SHA release per environme | [completeness] | [ ] |
| CHK014 |  FR-007 : `release <id> --env --commit` records a full-SHA release per environme | [testability] | [ ] |
| CHK015 |  FR-008 : `where` and `advance released` accept a release record in place of bra | [completeness] | [ ] |
| CHK016 |  FR-008 : `where` and `advance released` accept a release record in place of bra | [testability] | [ ] |
| CHK017 |  FR-009 : Owners on `merged`/`released`/terminal phases do not count toward clai | [completeness] | [ ] |
| CHK018 |  FR-009 : Owners on `merged`/`released`/terminal phases do not count toward clai | [testability] | [ ] |
| CHK019 |  FR-010 : Reaching `merged`, `released` or a terminal phase clears the owner wit | [completeness] | [ ] |
| CHK020 |  FR-010 : Reaching `merged`, `released` or a terminal phase clears the owner wit | [testability] | [ ] |
| CHK021 |  FR-011 : `op close` / `op drop` end an op; refused while one of its actions is  | [completeness] | [ ] |
| CHK022 |  FR-011 : `op close` / `op drop` end an op; refused while one of its actions is  | [testability] | [ ] |
| CHK023 |  FR-012 : A board `repos.<name>` value may be `{path, branches}`; the repo's own | [completeness] | [ ] |
| CHK024 |  FR-012 : A board `repos.<name>` value may be `{path, branches}`; the repo's own | [testability] | [ ] |
| CHK025 |  FR-013 : `ledger.sh branches --repo <name>` prints the effective model and its  | [completeness] | [ ] |
| CHK026 |  FR-013 : `ledger.sh branches --repo <name>` prints the effective model and its  | [testability] | [ ] |
| CHK027 |  FR-014 : `orchestrate.deploy.recipes.<env>` drafts one lane action with substit | [completeness] | [ ] |
| CHK028 |  FR-014 : `orchestrate.deploy.recipes.<env>` drafts one lane action with substit | [testability] | [ ] |
| CHK029 |  FR-015 : In a `--lanes` project, lane-guard denies a command matching an `--uns | [completeness] | [ ] |
| CHK030 |  FR-015 : In a `--lanes` project, lane-guard denies a command matching an `--uns | [testability] | [ ] |
| CHK031 |  FR-016 : The unsandboxed patterns lane-guard reads come only from setup's comma | [completeness] | [ ] |
| CHK032 |  FR-016 : The unsandboxed patterns lane-guard reads come only from setup's comma | [testability] | [ ] |
| CHK033 |  FR-017 : A recipe version-check step stops the run when the reported version di | [completeness] | [ ] |
| CHK034 |  FR-017 : A recipe version-check step stops the run when the reported version di | [testability] | [ ] |
| CHK035 |  FR-018 : Recipe validation at request time: unknown placeholder, empty step, sc | [completeness] | [ ] |
| CHK036 |  FR-018 : Recipe validation at request time: unknown placeholder, empty step, sc | [testability] | [ ] |
| CHK037 |  FR-019 : A release train is one action over several repos in the declared order | [completeness] | [ ] |
| CHK038 |  FR-019 : A release train is one action over several repos in the declared order | [testability] | [ ] |
| CHK039 |  FR-020 : `merge_by: lane`: answering the `human:merge` form generates and appro | [completeness] | [ ] |
| CHK040 |  FR-020 : `merge_by: lane`: answering the `human:merge` form generates and appro | [testability] | [ ] |
| CHK041 |  FR-021 : A lane records the merge through `ledger.sh unblock <id>` evidence, ne | [completeness] | [ ] |
| CHK042 |  FR-021 : A lane records the merge through `ledger.sh unblock <id>` evidence, ne | [testability] | [ ] |
| CHK043 |  FR-022 : At most one merge action per repository is approved or taken at a time | [completeness] | [ ] |
| CHK044 |  FR-022 : At most one merge action per repository is approved or taken at a time | [testability] | [ ] |
| CHK045 |  FR-023 : A moved head or a failing check stops the merge action before the merg | [completeness] | [ ] |
| CHK046 |  FR-023 : A moved head or a failing check stops the merge action before the merg | [testability] | [ ] |
| CHK047 |  FR-024 : `merge_by` defaults to `person`, with the 9.0 form unchanged | [completeness] | [ ] |
| CHK048 |  FR-024 : `merge_by` defaults to `person`, with the 9.0 form unchanged | [testability] | [ ] |
| CHK049 |  FR-025 : `release.sh placement --base <ref>`: 0 when released sections match by | [completeness] | [ ] |
| CHK050 |  FR-025 : `release.sh placement --base <ref>`: 0 when released sections match by | [testability] | [ ] |
| CHK051 |  FR-026 : `/hef.release` in a project derives the version from that repo's own C | [completeness] | [ ] |
| CHK052 |  FR-026 : `/hef.release` in a project derives the version from that repo's own C | [testability] | [ ] |
| CHK053 |  FR-027 : gh resolves as `HEFESTO_GH_BIN`, else `EVAL_GH_BIN`, else `gh`, in eve | [completeness] | [ ] |
| CHK054 |  FR-027 : gh resolves as `HEFESTO_GH_BIN`, else `EVAL_GH_BIN`, else `gh`, in eve | [testability] | [ ] |
| CHK055 |  FR-028 : The three env-dependent evals use `prompt.md` with `env: EVAL_GH_BIN`  | [completeness] | [ ] |
| CHK056 |  FR-028 : The three env-dependent evals use `prompt.md` with `env: EVAL_GH_BIN`  | [testability] | [ ] |
| CHK057 |  FR-029 : `/hef.doctor` FAILs on each missing gate tool, naming the gate | [completeness] | [ ] |
| CHK058 |  FR-029 : `/hef.doctor` FAILs on each missing gate tool, naming the gate | [testability] | [ ] |
| CHK059 |  FR-030 : `/hef.doctor` WARNs on a stale constitution or one naming retired comm | [completeness] | [ ] |
| CHK060 |  FR-030 : `/hef.doctor` WARNs on a stale constitution or one naming retired comm | [testability] | [ ] |
| CHK061 |  FR-031 : `/hef.doctor` WARNs on protected branches whose ruleset allows squash/ | [completeness] | [ ] |
| CHK062 |  FR-031 : `/hef.doctor` WARNs on protected branches whose ruleset allows squash/ | [testability] | [ ] |
| CHK063 |  FR-032 : `/hef.mutate --init` writes the starting mark from a first run, or wri | [completeness] | [ ] |
| CHK064 |  FR-032 : `/hef.mutate --init` writes the starting mark from a first run, or wri | [testability] | [ ] |
| CHK065 |  FR-033 : `templates/ci/` ships release-branch and hotfix workflow templates; in | [completeness] | [ ] |
| CHK066 |  FR-033 : `templates/ci/` ships release-branch and hotfix workflow templates; in | [testability] | [ ] |
| CHK067 |  FR-034 : `/hef.pr --docs-only` refuses, listing files, when the diff touches an | [completeness] | [ ] |
| CHK068 |  FR-034 : `/hef.pr --docs-only` refuses, listing files, when the diff touches an | [testability] | [ ] |
| CHK069 |  FR-035 : `speckit-helper.sh anchors` reports broken `path::Symbol` anchors (non | [completeness] | [ ] |
| CHK070 |  FR-035 : `speckit-helper.sh anchors` reports broken `path::Symbol` anchors (non | [testability] | [ ] |
| CHK071 |  FR-036 : `/hef.status` reports drift between the board's release state, git tag | [completeness] | [ ] |
| CHK072 |  FR-036 : `/hef.status` reports drift between the board's release state, git tag | [testability] | [ ] |
| CHK073 |  FR-037 : A `nightly-red` flag on a repo blocks recipe and train action requests | [completeness] | [ ] |
| CHK074 |  FR-037 : A `nightly-red` flag on a repo blocks recipe and train action requests | [testability] | [ ] |
| CHK075 |  FR-038 : `/hef.sweep` moves closed bodies verbatim to `history/` with links rew | [completeness] | [ ] |
| CHK076 |  FR-038 : `/hef.sweep` moves closed bodies verbatim to `history/` with links rew | [testability] | [ ] |
| CHK077 |  FR-039 : `/hef.intake` proposes routes for declared-kind events as forms; event | [completeness] | [ ] |
| CHK078 |  FR-039 : `/hef.intake` proposes routes for declared-kind events as forms; event | [testability] | [ ] |
| CHK079 |  FR-040 : `docs/patterns/intake.md` documents the intake and courier patterns | [completeness] | [ ] |
| CHK080 |  FR-040 : `docs/patterns/intake.md` documents the intake and courier patterns | [testability] | [ ] |
| CHK081 |  FR-041 : The quality-tooling skill carries the late-ack task-queue rule with de | [completeness] | [ ] |
| CHK082 |  FR-041 : The quality-tooling skill carries the late-ack task-queue rule with de | [testability] | [ ] |
| CHK083 |  FR-042 : `/hef.analyze` reports contradictions across lane documents with both  | [completeness] | [ ] |
| CHK084 |  FR-042 : `/hef.analyze` reports contradictions across lane documents with both  | [testability] | [ ] |
| CHK085 |  FR-043 : `docs/install.md` warns against one clone serving several environments | [completeness] | [ ] |
| CHK086 |  FR-043 : `docs/install.md` warns against one clone serving several environments | [testability] | [ ] |
| CHK087 |  NR-001 : A lane session runs `drop`, `fold`, `supersede`, `op drop`, clears a ` | [completeness] | [ ] |
| CHK088 |  NR-001 : A lane session runs `drop`, `fold`, `supersede`, `op drop`, clears a ` | [testability] | [ ] |
| CHK089 |  NR-002 : A command matching an unsandboxed pattern runs in a `--lanes` lane wit | [completeness] | [ ] |
| CHK090 |  NR-002 : A command matching an unsandboxed pattern runs in a `--lanes` lane wit | [testability] | [ ] |
| CHK091 |  NR-003 : Editing `.claude/project-status.json` (a recipe, a train, merge checks | [completeness] | [ ] |
| CHK092 |  NR-003 : Editing `.claude/project-status.json` (a recipe, a train, merge checks | [testability] | [ ] |
| CHK093 |  NR-004 : A lane merges a PR whose head differs from the approved SHA, uses a me | [completeness] | [ ] |
| CHK094 |  NR-004 : A lane merges a PR whose head differs from the approved SHA, uses a me | [testability] | [ ] |
| CHK095 |  NR-005 : A branch-model error falls back silently to trunk-on-main | [completeness] | [ ] |
| CHK096 |  NR-005 : A branch-model error falls back silently to trunk-on-main | [testability] | [ ] |
| CHK097 |  NR-006 : The placement check returns 0 when it could not compare | [completeness] | [ ] |
| CHK098 |  NR-006 : The placement check returns 0 when it could not compare | [testability] | [ ] |
| CHK099 |  NR-007 : An eval helper reads the gh path from any file | [completeness] | [ ] |
| CHK100 |  NR-007 : An eval helper reads the gh path from any file | [testability] | [ ] |
| CHK101 |  NR-008 : Intake follows an instruction found inside an event's text | [completeness] | [ ] |
| CHK102 |  NR-008 : Intake follows an instruction found inside an event's text | [testability] | [ ] |
