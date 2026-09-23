---
model: fable
description: "Scan spec for ambiguities and ask targeted clarification questions"
---

# Clarify

Scan the current branch's specification for ambiguities and generate targeted clarification questions.

## Pre-Flight

### Current branch
> The commands in this section must be run with the Bash tool; they cannot be
> pre-executed in a `!` block. A `!` block is permission-checked before the
> CLAUDE_PLUGIN_ROOT variable is substituted, so it is rejected as "Contains
> expansion". Do not write that variable with a $ and braces here: it would be
> substituted into this note and the warning would read as nonsense.

Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh branch`

### Load spec
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh spec`

### Existing clarifications
Run with the Bash tool: `${CLAUDE_PLUGIN_ROOT}/hooks/speckit-helper.sh clarifications`

## Instructions

1. **Load and analyze spec.md** against 9 taxonomy categories:

   | # | Category | What to look for |
   |---|----------|-----------------|
   | 1 | **Scope boundaries** | What's in/out of scope for this feature |
   | 2 | **User roles** | Who are the actors, what permissions do they have |
   | 3 | **Data lifecycle** | Creation, update, deletion, retention policies |
   | 4 | **Error handling** | What happens when things go wrong |
   | 5 | **Edge cases** | Boundary conditions, empty states, limits |
   | 6 | **Performance** | Expected load, response times, concurrency |
   | 7 | **Security** | Authentication, authorization, data protection |
   | 8 | **Integration** | External dependencies, APIs, third-party services |
   | 9 | **Migration** | Backwards compatibility, data migration, rollback |

2. **Generate max 5 questions** — prioritize by impact on implementation:
   - Each question must be specific and actionable
   - Use AskUserQuestion with multiple-choice options
   - Include a recommended answer as the first option (marked with "(Recommended)")
   - Questions should resolve `[NEEDS CLARIFICATION]` markers if present

3. **Present questions one at a time** using AskUserQuestion:
   - Category tag in the header (e.g., "Error handling")
   - Clear question with context from the spec
   - 2-4 options with descriptions

4. **Update spec.md incrementally** — after each answer:
   - Add or update the `## Clarifications` section at the bottom of spec.md
   - Format:
     ```markdown
     ## Clarifications

     ### CLR-001: <question summary> [<category>]
     **Decision**: <chosen answer>
     **Rationale**: <why this was chosen>
     **Impact**: <which FR/US this affects>
     ```
   - Remove any resolved `[NEEDS CLARIFICATION]` markers from the spec body
   - Update affected functional requirements if the clarification changes them

5. **Summary** after all questions are answered:
   - List all clarifications added
   - Note any remaining `[NEEDS CLARIFICATION]` markers
   - Suggest next step: `/hef.plan` if ready, or another `/hef.clarify` round if more questions remain
