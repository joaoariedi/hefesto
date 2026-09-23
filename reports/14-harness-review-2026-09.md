---
status: accepted
date: 2026-09-22
---

# Harness Review, September 2026: Toolbox, Drift, and the Evidence Behind Each Change

A structural audit of the framework's own commands, agents, skills, hooks, and rules, cross-checked
against three research tracks (harness capabilities per the official Claude Code docs; spec-to-code
drift practices; code-quality, security, documentation, and context-management evidence). **Adoption
status: accepted as the `harness-review-tiers` program** — Tier 1 shipped in 6.1.0, Tier 2 in
6.2.0, Tier 3 in 7.0.0; each tier's changelog entry cites this file, and
`.specify/specs/harness-review-tiers/` holds the spec, plan, and task list.

This file records the *findings and the evidence*. It does not restate what the rules now say —
where a finding is codified, it points at the rule, hook, or command.

**Sources:** the 2026-09-22 structural pass over this repository; `code.claude.com/docs/en/{hooks,skills,sub-agents}.md` (verified 2026-09-22); the studies and posts cited inline.
**Codified in:** `commands/speckit.verify.md`, `commands/hef.review.md`, `commands/hef.pr.md`, `hooks/implement-phase-test-guard.sh`, `hooks/session-start-context.sh`, `hooks/precompact-progress.sh`, `hooks/audit-config-change.sh`, `agents/{quality-guardian,test-specialist,review-coordinator,code-reviewer}.md`, `skills/{quality-tooling,mcp-security}/SKILL.md`, `.claude/rules/llm-security.md` (Tier 1); Tiers 2–3 per their changelog entries.

## Verdict

The framework's architecture is the one the evidence supports: mechanism over prose, a
deterministic workflow where the implementer never grades its own work, cost-tiered model routing,
an optional-lane doctrine for third-party tools. No better architecture surfaced. The gaps were in
**completeness**, not design:

1. The spec → implementation traceability chain ended in prose. `FR-NNN` ids flowed spec → tasks →
   a "coverage mapping" the model wrote about its own work; nothing mechanical tied requirements to
   tests after implementation.
2. Two of six agents (`code-reviewer`, `review-coordinator`) were reachable by no command. The
   documented chain `implement → code-reviewer → quality-guardian → review-coordinator` had no
   entry point for its first link.
3. Nothing stopped an agent from weakening a test to go green. `speckit.implement` said "never
   modify the test to make it pass" — prose.
4. The quality gate targeted complexity, which is the *least* AI-specific defect class.
5. The harness enforced quality on projects while being only structurally tested itself.
6. The toolbox was organized by origin (`hef.*` vs `speckit.*`), not by lifecycle; four of seven
   skills were reference knowledge presented as commands.

## Findings by area, with evidence

### Spec → code drift
- **Aggregate rules are not honored; named-file rules are.** A team audited a rule ("files under
  300 lines") present in all 17 revisions of their spec: 31% of files violated it; three rules that
  named specific files had 100% compliance in the same sessions. Diagnosis: "no single edit
  violates it." → aggregate rules become linters (Tier 2, `quality-before-commit.sh` delta gates).
  Source: heym.run/blog/spec-driven-development.
- **Post-implementation requirement coverage is the missing check in every SDD tool.** spec-kit's
  `analyze` maps FR → tasks before code exists; nothing maps FR → tests after. → `req-coverage`
  and `/speckit.verify`. Reference design: github.com/Antoine005/reqcov (borrowed, not depended on).
- **Ceremony must scale to task size.** Scott Logic measured spec-kit at roughly 10× slower than
  incremental prompting for one feature; Thoughtworks holds SDD at *Assess*. → `/hef.agent`
  becomes a size router (Tier 2). Sources: blog.scottlogic.com (2025-11-26),
  thoughtworks.com/radar/techniques/spec-driven-development.

### Testing
- **TDD instructions without a mechanism make agents worse.** TDAD on SWE-bench Verified: baseline
  regression 6.08%; procedural TDD instructions 9.94%; TDD plus a source→test map 1.82%. Kent Beck:
  agents delete tests to make them pass. → `implement-phase-test-guard.sh`; reachability map via
  graphify (Tier 2). Source: arxiv.org/abs/2603.17973.
- **Agents over-mock.** 36% of agent test commits add mocks vs 26% human, across 1.2M commits.
  → the mock budget in `test-specialist`. Source: arxiv.org/abs/2602.00409.
- **Coverage ≠ correctness; mutation score is the ratchet that measures assertions.** The
  framework's own memory already named it the highest-yield habit; it existed in no command.
  → `/hef.mutate` (Tier 2).

### Code quality
- **AI code's measured defect profile is duplication, dead code, error swallowing, over-mocking —
  not complexity.** GitClear (211M then 623M changed lines): copy/paste 8.3% → 12.3%, block
  duplication +81% since 2023, error-masking constructs +47%; arXiv 2508.21634 (500k samples):
  "simpler and more repetitive", more unused constructs. → `quality-guardian` and `quality-tooling`
  carry `jscpd`-baseline, dead-code, error-swallow, and `diff-cover` recipes as delta gates.
- **Hallucinated packages are squattable.** 5.2–21.7% of LLM-suggested packages do not exist; 58%
  repeat across runs (USENIX Security 2025, arxiv.org/abs/2406.10279). → lockfile-only installs,
  new-dependency review item.

### Security
- **A Bash deny rule is not a security boundary** — Claude Code's own docs say so. Live probe
  2026-09-22 of `block-destructive-commands.sh`: 8/10 bypass forms caught (`git -C`, `-c`, quoted
  verbs, short flags); `sh -c` and an absolute binary path pass, by the hook's documented threat
  model. → `/sandbox` documented as the boundary; the hook stays the seatbelt.
- **Prompt injection through PR titles, issue bodies, and hidden HTML comments hijacked three
  vendors' CI review agents** (CSA research note, 2026-04; CamoLeak CVE-2025-59145). → untrusted-input
  rule in every command that fetches such text.
- **Skills are a supply chain.** Snyk ToxicSkills: 3,984 skills, 36.8% flawed, 13.4% critical; a
  `` !` `` line in a `SKILL.md` executes before the model reasons (Reversec, 2026-05). → vetting
  checklist in `mcp-security`; `audit-config-change.sh`.
- OWASP GenAI LLM Top 10 2026 (2026-08-03) and Top 10 for Agentic Applications (2025-12-09) →
  `llm-security.md` refresh.

### Documentation and context
- **CLAUDE.md length folk wisdom is weak.** A 1,650-session factorial study (arXiv 2605.10039) found
  no detectable compliance effect from file size, position, nesting, or contradictions; compliance
  decays ~5.6% odds per function generated in a session. → do not shrink rules for their own sake;
  convert enforceable rules to hooks; keep sessions task-scoped.
- **The 40% "Dumb Zone" number has no controlled study behind it.** Chroma's context-rot and NoLiMa
  confirm early, monotonic degradation without a threshold. → the heuristic stays; the checkpoint
  becomes a `PreCompact` hook instead of a remembered ritual.
- **AGENTS.md** is the Linux Foundation-stewarded cross-tool standard → root shim (Tier 3).
- **ADR state must be machine-readable.** A 98-ADR repo had 59 misread by a fail-open parser →
  MADR frontmatter on `reports/` (Tier 3).

### Harness capabilities (official docs, verified 2026-09-22)
- Hook events available and unused before 6.1: `SessionStart`, `PreCompact`, `ConfigChange`,
  `SubagentStop`, `TaskCreated`, `WorktreeCreate`. `SessionStart` stdout is added to context.
- Subagent frontmatter supports `memory: user|project|local`, `isolation: worktree`, `skills`,
  per-agent `hooks`, `maxTurns`.
- `when_to_use` **is** a supported skill field; `commands/` remains supported ("prefer a skill for
  new work").
- `claude plugin eval` (CLI 2.1.278) runs each prompt with and without the plugin and exits
  non-zero under a threshold — a CI-gateable measure of whether the framework's prompts earn their
  keep (Tier 2).

### Parallel development
- 27.7% of 107k agent PRs conflicted; cross-agent pairs 41.7% vs same-agent 19.8%; 42% structural
  (add/add, modify/delete). → `owns:` file lists on `[P]` tasks, worktree isolation, a merge-tree
  probe, sequential merges by one lead (Tier 2). Sources: arxiv.org/abs/2604.03551,
  arxiv.org/abs/2607.04697.

## Rejected, with cause
Spec-as-source-of-truth (no field evidence; Thoughtworks *Assess*); AI-generated Gherkin as drift
control (vendor-only evidence); "AI slop" linters (hobby projects, no validation); SBOM as a
small-team default; GitHub merge queue (built for trunk contention this model does not have);
stacked-PR tooling (GitHub's preview can mark PRs merged on reorder); OpenAI's no-human-review
policy (7 engineers with per-worktree observability); Graft (`reports/13`).

## The program

| Tier | Version | Contents |
|---|---|---|
| 1 | 6.1.0 | `/speckit.verify` + `req-coverage`; `/hef.review`, `/hef.pr`; implement-phase test guard; SessionStart/PreCompact/ConfigChange hooks; AI-defect gates; mock budget; security refresh |
| 2 | 6.2.0 | `/hef.mutate`; aggregate rules → linters; `/hef.agent` router; `owns:` + worktree isolation + merge-tree probe; `/hef.release` + conventional commits; bats + shellcheck + `evals/` |
| 3 | 7.0.0 | `hef.sync` → `hef.doctor`; `hef.pr-summary` → `hef.pr`; knowledge skills `user-invocable: false`; MADR frontmatter + `/hef.adr`; `AGENTS.md`; `memory: project` on two agents |
