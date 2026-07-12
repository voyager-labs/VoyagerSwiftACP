---
description: "Deterministic placement strategy for all new harness rules and skills."
globs: ".agents/**"
schemaVersion: 2
---

# Harness Placement Governance

## Outcome

- Harness rules and skills have one deterministic home, sequential rule numbering, kebab-case skill directories, and a target maximum of 150 lines per rule file.
- Cross-cutting rules belong in `00-core/`; platform-specific rules belong in the matching domain directory; harness infrastructure belongs in `99-agent/`.

### Placement taxonomy

| Artifact kind                      | Target path                            | Examples                                                                           |
| ---------------------------------- | -------------------------------------- | ---------------------------------------------------------------------------------- |
| Cross-cutting deterministic rules  | `.agents/rules/00-core/`               | `00-execution-contract.md`, `02-verification.md`                                   |
| Platform-specific execution checks | `.agents/rules/30-macos/`              | `30-macos/03-voyager-app-workflow.md`, `30-macos/04-xcode-test-plan-visibility.md` |
| All new skills                     | `.agents/skills/<kebab-case>/SKILL.md` | `pr-review`, `compound-review`                                                     |
| Agent-harness infrastructure rules | `.agents/rules/99-agent/`              | This file, `01-agent-harness-artifacts.md`, `04-scope-diff-isolation.md`           |

## Default Actions

1. Classify the artifact as cross-cutting, platform-specific, skill, or harness infrastructure.
2. Select the target directory from the placement taxonomy and list its existing rules before assigning the next sequential number.
3. Write the rule using the canonical v2 format in `99-agent/00-rule-authoring.md`.
4. Keep skill directory names in `kebab-case` and keep each rule file to 150 lines or fewer.

## Decision Rules

- Place cross-cutting rules, which apply regardless of platform, in `00-core/`.
- Place rules applying only to `apps/macos/**` or `apps/backend/**` in the matching domain directory.
- Link to a canonical policy owner instead of duplicating policy text.

## Stop Conditions

- Do not create `.agents/rules/voyager/` or a subdirectory that duplicates the `30-macos/` domain split.
- Do not place cross-cutting rules in `20-backend/` or `30-macos/`, or platform-specific rules in `00-core/` or `99-agent/`.
- Do not duplicate canonical policy text or exceed 150 lines in a rule file.

## Verification

- `ls .agents/rules/voyager/ 2>&1` returns "No such file or directory".
- No rule file exceeds 150 lines (`wc -l .agents/rules/**/*.md`).
- Every new rule file conforms to the canonical v2 schema in `99-agent/00-rule-authoring.md`; this placement rule does not repeat the schema checklist.
