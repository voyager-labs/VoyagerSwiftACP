# Contract TOML Spec

This document defines the recommended shape for `PRODUCT/05_FEATURE_SPECS/<category>/contracts/*.toml`.

Use it when authoring or updating category-level contract files.

## Goal

A contract TOML file exists to make shared object/state vocabulary explicit and machine-readable.

Product-wide object definitions belong in `PRODUCT/03_INFORMATION_ARCHITECTURE/OBJECTS/data.tsv`.
Contract TOML should reference those object keys and add only category-local semantics.

It should answer:

- what is the primary object?
- what secondary objects are truly needed?
- what repeated category-local terms must be defined before policy uses them?
- what are the allowed user-visible states?
- what state terms are forbidden?
- which interactions read or write which states?
- which transitions are allowed?

Do not use contract TOML files for long prose explanations or flow narration.

## File Placement

Path pattern:

- `PRODUCT/05_FEATURE_SPECS/<category>/contracts/<name>.toml`

Examples:

- `PRODUCT/05_FEATURE_SPECS/cbw/contracts/request_lifecycle.toml`
- `PRODUCT/05_FEATURE_SPECS/cbw/contracts/conversation_session_contract.toml`

## Top-level Sections

Recommended sections:

- `[contract]`
- `[vocabulary]` for category-local terms only
- `[policy]`
- `[user_visible_states]` or `[user_visible_status]`
- `[state.<state_name>]` or `[status.<status_name>]`
- `[ownership."<interaction_id>"]`
- `[transitions.<transition_name>]`

Keep the structure shallow. Prefer a few stable sections over many nested aliases.

## Required Concepts

### `[contract]`

Required fields:

- `id`
- `category`
- `primary_object_key`

Optional fields:

- `secondary_object_keys`
- `display_region`
- `scope_region`

Example:

```toml
[contract]
id = "cbw.request_lifecycle"
category = "CBW"
primary_object_key = "request"
secondary_object_keys = ["response", "turn"]
```

Rules:

- `primary_object_key` and `secondary_object_keys` must reference `OBJECTS.key`
- if a truly product-wide object is missing from `OBJECTS`, add it there first before standardizing the contract around it
- keep category-local relational terms out of these fields
- legacy `primary_object` and `secondary_objects` may remain temporarily during migration, but new or revised contracts should prefer the `_key` field names

### `[vocabulary]`

Use this section to define category-local terms that are needed by the contract but are not the product-wide object definitions owned by `OBJECTS`.

Example:

```toml
[vocabulary]
downstream_turn = "특정 기준 turn 뒤에 이어지는 후속 turn"
regenerate = "기존 request를 다시 실행해 같은 turn 안에 새 response를 만드는 action"
```

Rules:

- use exact product-facing names
- avoid invented abstractions unless the user explicitly wants them
- do not restate the base definitions of `request`, `response`, `provider`, and similar product-wide objects here when they already live in `OBJECTS`
- if a term is shared broadly enough to behave like a product-wide object, add it to `OBJECTS` first instead of redefining it in multiple contracts
- keep this section for category-local, directional, or relational terms such as `downstream_turn`
- if the current contract shape has no dedicated action section, define repeated action or branch terms here before `[policy]` refers to them
- keep the definition short; let the linked flow doc carry the full sequence semantics

### `[policy]`

Use this section for global boolean or enumerated rules that multiple specs depend on.

Example:

```toml
[policy]
single_processing_response_per_request = true
regenerate_reuses_existing_request = true
regenerate_reuses_existing_request_note = "새 request를 만들지 않고 재생성 대상 request identity를 유지한다"
cancel_allowed_from = ["processing"]
```

Rules:

- use this section for category-wide invariants
- avoid stuffing interaction-local behavior here
- do not let a policy key become the first definition of a repeated term
- if a policy mentions a repeated action or branch term such as `submit`, `regenerate`, `retry`, or `restore`, define that term in `[vocabulary]` or the linked flow doc first
- use short `*_note` fields when the invariant would otherwise be easy to misread from the key name alone

### `[user_visible_states]` / `[user_visible_status]`

Use one of these sections to declare the canonical user-visible state vocabulary.

Example:

```toml
[user_visible_states]
allowed = ["processing", "completed", "failed", "cancelled"]
forbidden = ["queued", "cancelling"]
```

Rules:

- `allowed` is the only user-visible vocabulary that specs should use
- `forbidden` captures terms that should not appear in user-facing spec prose

### `[state.<name>]` / `[status.<name>]`

Use one table per declared state or status.

Recommended fields:

- `description`
- `entered_by`
- `exits_to`
- `terminal`
- `user_visible`
- `allows_submit`
- `fallback_status`
- `requires_followup`

Example:

```toml
[state.processing]
description = "요청이 현재 응답 생성 중인 상태"
entered_by = ["CBW-001-submit_chat_request", "CBW-001-regenerate_chat_response"]
exits_to = ["completed", "failed", "cancelled"]
terminal = false
user_visible = true
```

Rules:

- use one state name, not a list of near-synonyms
- interaction spec prose should mention the exact state or status key in inline code form, such as `` `processing` ``
- keep `entered_by` and `exits_to` deterministic

### `[ownership."<interaction_id>"]`

Use keyed subtables, not repeated array-of-table records.

Recommended fields:

- `reads`
- `writes`
- `target_object`
- `creates_objects`
- `preserves_objects`
- `display_region`
- `control_region`

Example:

```toml
[ownership."CBW-001-submit_chat_request"]
reads = []
writes = ["processing"]
target_object = "request"
creates_objects = ["request", "response"]
control_region = "file_manager_window.inspector_pane.inspector_mode_chat.chat_field"
```

Rules:

- the key must be the exact `interaction_id`
- use this section to map interaction responsibility, not to repeat full prose behavior

### `[transitions.<name>]`

Use one keyed subtable per allowed transition.

Required fields:

- `from`
- `to`

Optional fields:

- `trigger`

Example:

```toml
[transitions.processing_to_completed]
from = "processing"
to = "completed"
trigger = "CBW-003-stream_contextual_chat_response"
```

Rules:

- transition names should be readable and stable
- `from` and `to` must use declared state names from `allowed`

## Naming Rules

- use lowercase snake_case for TOML table keys where a free key name is needed
- use exact `interaction_id` for ownership keys
- use exact `OBJECTS.key` values for object-reference fields such as `primary_object_key`, `secondary_object_keys`, `target_object`, `creates_objects`, and `preserves_objects`
- use exact state names in `allowed`, `forbidden`, `from`, `to`, `reads`, and `writes`

## What Not To Put Here

Do not put these in contract TOML:

- long narrative explanation
- happy-path sequence prose
- UI copy alternatives
- open questions
- speculative implementation details

Those belong in:

- interaction specs
- flow docs
- review notes

## Flow Relationship

`OBJECTS` defines product-wide object nouns.

Contract TOML binds those object keys to category-specific state, ownership, policy, and transitions.

When policy depends on a repeated action or branch term, keep the minimum contract-local definition in `[vocabulary]` and keep the full sequence meaning in the linked flow doc.

Flow docs explain sequence and branching.

Use:

- `contracts/*.toml` for machine-readable consistency
- `flows/*.md` for human-readable end-to-end flow
