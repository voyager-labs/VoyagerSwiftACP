---
name: manage-skills
description: Analyze session changes to detect missing verification skills. Discover existing skills dynamically, create new or update existing skills, and manage CLAUDE.md.
argument-hint: "[Optional: specific skill name or focus area]"
---

# Session-Based Skill Maintenance

## Purpose

Detect and fix verification skill drifts based on current session changes:

1. **Missing Coverage** — Changed files unreferenced by any `verify-` skill.
2. **Invalid References** — Skills referencing deleted/moved files.
3. **Missing Checks** — New patterns/rules lacking coverage.
4. **Stale Values** — Outdated configurations or detection commands.

## When to Run

- After implementing features with new patterns/rules.
- To check consistency of existing verify skills.
- Pre-PR check to ensure changed areas are covered.

## Registered Verification Skills

_(No registered verification skills yet)_

<!-- Add new skills here:
| Skill | Description | Covered File Patterns |
|-------|-------------|-----------------------|
-->

## Workflow

### Step 1: Analyze Session Changes

Collect all changed files in the current session:

```bash
git diff HEAD --name-only
git log --oneline origin/main..HEAD 2>/dev/null
git diff origin/main...HEAD --name-only 2>/dev/null
```

Group files by top-level directory (first 1-2 path segments).

### Step 2: Map Files to Registered Skills

Read the **Registered Verification Skills** table.
For each skill, extract file patterns from `.claude/skills/verify-<name>/SKILL.md` (via "Related Files" or commands).
Match collected files against these patterns. Mark matched files as `CHECK`, unmatched as `UNCOVERED`.

### Step 3: Coverage Gap Analysis

For each AFFECTED skill (has matched files):

1. **Missing Files**: Are domain-related changed files absent in `Related Files`?
2. **Stale Commands**: Do grep/glob patterns still match? Test via dry-run.
3. **Uncovered Patterns**: Do changed files introduce new types, enums, rules not checked?
4. **Deleted File Refs**: Are files in `Related Files` deleted?
5. **Changed Values**: Did specific identifiers/keys change?

### Step 4: Decision (CREATE vs UPDATE)

For each UNCOVERED file group:

- IF related to existing skill domain → **UPDATE** existing skill.
- ELSE IF ≥3 files share a common rule/pattern → **CREATE** new `verify-` skill.
- ELSE → Mark as **Exempt** (no action needed).

**Prompt user** to confirm UPDATEs, CREATEs, or skip.

### Step 5: Update Existing Skills

For approved updates:

- **Append/Modify ONLY**: Never remove working checks.
- Add new file paths to `Related Files`.
- Add detection commands for new patterns.
- Remove deleted file references.

### Step 6: Create New Skill

1. **Explore**: Deeply analyze changed files for patterns.
2. **Confirm Name**: Ask user for name (must be `verify-kebab-case`).
3. **Create**: Generate `.claude/skills/verify-<name>/SKILL.md` using the exact structure:
    - Frontmatter (name, description)
    - **Purpose**: 2-5 validation categories
    - **When to Run**: 3-5 triggers
    - **Related Files**: Actual file paths (verify with `ls`)
    - **Workflow**: Grep/Glob/Bash steps, PASS/FAIL criteria, Fix instructions
    - **Exceptions**: 2-3 non-violation cases
4. **Update Parent Files**:
    - `manage-skills/SKILL.md` (this file, Registered table)
    - `verify-implementation/SKILL.md` (Target table)
    - `CLAUDE.md` (Skills table)

### Step 7: Validation

- Verify all `Related Files` exist (`ls`).
- Dry-run one detection command per updated skill.
- Ensure tables in `manage-skills` and `verify-implementation` are synced.

## Exceptions

Do NOT process:

- Lock files, generated files, build outputs.
- One-off config changes (version bumps).
- Documentation (README, CHANGELOG).
- Test fixtures.
