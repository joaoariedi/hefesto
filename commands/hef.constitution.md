---
model: fable
description: "Create or update .specify/memory/constitution.md with project governance principles"
---

# Constitution

Create or update the project constitution at `.specify/memory/constitution.md`.

## Pre-Flight

### Existing constitution
> The commands in this section must be run with the Bash tool; they cannot be
> pre-executed in a `!` block. A `!` block is permission-checked before the
> CLAUDE_PLUGIN_ROOT variable is substituted, so it is rejected as "Contains
> expansion". Do not write that variable with a $ and braces here: it would be
> substituted into this note and the warning would read as nonsense.

Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh constitution`

### Project context
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh readme-head`

### Tech stack detection
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh list-config-files`

### Existing rules
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh list-rules`

## Instructions

1. **Analyze project context** from the pre-flight data above:
   - Identify language, framework, architecture patterns
   - Read config files to understand dependencies and tooling
   - Check `.claude/rules/` to understand existing conventions (reference them, don't duplicate)

2. **Propose 5 principles** — these should cover project-specific governance that complements `.claude/rules/`:
   - **Tech stack decisions** (e.g., "Use PostgreSQL for all persistent storage")
   - **Architecture constraints** (e.g., "All API endpoints must be REST, no GraphQL")
   - **Code organization** (e.g., "Feature-based directory structure")
   - **Testing philosophy** (e.g., "Integration tests over unit tests for API layer")
   - **Dependency policy** (e.g., "Minimize external dependencies, prefer stdlib")

3. **Interactive confirmation** — present each principle using AskUserQuestion:
   - Show all 5 proposed principles with descriptions
   - Let user customize, reorder, or replace each one
   - Use multiSelect to let user approve multiple at once

4. **Write constitution** to `.specify/memory/constitution.md`:
   ```markdown
   # Project Constitution
   <!-- Version: 1.0.0 | Date: YYYY-MM-DD -->
   <!-- Updated by /hef.constitution -->

   ## Principles

   1. **<Principle Name>** — <description>
   2. **<Principle Name>** — <description>
   3. **<Principle Name>** — <description>
   4. **<Principle Name>** — <description>
   5. **<Principle Name>** — <description>

   ## Tech Stack
   - Language: <detected>
   - Framework: <detected>
   - Database: <detected or N/A>
   - Testing: <detected>

   ## Architecture Constraints
   <user-confirmed constraints>

   ## References
   - Project rules: `.claude/rules/`
   - Code quality: `.claude/rules/code-quality.md`
   - Git workflow: `.claude/rules/git-workflow.md`
   ```

5. **Version management**:
   - If creating new: version `1.0.0`
   - If updating existing: bump minor version (e.g., `1.0.0` → `1.1.0`)
   - Always include current date

6. **Post-write**: suggest committing the updated constitution
