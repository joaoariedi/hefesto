---
status: proposed
date: 2026-07-12
---

# Project Organization & Delivery

How the surveyed repositories organize the artifacts *around* the code — version-controlled release notes, throwaway research directories, design-rationale documents — and how they package and ship the result. This is the smallest subject in the corpus and the one with the weakest connection to an AI development framework: containerization and deployment are engineering practice, not context engineering, and are retained here only because the source report documented them and dropping them would lose evidence.

This file does NOT cover CLAUDE.md or AGENTS.md as configuration documents (see `02-claude-md-authoring.md`), CI/CD workflows, testing, pre-commit hooks, or dependency management (see `07-quality-gates.md`), or security scanning of containers and images (see `06-security-devsecops-for-agents.md`).

**Sources:** Frank Repos Best Practices Analysis §6, §7
**Codified in:** Not yet codified. (`.claude/rules/git-workflow.md` covers commit message format, commit types, branch naming, and staging conventions — it says nothing about release notes, research directories, IDEA.md, or deployment.)

## The Release Notes Pattern (FrankYomik, FrankSherlock)

Both repos keep release notes as `releases/vX.Y.Z.md` files, loaded by CI at tag time:

```bash
TAG="${GITHUB_REF_NAME}"
NOTES_FILE="releases/${TAG}.md"
if [ -f "$NOTES_FILE" ]; then
  BODY=$(cat "$NOTES_FILE")
else
  BODY="Release ${TAG}"
fi
```

Benefits:

- Release notes are version-controlled and reviewable in PRs
- CI appends install instructions automatically
- Fallback to tag name if no notes file exists

The reviewability point is the interesting one for an agent workflow: notes written into a file get the same review treatment as code, whereas notes typed into a GitHub release form at tag time get none.

## Research Documentation (FrankSherlock)

FrankSherlock uses `_`-prefixed directories for research that informed the final design but should not ship:

- `_classification/` — Python classification PoC
- `_research_ab_test/` — A/B benchmark scripts with docs, ground truth, and results
- `_face_ab_test/` — Face detection/embedding benchmarks

Each research dir has its own README, requirements, and structured docs (`BENCHMARK_CONFIG.json`, `GROUND_TRUTH.json`, `RESULTS.md`).

The `_` prefix is a naming convention doing real work: it marks a directory as *exploratory, not production*, which is a distinction an agent otherwise cannot infer from the file tree. Without it, a benchmark script and a shipped module look identical to a code search.

## The IDEA.md Pattern (FrankSherlock, FrankMega)

`docs/IDEA.md` files document the original concept and design rationale. FrankSherlock also has `IDEA2.md` for evolved thinking. These serve as architectural decision context.

IDEA.md is best understood as a **lightweight ADR alternative** — cheaper than a full architecture-decision-record process, and specifically valuable to an AI agent, which can read *why* a design was chosen but cannot reconstruct it from the code alone.

## Actionable Patterns for the Framework

Source §6 names three:

1. **`releases/` directory pattern** — standardize version-controlled release notes
2. **`_`-prefixed research directories** — convention for exploratory work that shouldn't ship
3. **IDEA.md** — lightweight ADR alternative for documenting design rationale

## Containerization & Deployment

Three distinct packaging shapes appear across the repos.

### FrankYomik — Multi-Container with Variants

- `Dockerfile.api` — Go API server
- `Dockerfile.worker` — Python worker (CUDA)
- `Dockerfile.worker-rocm` — Python worker (AMD ROCm variant)
- `docker-compose.yml` — standard deployment
- `docker-compose.prod.yml` — production overrides
- `docker-compose.rocm.yml` — AMD GPU variant
- `scripts/deploy.sh`, `scripts/push-images.sh` — deployment automation

The variant axis here is hardware (CUDA vs ROCm), not environment — a dimension most compose setups do not have to model.

### FrankMega — Kamal Deployment

- `.kamal/` directory with hook samples (pre-deploy, post-deploy, etc.)
- `config/deploy.yml` — Kamal deployment config
- `docker-compose.yml` — local development
- `bin/docker-entrypoint` — container entrypoint

Note the split: **Kamal** for deploy, Docker Compose for local development only.

### FrankMD — Docker with Desktop Wrapper

- `docker-compose.yml` — service definition
- `config/fed/fed.sh` — shell function for Docker-based desktop usage
- `install.sh` — installation script

The `fed.sh` shell function is the notable piece — it wraps a containerized service behind a desktop-feeling command, so the container is an implementation detail rather than something the user operates.

## Not Yet Adopted

Source C §9 ("Recommended Enhancements for the AI Development Framework") lists two items belonging to this subject, both **Medium Priority**:

| Enhancement | Source Repo | Where to Apply |
|---|---|---|
| Document `releases/vX.Y.Z.md` pattern for release notes | FrankYomik, FrankSherlock | `git-workflow.md` |
| Document `_`-prefixed research directory convention | FrankSherlock | `context-management.md` |

Neither has been written into `.claude/rules/`. The report's own routing is worth keeping: release notes belong with the git conventions, and the `_`-prefix convention belongs with context management (its purpose is to tell an agent which directories to ignore).

**IDEA.md is not in §9 at all** — it is described in §6 but was never promoted to a recommendation. If adopted, the natural home is `02-claude-md-authoring.md`'s territory, as a companion document to CLAUDE.md rather than a rules-file entry.

**Containerization and deployment produced zero §9 recommendations.** The report documented the patterns and recommended none of them for the framework — an honest signal that this material is descriptive prior art, not a backlog.
