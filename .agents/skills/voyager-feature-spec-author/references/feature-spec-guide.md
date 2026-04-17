# FEATURE_SPEC Guide

This document explains how to write or refactor `PRODUCT/05_FEATURE_SPECS` documents.

- Use `.agents/skills/voyager-feature-spec-author/references/TEMPLATE-feature-spec.md` as the actual output template.
- Store metadata in YAML frontmatter, not in a markdown table.
- This guide should explain the contract and writing rules, not duplicate the template body.
- Guide prose should be written in English.
- Actual generated document prose should be written in Korean.
- Generation-only notes or author instructions must stay in this guide or the skill docs, not inside the output template or generated documents.

## Writing rules

- Write metadata in YAML frontmatter at the top of the document.
- Keep the fixed section titles defined by the template.
- Write the actual section body prose in Korean.
- Do not embed internal authoring comments, reminder comments, or generation instructions in the generated markdown body.
- Use `-` for intentionally empty values and `TBD` for values that are still undecided.
- Apply the same `-` / `TBD` convention to frontmatter values as well as body sections.
- When body prose references another `interaction_id`, use a markdown link to the target FEATURE_SPEC file instead of plain backticks.
- Prefer relative links such as `[CBW-002-capture_request_context_snapshot](../CBW-002-manage-request-context/CBW-002-capture_request_context_snapshot.md)`.
- Do not use vague hedge phrases when a concrete product term can be written.
- Avoid wording such as `또는 동등한`, `유사한`, `적절한`, `필요 시`, `가능한 경우`, `등` for states, CTAs, triggers, or outcomes unless the ambiguity is intentional and explicitly part of the product contract.
- Prefer exact state names, button labels, UI regions, and trigger conditions.
- When referring to a literal UI label, use the exact product label verbatim.
- Do not translate a literal UI label into Korean if the UI itself uses English.
- If the user explicitly confirms that an FS long-text field has been human-reviewed and its `<<AI>>` marker should be removed, remove the marker from the corresponding FI long-text cell in the same pass.
- Do not assume that prose-level object/state consistency can be proved from text alone.
    - Use exact object names and exact state names.
    - If the contract is ambiguous, flag it instead of smoothing it over with similar wording.
- When multiple interactions share the same object/state vocabulary, prefer a machine-readable category-level `contracts/*.toml` file over repeating the same lifecycle in each interaction spec.
- When one user flow spans multiple features, prefer a category-level `flows/` doc over scattering the end-to-end sequence across unrelated interaction specs.
- Interaction specs should reference shared contracts and flows when those artifacts exist.
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

## Shared document types

`FEATURE_SPECS` now supports three document types:

1. `interaction spec`
2. `category contract`
3. `category flow`

Use them for different purposes instead of forcing everything into one interaction document.

### 1. Interaction spec

Path shape:

- `PRODUCT/05_FEATURE_SPECS/<category>/<feature_id>-<feature_slug>/<interaction_id>.md`

Purpose:

- describe one interaction
- define its trigger, preconditions, outcome, state changes, and dependencies
- reference shared contracts and flows when they exist

### 2. Category contract

Path shape:

- `PRODUCT/05_FEATURE_SPECS/<category>/contracts/<name>.toml`

Purpose:

- define machine-readable shared object/state vocabulary
- define allowed and forbidden user-visible states
- define ownership of states and transitions across interactions

Writing rules:

- use TOML, not markdown
- keep names explicit and stable
- prefer keyed subtables over repeated array-of-table records when the entry is naturally keyed by an identifier
- use exact object names and exact state names
- keep the file machine-readable first; avoid prose-heavy commentary

Recommended sections:

```toml
[contract]
id = "cbw.request_lifecycle"
category = "CBW"
primary_object = "request"

[vocabulary]
request = "..."

[constraints]
single_processing_run_per_request = true

[user_visible_states]
allowed = ["processing", "completed", "failed", "cancelled"]
forbidden = ["queued", "cancelling"]

[state.processing]
description = "..."
entered_by = ["CBW-001-submit_chat_request"]
exits_to = ["completed", "failed", "cancelled"]

[ownership."CBW-001-submit_chat_request"]
reads = []
writes = ["processing"]

[transitions.processing_to_completed]
from = "processing"
to = "completed"
trigger = "CBW-003-stream_contextual_chat_response"
```

### 3. Category flow

Path shape:

- `PRODUCT/05_FEATURE_SPECS/<category>/flows/<name>.md`

Purpose:

- describe a cross-feature user flow
- show branching paths such as happy path, cancel path, regenerate path
- carry human-readable diagrams and overview sequence

Writing rules:

- use markdown
- keep the flow at category or multi-feature scope
- reference interaction specs and contract files directly
- prefer one flow doc over repeating the same end-to-end sequence in many interaction specs

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
