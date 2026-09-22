# Graft: Code-Context Graph for Agents, Evaluated Against the graphify Lane

Everything measured about [trailhq/Graft](https://github.com/trailhq/Graft) (`@nanonets/graft` 0.17.0, TypeScript, MIT, pre-1.0): what it is, where it would slot into the framework's optional provider lane next to graphify, and whether it is worth adopting. **Adoption status: evaluated 2026-09-06, not adopted.** Nothing described here is wired into the framework — no rule, hook, skill, or manifest entry references Graft, and the decision on record is that it does not add enough real gain over the existing graphify lane to justify a second code-graph tool now. It stays documented as a possible future enhancement.

This file does **not** cover the retrieval theory behind structural code graphs (cAST, HCAG — see `05-codebase-retrieval-at-scale.md`), the optional-lane doctrine itself (auto-detected, degrades silently, never in the manifest — see `context-management.md` and the PR #51 lesson), or MCP security posture in general (see `06-security-devsecops-for-agents.md` and the `mcp-security` skill).

**Sources:** source build of the clone at 0.17.0 (telemetry inert by construction), an empirical probe against a scratch clone of a 633-file Django repo, a `graft init --dry-run` and real run in that clone under an isolated `HOME` and `CLAUDE_CONFIG_DIR`, `TELEMETRY.md`, `docs/github-app.md`, and a file:line digest of `src/`.
**Codified in:** Not yet codified — evaluated here, not adopted.

## What Graft Is

A CLI that builds a persistent, human-readable context graph of a code repository so agents stop re-discovering the codebase every session. Three tiers: a deterministic tree-sitter pass (symbols, call edges, imports — no model, `$0`, offline), an optional per-file LLM summary pass, and an optional synthesis pass that groups summaries into curated concept nodes with typed links. Output is `graft/*.md` cards plus `graft/.graph/wiring.json`, auto-gitignored as a regenerable cache. It exposes the graph through a CLI (`ask`, `skeleton`, `callers`, `grep`, `map`, `blast`, `viz`), a hand-rolled stdio MCP server (six tools, advertised only when a graph exists), and Claude Code hooks (SessionStart orientation, UserPromptSubmit locator injection, PostToolUse refresh, Stop re-sync). A separate self-hostable GitHub App posts blast-radius reviews on pull requests using an installation token, which makes fork PRs first-class.

## Measured Against graphify on the Same Repository

The probe repo was a scratch clone of a Django backend (633 Python files) that already carried a graphify graph. Same machine, same question ("how does the celery refresh worker queue get routed and which tasks run on it").

| | Graft (structural tier) | graphify |
|---|---|---|
| Build | 5 s, `$0`, offline → 8,289 nodes / 21,103 edges, 37 MB | 9,425 nodes / 18,735 edges, 36 MB; community labeling costs API |
| Answer | 1 s, lexical rank: 8 exact symbols with `file:L-L` and signatures | 0 s, BFS neighborhood of 309 nodes truncated to 57 by the token budget |
| Freshness after an edit | auto-refreshed the one changed file before answering, 1 s | requires `graphify update .` |
| `skeleton <file>` | signatures only, ~90 % token reduction | no equivalent |
| `blast --base` | per-changed-symbol **test reachability** ("0/6 reached by a test") | no equivalent |
| Markdown, specs, docs | ignored — "12 changed files not in the graph" | first-class, plus cross-repo merged graphs |

Two capabilities are genuinely new to the framework: test reachability of changed symbols (nothing in the harness answers "which changed symbol does no test reach"), and a zero-cost symbol-level tier with automatic freshness. Everything else is a different presentation of what graphify already provides. Graft is code-only; the framework's own repository is markdown, so it would gain nothing there.

## What a Default `graft init` Writes, and Why It Cannot Run Here

Verified by a dry run and a real run inside the scratch clone with `HOME` and `CLAUDE_CONFIG_DIR` pointed at throwaway directories:

1. **Statusline.** It writes `statusLine` and `subagentStatusLine` into the repo's `.claude/settings.json`. Its "preserve a foreign statusline" logic only inspects that repo file, so the profile-level `claude-statusline` (the fxcube/mbq/sankofa identity indicator) is invisible to the check and gets shadowed by project settings in every repo without its own statusline. `--no-statusline` avoids it.
2. **Profile isolation.** Global mode writes `~/.claude/settings.json`, `~/.claude/helpers`, and `~/.claude.json` through `homedir()`. `CLAUDE_CONFIG_DIR` is honored only when *reading* existing hooks (`src/claude/hooks.ts:72`); with the variable set, the dry run still targeted `~/.claude`. From the bedrock or sankofa profile, a default init would write into the personal profile — the cross-profile poisoning class this framework isolated profiles to prevent. `--no-global` is mandatory.
3. **Project-local skill.** It installs `.claude/skills/graft/SKILL.md` in the repo, the layout that fails the framework's smoke shadow check — the same trap graphify hit before its skill moved to the global root.
4. **Unpinned MCP entry and broad allow.** `.mcp.json` becomes `npx -y @nanonets/graft mcp` (unversioned, auto-installed at session start) and the permissions allow-list gains `Bash(node dist/cli.js:*)`.
5. **Reply shaping.** Every CLI and MCP output appends an instruction telling the agent to end its reply with a "🌱 graft saved ~N tokens this turn" line (`src/context/savings.ts`), and the Stop hook tail-reads the transcript to count replies that comply. The text never leaves the machine, but this is the tool-poisoning-class pattern `llm-security.md` and the `mcp-security` skill flag: output that carries instructions.
6. **Hook overlap.** Five hook events, including per-prompt context injection, would run alongside graphify's `hook-guard` PreToolUse nudges in the same repo and give the agent two competing sources of "query the graph first" guidance.

## Telemetry, Data Egress, and Supply Chain

Telemetry is on by default and unusually well specified: `TELEMETRY.md` is a hard allowlist enforced in `src/telemetry/contract.ts`, every number is a bucket, every string a fixed enum, no paths, code, prompts, or symbol names are sent, and events go to Nanonets' own PostHog front door. Four independent off switches exist (`DO_NOT_TRACK`, CI detection, `graft telemetry disable`, and building from source, which compiles with an empty key). The npm `postinstall` records one install event and spawns a detached flush; it downloads nothing.

The README's "hard refusals for secrets and binaries" has no code behind it. The real controls are indirect: a gitignore-respecting file walk, a 1 MB size cap, and the extension allow-list. Because the deep pass ships tracked file contents to whichever `GRAFT_API_KEY` provider is configured (it cannot reuse Claude Code's session auth; the Anthropic default model is hardcoded to `claude-sonnet-5`, overridable via `GRAFT_MODEL`), a secret literal in tracked code would both be indexed and leave the machine. Only gitleaks-clean repositories qualify for the deep pass.

Eighteen runtime dependencies including native tree-sitter grammars, the Anthropic and OpenAI SDKs, and LSP protocol libraries; no runtime binary downloads (language servers are used only if already on `PATH`). 125 test files, roughly 1,188 cases. The org was renamed from NanoNets to trailhq and `SECURITY.md` still points at the old one. The repo's own `.claude/proven-config.json` references an unexplained `ruflo` schema that nothing in `src/` reads — a provenance oddity, not a risk.

## The Shape It Would Take If Ever Adopted

Recorded so the evaluation does not have to be repeated:

- A third optional-lane member beside rtk and graphify — never in `.claude-plugin/plugin.json`, auto-detected by the presence of `graft/.graph/wiring.json`.
- CLI-only surface taught through rules text, the way graphify is: `graft ask`, `callers`, `skeleton`, `blast`. No hooks, no statusline, no MCP registration — or, if MCP, pinned to an exact version and repo-scoped.
- `DO_NOT_TRACK=1` exported by the profile launcher.
- First and highest-value use: `graft blast --base origin/dev` as an advisory pull-request comment feeding `code-reviewer` and `quality-guardian`, either through the reusable CI workflow or the self-hosted GitHub App inside the tailnet.
- Pilot on one code-heavy repository against graphify on the same ten questions for two weeks; if adopted, split by repo type — Graft for code, graphify for docs, specs, and cross-repo graphs.

## Not Yet Adopted

The gain is real but narrow: one new review signal (test reachability) and a faster symbol-level answer on code repos. Against that stands a second graph tool to teach, keep fresh, and keep isolated per profile, plus six install-time behaviors that each need a flag or a manual strip to fit the framework. graphify already covers the retrieval need across every repo type the framework serves. The decision is to keep this record as prior art and revisit only if the blast-radius review signal becomes something a quality gate is missing in practice.
