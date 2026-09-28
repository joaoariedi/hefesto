#!/usr/bin/env bash
# Fixture: a git repo on a feature branch with .specify/, a constitution, a spec and an UNREVIEWED
# plan — the exact state /hef.review resolves to plan mode. The eval workspace is empty until this
# runs (evals/README.md).
set -euo pipefail
git init -q -b main .
mkdir -p .specify/memory .specify/specs/rate-limit src
cat > .specify/memory/constitution.md <<'EOF'
# Project Constitution
<!-- Version: 1.0.0 -->
## Principles
1. Every public function has a test.
2. No new runtime dependency without a recorded decision.
EOF
cat > .specify/specs/rate-limit/spec.md <<'EOF'
# Spec: rate-limit
## Overview
Per-client rate limiting on the public API: 100 requests per minute, HTTP 429 beyond.
## User Scenarios
### US1: A client over the limit is refused [P1]
- **Given** a client id with 100 requests in the current minute
- **When** it sends the 101st
- **Then** the API answers 429 with a Retry-After header
## Functional Requirements
| ID | Requirement | Priority | Scenario |
|----|-------------|----------|----------|
| FR-001 | Count requests per client id per calendar minute | P1 | US1 |
| FR-002 | Answer 429 with Retry-After when the count exceeds 100 | P1 | US1 |
| FR-003 | Counts reset at the minute boundary | P1 | US1 |
## Success Criteria
| ID | Criterion | Validation Method |
|----|-----------|-------------------|
| SC-001 | 101st request in a minute gets 429 | integration test |
EOF
cat > .specify/specs/rate-limit/plan.md <<'EOF'
# Plan: rate-limit
## Affected Files
| File | Change Type | Description |
|------|------------|-------------|
| `src/limiter.py` | create | in-memory counter keyed by client id and minute |
| `src/api.py` | modify | call the limiter before routing |
## Implementation Approach
A module-level dict `{(client, minute): count}`; the API middleware increments and compares. Old
minutes are never evicted. No tests planned for the boundary case; the dict is fine for one process.
## Constitution Compliance
- [x] Principle 1: the limiter has a unit test.
- [x] Principle 2: no dependency.
EOF
printf 'def handle(request):\n    return 200\n' > src/api.py
git add -A && git -c user.email=fixture@eval -c user.name=fixture commit -q -m "fixture: spec and unreviewed plan"
git checkout -q -b feature/rate-limit
