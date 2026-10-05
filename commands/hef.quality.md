---
model: opus
description: "Run comprehensive quality checks"
---

Use the Task tool to spawn a quality-guardian agent with model: "opus" to run all available quality checks.

## Quality Checks

### 0. Secrets Detection (Mandatory First)
- **All projects**: `gitleaks detect` (if available) — block on any findings

### 1. Linting
Detect and run available linters:
- **JavaScript/TypeScript**: `npm run lint`, `npx biome check .` (if biome.json present), or `npx eslint .`
- **Python**: `ruff check .`
- **Rust**: `cargo clippy`
- **Go**: `golangci-lint run` (preferred, 50+ linters) or `go vet ./...`
- **Java**: Checkstyle, PMD (`mvn pmd:check`), SpotBugs (`mvn spotbugs:check`)

### 2. Type Checking
Run type validation:
- **TypeScript**: `npm run typecheck` or `npx tsc --noEmit`
- **Python**: `mypy .` (deep) or `pyright .` (faster)
- **Rust**: `cargo check`
- **Go**: Built into compilation
- **Java**: Error Prone (compile-time)

### 3. Formatting
Check code formatting:
- **JavaScript/TypeScript**: `npx biome format --check .` or `npx prettier --check .`
- **Python**: `ruff format --check .`
- **Rust**: `cargo fmt --check`
- **Go**: `gofmt -l .`
- **Java**: `mvn spotless:check` or `./gradlew spotlessCheck`

### 4. Security & Supply Chain
- **SAST**: `semgrep scan --config auto` (cross-language, if available)
- **Go**: `govulncheck ./...` (reachability-based SCA)
- **JS/TS**: `npm audit`
- **Rust**: `cargo audit`
- **Python**: `pip-audit` or `ruff check --select S .`

### 5. Tests
Run test suite:
- **JavaScript/TypeScript**: `npm test`
- **Python**: `pytest`
- **Rust**: `cargo test`
- **Go**: `go test -race ./...`
- **Java**: `mvn test` or `./gradlew test`

### 6. Complexity Metrics
Check code complexity:
- Functions > 50 lines
- Files > 500 lines
- Cyclomatic complexity > 10

## Report Format

```
QUALITY REPORT
==============
Secrets:     [PASS/FAIL] - [findings]
Linting:     [PASS/FAIL] - [issues found]
Types:       [PASS/FAIL] - [errors]
Formatting:  [PASS/FAIL] - [files to format]
Security:    [PASS/FAIL] - [vulnerabilities]
Tests:       [PASS/FAIL] - [passed/failed/skipped]
Complexity:  [PASS/WARN] - [violations]

Overall:     [PASS/FAIL]
```
