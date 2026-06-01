---
name: verify-implementation
description: Sequentially executes all verify skills in the project to generate a unified validation report. Run after feature implementation, pre-PR, or during code review.
argument-hint: "[Optional: specific verify skill name]"
---

# Verify Implementation

## Purpose

Executes all registered `verify-*` skills in sequence for unified validation:

- Runs checks defined in each skill's `Workflow`.
- References each skill's `Exceptions` to prevent false positives.
- Provides fix methods for discovered issues.
- Applies fixes after user approval and re-verifies.

## When to Run

- After implementing a new feature.
- Before creating a Pull Request.
- During code review.
- To audit codebase rule compliance.

## Target Skills

This skill sequentially runs the verification skills listed below. `/manage-skills` auto-updates this list.

_(No registered verification skills yet)_

<!-- Add new skills here:
| # | Skill | Description |
|---|-------|-------------|
-->

## Workflow

### Step 1: Initialization

Check the **Target Skills** list above.
If an optional argument is provided, filter the list to that specific skill.

**If 0 skills registered:** Display a message to run `/manage-skills` and terminate.

**If ≥1 skills registered:** Display the list of target skills and begin verification.

### Step 2: Sequential Execution

For each listed skill:

1. **Read SKILL.md**: Parse `Workflow` (commands), `Exceptions` (non-violations), and `Related Files`.
2. **Execute Checks**:
    - Run detection tools (Grep, Glob, Read, Bash).
    - Match results against PASS/FAIL criteria.
    - Exempt patterns listed in `Exceptions`.
3. **Record Issues**: Track file, line number, problem description, and recommended fix code for failures.

### Step 3: Unified Report

Compile results for all skills.

**If all pass:**
Print success summary per skill and state "Ready for code review."

**If issues found:**
List issues containing `# | Skill | File | Problem | Fix Method`.

### Step 4: User Action

Ask the user how to proceed via `AskUserQuestion`:

1. **Fix All** - Apply all recommended fixes automatically.
2. **Fix Individual** - Review and apply fixes one by one.
3. **Skip** - Exit without changes.

### Step 5: Apply Fixes

Apply fixes based on user selection. Show progress per skill/file.

### Step 6: Re-verification

Run the affected `verify-*` skills again.

- If all pass: "All verifications passed!"
- If issues remain: "Residual Issues - manual fix required." Prompt user to fix manually and re-run.

## Exceptions

Do NOT flag:

- Empty registered skills list (just output a guide message).
- Internal exceptions defined in individual `verify-*` skills.
- `verify-implementation` itself (do not include in the execution list).
- `manage-skills` (not a `verify-` skill).

## Related Files

| File                                    | Purpose                                        |
| --------------------------------------- | ---------------------------------------------- |
| `.claude/skills/manage-skills/SKILL.md` | Skill Maintenance (manages Target Skills list) |
| `CLAUDE.md`                             | Project Guidelines                             |
