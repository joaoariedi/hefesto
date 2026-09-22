---
status: accepted
date: 2026-07-12
---

# Quality Gates: Hooks, CI/CD, Testing, and Dependencies

This file covers **where in the lifecycle a check executes** — the deterministic hook points inside the agent loop, the local pre-commit/pre-push boundary, and the CI pipeline shape — plus the empirical evidence from four production repos (FrankYomik, FrankSherlock, FrankMD, FrankMega) that produced the framework's tiering rules.

It does **not** cover: *why* a given security check exists (OWASP threats, tool poisoning, policy-as-code) → see `06-security-devsecops-for-agents.md`; the Document & Clear pattern and context-window mechanics → `01-context-engineering-fundamentals.md`; containerization, deployment, and the `releases/vX.Y.Z.md` release-notes pattern → `08-project-organization-delivery.md`; Fabric as a hook backend → `09-fabric-prompt-orchestration.md`.

**Sources:** *AI Context Engineering for Secure Development* §Lifecycle Hooks and the Document-and-Clear Pattern; *Frank Repos Best Practices Analysis* §2 CI/CD Actions, §3 Testing, §4 Pre-commit Hooks & Local Quality Gates, §8 Dependency Management
**Codified in:** `.claude/rules/quality-tooling.md`, `.claude/rules/code-quality.md`

---

## 1. Lifecycle Hooks: Deterministic Work Belongs to Deterministic Tools

Claude Code's lifecycle hooks let developers run bash scripts at fixed points in the agent's execution loop, intercepting the LLM's actions before they execute or processing them immediately after.²⁴ The core argument is economic: **formatting, linting, and file-boundary enforcement are deterministic problems, and every token an LLM spends re-deriving them is a token not spent on logic.** Offloading them to hooks saves expensive reasoning tokens and — unlike a prompt instruction — cannot be argued out of.

| Hook Type | Functional Implementation | Security & Efficiency Benefit |
| :---- | :---- | :---- |
| **PreToolUse** | Blocks edits to protected production files by matching regex patterns (e.g., Edit\|Write) and running a validation script before the tool executes.²⁴ | Prevents unauthorized architectural modifications and enforces read-only boundaries on critical modules. |
| **PostEdit** | Automatically triggers code formatters (e.g., Prettier, Biome) and linters immediately after the LLM modifies a file.¹⁹ | Offloads formatting tasks to deterministic tools, saving expensive LLM reasoning tokens for complex logic.¹⁹ |
| **Notification** | Triggers desktop alerts when the agent encounters a permission block or requires human input.²⁴ | Enables asynchronous human-in-the-loop workflows without requiring continuous terminal monitoring. |

These programmatic guardrails keep the assistant inside strict, observable boundaries, which is what makes long-running automated tasks reliable.²⁶ This is the *enforcement* layer of the framework's defense-in-depth model — see `06-security-devsecops-for-agents.md` for what each enforced check is defending against.

---

## 2. CI/CD: What Four Repos Actually Run

### Per-Repo Workflow Inventory

**FrankYomik — 2 workflows.** `ci.yml` (push/PR to master) splits into `flutter-test` (`flutter pub get` → `flutter analyze` → `flutter test`) and `server-test` (Python venv + `pytest tests/unit/`, then `go test -v .`), with `cancel-in-progress: true`. `release.yml` (tag push `v*` + manual dispatch) fans out into 4 parallel build jobs — Linux AppImage, macOS DMG, Windows Inno Setup, Android APK — with GPG signing for Linux and Apple codesign/notarize/staple for macOS, both **optional with graceful skip if secrets are missing**. Android uses `fetch-depth: 0` for git-based versionCode. A `create-release` job downloads all artifacts into a draft GitHub Release.

**FrankSherlock — 3 workflows.** `ci.yml` runs a cross-platform matrix `[ubuntu-22.04, macos-latest, windows-latest]` with `fail-fast: false`, so all platforms report even when one fails. Each platform runs `cargo test` → `cargo fmt --check` → `cargo clippy -- -D warnings` → `npm run build` → `npm run test`; Linux additionally runs `cargo audit`. Rust caching via `swatinem/rust-cache@v2`. `release.yml` re-runs tests inside the release pipeline before Tauri builds installers. `aur-publish.yml` downloads the AppImage, computes SHA256, generates a PKGBUILD, and publishes to AUR over SSH.

**FrankMD — 1 workflow.** `ci.yml` runs `scan_ruby` (`brakeman --no-pager` + `bundler-audit`), `scan_js` (`importmap audit`), and `lint` (rubocop with a smart cache key = ruby-version + rubocop config + lockfile hash). **No test job in CI** — tests run locally via `bin/ci`. Dependabot covers bundler + github-actions weekly.

**FrankMega — 1 workflow, the most complete Rails pipeline.** `ci.yml` runs `scan_ruby`, `scan_js`, and `lint` as above, plus:
- `outdated`: `bundle outdated --only-explicit` with `continue-on-error: true` — non-blocking dependency-freshness visibility
- `test`: `rails db:test:prepare test`
- `system-test`: `rails db:test:prepare test:system` with **screenshot artifacts on failure** (`actions/upload-artifact` with `if: failure()`)
- Dependabot for bundler + github-actions, weekly

### Cross-Repo CI Pattern Matrix

| Pattern | Yomik | Sherlock | MD | Mega |
|---------|-------|---------|-----|------|
| Concurrency / cancel-in-progress | yes | yes | -- | -- |
| Multi-platform matrix | release only | CI + release | -- | -- |
| fail-fast: false | -- | yes | -- | -- |
| Security scanning (SAST) | -- | cargo audit | brakeman | brakeman |
| Dependency vulnerability scan | -- | cargo audit | bundler-audit | bundler-audit + outdated |
| JS dependency audit | -- | -- | importmap audit | importmap audit |
| Lint enforcement | flutter analyze | fmt + clippy -D warnings | rubocop | rubocop |
| Test in CI | pytest + go test + flutter test | cargo test + vitest | -- (local only) | minitest + system tests |
| Release signing (GPG) | yes | yes | -- | -- |
| Release signing (Apple) | yes | yes | -- | -- |
| Release notes from file | `releases/vX.Y.Z.md` | `releases/vX.Y.Z.md` | -- | -- |
| Package distribution | AppImage + DMG + MSI + APK | AppImage + DMG + MSI + AUR | -- | Docker (Kamal) |
| Dependabot | -- | -- | yes | yes |
| Artifact upload on failure | -- | -- | -- | screenshots |
| RuboCop cache optimization | -- | -- | yes | yes |
| Rust cache | -- | swatinem/rust-cache | -- | -- |

The matrix is the evidence, not the prescription. Read down a column and you get a repo's posture; read across a row and you get how universal a practice really is. Note the asymmetry: *no single repo does everything.* SAST is universal, but concurrency control, matrix builds, and artifact-on-failure each appear in only one or two.

> **Codified in** `.claude/rules/quality-tooling.md` — the CI/CD Best Practices list (`cancel-in-progress`, `fail-fast: false`, `continue-on-error` for dependency freshness, screenshot artifacts on failure, Dependabot for github-actions, smart cache keys) is the distillation of the rows above. Do not re-derive it here.

---

## 3. Testing: Coverage Evidence

### Test Coverage Comparison

| Repo | Frameworks | Unit Tests | Integration | System | Security-Specific |
|------|-----------|------------|-------------|--------|-------------------|
| FrankYomik | pytest + go test + flutter test | ~20 Python + Go + Flutter | 3 integration | -- | -- |
| FrankSherlock | cargo test + Vitest | 322 Rust + 299 frontend | -- | -- | -- |
| FrankMD | Minitest + Vitest | 420+ Ruby + 1370+ JS | Controllers | Capybara | -- |
| FrankMega | Minitest + FactoryBot + Shoulda + SimpleCov | Models + Jobs | Controllers | Capybara | 5 dedicated files |

**FrankYomik** organizes Python unit tests in `server/tests/unit/` (19 files: cache, processors, translators, OCR), integration tests in `server/tests/integration/` (bubble detector, full pipeline, webtoon scraper), Go tests alongside source (`server/handlers_test.go`), and Flutter widget tests. Its CLAUDE.md documents the test commands.

**FrankSherlock** enforces a hard convention: every module carries `#[cfg(test)] mod tests` — 322 Rust unit tests, plus 299 Vitest frontend tests with shared fixtures in `src/__tests__/fixtures.ts`. CI runs the suite on all three platforms; the pre-commit script runs it locally too.

**FrankMD** mirrors its `app/javascript/` tree in its JS test tree (1370+ Vitest tests) and mocks browser APIs via jsdom globals (marked.js, requestjs, turbo-rails), alongside 420+ Ruby tests.

**FrankMega — the most mature.** FactoryBot factories with security-state traits (`:admin`, `:banned`, `:expired`, `:with_otp`), SimpleCov for coverage, Capybara system tests with screenshot preservation, and **5 dedicated security test files**: `test/controllers/security_test.rb`, `test/models/ban_security_test.rb`, `test/models/user_security_test.rb`, `test/models/shared_file_security_test.rb`, `test/models/invitation_security_test.rb`.

> **Codified in** `.claude/rules/code-quality.md` — the "Security-Specific Test Files" section is FrankMega's five-file pattern, generalized.

Two testing patterns from this evidence are **not** yet codified: the *every-new-module-has-tests* rule (FrankSherlock's `#[cfg(test)]` discipline, which is mechanically enforceable) and *centralized test fixtures* to cut duplication.

---

## 4. Local Quality Gates: Shell Script vs Structured YAML

The two live approaches sit at opposite ends of the same tradeoff.

**FrankSherlock — `scripts/pre-commit.sh`**, sequential, exits on first failure:

```bash
cargo fmt --check
cargo clippy -- -D warnings
cargo test
npx vitest run
```

**FrankMega — `lefthook.yml`**, the structured alternative it actually runs:

```yaml
pre-commit:
  parallel: true
  commands:
    rubocop:
      run: bundle exec rubocop --parallel {staged_files}
      glob: "*.rb"
    brakeman:
      run: bundle exec brakeman --no-pager --quiet
    bundle-audit:
      run: bundle exec bundler-audit check --update
pre-push:
  commands:
    tests:
      run: bundle exec rails test
```

The shell script is honest and portable but pays for it: it lints the whole tree, runs the full test suite at *commit* time, and serializes independent checks. Lefthook buys back all three — `parallel: true`, `glob` filtering, `{staged_files}` for incremental linting, and a hook split that keeps commit-time fast while pushing the expensive suite to `pre-push`. That split is the whole point: a slow pre-commit hook trains developers to `--no-verify`.

The security tools named above (brakeman, bundler-audit; and gitleaks/semgrep in the framework's own tiers) are placed here because this is the *cheapest point at which they can still block*. What each one defends against is `06-security-devsecops-for-agents.md`'s subject.

> **Codified in** `.claude/rules/quality-tooling.md` — Lefthook as the recommended structured hook alternative, the pre-commit (<5s) vs pre-push (thorough) separation, staged-files-only linting, and the Tier 1/2/3 validation strategy.

---

## 5. Dependency Management

| Pattern | Yomik | Sherlock | MD | Mega |
|---------|-------|---------|-----|------|
| Lockfile committed | go.sum + pubspec.lock | Cargo.lock + package-lock.json | Gemfile.lock | Gemfile.lock |
| Dependabot | -- | -- | weekly (bundler + actions) | weekly (bundler + actions) |
| `bundle outdated` in CI | -- | -- | -- | yes (non-blocking) |
| `cargo audit` in CI | -- | yes | -- | -- |
| `bundler-audit` in CI | -- | -- | yes | yes |
| `.python-version` | -- | yes | -- | -- |
| `.ruby-version` | -- | -- | yes | yes |

Three things generalize. **Lockfiles are committed everywhere, without exception** — the one universal row in any of these matrices. **Toolchain version is pinned in a file** (`.ruby-version`, `.python-version`), not left to CI configuration. And the audit/freshness split is deliberate: vulnerability scans (`cargo audit`, `bundler-audit`) *block*, while freshness checks (`bundle outdated`) run `continue-on-error` and merely inform. Blocking on staleness would make every PR hostage to an upstream release cadence nobody controls.

---

## 6. Contract Testing as a Drift Gate

The failure mode specific to AI-assisted work is not a broken build — it is an implementation that compiles, passes its own tests, and quietly no longer matches the contract it was specified against. Tests written by the same agent that wrote the code cannot catch this: they encode the agent's *interpretation*, so agent and test drift together.

A **contract** breaks that circularity because it is authored independently of the implementation:

- **Schema validation** (e.g. Spectral against an OpenAPI spec) — the API surface must still match the declared spec after the agent has edited it.
- **Consumer-driven contract tests** (e.g. Pact) — the consumer's expectations are the fixture; the provider must satisfy them regardless of how it was rewritten.

Run both immediately after the build step, before anything downstream. They are the cheapest available check on *spec-to-implementation drift*, which is precisely what the spec-kit pipeline exists to prevent — and the only one in this file that an agent cannot satisfy by rewriting the assertion.

> **Codified in** — nothing yet. The framework has no contract-testing gate. This is the strongest unadopted idea in this file.

## Not Yet Adopted

Quality, CI, and testing items from the source's recommended-enhancements list that the framework has **not** implemented:

| Item | Evidence | Why it is worth adopting |
|------|----------|--------------------------|
| **Every new module must have tests** (`#[cfg(test)] mod tests`) | FrankSherlock | A mechanically checkable convention — a linter or PostEdit hook can assert it. Stronger than "aim for reasonable coverage." |
| **Factory traits for security states** (`:banned`, `:expired`, `:with_otp`) | FrankMega | Makes negative-path auth tests cheap to write, which is why FrankMega has five security test files and the others have none. |
| **Centralized/shared test fixtures** | FrankSherlock (`src/__tests__/fixtures.ts`) | Reduces duplication as suites grow past a few hundred tests. |
| **GPG / Apple signing with graceful fallback** in release CI | FrankYomik, FrankSherlock | Signing steps skip cleanly when secrets are absent, so forks and PR builds don't break. Belongs in a release-CI template. |
| **Language-specific cache-key strategies** | `swatinem/rust-cache` (Sherlock); RuboCop smart key (MD, Mega) | `quality-tooling.md` names "smart cache keys" generically but gives no per-ecosystem recipe. |
| **AUR auto-publish** | FrankSherlock | Niche, but it is the only fully automated downstream-package path in the corpus. Distribution mechanics belong to `08-project-organization-delivery.md`. |
