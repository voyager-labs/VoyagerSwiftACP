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
  6. One representative code snippet when the module includes substantive code changes

## Code snippet rules

- Use snippets from the actual diff or current file contents, not invented pseudo-code.
- Prefer one short snippet per module that best explains the behavioral change.
- Keep snippets concise enough for PR readability. Prefer roughly 3-12 lines.
- Use fenced code blocks and include a language tag when it is obvious.
- Introduce the snippet with one sentence that explains why this excerpt matters.
- For doc-only, copy-only, or trivial rename-only modules, omit the snippet and state briefly why there is no code excerpt.

## Writing rules

- Avoid vague wording:
  - Avoid: "cleaned up", "improved", "updated" without specifics
  - Prefer: concrete "what changed where and how" with path evidence
- Do not list only high-level bullets without evidence.
- Separate code, infra, and docs changes by module.
- When multiple files make up one behavioral unit, choose the snippet from the file that most directly shows the contract change.

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
