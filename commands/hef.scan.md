---
model: opus
description: "Quick security scan of current changes — --deps adds the dependency section: new direct dependencies and the installed auditors' findings"
argument-hint: "[--deps]"
---

Perform a quick security review of the current changes.

> **Scope note.** This is the *fast, changes-only* scan. For a full review of every pending
> change on the branch, use the built-in `/security-review` skill instead. This command exists
> because it is narrower and cheaper: staged/unstaged diff only, with the checklist below.
> `--deps` is the one exception to "fast and offline": the auditors it runs need the network and can
> take minutes (a govulncheck build). None of them installs what it audits — pip-audit runs only on
> pinned requirements with `--no-deps --disable-pip`.

## Scope
Focus on staged and unstaged changes:
1. Run `git diff --staged` and `git diff` to identify changed files
2. Apply the checklist below to those changes only

## Checklist
- [ ] No hardcoded secrets, API keys, or passwords in code
- [ ] No sensitive data in committed files
- [ ] SQL queries use parameterized statements
- [ ] User input is validated and output is encoded
- [ ] Auth/authz patterns follow existing project conventions
- [ ] New dependencies checked for known vulnerabilities — with `--deps`, the `## Dependencies` section below

## Automated Tool Checks (if available)
- **Secrets**: `gitleaks detect --staged` — scans for 150+ secret types
- **SAST**: `semgrep scan --config auto` — cross-language pattern-based security analysis
- **SCA**: language-specific dependency scanning:
  - Go: `govulncheck ./...` (reachability-based — only flags actually-called vulnerable code)
  - JS/TS: `npm audit`
  - Python: `pip-audit`
  - Rust: `cargo audit`
  - Java: OWASP Dependency-Check

## Dependencies — only when `--deps` is in **$ARGUMENTS** (board item HEF-9)

1. Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh deps-diff` — every direct
   dependency the branch adds, re-versions or removes, one line each (`added npm left-pad ^1.3.0`;
   ecosystems `npm`, `pypi`, `crates`, `go`). Non-zero → report its line; the rest of the scan stands.
2. Run with the Bash tool (timeout 600000): `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh deps-audit`
   — one line per auditor that ran (`<tool> exit <rc> findings <n|unknown> report <path>`), one
   `missing <ecosystem>: <tool> (<install hint>)` per ecosystem without one. Exit 0 = every auditor
   clean; 1 = findings, or a count it could not read (`unknown` is never clean — open the report);
   3 = no auditor could run.
3. Add a `## Dependencies` section to the report:
   - **Every `added` dependency is a review item** (llm-security.md, supply chain): confirm it exists on
     its registry and is the package you meant — 5–22 % of LLM-suggested names do not exist and are
     squattable; a near-miss name (`reqeusts`) is CRITICAL until disproven.
   - **Findings**, read from each report: a known vulnerability in a dependency this branch ADDED or
     re-versioned → **HIGH**; in one it did not touch → **MEDIUM**, documented and tracked; `unknown` →
     name the tool and the report path for a person to read.
   - **Missing auditors** as a note with the install hint; exit 3 → the section says "unaudited — no
     auditor installed" and names them. No change and no findings → one line: "dependencies: no change,
     no findings".

## Report Format
- **CRITICAL**: Block merge immediately (active secrets, exploitable RCE)
- **HIGH**: Require remediation before merge (SQLi, auth bypass, reachable CVEs)
- **MEDIUM**: Document and track (XSS, missing validation)
- **LOW**: Note for future improvement
- With `--deps`: the `## Dependencies` section (new dependencies, findings by severity, missing auditors)

Note: For full incident response, threat hunting, or forensic investigation, use the `forensic-specialist` agent instead.
