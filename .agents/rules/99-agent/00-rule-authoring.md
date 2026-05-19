---
description: "How to author and maintain high-signal agent rules."
globs: ".agents/rules/**"
---

# Rule Authoring Governance

## Must

- Keep rules in English and imperative voice.
- Use this section order in each rule file:
    1. Applies when
    2. Must
    3. Must not
    4. Execution steps
    5. Verification
- Keep one topic per file.
- Prefer links over duplicated policy text.
- Keep files concise (target <= 150 lines).
- Treat this format as mandatory for all new or updated rules.
- If a rule cannot use this format, document the exception and reason in the same PR.

## Must not

- Store long tutorials or product narratives in rule files.
- Duplicate the same policy across multiple files.

## Change protocol

1. Search for related rule files before adding a new one.
2. Update references when moving/renaming files.
3. Verify no dead links and no contradictory statements.

## Mandatory checklist for rule updates

- Every changed rule includes `Applies when`, `Must`, and `Must not`.
- Every changed rule includes actionable `Execution steps`.
- Every changed rule includes at least one verifiable check in `Verification`.
- No duplicated policy text when a canonical rule already exists.
- New rule files are added only when existing files cannot represent the policy.

## Quality gate

- A rule change is complete only when it is specific, testable, and non-duplicative.
