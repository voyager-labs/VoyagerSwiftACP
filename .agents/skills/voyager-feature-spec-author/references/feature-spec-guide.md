# FEATURE_SPEC Guide

This document explains how to write or refactor `PRODUCT/05_FEATURE_SPECS` documents.

- Use `.agents/skills/voyager-feature-spec-author/references/TEMPLATE-feature-spec.md` as the actual output template.
- Store metadata in YAML frontmatter, not in a markdown table.
- This guide should explain the contract and writing rules, not duplicate the template body.
- Guide prose should be written in English.
- Actual generated document prose should be written in Korean.

## Writing rules

- Write metadata in YAML frontmatter at the top of the document.
- Keep the fixed section titles defined by the template.
- Write the actual section body prose in Korean.
- Use `-` for intentionally empty values and `TBD` for values that are still undecided.
- Apply the same `-` / `TBD` convention to frontmatter values as well as body sections.
- Strict lint still requires all frontmatter keys and fixed sections to be present, but it does not reject `-` / `TBD` values in metadata or body sections.
- In strict mode, `-` is treated as confirmed not-applicable and does not emit a warning.
- In strict mode, `TBD` is treated as unresolved and is surfaced as a warning for review instead of a hard failure.

## Frontmatter fields

Keep the following keys in YAML frontmatter:

- `interaction_id`
- `interaction_type`
- `feature`
- `category_key`
- `feature_id`
- `status`
- `summary`
- `related_region`
- `menu`
- `shortcut`

## Fixed section contract

The document body must keep these fixed sections:

1. `Intent`
2. `Trigger / Entry Points`
3. `Preconditions`
4. `Expected Outcome`
5. `State Changes`
6. `User-visible Feedback`
7. `Edge Cases / Failure Handling`
8. `Acceptance Criteria`
9. `Permissions / Dependencies`
10. `Observability / Analytics`
11. `Related Interactions`
12. `Source`

## Section guidance

### Intent

- Explain why the interaction exists.
- Keep the purpose short and user-facing.

### Trigger / Entry Points

- Describe menu paths, shortcuts, visible entry points, and invocation conditions.
- Do not omit meaningful entry paths.

### Preconditions

- Describe the state, selection, permission, or environment conditions required before execution.

### Expected Outcome

- Describe what must be true when execution succeeds.

### State Changes

- Describe which states change and how.
- Include state preservation behavior when failure matters.

### User-visible Feedback

- Describe what the user sees, such as loading, success, error, or retry messaging.

### Edge Cases / Failure Handling

- Cover invalid input, permission issues, duplicate execution, cancellation, and partial failure.

### Acceptance Criteria

- Write testable statements in Korean using the pattern `...한 상황에서, ...하면, ...해야 한다.`
- Keep each statement specific and verifiable.

### Permissions / Dependencies

- Describe permissions, system conditions, network constraints, and external dependencies.

### Observability / Analytics

- Describe events worth tracking, such as entry, success, failure, and retry.

### Related Interactions

- Link related interactions within the same feature where relevant.

### Source

- Keep the inventory path and source line accurate.

## Optional additions

- Add extra explanatory material only when it is truly needed.
- Optional additions must not replace the fixed section contract.
