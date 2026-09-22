---
name: "Pipeline Security Tooling"
user-invocable: false
description: |
  Reference for evaluating or recommending security tooling across the CI/CD
  pipeline: SAST, DAST, SCA, secrets, and ASPM platforms — managed services and
  open-source — chosen by team size, budget, and pipeline tier. Load when
  choosing or comparing security scanners for a project.
when_to_use: |
  "which SAST/DAST tool", "recommend a security scanner", "SCA or secrets tooling",
  "reachability analysis", "ASPM", or evaluating a project's security posture
---

# Pipeline Security Services & Tools Reference

Reference for the quality-guardian and forensic-specialist agents, and for the `/hef.security-scan` command, when recommending or evaluating security tooling.

## Application Security Posture Management (ASPM)

Modern pipelines consolidate SAST, DAST, SCA, and Secrets scanning into unified platforms. When evaluating a project's security posture, consider these categories.

## Managed Security Services

### Developer-First / Startups
| Service | Type | Focus |
|---------|------|-------|
| **Snyk Code** | SAST/SCA | Real-time IDE feedback, one-click PR auto-fixes (~$25/dev/month) |
| **Aikido Security** | SAST/DAST | Unified platform, noise reduction via reachability analysis (flat-rate) |
| **DeepSource** | SAST/Quality | Automated refactoring and autofixes in PRs (Python, Go, Node) |
| **SonarCloud** | SAST/Quality | "Clean as You Code" methodology, technical debt tracking |

### Enterprise / Compliance
| Service | Type | Focus |
|---------|------|-------|
| **Checkmarx One** | SAST/DAST | Enterprise-grade, customizable via CxQL for strict compliance |
| **Veracode** | SAST/DAST | Binary/bytecode analysis, lowest false positive rate (<1.1%) for regulated industries |
| **Cycode** | ASPM/SAST | AI-native "Maestro" engine, unifies third-party scanner data to prioritize fixes |

### AI-Native / Specialized
| Service | Type | Focus |
|---------|------|-------|
| **Corgea** | SAST (AI) | Finds business logic and auth flaws traditional tools miss, remediation-first (Java, Python) |
| **Semgrep Pro** | SAST | Adds reachability analysis to open-source engine (~$40/dev/month) |
| **StackHawk** | DAST | Purpose-built for API security (REST, GraphQL, gRPC) in CI/CD, fast scanning |

### Legacy Modernization (Java)
| Service | Type | Focus |
|---------|------|-------|
| **Byteable** | AI Analysis | AI-powered dead code detection in massive Java monoliths |
| **Moderne** | Migration | Automated Java version migrations (e.g., Java 8 to 21) |

## Open-Source Tools by Category

### SAST (Static Application Security Testing)
| Tool | Ecosystem | Use Case |
|------|-----------|----------|
| **Semgrep** | Universal (30+ languages) | Pattern-matching SAST, millisecond pre-commit gates |
| **Ruff** (`--select S`) | Python | Rust-based, replaces Flake8+Bandit+isort, 10-100x faster |
| **gosec** | Go | AST-based scanning for SQLi, weak crypto, hardcoded creds |
| **ESLint** + `eslint-plugin-security` | Node (JS/TS) | Pluggable SAST rules for JavaScript |
| **PMD / SpotBugs** | Java | Code smells (PMD) and bytecode vulnerability detection (SpotBugs) |

### DAST (Dynamic Application Security Testing)
| Tool | Ecosystem | Use Case |
|------|-----------|----------|
| **OWASP ZAP** | Universal | Industry-standard open-source web app and API scanner |

### Secrets Detection
| Tool | Ecosystem | Use Case |
|------|-----------|----------|
| **Gitleaks** | Universal | High-performance, Git history + pre-commit, 150+ secret types, SARIF output |
| **TruffleHog** | Universal | Live credential verification against provider APIs |

### Dead Code Detection
| Tool | Ecosystem | Use Case |
|------|-----------|----------|
| **Knip** | Node (JS/TS) | Detects unused files, exports, and dependencies in modern JS frameworks |
| **deadcode** | Go | Official Go tool, unreachable function detection via call graph analysis |
| **PMD** | Java | Unused variables, dead code paths, empty catch blocks |
| **Ruff** (`F811`, `F841`) | Python | Unused imports and variables (fast, but shallow) |

## Strategic Selection Guide

### By Team Size & Budget
- **Startups / fast-moving teams**: Aikido or Snyk (freemium entry, easy setup)
- **Large enterprises / regulated**: Checkmarx One or Veracode (compliance focus, managed accuracy)
- **Performance-centric CI/CD**: Semgrep Pro + StackHawk (fast, reachability filtering)
- **Legacy Java modernization**: Byteable or Moderne (AI-driven dead code + migration)

### By Pipeline Tier (align with the `quality-tooling` skill's tiers)
- **Tier 1 (Pre-commit)**: Gitleaks, Semgrep (open-source), Ruff security rules, gosec
- **Tier 2 (PR/CI)**: Snyk Code, SonarCloud, OWASP ZAP, Knip, govulncheck, full golangci-lint
- **Tier 3 (Release)**: Veracode/Checkmarx (compliance), SBOM with Syft+Grype, Sigstore signing

### Reachability Analysis (Noise Reduction)
Prefer tools that filter by reachability over raw CVE lists:
- **Go**: `govulncheck` (built-in, analyzes call graph)
- **Managed**: Aikido, Semgrep Pro, Cycode (AI-driven prioritization)
- **Rationale**: Reduces developer alert fatigue by focusing on exploitable vulnerabilities only
