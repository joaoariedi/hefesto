---
model: opus
description: "Quick security scan of current changes"
---

Perform a quick security review of the current changes.

> **Scope note.** This is the *fast, changes-only* scan. For a full review of every pending
> change on the branch, use the built-in `/security-review` skill instead. This command exists
> because it is narrower and cheaper: staged/unstaged diff only, with the checklist below.

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
- [ ] New dependencies checked for known vulnerabilities

## Automated Tool Checks (if available)
- **Secrets**: `gitleaks detect --staged` — scans for 150+ secret types
- **SAST**: `semgrep scan --config auto` — cross-language pattern-based security analysis
- **SCA**: language-specific dependency scanning:
  - Go: `govulncheck ./...` (reachability-based — only flags actually-called vulnerable code)
  - JS/TS: `npm audit`
  - Python: `pip-audit`
  - Rust: `cargo audit`
  - Java: OWASP Dependency-Check

## Report Format
- **CRITICAL**: Block merge immediately (active secrets, exploitable RCE)
- **HIGH**: Require remediation before merge (SQLi, auth bypass, reachable CVEs)
- **MEDIUM**: Document and track (XSS, missing validation)
- **LOW**: Note for future improvement

Note: For full incident response, threat hunting, or forensic investigation, use the `forensic-specialist` agent instead.
