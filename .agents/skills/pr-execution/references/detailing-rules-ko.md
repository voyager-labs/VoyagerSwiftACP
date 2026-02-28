# PR Body Detailing Rules

## Goal

Write PR bodies at a level where reviewers can trace code changes directly from the text.

## Detail density requirements

- Include both commit-level scope and module-level scope.
- Use exact file paths in module sections.
- Each module block must contain at least:
  1. Change type (`add|modify|delete|migrate`)
  2. Core change summary
  3. Behavior difference from previous state
  4. Intent and impact
  5. Risk or compatibility notes

## Writing rules

- Avoid vague wording:
  - Avoid: "cleaned up", "improved", "updated" without specifics
  - Prefer: concrete "what changed where and how" with path evidence
- Do not list only high-level bullets without evidence.
- Separate code, infra, and docs changes by module.

## Mismatch handling

- If PR body and actual diff disagree, update the body first.
- If Linear request and implementation differ, separate:
  - Included in this PR
  - Follow-up track

## When new commits are added

- Do not partially patch old text without re-checking these sections:
  - Commit-level scope
  - Module-level details
  - Verification section
