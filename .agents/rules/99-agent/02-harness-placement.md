---
alwaysApply: true
description: "Deterministic placement strategy for all new harness rules and skills."
---

# Harness Placement Governance

## Applies when

- Creating new files under `.agents/rules/**` or `.agents/skills/**`.
- Deciding where a cross-cutting or platform-specific rule belongs.

## Placement taxonomy

| Artifact kind                      | Target path                            | Examples                                                                           |
| ---------------------------------- | -------------------------------------- | ---------------------------------------------------------------------------------- |
| Cross-cutting deterministic rules  | `.agents/rules/00-core/`               | `05-scope-diff-isolation.md`                                                       |
| Platform-specific execution checks | `.agents/rules/30-macos/`              | `30-macos/03-voyager-app-workflow.md`, `30-macos/04-xcode-test-plan-visibility.md` |
| All new skills                     | `.agents/skills/<kebab-case>/SKILL.md` | `bug-triage`, `pr-review`                                                          |
| Agent-harness infrastructure rules | `.agents/rules/99-agent/`              | This file, `01-agent-harness-artifacts.md`                                         |

## Must

- Assign sequential numbering within the target directory (next available number).
- Follow the rule format defined in `99-agent/00-rule-authoring.md`.
- Place cross-cutting rules (applying to all tasks regardless of platform) in `00-core/`.
- Place platform-specific rules (applying only when touching `apps/macos/**` or `apps/backend/**`) in the matching domain directory.
- Keep skill directory names in `kebab-case`.
- Target <= 150 lines per rule file.

## Must not

- Create `.agents/rules/voyager/` or any subdirectory that duplicates the domain split already covered by `30-macos/`.
- Place cross-cutting rules inside a platform-specific directory (`20-backend/`, `30-macos/`).
- Place platform-specific rules in `00-core/` or `99-agent/`.
- Duplicate policy text that already exists in a canonical rule; link instead.
- Exceed 150 lines in any single rule file.

## Execution steps

1. Classify the artifact: cross-cutting, platform-specific, skill, or harness-infra.
2. Look up the target directory from the placement taxonomy above.
3. List existing files in that directory. Assign the next sequential number.
4. Write the file using the mandatory format from `99-agent/00-rule-authoring.md`.

## Verification

- `ls .agents/rules/voyager/ 2>&1` returns "No such file or directory".
- No rule file exceeds 150 lines (`wc -l .agents/rules/**/*.md`).
- Every new rule file contains all five mandatory sections: Applies when, Must, Must not, Execution steps, Verification.
