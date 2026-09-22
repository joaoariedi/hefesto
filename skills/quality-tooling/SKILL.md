---
name: "Quality Tooling by Language"
description: |
  Lint, format, type-check, test, and security commands per language
  (JavaScript/TypeScript, Python, Rust, Go, Java), plus the tiered validation
  strategy, RTK CLI output compression, and structured pre-commit hooks
  (Lefthook). Load when running quality checks or choosing a project's
  lint/format/test commands.
when_to_use: |
  "how do I lint/format/typecheck this", "test command for <language>",
  "pre-commit or CI quality gates", "reduce tool output", "RTK", "Lefthook"
---

# Quality Tooling by Language

## Tool Detection
- Use Glob to find config files: `**/.eslintrc*`, `**/pyproject.toml`, `**/biome.json`, etc.
- Check `package.json` scripts section for available commands
- Look for common patterns: `lint`, `test`, `typecheck`, `format`
- Ask user for commands if not obvious

## Universal (Language-Agnostic)
- **Secrets detection**: `gitleaks detect` (pre-commit), `trufflehog filesystem .` (with live credential verification)
- **SAST**: `semgrep scan` — pattern-based static analysis across 30+ languages, runs in milliseconds
- **SBOM generation**: `syft .` (CycloneDX/SPDX), then `grype <sbom>` for vulnerability matching
- **All-in-one scanning**: `trivy fs .` — combines SCA, secrets, IaC, and SBOM in one tool
- Config files: `.gitleaks.toml`, `.semgrep.yml`, `.trivyignore`

## AI-Code Defect Profile — Gates That Match How Agent Code Actually Fails

Agent-written code is measurably more **duplicated**, more **dead**, more **error-swallowing**, and
more **over-mocked** than human code — and not more complex (GitClear 2025/2026; arXiv 2508.21634;
arXiv 2602.00409). Cyclomatic gates therefore catch the least of it. Add these, as **delta** gates
(fail on what the change *added*, never on pre-existing debt):

| Defect | Tool | Recipe |
|---|---|---|
| New duplication | `jscpd` (any language) | `jscpd --min-lines 10 --exitCode 1 .` with a committed `.jscpd.json` ignore list as the baseline; v5 ships SARIF |
| Dead code | `knip` (JS/TS), `vulture` (Python), `deadcode` (Go), `ruff --select F401,F841` | run on the diff's files; brownfield needs a one-time ignore list |
| Swallowed errors | `ruff --select BLE001,S110,S112`, eslint `no-empty`, Go `errcheck` | an empty handler added to make a check pass is blocking |
| Patch coverage | `diff-cover coverage.xml --compare-branch=origin/main --fail-under=80` | gates the changed lines; the total stays visible, non-blocking |
| Weak assertions | mutation testing (`mutmut`, Stryker) | the ratchet lives in `/hef.mutate` (6.2) |
| Complexity drift | `radon cc` / `xenon`, eslint `complexity`, `gocyclo`, `lizard` (polyglot) | fail when a changed function's CC rose by ≥3, not on an absolute cap |

Hallucinated packages: install only from the lockfile in CI, and treat a dependency that did not
exist in the lockfile before the change as a review item (5–22% of LLM-suggested packages do not
exist; the names repeat across runs, so they are squattable — USENIX Security 2025).

## CLI Output Compression (RTK) — Use When Available

`rtk` is a CLI proxy that strips boilerplate, deduplicates repeated lines, and groups
errors from common developer tools, typically reducing tool-output tokens by 60–90%.
Token output is the single largest consumer of the context window in agent sessions,
so this is the highest-leverage context-window optimization in the framework.

**Detection first, fallback always.** RTK is an optional optimization — the framework
never *requires* it. Before invoking, detect availability and fall back to the plain
command if not installed:

```bash
# Inline pattern
command -v rtk >/dev/null 2>&1 && rtk pytest -q || pytest -q

# Or use the framework helper (plugin install: the path is substituted for you)
"${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh" rtk-available \
  && rtk pytest -q \
  || pytest -q
```

Agents SHOULD prefer `rtk <cmd>` when `rtk-available` returns `RTK_AVAILABLE`, especially
for these high-savings commands (per RTK's documented compression):

| Command | Typical savings | Use case |
|---------|-----------------|----------|
| `rtk git add/commit/push/status` | 80–92% | Workflow sync noise |
| `rtk git diff` | ~75% | Condensed hunks |
| `rtk pytest` / `rtk go test` / `rtk cargo test` | ~90% | Failure-focused test output |
| `rtk golangci-lint` / `rtk ruff check` | 80–85% | Grouped lint findings |
| `rtk docker ps` / `rtk ls` / `rtk tree` | 80% | Directory and container summaries |
| `rtk cat` / `rtk read` | ~70% | Strips boilerplate from file reads |

**Do NOT install or assume rtk is present.** If it is missing on the user's machine,
continue with the plain tool — this is a silent, non-blocking enhancement. Never add
`rtk` as a required dependency in hooks, CI, or project scripts without the user's
explicit opt-in.

## JavaScript/TypeScript
- Config files: `package.json`, `.eslintrc*`, `tsconfig.json`, `biome.json`
- Lint: `npm run lint` or `npx biome check .` (Biome: ~35x faster than ESLint+Prettier)
- Type check: `npm run typecheck`
- Format: `npm run format` or `npx biome format .`
- Test: `npm test`
- Security: `npm audit`, Snyk for deeper SCA
- Tools: ESLint, Prettier, Jest, Vitest — or **Biome** as unified lint+format replacement
- **Biome vs ESLint**: Prefer Biome for speed; use ESLint when plugin ecosystem needed (React hooks, specialized security rules)

## Python
- Config files: `pyproject.toml`, `requirements.txt`, `setup.py`
- Lint: `ruff check .` (replaces Flake8, isort, Bandit via `S` rules, pyupgrade)
- Type check: `mypy .` (deep analysis) or `pyright .` (faster, better IDE integration)
- Format: `ruff format .` (Black-compatible, 10-100x faster)
- Security: `ruff check --select S .` (Bandit rules) or `bandit -r .` for standalone
- Test: `pytest`
- Virtual environment detection

## Rust
- Config files: `Cargo.toml`, `Cargo.lock`
- Lint: `cargo clippy`
- Format: `cargo fmt`
- Security: `cargo audit`
- Test: `cargo test`
- Check workspace configuration

## Go
- Config files: `go.mod`, `go.sum`, `Makefile`
- Lint: `golangci-lint run` (preferred, orchestrates 50+ linters including staticcheck, errcheck, revive)
- Format: `go fmt ./...`
- Security: `gosec ./...` (AST-based SAST), `govulncheck ./...` (reachability-based SCA — only flags vulnerabilities in actually-called code)
- Dead code: `deadcode ./...` (traces call graph from main), `ineffassign ./...`
- Test: `go test -race ./...`
- Check module structure and build tools

## Java
- Config files: `pom.xml` (Maven), `build.gradle`/`build.gradle.kts` (Gradle)
- Lint: Checkstyle (style), PMD (code smells, dead code), SpotBugs (bytecode analysis)
- Format: `mvn spotless:apply` or `./gradlew spotlessApply` (fast, pre-commit friendly)
- Type safety: Error Prone (compile-time bug catching, zero overhead)
- Security: SpotBugs + FindSecBugs plugin, SonarQube
- Test: `mvn test` or `./gradlew test`
- **Note**: JVM startup makes full builds too slow for pre-commit; use Spotless for hooks, full suite in CI

## Other Languages
- Examine project files to understand toolchain
- Ask user for specific quality commands if unclear
- Adapt patterns to match existing project structure

## Tiered Validation Strategy

### Tier 1: Pre-commit (<5 seconds)
Block obvious mistakes before they reach the repository:
- Universal: `gitleaks detect --staged` for secrets
- Python: `ruff check`, `ruff format --check`
- Go: `gofmt`, `goimports`
- JS/TS: `biome check` or `eslint` + `prettier`
- Java: `spotlessApply`
- Rust: `cargo fmt --check`

### Tier 2: Pull Request (CI)
Deep semantic analysis on every PR:
- Python: `mypy`/`pyright`, `bandit`, `semgrep`
- Go: `golangci-lint` (full suite), `govulncheck`
- JS/TS: full ESLint suite, `npm audit`, Snyk
- Java: PMD, Checkstyle, SpotBugs
- Universal: `semgrep scan`, `trivy fs .`

### Tier 3: Release (Compliance)
Artifact integrity and supply chain verification:
- SBOM: `syft` for generation, `grype` for vulnerability matching
- Container: `trivy image <image>`
- Signing: Sigstore for artifact provenance
- Monitoring: Dependency-Track or SonarQube for continuous tracking

## Structured Hook Alternatives

### Lefthook (Recommended for Teams)
- Declarative YAML configuration (`lefthook.yml`) vs imperative bash scripts
- Parallel execution of independent checks at pre-commit
- `{staged_files}` variable for incremental, staged-files-only linting
- Glob filtering: only lint files matching `*.rb`, `*.py`, etc.
- Install: `npm install lefthook --save-dev` or `brew install lefthook`
- Example:
  ```yaml
  pre-commit:
    parallel: true
    commands:
      lint:
        run: bundle exec rubocop {staged_files}
        glob: "*.rb"
      secrets:
        run: gitleaks detect --staged
  pre-push:
    commands:
      tests:
        run: bundle exec rails test
  ```

### Pre-commit vs Pre-push Separation
- **Pre-commit** (< 5 seconds): formatting, staged-file linting, secrets detection
- **Pre-push** (thorough): full test suite, comprehensive lint, dependency audit
- Rationale: fast pre-commit reduces friction; thorough pre-push catches deeper issues

### Staged-Files-Only Linting
- At pre-commit, lint ONLY staged files — not the entire project
- Prevents slow pre-commit hooks that discourage frequent commits
- Most tools support file list input: `ruff check <files>`, `eslint <files>`, `rubocop <files>`

## CI/CD Best Practices
- **`cancel-in-progress` concurrency**: Cancel redundant CI runs when new commits push to same branch
- **`fail-fast: false`** for cross-platform matrices: ensures visibility into all platform failures
- **`continue-on-error`** for dependency freshness: non-blocking `bundle outdated` / `npm outdated`
- **Screenshot artifacts on test failure**: `actions/upload-artifact` with `if: failure()` for system tests
- **Dependabot for github-actions**: not just language packages — keep CI actions up to date
- **Smart cache keys**: hash config files + lockfiles for cache invalidation (e.g., rubocop config + Gemfile.lock)
