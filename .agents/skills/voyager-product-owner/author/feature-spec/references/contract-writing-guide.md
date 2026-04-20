# Contract Writing Guide

Use this guide when writing or revising `PRODUCT/05_FEATURE_SPECS/<category>/contracts/*.toml`.

This guide is about authoring decisions.

For field shapes and section schema, see:

- `contract-toml-spec.md`

## Purpose

A contract file should make shared product terms explicit enough that:

- multiple interaction specs can use the same object vocabulary
- multiple interaction specs can use the same state vocabulary
- consistency review can compare prose against one declared contract
- future checker logic can validate against stable keys instead of guessing from prose

Do not use a contract file just because a feature has states.
Use it when the same vocabulary must stay aligned across multiple specs.

## When To Create A Contract

Create a contract when one or more of these are true:

- more than one interaction spec refers to the same object lifecycle
- state names are being repeated across multiple specs
- object naming is drifting across specs
- user-visible states must be explicitly allowed or forbidden
- one category needs a stable contract before checker automation can be trusted

Do not create a contract for a one-off interaction that has no shared vocabulary.

## Authoring Order

Write a contract in this order:

1. decide the primary object
2. decide whether any secondary objects are truly needed
3. settle the exact vocabulary names
4. declare allowed and forbidden user-visible states
5. define state meanings
6. assign ownership by interaction
7. declare allowed transitions

Do not start from transitions before the object and vocabulary are settled.

## Object Rules

### Choose the narrowest stable object

Prefer the most stable product-facing object that multiple specs already need.

Good:

- `request`
- `response`
- `turn`
- `chat_session`

Bad:

- `active_regenerate_run`
- `processing_entity`
- `conversation_unit`

If an object is only needed to explain one local implementation detail, it probably does not belong in the contract.

### Add secondary objects only when they carry real contract weight

If the contract can be expressed with one object, keep it to one object.

Only add `secondary_objects` when:

- the secondary object has its own vocabulary burden
- multiple interactions really refer to it
- removing it would make the contract ambiguous

## Vocabulary Rules

- Use exact product terms.
- Do not smooth over ambiguity with near-synonyms.
- Do not create alias registries unless synonym normalization is an explicit requirement.
- If the user has not settled a term yet, surface that ambiguity instead of inventing a new one.

Examples:

- prefer `request` over `request object`
- prefer `response` over `assistant output artifact`
- prefer `chat_session` over `conversation_session` if the product language already uses `chat`

## State Rules

### Only declare user-visible states in `allowed`

If the user is not supposed to see the state name in the product contract, do not put it in `allowed`.

Example:

- allowed: `processing`, `completed`, `failed`, `cancelled`
- forbidden: `queued`, `cancelling`

### Keep state names atomic

Use one stable name per state.

Good:

- `processing`
- `completed`
- `failed`
- `cancelled`

Bad:

- `running_or_processing`
- `complete`
- `cancel_in_progress`

### Each state section should answer one question

For each `[state.<name>]` or `[status.<name>]`, the author should be able to answer:

- what does this state mean?
- who puts the object into this state?
- what states can follow it?
- is it terminal?
- is it user-visible?

If you cannot answer those clearly, the state is not ready.

## Ownership Rules

Use `ownership` to show which interaction reads or writes the contract state.

Good ownership entries:

- small
- exact
- tied to one `interaction_id`
- written in terms of `reads` and `writes`

Do not restate the whole spec inside the contract.

## Transition Rules

Only encode transitions that matter for cross-spec consistency.

Good:

- `processing -> completed`
- `processing -> failed`
- `processing -> cancelled`
- `failed -> processing` via regenerate

Bad:

- internal micro-transitions that only matter to implementation
- speculative transitions that no interaction currently owns

## Scope Rules

Keep contracts category-scoped.

If a contract spans multiple features inside the same category, that is expected.
If a contract seems to span multiple categories, stop and check whether the vocabulary is too broad.

## Relationship To Flow Docs

Use contracts for:

- object vocabulary
- state vocabulary
- ownership
- transitions

Use flow docs for:

- sequence
- branching paths
- end-to-end explanation
- diagrams

Do not try to make one document do both jobs.

## Review Checklist

Before finishing a contract change, ask:

- does this contract have one clear primary object?
- are the object names the exact product terms?
- are forbidden states excluded from user-visible vocabulary?
- does each owned interaction really read/write the declared states?
- are the transitions consistent with the current specs?
- would this contract help a checker compare specs without guessing?
