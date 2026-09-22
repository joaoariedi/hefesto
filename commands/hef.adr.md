---
model: sonnet
description: "Record an architecture decision as a report with machine-readable MADR status"
argument-hint: "<short-title> [--status proposed|accepted|rejected]"
---

# Decision record

Every file under `reports/` is a decision with evidence behind it, and every one carries MADR
frontmatter so an agent can tell a live decision from a dead one without reading prose. A
98-record repository once had 59 of them misread because status was inferred from body text —
retired mandates treated as active fences, active ones as undecided. Status lives in frontmatter
only.

Title: **$ARGUMENTS**

## Pre-Flight

> The commands in this section must be run with the Bash tool; they cannot be
> pre-executed in a `!` block. A `!` block is permission-checked before the
> CLAUDE_PLUGIN_ROOT variable is substituted, so it is rejected as "Contains
> expansion". Do not write that variable with a $ and braces here: it would be
> substituted into this note and the warning would read as nonsense.

Run with the Bash tool: `ls reports/ 2>/dev/null | tail -3 || echo NO_REPORTS_DIR`

## Instructions

1. **Number and name.** Next two-digit number after the highest in `reports/`; kebab-case slug
   from the title: `reports/NN-<slug>.md`. If `reports/` does not exist, create it and say so.

2. **Write the file** with this exact shape. Status defaults to `proposed`; `--status` overrides.

   ```markdown
   ---
   status: proposed
   date: YYYY-MM-DD
   supersedes:            # a report number this replaces, or omit the line
   ---
   # <Title>

   <One paragraph: what was decided, or what is being evaluated. Adoption status stated plainly.>

   **Sources:** <what the decision rests on — measurements, docs, incidents, papers>
   **Codified in:** <the rule, hook, command, or skill that now enforces it — or "Not yet codified">

   ## Context
   ## Decision
   ## Consequences
   ## Rejected alternatives
   ```

3. **Index it.** Add a row to `docs/research.md`'s corpus table and bump its count. The smoke suite
   checks that every report has a status in `{proposed, accepted, rejected, deprecated, superseded}`
   and a date.

4. **Lifecycle.** A decision changes state by editing `status:` — never by rewriting history. To
   replace a decision, write a new report with `supersedes: NN` and set the old one to
   `superseded`. Evaluated-and-not-adopted ideas are `rejected` and kept as prior art.
