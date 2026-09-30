#!/usr/bin/env bash
# Fixture: a git repo on a feature branch with .specify/, a constitution and a spec but NO plan — the
# state /hef.plan starts from. src/ holds a stub api.py and deliberately no limiter.py: a scout or a
# planner that "helpfully" creates the limiter, or edits src/ at all, is the failure the graders catch.
# The eval workspace is empty until this runs (evals/README.md).
set -euo pipefail
git init -q -b main .
mkdir -p .specify/memory .specify/specs/rate-limit src tests
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
cat > src/api.py <<'EOF'
"""Public API entry point. Errors are returned as (status, body) tuples — see handle()."""
import logging

log = logging.getLogger("api")


def handle(request):
    """Route a request. Returns (status, body)."""
    client = request.get("client")
    if not client:
        log.warning("request without client id")
        return 400, {"error": "client id required"}
    return 200, {"ok": True}
EOF
cat > tests/test_api.py <<'EOF'
from src.api import handle


def test_missing_client_is_400():
    assert handle({})[0] == 400
EOF
git add -A && git -c user.email=fixture@eval -c user.name=fixture commit -q -m "fixture: spec, stub api, no plan"
git checkout -q -b feature/rate-limit
