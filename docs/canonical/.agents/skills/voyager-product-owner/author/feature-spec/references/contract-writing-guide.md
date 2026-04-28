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

Product-wide object nouns should be owned by `PRODUCT/03_INFORMATION_ARCHITECTURE/OBJECTS/data.tsv`.
The contract should decide category semantics on top of those object keys, not redefine the same product object in multiple places.

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

1. check whether the primary object already exists in `OBJECTS`
2. decide the primary object key
3. decide whether any secondary object keys are truly needed
4. settle the remaining category-local vocabulary names
5. settle any repeated action or branch term that policy will rely on
6. declare policy invariants on the settled terms
7. declare allowed and forbidden user-visible states
8. define state meanings
9. assign ownership by interaction
10. declare allowed transitions

Do not start from policy or transitions before the object and vocabulary are settled.

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

### Start from `OBJECTS`

If the object is product-wide, use the existing `OBJECTS.key` as the contract object key.

Good:

- `request`
- `response`
- `provider`
- `context`

Rules:

- add a new row to `OBJECTS` first when the contract introduces a product-wide object that does not exist yet
- use `primary_object_key` and `secondary_object_keys` to reference those canonical keys
- keep contract-specific semantics in state, policy, ownership, and transitions
- do not use `[vocabulary]` to restate the base definition of an `OBJECTS` entry

### Add secondary objects only when they carry real contract weight

If the contract can be expressed with one object, keep it to one object.

Only add `secondary_object_keys` when:

- the secondary object has its own vocabulary burden
- multiple interactions really refer to it
- removing it would make the contract ambiguous

## Vocabulary Rules

- Use exact product terms.
- Do not smooth over ambiguity with near-synonyms.
- Do not create alias registries unless synonym normalization is an explicit requirement.
- If the user has not settled a term yet, surface that ambiguity instead of inventing a new one.
- Keep `[vocabulary]` for category-local or relational terms that are not yet product-wide `OBJECTS` entries.
- Do not duplicate the base definition of shared objects such as `request`, `response`, or `provider` when `OBJECTS` already owns them.

Examples:

- prefer `request` over `request object`
- prefer `response` over `assistant output artifact`
- prefer `chat_session` over `conversation_session` if the product language already uses `chat`
- prefer `downstream_turn` in `[vocabulary]` when the term is a directional concept tied to one contract

## Term Definition Before Policy

- If a repeated non-object term appears in spec prose, flow prose, and policy, define that term before writing the policy key that depends on it.
- Decide term ownership in this order:
    - product-wide noun -> `OBJECTS`
    - category-local relational term -> `[vocabulary]`
    - branch or sequence term -> linked `flows/*.md`
    - invariant over already-defined terms -> `[policy]`
- If the current contract shape has no dedicated section for an action or branch term that policy depends on, put the minimum contract-relevant definition in `[vocabulary]` and let the flow doc own the sequence semantics.
- Do not let a boolean key such as `regenerate_reuses_existing_request` become the first place where a reviewer infers what `regenerate` means.
- If the meaning of a repeated term is still unsettled, stop and resolve the term definition before adding policy, ownership, or transitions.

## Policy Rules

- Use `[policy]` to constrain already-defined objects, states, and repeated terms.
- Keep policy values focused on invariants, allowed sets, forbidden sets, fallback rules, and ownership-neutral constraints.
- When a policy key mentions a repeated action or branch term such as `submit`, `regenerate`, `retry`, or `restore`, the linked flow doc must already explain that term's sequence semantics.
- Add a short note field when a boolean or enum policy would otherwise be easy to misread from the key name alone.
- Do not use `[policy]` to smuggle in a new term definition that should live in `OBJECTS`, `[vocabulary]`, or a flow doc.

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

Interaction specs should mention contract-declared state or status names using the exact key in inline code form.
Example:

- use `` `processing` `` instead of prose variants like `running`
- use `` `restore_failed` `` instead of label-only phrases like `restore failed`

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

- object-key selection against `OBJECTS`
- state vocabulary
- ownership
- transitions

Use flow docs for:

- sequence
- branching paths
- end-to-end explanation
- diagrams

For contract-driven categories, keep at least one flow doc as a required companion artifact.

Do not try to make one document do both jobs.

## Review Checklist

Before finishing a contract change, ask:

- does this contract have one clear primary object?
- does that primary object resolve to the right `OBJECTS.key`?
- are the object names the exact product terms?
- are forbidden states excluded from user-visible vocabulary?
- does each owned interaction really read/write the declared states?
- are the transitions consistent with the current specs?
- would this contract help a checker compare specs without guessing?
