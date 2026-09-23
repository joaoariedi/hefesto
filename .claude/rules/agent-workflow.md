# Development Workflow

## Phase 0: Multi-Environment Setup (Optional)

### Remote Control
Continue local Claude Code sessions from any device:
- Start work locally in terminal: `claude`
- Resume the same session from phone/browser via claude.ai/code
- Context, files, and conversation history carry over across surfaces
- Useful for monitoring long-running tasks or reviewing results on the go

### Teleport
Move sessions between surfaces:
- Start a task on web (claude.ai/code) or mobile
- Pull into local terminal: `/teleport`
- Full context transfers — no re-explaining needed
- Ideal for starting tasks during commute, finishing at workstation

### When to Use
- Long-running implementations you want to monitor from mobile
- Starting research/planning on web, then implementing locally
- Reviewing PR feedback on mobile, then switching to terminal to fix

## Phase 1: Planning & Context (Steps 1-4)

### Step 1: Context Preparation
- Use built-in `Explore` agent or `/hef.context` command for project analysis
- Auto-detect tech stack from `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`
- Identify existing patterns, conventions, and quality tools
- Use `ultrathink` for complex architectural analysis or ambiguous requirements

### Step 2: Create Task List & Plan
- Use TaskCreate for comprehensive task breakdown with acceptance criteria
- Use EnterPlanMode/ExitPlanMode for complex implementations

### Step 3: Plan Review (Optional for Simple Tasks)
- For complex features (>5 tasks), use EnterPlanMode for user approval
- Skip for simple tasks (<3 tasks)

### Step 4: Plan Refinement
- Iterate tasks based on user feedback
- Break down large tasks into smaller, manageable pieces

## Phase 2: Implementation with Quality Gates (Steps 5-10)

### Step 5: Pre-Implementation Setup
- Detect existing quality tools using Grep/Glob
- Identify available lint, format, and test commands

### Step 6: Branch Creation (Git Projects Only)
- Create feature branches with semantic naming
- Skip for non-git projects

### Step 7: Incremental Development with Task Tracking
- **Use TaskUpdate to mark task as "in_progress" before starting work**
- Follow code quality limits (functions <50 lines, files <500 lines)
- **Use TaskUpdate to mark task as "completed" immediately after finishing**
- Use semantic commit messages

### Step 8: Documentation During Development
- Inline documentation for complex functions only
- Focus on code clarity over excessive documentation

### Step 9: Test Creation & Validation
- For spec-driven development (SDD), use the SDD pipeline: `/hef.spec` → `/hef.plan` → `/hef.tasks` → `/hef.implement`
- Use `test-specialist` agent for comprehensive test suites
- Find existing test patterns using Glob: `**/*test*`, `**/spec/**`
- PostToolUse hook auto-runs tests after source file edits (throttled to 15s)

### Step 10: Quality Checks
- Use `quality-guardian` agent before any commit or PR
- ALWAYS run quality checks after implementation
- Fix any issues before considering task complete

## Phase 3: Review & Integration (Steps 11-16)

### Step 11: Local Validation
- Ensure all tasks are completed via TaskList
- Run full test suite, verify no regressions

### Step 12: Git Integration
- Stage relevant changes by name
- Create semantic commit with co-author option

### Step 13-14: Self-Review & Issue Resolution
- Review for security, performance, maintainability
- Use `ultrathink` for complex debugging, race conditions, or security-sensitive reviews
- Fix quality check failures, re-run tests

### Step 15-16: Final Validation & Completion
- Verify all acceptance criteria met
- Use `review-coordinator` agent for PR creation if needed
- Only commit when user explicitly requests it

## Phase 4: Post-Implementation (Steps 17-18) - Optional

### Step 17-18: Retrospective
- Note lessons learned in auto-memory
- Record useful patterns discovered

## CLAUDE.md Template Guidance

When creating or updating `CLAUDE.md` files for projects, include these sections as applicable:

### Cross-Cutting Change Maps
Document files that must change together to prevent partial updates:
```
If you change X, also update Y and Z:
- Cache paths: update both server/cache.go AND server/worker/page_cache.py
- Job payloads: update handlers.go, consumer.py, AND provider.dart
- API contracts: update schema.graphql AND generated types
```

### "What NOT to Change" Guardrails
Explicitly list things AI agents should never modify:
```
NEVER:
- Remove the FTS5 virtual table from the schema
- Change csp: null in tauri.conf.json
- Modify migration files that have already shipped
- Edit generated files under src/generated/
```

### Trust Boundary Documentation
List hostile input surfaces so agents apply proper validation:
```
Trust boundaries (sanitize all input from these sources):
- Image uploads to POST /api/v1/jobs (user-controlled content)
- Metadata fields (title, chapter) — sanitize before storage
- WebSocket clients — validate subscription requests
- Anything persisted under cache/ — treat as untrusted
```

### Security Posture Statement
Acknowledge what kind of app it is to calibrate security decisions:
```
This is a public-facing web app with user authentication.
Security posture: production-grade (rate limiting, CSP, CSRF, encrypted sessions).
```

These patterns are derived from production repos and significantly reduce AI agent errors in cross-cutting changes.
