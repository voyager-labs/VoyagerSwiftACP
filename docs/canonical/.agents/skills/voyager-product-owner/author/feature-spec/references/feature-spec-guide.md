# FEATURE_SPEC Guide

This document explains how to write or refactor `PRODUCT/05_FEATURE_SPECS` documents.

- Use `.agents/skills/voyager-product-owner/author/feature-spec/assets/TEMPLATE-feature-spec.md` as the actual output template.
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
- Keep one document scoped to one `interaction_id`.
- Preserve the fixed section shell even when the section is sparse.
- Use `-` for intentionally empty values and `TBD` for values that are still undecided.
- Apply the same `-` / `TBD` convention to frontmatter values as well as body sections.
- Do not use `NULL`.
- When body prose references another `interaction_id`, use a markdown link to the target FEATURE_SPEC file instead of plain backticks.
- Prefer relative links such as `[CBW-002-capture_request_context_snapshot](../CBW-002-manage-request-context/CBW-002-capture_request_context_snapshot.md)`.
- In frontmatter `summary`, prefer product labels or natural Korean concept names over raw object keys.
- In interaction spec body prose, prefer stable English label forms over raw snake_case object or state keys.
- That body-prose English-label preference does not apply to FI `INTERACTIONS.summary` or FS frontmatter `summary`.
- For example, prefer `request context`, `request message`, `turn history`, `context snapshot`, `chat session`, `attachment`
  over raw keys such as `request_context`, `request_message`, `turn_history`, `context_snapshot`, `chat_session`, `attachment`.
- Keep raw snake_case keys in contracts and flows; do not carry them into interaction spec prose unless the literal UI label itself uses that form.
- Apply exact state/status key formatting only in body prose.
- Never rewrite `interaction_id`, filenames, markdown link labels or targets, relative paths, frontmatter keys, or deterministic IA/TSV reference values when applying status-key formatting.
- Do not use vague hedge phrases when a concrete product term can be written.
- Avoid wording such as `또는 동등한`, `유사한`, `적절한`, `필요 시`, `가능한 경우`, `등` for states, CTAs, triggers, or outcomes unless the ambiguity is intentional and explicitly part of the product contract.
- Prefer exact state names, button labels, UI regions, and trigger conditions.
- When referring to a literal UI label, use the exact product label verbatim.
- Do not translate a literal UI label into Korean if the UI itself uses English.
- Default user-visible labels, status names, CTA examples, and menu labels to English unless the product truth already establishes another literal label.
- If the user explicitly confirms that an FS long-text field has been human-reviewed and its `<<AI>>` marker should be removed, remove the marker from the corresponding FI long-text cell in the same pass.
- If the user explicitly asks to mark one named interaction spec as reviewed or `검토 완료`, treat that as a human-review handoff for that one file only.
- If a named target interaction spec already shows a one-file human-review signal relative to FI, treat that as the same handoff even without a fresh explicit command.
    - accepted signal: the target FEATURE_SPEC no longer carries `<<AI>>` markers while the matching FI `summary` still does
    - accepted signal: the target FEATURE_SPEC frontmatter `status` is no longer `아이디어` / `드래프트` while the matching FI row still is
- During that handoff, remove `<<AI>>` markers from the target interaction spec's human-readable frontmatter values and body prose in the same file.
- During that handoff, if the target interaction spec frontmatter `status` is `아이디어` or `드래프트`, promote it to `기획 완료`.
- During that handoff, update the matching `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv` row in the same pass:
    - remove `<<AI>>` from the matching long-text cell such as `summary`
    - if the row `status` is `아이디어` or `드래프트`, promote it to `기획 완료`
- Do not auto-promote sibling interaction specs, the parent `FEATURES` row, category `flows/*.md`, or category `contracts/*.toml` during a one-file human-review handoff.
- Do not assume that prose-level object/state consistency can be proved from text alone.
    - Use exact object names and exact state names.
    - If the contract is ambiguous, flag it instead of smoothing it over with similar wording.
- Strict lint still requires all frontmatter keys and fixed sections to be present, but it does not reject `-` / `TBD` values in metadata or body sections.
- In strict mode, `-` is treated as confirmed not-applicable and does not emit a warning.
- In strict mode, `TBD` is treated as unresolved and is surfaced as a warning for review instead of a hard failure.

## Priority Order

When style rules and sync rules pull in different directions, use this precedence order:

1. `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv` row truth
2. interaction spec frontmatter exact-match requirements
3. frontmatter `summary` wording rule
4. interaction spec body prose wording rule
5. contract/flow vocabulary preference

Apply that order as follows:

- Treat the matching FI `INTERACTIONS` row as the SSOT for interaction-spec frontmatter values that the bundle checker compares directly, especially `feature`, `category_key`, `feature_id`, `status`, `summary`, and `related_region`.
- If an interaction spec frontmatter `summary` needs to change, update the matching FI `INTERACTIONS` row in the same pass or keep the existing frontmatter value unchanged.
- Do not let body-prose wording preferences rewrite frontmatter `summary` away from the matching FI row.
- The rule "prefer product labels or natural Korean concept names in frontmatter `summary`" applies after FI/frontmatter sync, not before it.
- The rule "prefer stable English label forms in body prose" applies only to body prose unless the FI row itself already uses that wording.
- Contract and flow wording may use more explicit object/state labels for alignment, but that does not overrule FI/frontmatter exact-match fields.

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

## Human-review handoff

Use this when either:

1. the user explicitly confirms human review for a specific interaction spec path or `interaction_id`, or
2. a specific target interaction spec already shows a one-file human-review signal relative to its matching FI row.

Required behavior:

1. Remove `<<AI>>` markers from the target interaction spec's human-readable frontmatter values and body prose.
2. If the target spec `status` is `아이디어` or `드래프트`, change it to `기획 완료`.
3. Sync the matching FI `INTERACTIONS` row in the same pass.
4. Re-run local checks on the touched spec and FI row before finishing.

Do not infer human review from:

- `AI Draft Complete`
- passing lint or consistency checks
- broad requests such as `spec 정리해줘`
- generic wording edits that do not carry the file-state signal above

Human-review handoff requires either:

- an explicit user instruction such as `검토 완료로 넘겨줘`, `human-reviewed 처리해줘`, or equivalent wording that names the target, or
- a named target interaction spec whose file state already shows the explicit one-file handoff signal above.

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

Optional addition:

- `Boundary Notes`

## Interaction Spec Scope

This guide is only for `interaction spec` writing.

Path shape:

- `PRODUCT/05_FEATURE_SPECS/<category>/<feature_id>-<feature_slug>/<interaction_id>.md`

Purpose:

- describe one interaction
- define its trigger, preconditions, outcome, state changes, and dependencies

Do not use this guide as the authoring source for:

- `contracts/*.toml`
- `flows/*.md`

For those, use:

- `contract-writing-guide.md`
- `contract-toml-spec.md`
- `contract-consistency-workflow.md`
- `flow-writing-guide.md`

## Contract Alignment Rules

If a category-level contract already exists, interaction specs must align to it.

That means:

- use the exact object names declared in the contract
- use the exact allowed state names declared in the contract
- do not use contract-forbidden state terms in interaction prose
- do not invent alternate labels for the same object or state
- add an explicit reference to the relevant `contracts/*.toml` file in the interaction spec

This guide does not explain how to design or author the contract itself.
It only defines how an interaction spec must stay consistent with an existing contract.

## Section guidance

### Intent

- Explain why the interaction exists.
- Keep the purpose short and user-facing.
- Do not restate implementation structure or acceptance-criteria wording.

### Trigger / Entry Points

- Describe menu paths, shortcuts, visible entry points, and invocation conditions.
- Do not omit meaningful entry paths.

### Preconditions

- Describe the state, selection, permission, or environment conditions required before execution.

### Expected Outcome

- Describe what must be true when execution succeeds.
- Focus on what becomes true from the user's point of view.

### State Changes

- Describe which states change and how.
- Include state preservation behavior when failure matters.
- Keep this distinct from `Expected Outcome`.
    - `Expected Outcome` answers what should be established.
    - `State Changes` answers what is updated, moved, cleared, preserved, or recalculated.

### User-visible Feedback

- Describe what the user sees, such as loading, success, error, or retry messaging.

### Edge Cases / Failure Handling

- Cover invalid input, permission issues, duplicate execution, cancellation, and partial failure.

### Acceptance Criteria

- Write testable statements in Korean using the pattern `...한 상황에서, ...하면, ...해야 한다.`
- Keep each statement specific and verifiable.
- Keep one AC line scoped to one observable result.

### Permissions / Dependencies

- Describe permissions, system conditions, network constraints, and external dependencies.
- Keep this at product-contract level, not architecture-design level.

### Observability / Analytics

- Describe events worth tracking, such as entry, success, failure, and retry.
- Prefer observable checkpoints over implementation plumbing.

### Related Interactions

- Link related interactions within the same feature where relevant.

### Source

- Keep the inventory row reference accurate in the form `Inventory row: <path>:<line>`.
- When the interaction spec depends on category-level contracts, include a `Contracts:` line with links to the relevant `contracts/*.toml` files.
- `Contracts:` is optional only when no contract-backed reference is relevant to that interaction spec.
- When category-level flow docs directly sequence the interaction, include a `Flows:` line with links to the relevant `flows/*.md` files.
- `Flows:` is optional only when no category flow directly sequences that interaction.

## Optional additions

- Add extra explanatory material only when it is truly needed.
- Optional additions must not replace the fixed section contract.
